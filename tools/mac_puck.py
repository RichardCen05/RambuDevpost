"""Stand-in puck: the Mac's microphone listens to the parent's phone on loudspeaker.

It talks to the backend exactly like the puck firmware: start a session, send ~3 s WAV pieces, end.
Recording starts by itself when speech is heard and stops after the call goes quiet (or on Enter).

First run (pairs with the family whose invite code is on the parent's phone, Home → Connect family / Profile):
  uv run --project backend python tools/mac_puck.py --server https://….trycloudflare.com --code 472141
Later runs reuse the saved pairing:
  uv run --project backend python tools/mac_puck.py
"""

import argparse
import collections
import io
import json
import queue
import subprocess
import sys
import threading
import time
import wave
from pathlib import Path

import httpx
import numpy as np

RATE = 16000
FRAME = RATE // 10  # 100 ms
PIECE_SECONDS = 3
CONFIG = Path.home() / ".rambu-puck.json"


def wav_bytes(pcm16: bytes) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(pcm16)
    return buffer.getvalue()


def rms(frame: bytes) -> float:
    samples = np.frombuffer(frame, dtype="<i2").astype(np.float32) / 32768.0
    return float(np.sqrt(np.mean(samples ** 2))) if len(samples) else 0.0


class Uploader(threading.Thread):
    """Sends pieces in order on its own thread so the microphone never waits on the network."""

    def __init__(self, client: httpx.Client):
        super().__init__(daemon=True)
        self.client = client
        self.jobs: queue.Queue = queue.Queue()
        self.session_id: str | None = None
        self.done = threading.Event()

    def run(self):
        while True:
            kind, data = self.jobs.get()
            try:
                if kind == "start":
                    reply = self.client.post("/api/puck/sessions", json={})
                    reply.raise_for_status()
                    self.session_id = reply.json()["sessionId"]
                    print(f"● recording (session {self.session_id[:8]})", flush=True)
                elif kind == "piece" and self.session_id:
                    self.client.post(f"/api/puck/sessions/{self.session_id}/chunks", content=wav_bytes(data),
                                     headers={"Content-Type": "audio/wav"}).raise_for_status()
                elif kind == "end" and self.session_id:
                    self.client.post(f"/api/puck/sessions/{self.session_id}/end").raise_for_status()
                    summarize(self.client, self.session_id)
                    self.session_id = None
                elif kind == "hello":
                    self.client.post("/api/puck/hello", json={"firmware": "mac-stand-in"})
            except httpx.HTTPError as exc:
                print(f"! {kind} failed: {exc}", flush=True)


def summarize(client: httpx.Client, session_id: str) -> None:
    for _ in range(60):
        status = client.get(f"/api/puck/sessions/{session_id}").json()
        if status["status"] != "listening":
            break
        time.sleep(0.5)
    print(f"■ call ended: {status['status']} · {status['level']} {status['signals']}", flush=True)
    for item in status["evidence"]:
        print(f"   “{item['quote']}” {item['signals']}", flush=True)
    print(f"   transcript: {status['transcript']}", flush=True)


def pick_microphone() -> str:
    """The built-in microphone; virtual devices (Zoom, Teams, BlackHole) are skipped."""
    listing = subprocess.run(["ffmpeg", "-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""],
                             capture_output=True, text=True).stderr
    audio = listing.split("audio devices:")[-1]
    devices = [line.split("] ", 2)[-1].strip() for line in audio.splitlines() if "] [" in line]
    for name in devices:
        if "microphone" in name.lower():
            return f":{name}"
    real = [d for d in devices if not any(v in d.lower() for v in ("zoom", "teams", "blackhole", "virtual"))]
    return f":{(real or devices or ['0'])[0]}"


def pair(server: str, code: str) -> dict:
    reply = httpx.post(f"{server}/api/pucks/claim", json={"code": code}, timeout=15)
    if reply.status_code != 201:
        sys.exit(f"pairing failed ({reply.status_code}): {reply.text}")
    config = {"server": server, **reply.json()}
    CONFIG.write_text(json.dumps(config))
    CONFIG.chmod(0o600)
    print(f"paired as puck {config['puckId'][:8]}; saved to {CONFIG}")
    return config


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--server", help="backend address (saved after pairing)")
    parser.add_argument("--code", help="six-digit invite code shown on the parent's phone, to pair")
    parser.add_argument("--device", help="avfoundation audio input, e.g. ':MacBook Pro Microphone' (default: built-in mic)")
    parser.add_argument("--threshold", type=float, default=0.02, help="speech level that starts a recording")
    parser.add_argument("--quiet", type=float, default=6.0, help="seconds of quiet that end a call")
    args = parser.parse_args()

    config = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    if args.code:
        config = pair((args.server or config.get("server", "")).rstrip("/"), args.code)
    elif args.server:
        config["server"] = args.server.rstrip("/")
    if not config.get("puckToken") or not config.get("server"):
        parser.error("pair first: --server <address> --code <invite code>")

    client = httpx.Client(base_url=config["server"], headers={"Authorization": f"Bearer {config['puckToken']}"}, timeout=20)
    uploader = Uploader(client)
    uploader.start()
    uploader.jobs.put(("hello", None))

    device = args.device or pick_microphone()
    print(f"microphone {device[1:]}", flush=True)
    mic = subprocess.Popen(
        ["ffmpeg", "-loglevel", "error", "-f", "avfoundation", "-i", device,
         "-ac", "1", "-ar", str(RATE), "-f", "s16le", "-"],
        stdout=subprocess.PIPE,
    )
    stop_now = threading.Event()
    threading.Thread(target=lambda: (sys.stdin.readline(), stop_now.set()), daemon=True).start()

    preroll: collections.deque[bytes] = collections.deque(maxlen=15)  # 1.5 s before speech starts
    recent: collections.deque[bool] = collections.deque(maxlen=10)
    recording = False
    piece = bytearray()
    quiet_since = None
    last_hello = time.monotonic()
    print("listening for a call on speaker… (Enter ends a call, Ctrl+C quits)", flush=True)

    try:
        while True:
            frame = mic.stdout.read(FRAME * 2)
            if not frame:
                print("microphone closed (check System Settings → Privacy → Microphone)")
                return 1
            loud = rms(frame) > args.threshold
            recent.append(loud)
            now = time.monotonic()
            if not recording:
                preroll.append(frame)
                if sum(recent) >= 8:
                    recording = True
                    quiet_since = None
                    stop_now.clear()
                    uploader.jobs.put(("start", None))
                    piece = bytearray(b"".join(preroll))
                elif now - last_hello > 60:
                    uploader.jobs.put(("hello", None))
                    last_hello = now
                continue
            piece += frame
            if len(piece) >= RATE * 2 * PIECE_SECONDS:
                uploader.jobs.put(("piece", bytes(piece)))
                piece = bytearray()
            quiet_since = None if loud else (quiet_since or now)
            if stop_now.is_set() or (quiet_since and now - quiet_since > args.quiet):
                if piece:
                    uploader.jobs.put(("piece", bytes(piece)))
                uploader.jobs.put(("end", None))
                recording = False
                preroll.clear()
                recent.clear()
                piece = bytearray()
    except KeyboardInterrupt:
        if recording:
            uploader.jobs.put(("end", None))
            time.sleep(3)
        return 0
    finally:
        mic.terminate()


if __name__ == "__main__":
    sys.exit(main())
