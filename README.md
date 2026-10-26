# Rambu

Rambu warns older parents about scam phone calls while the call is still going.

A small puck sits on the back of the parent's iPhone and listens to calls on loudspeaker. The backend turns the audio into text, an AI model looks for five scam signals, and the parent and their caregivers (usually a grown child in another city) get a warning with the caller's exact words. The first caregiver to tap **Scam** or **Safe** decides, and that answer reaches the parent's phone before they hand over a code or send money.

Rambu is built for families in Indonesia, where older parents are frequent targets of callers posing as a bank, the police, or a child in trouble. The app works in English and Bahasa Indonesia.

## How it works

```
parent's iPhone (loudspeaker)
        │ sound
        ▼
puck / stand-in ──3 s WAV pieces──▶ backend (Mac) ──▶ Whisper (on the Mac)
                                        │            └─▶ OpenAI model via OpenRouter
                                        │                 level + signals + exact quotes
                                        ▼
                         Apple Push ──▶ parent: warning, Live Activity, verdict
                                    └─▶ caregivers: alert → Scam / Safe
```

- **Levels:** `low` (safe), `needs_review` (worth a look), `high_risk` (danger).
- **Signals:** `impersonation`, `urgency`, `secret_code`, `transfer`, `remote_app`.
- **Evidence:** every warning carries sentences copied word for word from the transcript. The backend checks each quote against the transcript and drops anything the model made up. A small keyword check catches plain requests for a code ("read it to me", "sebutkan kodenya") if the model misses them.
- **Privacy:** digits of codes, PINs and account numbers are masked before anything is stored or sent to the model. Raw audio is processed in memory and never written to disk. Caregivers only see the flagged sentences; the parent's full (masked) transcript stays with the parent.
- **Failures are visible:** a call that couldn't be analyzed is shown as "Could not assess", never as safe.

## Repository

| Path | What's there |
|---|---|
| `backend/` | Python 3.12 + FastAPI: call pipeline, scam analysis, families, alerts, Apple push |
| `ios/` | SwiftUI app (iOS 26) with a Live Activity widget, generated with XcodeGen |
| `firmware/rambu-puck/` | ESP32 firmware for the puck |
| `tools/mac_puck.py` | Stand-in puck: the Mac's microphone in place of the puck |
| `samples/test-calls/` | Synthetic test calls (macOS text-to-speech) |
| `devpost/` | Planning documents: scope, PRD, technical spec, build checklist |

## Run it

