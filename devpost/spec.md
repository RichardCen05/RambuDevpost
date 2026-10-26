---
doc: spec
status: approved
---

# Rambu — Technical Spec

## How This Works, In Plain Language
Rambu has four pieces.

1. **The puck** (ESP32 + mic) is paired with the parent's iPhone over Bluetooth. iOS tells paired accessories about notifications through a built-in service called **ANCS** (Apple Notification Center Service), and an answered phone call shows up there as an "active call". When that appears, the puck turns on its blue light, records the loudspeaker sound in short pieces, and uploads each piece over Wi-Fi to the backend. When the call disappears from ANCS, it stops. The Rambu app doesn't need to be open.
2. **The backend** is a small Python server running on Richard's Mac. For every audio piece it turns speech into text with **Whisper** (running on the Mac itself), masks digits, and asks an **OpenAI model through OpenRouter** to rate the call so far: level, signals, and exact quotes. It keeps families, calls, alerts, and decisions in one **SQLite** file, a spreadsheet-like file on the Mac.
3. **A Cloudflare quick tunnel** gives the Mac a public HTTPS address, so the puck and both iPhones can reach it from anywhere. The address changes when the tunnel restarts, so it's typed into the app's settings and passed on to the puck.
4. **The iPhone app** (SwiftUI) has a parent side and a caregiver side. The backend sends **push notifications** through Apple (APNs): warnings, the caregiver's verdict, and updates to the parent's **Live Activity** on the Lock Screen and Dynamic Island. A caregiver's **Scam/Safe** tap goes to the backend, which pushes it to the parent immediately.

Why this shape: the puck already exists, the Mac is fast enough (Apple M5, 24 GB) to transcribe locally for free, and one backend with one database file is the least that can coordinate two phones and a puck in real time. There's no separate AI workflow service: the backend calls the model directly.

## The Core Journey Through the System
PRD ref: `prd.md > The Core Journey`.

**Setup**
1. Parent picks language and role → app calls `POST /api/families` → backend creates the family and a parent device, returns a device token (kept in the iPhone Keychain) and a six-digit invite code.
2. **Find puck** → app scans over Bluetooth for "Rambu Puck", connects, and iOS shows the pairing prompt (bonding is required for ANCS). App calls `POST /api/pucks` → gets a puck ID + puck token → writes `{ssid, password, serverURL, puckID, puckToken}` to the puck's config characteristic. The puck joins Wi-Fi, calls `POST /api/puck/hello`, and notifies "online" back over Bluetooth.
3. Caregiver enters the code → `POST /api/families/join` → a pending caregiver device. The parent app polls `GET /api/family` on the invite screen and shows the request → **Allow** → `POST /api/family/members/{id}/allow`.
4. Both apps register their APNs device token (and the parent its Live Activity push-to-start token) with `PUT /api/devices/me/push`.

**A real call**
5. Parent answers on speaker → iOS posts an ANCS "active call" → puck calls `POST /api/puck/sessions` → backend creates a session and sends a Live Activity **start** push to the parent ("Rambu is listening").
6. Every ~3 s the puck uploads a WAV piece to `POST /api/puck/sessions/{id}/chunks`. Backend: Whisper → mask → append to transcript → OpenRouter analysis (`live` mode) on the transcript so far.
7. When the level first rises to `needs_review` or `high_risk` (or rises again), backend creates or updates the alert, then in one go: alert push to the parent (urgent sound, time-sensitive), alert push to every active caregiver, and a Live Activity **update** to amber/red with the signal headline.
8. Caregiver taps the push → app opens `GET /api/alerts/{id}` → **Scam** → `POST /api/alerts/{id}/decision`. First write wins (checked in one SQL transaction); later callers get the existing decision back.
9. Backend pushes the verdict to the parent (alert push + Live Activity update to red "Dimas says this is a scam. Hang up."). The other caregivers get a quiet update so their screen locks.
10. Parent hangs up → ANCS call removed → puck sends its last piece and `POST /api/puck/sessions/{id}/end` → backend runs one `final` analysis on the whole transcript, stores the call record, and sends a Live Activity **end**. Both apps' History lists (`GET /api/history`) now show it.

