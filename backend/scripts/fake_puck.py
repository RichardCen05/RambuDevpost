"""Streams a WAV file to the backend exactly like the puck does: start, ~3 s pieces, end.

Usage:
  uv run python scripts/fake_puck.py ../samples/test-calls/bank-otp-en.wav
  uv run python scripts/fake_puck.py call.wav --language id --speed 0   # as fast as possible
The puck token comes from --token or DEV_PUCK_TOKEN.
"""

import argparse
import io
import json
import os
import sys
import time
import wave

import httpx

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from rambu.transcribe import SAMPLE_RATE, decode_wav  # noqa: E402


def wav_bytes(pcm16: bytes) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(pcm16)
    return buffer.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("wav")
    parser.add_argument("--server", default=os.environ.get("RAMBU_SERVER", "http://127.0.0.1:8001"))
    parser.add_argument("--token", default=os.environ.get("DEV_PUCK_TOKEN", ""))
    parser.add_argument("--language", default="en")
    parser.add_argument("--chunk", type=float, default=3.0, help="seconds per piece")
    parser.add_argument("--speed", type=float, default=1.0, help="1 = real time, 0 = no waiting")
    args = parser.parse_args()
    if not args.token:
        parser.error("set --token or DEV_PUCK_TOKEN")

    with open(args.wav, "rb") as f:
        pcm = decode_wav(f.read())
    pcm16 = (pcm.clip(-1, 1) * 32767).astype("<i2").tobytes()
    step = int(args.chunk * SAMPLE_RATE) * 2

    client = httpx.Client(base_url=args.server, headers={"Authorization": f"Bearer {args.token}"}, timeout=30)
    session_id = client.post("/api/puck/sessions", json={"language": args.language}).raise_for_status().json()["sessionId"]
    print(f"session {session_id} ({len(pcm) / SAMPLE_RATE:.1f} s of audio)")

    started = time.monotonic()
    for i in range(0, len(pcm16), step):
        client.post(
            f"/api/puck/sessions/{session_id}/chunks",
            content=wav_bytes(pcm16[i:i + step]),
            headers={"Content-Type": "audio/wav"},
        ).raise_for_status()
        if args.speed > 0:
            target = started + (i + step) / 2 / SAMPLE_RATE / args.speed
            time.sleep(max(0.0, target - time.monotonic()))
    client.post(f"/api/puck/sessions/{session_id}/end").raise_for_status()

    for _ in range(120):
        status = client.get(f"/api/puck/sessions/{session_id}").raise_for_status().json()
        if status["status"] != "listening":
            break
        time.sleep(0.5)
    else:
        print("session did not finish in 60 s", file=sys.stderr)
        return 1

    print(json.dumps({
        "status": status["status"],
        "level": status["level"],
        "signals": status["signals"],
        "evidence": status["evidence"],
        "firstWarningAfterSeconds": status["firstWarningAfterSeconds"],
        "failure": status["failure_reason"],
        "transcript": status["transcript"],
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