You need a Mac with Xcode 27, [uv](https://docs.astral.sh/uv/), ffmpeg, XcodeGen and cloudflared (`brew install uv ffmpeg xcodegen cloudflared`), an [OpenRouter](https://openrouter.ai) API key, and an Apple Developer account for push notifications.

### 1. Backend

```bash
cd backend
cp .env.example .env    # fill in OPENROUTER_API_KEY and the APNS_* values
uv run uvicorn rambu.main:create_app --factory --port 8001 --env-file .env
```

The first start downloads the Whisper model (about 500 MB). Calls, families and alerts are kept in `backend/data/rambu.sqlite3`.

### 2. Public address

```bash
cloudflared tunnel --url http://localhost:8001
```

It prints an address like `https://something.trycloudflare.com`. In the app, enter it under **Server** on the welcome screen or in **Profile → Server address**, on both phones. A quick tunnel gets a new address every time it restarts.

### 3. iPhone app

```bash
cd ios && xcodegen generate && open Rambu.xcodeproj
```

Pick your team under Signing & Capabilities, then run on each iPhone. One phone sets up as the parent, the other joins as a caregiver with the six-digit code the parent's phone shows, and the parent taps **Allow**.

### 4. Listening to calls

For this version, the Mac stands in for the puck. Put the Mac next to the parent's iPhone, then pair it with the invite code shown on the parent's phone (Profile → Invite a caregiver):

```bash
uv run --project backend python tools/mac_puck.py --server https://something.trycloudflare.com --code 123456
```

Later runs reuse the pairing: `uv run --project backend python tools/mac_puck.py`. It starts recording on its own when someone speaks and ends the call after six seconds of quiet (or when you press Enter).

### Recording a demo on simulators

Without two iPhones, run the parent and caregiver apps in two iOS Simulators on the same Mac (the simulators reach the backend at `http://127.0.0.1:8001`, no tunnel needed) and record both screens:

```bash
tools/record_demo.sh ~/Movies/rambu-take1
```

Turn off **Read alerts aloud** on the simulators (or mute them) while the stand-in puck is listening, so the Mac's speakers don't feed the app's voice back into the microphone.

### Tests

```bash
cd backend && uv run pytest
cd ios && xcodebuild -project Rambu.xcodeproj -scheme Rambu -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

To push a recorded call through the pipeline without a microphone, set `DEV_PUCK_TOKEN` in `backend/.env`, restart the backend, then from `backend/`: `DEV_PUCK_TOKEN=… uv run python scripts/fake_puck.py ../samples/test-calls/bank-otp-en.wav`.

## The puck

The puck is a prototype: an ESP32 and a microphone in a 3D-printed case, stuck to the back of the phone below the camera and powered over USB-C. The firmware is in this repo and compiles; recording calls on the puck itself and pairing it from the app are the next hardware phase, so the demo uses the Mac stand-in, which talks to the backend through the same API.

### Parts

| Part | Qty | Notes |
|---|---|---|
| ESP32 DevKit V1, 30-pin, USB-C | 1 | headers soldered |
| INMP441 I²S microphone, round board | 1 | headers soldered |
| Female–female jumper wires, 10 cm | 6 | |
| USB-C cable | 1 | plug housing no larger than 12 × 7 mm |
| Thick foam double-sided tape (2–3 mm) | some | mic ring and board gap |
| 3D-printed case: body + lid | 1 set | PETG (or PLA+), white |

### Case

Ø66 × 30 mm. The board sits on two support blocks between side guides, with a stop at the antenna end so plugging in USB-C doesn't push it; spare wire wraps around two posts. The lid snaps on at three points, has a 7-hole grill over the mic, and a notch for opening it.

Print settings: 0.2 mm layers, 3 walls, 20% infill, no supports, 100% scale. The body prints standing on its base, the lid top-down.

### Wiring

| Mic pin | ESP32 pin | GPIO |
|---|---|---|
| VDD | 3V3 | |
| GND | GND | |
| L/R | GND | (left channel) |
| SD | D32 | GPIO32 |
| SCK | D33 | GPIO33 |
| WS | D25 | GPIO25 |

Match the small white labels on the board rather than counting pins. The mic's sound hole faces the lid grill; a foam ring with a 6 mm hole keeps it clear.

### Firmware

```bash
arduino-cli core install esp32:esp32
arduino-cli lib install ArduinoJson NimBLE-Arduino
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app firmware/rambu-puck
arduino-cli upload  --fqbn esp32:esp32:esp32:PartitionScheme=huge_app -p /dev/cu.usbserial-XXXX firmware/rambu-puck
```

What it does:

- Advertises as "Rambu Puck" over Bluetooth and asks the iPhone for the Apple Notification Center Service (ANCS). Once the phone is bonded, iOS reports calls to the puck even when the Rambu app is closed. An answered call ("active call") starts recording; when it disappears, recording stops.
- Records the INMP441 at 16 kHz and sends 3-second WAV pieces at 8 kHz over Wi-Fi (HTTPS) to `/api/puck/sessions/...`. A loudspeaker call only carries about 300–3400 Hz, and 8 kHz keeps two audio buffers within the ESP32's RAM next to Wi-Fi, TLS and Bluetooth.
- Blue LED on while recording, slow blink while Wi-Fi is down. A heartbeat every minute keeps the app's puck status current.
- Settings (Wi-Fi, server address, puck token) are written by the app over Bluetooth, or typed on the serial console at 115200 baud for bench testing:

```
config {"ssid":"…","pass":"…","url":"https://….trycloudflare.com","token":"…"}
status
start
stop
```

Bluetooth service `6b1f0001-5a3e-4c8e-9d2a-7a0c52b1e001`: `…0002` info (read), `…0003` settings JSON (encrypted write), `…0004` status (notify), `…0005` start/stop (encrypted write).

### Next hardware phase

Smaller, PopSocket-sized builds: an ESP32-S3 SuperMini on a cable (about Ø36 × 12 mm), a XIAO ESP32S3 with a 200 mAh LiPo (about Ø40 × 15 mm), an M5Stack Atom Echo (about Ø38 × 20 mm), or a custom PCB (about Ø40 × 9 mm).

## Built with

Planned and built with the [Devpost Learn "Build With AI: Basics"](https://learn-ai-basics.devpost.com/) skill pack and Claude Code. The planning documents are in [`devpost/`](devpost/).