## Stack
| Part | Choice | Docs |
|---|---|---|
| iOS app | Swift 6, SwiftUI, iOS 26.0+, Xcode 27.1, XcodeGen project | [SwiftUI](https://developer.apple.com/documentation/swiftui), [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| Live Activity | ActivityKit + WidgetKit extension, updated by push | [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications) |
| Bluetooth (app) | CoreBluetooth central | [CoreBluetooth](https://developer.apple.com/documentation/corebluetooth) |
| Notifications | UserNotifications + APNs (token auth, `.p8` key) | [APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns) |
| Copy in 2 languages | String Catalog (`Localizable.xcstrings`), `en` + `id` | [String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) |
| Spoken alerts | AVSpeechSynthesizer | [AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer) |
| Backend | Python 3.12, FastAPI, uvicorn, managed with `uv` | [FastAPI](https://fastapi.tiangolo.com) |
| Storage | SQLite (stdlib `sqlite3`), one file | [sqlite3](https://docs.python.org/3/library/sqlite3.html) |
| Speech to text | faster-whisper, multilingual `small` model on CPU, int8; switch to a larger model if accuracy is poor | [faster-whisper](https://github.com/SYSTRAN/faster-whisper) |
| Scam analysis | OpenRouter chat completions with an OpenAI model and a strict JSON schema | [OpenRouter API](https://openrouter.ai/docs/api-reference/chat-completion), [structured outputs](https://openrouter.ai/docs/features/structured-outputs) |
| APNs client | `httpx` (HTTP/2) + `PyJWT` (ES256) | [httpx](https://www.python-httpx.org), [PyJWT](https://pyjwt.readthedocs.io) |
| Public address | Cloudflare Tunnel (`cloudflared`) | [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) |
| Puck firmware | Arduino core for ESP32 (3.x), `ESP_I2S`, `WiFiClientSecure`/`HTTPClient`, `Preferences`, NimBLE-Arduino 2.x (peripheral + ANCS client); built with `arduino-cli` | [arduino-esp32](https://docs.espressif.com/projects/arduino-esp32/), [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino), [ANCS spec](https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/Specification/Specification.html) |
| Distribution | TestFlight, Richard's Apple Developer team, internal testing | [TestFlight](https://developer.apple.com/testflight/) |

**Verify early in the build (not checked yet):** the exact OpenAI model ID on OpenRouter that supports `json_schema` structured output; that ANCS reports an answered cellular call as category `ActiveCall` (12) on iOS 26/27; that the ESP32 has enough RAM for TLS plus double-buffered 3 s audio.

## Where It Runs and How Someone Tries It
- **Backend:** Richard's Mac. `uv run --project backend uvicorn rambu.main:app --host 127.0.0.1 --port 8001 --env-file backend/.env`. Needs `backend/.env` (from `.env.example`): `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`, `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_KEY_PATH`, `APNS_BUNDLE_ID`, `APNS_ENV` (`sandbox` for Xcode builds, `production` for TestFlight), `WHISPER_MODEL`, `DATABASE_PATH`.
- **Public address:** a Cloudflare **quick tunnel** on this Mac: `cloudflared tunnel --url http://localhost:8001` prints a `https://<random>.trycloudflare.com` address. It changes every time the tunnel restarts, so the app keeps it as a setting: **Server address** in Profile, also reachable from a small **Server** link on Welcome (needed before the family is created). Saving a new address on the parent's phone re-sends it to the puck over Bluetooth. Both iPhones must use the same address.
- **Puck:** wire per README, then `arduino-cli compile/upload` the `firmware/rambu-puck` sketch once. Powered from USB-C.
- **iPhones:** installed from Xcode (Richard's team, sandbox APNs) on Richard's iPhone (caregiver, "Dimas") and Zahra's iPhone (parent, "Ratna"). During development, the simulator.
- **Stand-in puck:** `uv run --project backend python tools/mac_puck.py --server <address>` on a Mac placed beside the parent's iPhone on loudspeaker. It uses the puck API with the dev puck token.
- **Demo recording:** the 60-second scene from `scope.md > What "Working" Looks Like`, both iPhones in English. Mac on, tunnel up, puck on Wi-Fi.
- **Deployment:** none. The Mac + tunnel only runs while testing or recording. TestFlight was considered at ship time and skipped: a public link needs Beta App Review, and testers couldn't use the app without the Mac backend and a puck.
- **Sharing:** public repository https://github.com/RichardCen05/RambuDevpost (MIT). Demo video: recorded on two simulators, link to be added once uploaded.

## Look and Feel
From `prd.md > Look and Feel`, as SwiftUI tokens in `Brand.swift`:
- Colors: teal `#006F63` / bright `#00937F` / deep `#054F47` / soft `#E2F2EF`; ink `#0F2A29` / `#3B5250` / `#5B716F`; canvas `#F2F6F5`; hairline `#DCE7E4`; amber `#F4B400` / `#FFF3C7` / ink `#5A4100`; red `#D2372C` / `#FDE6E3` / ink `#9E1F15`; green `#1E8259` / `#E4F3EC` / ink `#14603F`; puck cream `#F4F0E6`.
- Type: SF Pro Rounded, bold for titles (`.largeTitle`/`.title` bold), regular body; Dynamic Type respected.
- Shapes: white cards with 20 pt corner radius on the canvas, capsule buttons 56 pt tall, SF Symbols in teal rounded squares, floating pill tab bar.
- Mascot: image assets for six poses (wave, calm, stop, check, happy, rest) and a sign badge per level; used in alerts, Live Activity, and empty states.
- Copy: short, warm, plain; second person; never says "definitely a scammer".
- Assets (the learner's own, used as is): logo/wordmark, app icon, mascot pose images, puck renders, welcome/guardian/speaker-call photos, `rambu-urgent.caf`, sample call audio.

## Components

### Puck firmware
Implements `prd.md > Puck pairing and Wi-Fi`, `prd.md > Call listening`.
- **BLE peripheral** named "Rambu Puck", Just Works bonding. Custom service with: `info` (read: puck ID, firmware version), `config` (encrypted write: JSON `{ssid, pass, url, puckId, token}`; saved to flash with `Preferences`), `status` (notify: `wifi_ok`, `wifi_fail`, `online`, `recording`), `command` (encrypted write: `start`/`stop`, fallback trigger from the app).
- **ANCS client** on the bonded iPhone: subscribes to Notification Source. `ActiveCall` added → start; removed → stop. `IncomingCall` → arm (no recording until answered).
- **Recorder:** INMP441 over I2S, 16 kHz, 16-bit mono (SD=GPIO32, SCK=GPIO33, WS=GPIO25; L/R to GND). Double buffer of ~3 s each; one fills while the other uploads.
- **Uploader:** HTTPS POST of each piece as WAV with `Authorization: Bearer <puckToken>`; retries once; drops a piece rather than stalling.
- **LED:** on-board blue LED (GPIO2) on while recording; slow blink while not on Wi-Fi.

### Stand-in puck (Mac)
Implements `prd.md > Call listening` for this submission while the hardware is in its next phase.
Records the Mac microphone at 16 kHz with ffmpeg (avfoundation), starts a session when speech energy stays above a threshold for ~1 s, uploads 3 s WAV pieces to the same endpoints as the puck, and ends the session after ~6 s of quiet or on Enter.

### Backend API
Implements `prd.md > Family linking`, `prd.md > History`, `prd.md > Caregiver decision`.
FastAPI routes; every app call carries `Authorization: Bearer <deviceToken>`, every puck call `Bearer <puckToken>`. Tokens are random 32-byte strings, stored hashed.

| Method & path | Who | Does |
|---|---|---|
| `POST /api/families` | parent app | `{name, language}` → `{deviceToken, familyId, invite:{code, expiresAt}}` |
| `POST /api/families/invite` | parent | renews the code (valid 15 min) |
| `POST /api/families/join` | caregiver app | `{code, name, relationship, language}` → `{deviceToken, status:"pending"}`; wrong/expired code → 404/410 |
| `GET /api/family` | both | family, members with status, invite, puck status |
| `POST /api/family/members/{id}/allow` | parent | pending → active |
| `PUT /api/devices/me` | both | update name, relationship, language |
| `PUT /api/devices/me/push` | both | `{apnsToken, liveActivityStartToken?, liveActivityUpdateToken?, environment}` |
| `POST /api/pucks` | parent | → `{puckId, puckToken}` |
| `POST /api/puck/hello` | puck | marks online, firmware version |
| `POST /api/puck/sessions` | puck | → `{sessionId}`; starts the parent's Live Activity |
| `POST /api/puck/sessions/{id}/chunks` | puck | body `audio/wav`; runs the pipeline; → `{level}` |
| `POST /api/puck/sessions/{id}/end` | puck | final analysis, record, Live Activity end |
| `GET /api/alerts`, `GET /api/alerts/{id}` | both | alerts (caregivers get evidence only) |
| `POST /api/alerts/{id}/decision` | caregiver | `{verdict:"scam"\|"safe"}` → `{decision, accepted:bool}` |
| `GET /api/history`, `GET /api/history/{id}` | both | call records; parent also gets the masked transcript |
| `GET /health` | anyone | `{"ok":true}` |

### Call pipeline (backend)
Implements `prd.md > Call listening`, `prd.md > Scam analysis`, `prd.md > Warnings`.
Per chunk: decode WAV → skip if silent (RMS below a threshold) → Whisper with the session's language → **mask** (digit runs ≥3 become `•••`, spelled-out code digits too) → append segment → analysis on the full masked transcript (`live`) → compare with the session's highest level → if higher than before and ≥ `needs_review`, raise/update the alert and send pushes. Chunks are processed in order per session (one worker per session) so the transcript stays in sequence. On end: one `final` analysis; no speech at all → `no_speech`; any transcription/model failure → `failed` with the reason. A failure never turns into `low`.

### Scam analyzer
Implements `prd.md > Scam analysis`.
- One system prompt, written fresh, with the session language (`en`/`id`): rate only what's in the transcript; levels `low` / `needs_review` / `high_risk`; the five signals; warnings and refusals aren't requests; "read me the SMS you just got" counts as `secret_code`; never claim certainty; reply in the session language.
- Strict JSON schema: `{risk_level, signals[], evidence[{quote, signals[]}], explanation, recommended_action}`.
- **Validation in code** after the reply: each `quote` must appear verbatim in the transcript (else dropped); `signals` = union of evidence signals; `low` ⇒ empty lists; non-low with no surviving evidence ⇒ `low`. Invalid JSON ⇒ one retry, then the chunk counts as an analysis failure.
- **Bilingual safety net:** a small keyword check (OTP, PIN, password, kode, "bacakan", "read it to me") that lifts a `low` live result to `needs_review` with `secret_code` and the matching sentence as evidence, so the demo's key line can't slip through on a bad model reply.

### Push sender
Implements `prd.md > Warnings`, `prd.md > Caregiver decision`.
APNs over HTTP/2 with a cached ES256 JWT. Three kinds:
- **Alert push** (`apns-push-type: alert`, `interruption-level: time-sensitive`, sound `rambu-urgent.caf` for warnings): payload has `alertId`, `kind` (`warning`/`verdict`/`locked`), text localized per recipient's language from `i18n.py`.
- **Live Activity** (`apns-push-type: liveactivity`, topic `<bundle>.push-type.liveactivity`): `start` via the push-to-start token with attributes `{parentName, startedAt}`; `update`/`end` via the activity's update token (the app reports it with `PUT /api/devices/me/push` when iOS hands it over). Content state `{level, headline, decidedBy?, verdict?}`.
- Sandbox vs production host chosen per device from the `environment` it registered with.

### iOS app — Onboarding
Implements `prd.md > Screens and Layout` (onboarding), `prd.md > Language`, `prd.md > Practice call (onboarding)`.
Step-based flow with progress bar; welcome → role branch. Practice call is a local, clearly labeled simulation (no network, no history).

### iOS app — Parent
Implements Parent Home and Puck tab in `prd.md > Screens and Layout`, `prd.md > Issue banners`.
Home refreshes `GET /api/family` and `GET /api/history` on appear and on push; issue banners from notification permission, network path monitor, Bluetooth state, and puck status. Puck tab uses `PuckManager` (CoreBluetooth) for pairing and the Wi-Fi write.

### iOS app — Caregiver
Implements Caregiver Home and Alert detail in `prd.md > Screens and Layout`, `prd.md > Caregiver decision`.
Notification tap → deep link to alert detail. **Safe** shows a confirm sheet; **Scam** submits at once. Locked state when a decision exists and isn't theirs.

### iOS app — Shared
History list/detail, Profile (family, notifications, Read alerts aloud, language, name, relationship), `SpeechService` (speaks warnings in the app language when the toggle is on), `APIClient`, `PushService`, `LiveActivityService` (requests the push-to-start token, forwards update tokens).

### Live Activity widget
Implements the Live Activity in `prd.md > Screens and Layout`.
Lock Screen card + Dynamic Island (compact, expanded) with mascot pose by level, headline, verdict, timer.

## Data Model
SQLite, times as ISO 8601 UTC strings (e.g. `2026-10-26T10:41:07Z`).

| Table | Fields |
|---|---|
| `families` | `id`, `created_at` |
| `devices` | `id`, `family_id`, `role` (`parent`/`caregiver`), `status` (`pending`/`active`), `name`, `relationship`, `language` (`en`/`id`), `token_hash`, `apns_token`, `apns_env`, `la_start_token`, `la_update_token`, `created_at` |
| `invites` | `code`, `family_id`, `expires_at` |
| `pucks` | `id`, `family_id`, `token_hash`, `firmware`, `last_seen_at` |
| `sessions` | `id`, `family_id`, `puck_id`, `language`, `status` (`listening`/`completed`/`no_speech`/`failed`), `failure_reason`, `started_at`, `ended_at`, `level`, `signals` (JSON), `evidence` (JSON) |
| `segments` | `session_id`, `seq`, `offset_s`, `text_masked` |
| `alerts` | `id`, `session_id`, `level`, `signals` (JSON), `evidence` (JSON), `raised_at`, `verdict`, `decided_by`, `decided_at`, `call_ended` |

Example evidence (synthetic): `[{"quote":"Read it to me now, before the money leaves.","signals":["secret_code","urgency"]}]`.

**Where things live**
- **On the iPhone:** device token (Keychain); role, name, language, Read-aloud toggle, onboarding done, server URL (UserDefaults). Leaving and returning keeps all of it; everything else is fetched fresh from the backend.
- **On the Mac:** everything shared (families, calls, alerts, decisions) in `backend/data/rambu.sqlite3`. Survives restarts. Raw audio is processed in memory and never written to disk.
- **On the puck:** Wi-Fi, server URL, puck ID/token in flash (survive power-off). Re-pairing overwrites them.

## File Structure
```
RambuDevpost/
├── README.md                     # what Rambu is, setup, puck build (BOM, wiring, 3D print), demo
├── backend/
│   ├── pyproject.toml            # uv project
│   ├── .env.example              # every setting, no secrets
│   ├── rambu/
│   │   ├── main.py               # FastAPI app and routes
│   │   ├── config.py             # settings from env
│   │   ├── db.py                 # schema + queries
│   │   ├── auth.py               # token issue/check
│   │   ├── families.py           # create, join, allow, invites
│   │   ├── pipeline.py           # per-session chunk worker
│   │   ├── transcribe.py         # faster-whisper wrapper
│   │   ├── mask.py               # digit masking
│   │   ├── analyze.py            # OpenRouter call + validation + safety net
│   │   ├── prompt.md             # analysis instructions
│   │   ├── push.py               # APNs alert + Live Activity
│   │   └── i18n.py               # push copy in en/id
│   ├── scripts/
│   │   ├── fake_puck.py          # streams a WAV file through the API like the puck
│   │   └── make_samples.sh       # builds English test calls with macOS `say`
│   ├── data/                     # SQLite file (git-ignored)
│   └── tests/                    # pytest: masking, validation, decision race, API
├── firmware/
│   └── rambu-puck/
│       ├── rambu-puck.ino        # setup/loop, state machine
│       ├── ble_link.h/.cpp       # peripheral service + ANCS client
│       ├── recorder.h/.cpp       # I2S double buffer
│       └── uploader.h/.cpp       # Wi-Fi + HTTPS
├── ios/
│   ├── project.yml               # XcodeGen: app, widget extension, tests
│   ├── Rambu/
│   │   ├── App/                  # entry point, app delegate (push), root router
│   │   ├── DesignSystem/         # Brand tokens, buttons, cards, risk badges, mascot view
│   │   ├── Onboarding/           # welcome, parent steps, caregiver steps, practice
│   │   ├── Parent/               # home, puck tab, banners
│   │   ├── Caregiver/            # home, alert detail
│   │   ├── Common/               # history, call detail, profile
│   │   ├── Services/             # APIClient, PuckManager, PushService, LiveActivityService, SpeechService
│   │   ├── Models/               # API types, app settings
│   │   └── Resources/            # Assets.xcassets, Localizable.xcstrings, rambu-urgent.caf
│   ├── RambuWidgets/             # Live Activity UI
│   ├── Shared/                   # ActivityAttributes, Brand colors (app + widget)
│   └── RambuTests/
├── hardware/
│   ├── puck-body.stl, puck-lid.stl
│   ├── wiring.png, previews/*.png
│   └── puck.py                   # Blender source for the case
├── samples/                      # sample call audio (scam + safe)
├── tools/mac_puck.py             # stand-in puck: Mac mic → puck API
└── devpost/                      # planning docs
```

## External Services and Dependencies
- **OpenRouter** — `POST https://openrouter.ai/api/v1/chat/completions`, header `Authorization: Bearer $OPENROUTER_API_KEY`; body `{model, messages:[system, user(JSON {transcript, mode, language})], response_format:{type:"json_schema", json_schema:{name:"rambu_risk", strict:true, schema}}, temperature:0}`; reply in `choices[0].message.content`. Pay per token; one call per ~3 s of speech during a call (a 60 s call ≈ 20 small calls). Key already available.
- **Apple Push Notification service** — `POST https://api.sandbox.push.apple.com/3/device/<token>` (or `api.push.apple.com`), headers `authorization: bearer <JWT>`, `apns-topic`, `apns-push-type`, `apns-priority: 10`. Needs an APNs Auth Key (`.p8`, git-ignored) from Richard's team, plus capabilities: Push Notifications, Time Sensitive Notifications. Free.
- **Cloudflare quick tunnel** — free, no account; `brew install cloudflared`. No uptime guarantee and a new address on every restart. [Quick tunnels](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/do-more-with-tunnels/trycloudflare/)
- **faster-whisper** — local; downloads the model once (~500 MB for `small`). Free.
- **App Store Connect / TestFlight** — Richard's team; bundle IDs `id.rambu.app` and `id.rambu.app.widgets` (change if taken); internal testing needs no review.
- **Tools to install:** `brew install arduino-cli cloudflared`; ESP32 core and NimBLE-Arduino via `arduino-cli`.

## Important Failure Modes
- **ANCS doesn't fire on answer** (call category differs, bond lost) → puck LED stays off. Fallback: the app, when open, tells the puck to start through the `command` characteristic. Checked first in the build.
- **Model reply slow or broken** → retry once, keyword safety net still raises `secret_code`; if both fail the call ends as "Call analysis failed", never Safe.
- **Mac or tunnel down** → puck uploads fail, app shows "The Rambu server could not be reached"; History marks the call Could not assess.
- **Push not delivered** (wrong APNs environment) → the app refreshes alerts and history whenever it's opened, so nothing is lost; `APNS_ENV` must be `production` for TestFlight builds.

## What Was Simplified and Why
- **Mac + Cloudflare quick tunnel** instead of a cloud server or a fixed hostname — no accounts, free, the Mac is fast enough; the cost is a Server address setting in the app and re-sending it to the puck after a tunnel restart. A permanent version would use a named tunnel on a fixed hostname, or a container host plus a paid transcription API.
- **Backend calls the model directly** instead of a separate AI-workflow service — one service and one failure point fewer.
- **Local Whisper** instead of a paid transcription API — free, and audio never leaves the Mac.
- **Device tokens instead of accounts** — joining with a six-digit code and a parent's Allow is enough to keep families apart; no passwords or sign-in.
- **Refreshing the family/invite screen** instead of live sockets — pushes carry the urgent moments; screens refresh on open and on push.
- **Mascot as image assets** instead of drawn-in-code animation — same artwork, much less code.

## Decisions and Open Issues
**Learner decisions**
- AI through **OpenRouter with an OpenAI model**; backend on **this Mac behind a Cloudflare quick tunnel**, address set in the app; TestFlight and APNs on **Richard's Apple Developer team**.
- English for the demo, Indonesian fully supported (`prd.md > Product Decisions`).
- Puck stays prototype v3 on USB-C power (`scope.md > The POC Boundary`).

**Recommended here, accepted by approving this spec**
- No separate AI-workflow service; backend calls OpenRouter directly with a strict JSON schema plus code validation.
- Speech to text with local faster-whisper on the Mac.
- Puck detects calls through ANCS, so the app can stay closed.

**Useful unknown:** how the puck can know a phone call was answered when an iPhone app can't hear calls. Clarified: iOS shares notification events, including active calls, with bonded Bluetooth accessories through ANCS. The puck listens to that, not to the app. Checked as the first build step with a real call and the puck's serial log.

**Open, to settle at the start of the build**
- Public address decided (learner): a quick tunnel on this Mac with the address set in the app, not a fixed hostname. The address is only needed for testing and recording; the submission is the video and the public repo.
- Exact OpenRouter model ID (see Stack).
- Zahra added to Richard's App Store Connect team as an internal tester.
- Measured warning time from the OTP sentence (`prd.md > Open Questions`).
