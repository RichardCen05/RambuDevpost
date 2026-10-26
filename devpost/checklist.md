---
doc: checklist
status: approved
---

# Build Checklist

Build mode: fast

## Slices

- [x] **1. A recorded scam call gets flagged with the caller's exact words**
  Becomes usable: Running the backend and feeding it an English test call (the demo's bank-OTP script) prints `high_risk` with "Read it to me now" quoted as evidence; a friendly call stays `low`.
  Why now: This is the kernel's brain and the two riskiest services (local Whisper, the OpenRouter model). Everything else just carries its result around.
  PRD ref: `prd.md > Scam analysis`, `prd.md > Call listening`
  Spec ref: `spec.md > Call pipeline (backend)`, `spec.md > Scam analyzer`, `spec.md > Backend API`, `spec.md > Data Model`, `spec.md > External Services and Dependencies`
  Build: Scaffold `backend/` with uv (FastAPI, faster-whisper, httpx, PyJWT), `.env.example`, SQLite schema, puck session endpoints (start/chunks/end with a dev puck token), masking, transcription, analyzer with strict schema + quote validation + keyword safety net, `scripts/make_samples.sh` (English scam + safe calls via `say`), `scripts/fake_puck.py` (uploads a WAV in 3 s pieces like the puck).
  Verify (mechanical): `uv run pytest` passes (masking, validation, safety net); `fake_puck.py` on the scam sample ends `high_risk` with a verbatim `secret_code` quote containing "Read it to me now"; on the safe sample ends `low` with no evidence.
  Learner check: Run the fake-puck command on both samples and read the result: does the evidence look like what Dimas should see?
  Commit: `Add backend call pipeline with scam analysis`

- [x] **2. A live call next to the Mac reaches the backend by itself (stand-in puck)**
  Becomes usable: `tools/mac_puck.py` listens through the Mac microphone placed beside the parent's iPhone on loudspeaker, starts a session by itself when speech begins, uploads ~3 s pieces through the same puck API, and ends the session after the call goes quiet.
  Why now: The physical puck moved to the next hardware phase; the demo still needs a real call's audio to flow into the pipeline, so the stand-in replaces it before the app's warning loop is built on top.
  PRD ref: `prd.md > Call listening`
  Spec ref: `spec.md > Backend API`, `spec.md > Call pipeline (backend)`, `spec.md > Decisions and Open Issues`
  Build: `tools/mac_puck.py` (mic capture via ffmpeg/avfoundation, energy-based start/stop, upload loop, Enter to end), README note; the ESP32 firmware stays in `firmware/` (compiles, hardware run deferred).
  Verify (mechanical): playing `samples/test-calls/bank-otp-en.wav` out of the Mac speaker near the mic makes `mac_puck.py` start a session on its own and the backend end it `high_risk` with the OTP sentence as evidence; `arduino-cli compile` of the firmware still succeeds.
  Learner check: Call the parent iPhone, answer on speaker next to the Mac, say the OTP line, hang up, and read the transcript the stand-in printed.
  Commit: `Add Mac stand-in puck and puck firmware`

- [x] **3. Parent and caregiver can set up and link in the app**
  Becomes usable: On two simulators, one person finishes parent onboarding and gets a code; the other joins as caregiver; the parent taps Allow; both Homes show each other, in English or Indonesian.
  Why now: The warning loop needs two linked devices with tokens; this also sets up the design system everything else reuses.
  PRD ref: `prd.md > The Core Journey` (steps 1–3), `prd.md > Screens and Layout`, `prd.md > Look and Feel`, `prd.md > Family linking`, `prd.md > Language`
  Spec ref: `spec.md > iOS app — Onboarding`, `spec.md > iOS app — Parent`, `spec.md > iOS app — Caregiver`, `spec.md > Look and Feel`, `spec.md > Backend API`, `spec.md > File Structure`
  Build: XcodeGen project (app, widget, tests), Brand tokens, components, assets (logo, mascot poses, photos, sound), String Catalog en/id, APIClient + Keychain, Welcome (language, roles, Server link), parent steps (tutorial, name, before you begin, invite with countdown + Allow), caregiver steps (code, who are you), Homes, tab bars; backend family/invite/join/allow routes.
  Verify (mechanical): `xcodebuild build test` passes; backend pytest for families passes; two simulators complete the link flow against the local backend; screenshots of each screen captured and compared with `prd.md > Screens and Layout`.
  Learner check: Look at the screenshots (or run the simulators): welcome through both Homes. Does it look and read the way you want?
  Commit: `Add onboarding and family linking`

- [x] **4. A warning reaches both phones mid-call and the caregiver's Scam turns the parent red**
  Becomes usable: Running the scam sample through the fake puck makes the parent simulator get the urgent warning and a Live Activity, the caregiver simulator get "Ratna may be getting scammed" with the evidence, and tapping Scam turns the parent's screen and Live Activity red.
  Why now: This is the kernel's "oh, that's cool" beat; it comes right after the devices can be linked.
  PRD ref: `prd.md > Warnings`, `prd.md > Caregiver decision`, `prd.md > The Core Journey` (steps 5–10)
  Spec ref: `spec.md > Push sender`, `spec.md > Live Activity widget`, `spec.md > iOS app — Caregiver`, `spec.md > iOS app — Shared`, `spec.md > Backend API`
  Build: APNs sender (alert + Live Activity start/update/end, localized copy), push token routes, alerts + decision routes (first wins), PushService, LiveActivityService, widget extension UI, alert detail with Safe confirm/Scam, parent warning + verdict views, Read alerts aloud speech.
  Verify (mechanical): pytest for decision race and push payloads; with the APNs key, fake-puck run delivers pushes to both simulators; screenshots of warning, alert detail, red verdict, Live Activity; second caregiver sees locked state.
  Learner check: Run the fake call yourself, tap Scam on the caregiver simulator, and watch the parent simulator turn red.
  Commit: `Add live warnings, caregiver decision, and Live Activity`

- [x] **5. History, profile, practice, and every failure state**
  Becomes usable: Both sides can browse History and call details, change language/name/read-aloud in Profile, do the practice runs, and see clear states for speaker off, no speech, analysis failed, puck offline, no internet, and call ended.
  Why now: Fills out the supporting features after the end-to-end loop works.
  PRD ref: `prd.md > History`, `prd.md > Practice call (onboarding)`, `prd.md > Issue banners`, `prd.md > States and Boundaries`, `prd.md > Language`
  Spec ref: `spec.md > iOS app — Shared`, `spec.md > iOS app — Parent`, `spec.md > Important Failure Modes`, `spec.md > Backend API`
  Build: history routes + list/detail views, Profile, practice call + sample alert, issue banners, no-speech/failed/ended/locked states, Indonesian strings complete.
  Verify (mechanical): pytest for history and failure states; `xcodebuild test`; String Catalog compiles with no missing `en`/`id`; screenshots of each state in both languages.
  Learner check: Switch the language in Profile, open History, and try the practice call on a fresh install.
  Commit: `Add history, profile, practice, and protection states`

- [x] **6. The demo scene runs for real on two simulators with the stand-in puck**
  Becomes usable: On this Mac, the parent and caregiver apps run in two iOS Simulators against the local backend; a call on loudspeaker next to the Mac is heard by the stand-in puck, both screens get the warning, the caregiver taps Scam, and the parent's screen turns red. `tools/record_demo.sh` records both screens for the video. The README documents setup, the puck's 3D design, parts, wiring, firmware, and pairing.
  Why now: Last, because it packages everything; the rehearsal is the finish line from `scope.md > What "Working" Looks Like`.
  PRD ref: `prd.md > What We're Building`, `prd.md > The Core Journey`
  Spec ref: `spec.md > Where It Runs and How Someone Tries It`
  Build: `tools/record_demo.sh`, README, rehearsal with the demo audio.
  Verify (mechanical): a rehearsal run produces two screen recordings in which the warning and the red verdict appear while the call audio is still playing; the measured OTP-to-warning time is noted.
  Learner check: Watch the two recordings side by side, or run one take yourself with a phone on speaker next to the Mac.
  Commit: `Add demo recording script and README`

## Hands-on Checkpoints

- [x] Early usable behavior explored — after slice 4: the full warning → Scam → red loop on simulators (agent-verified on two simulators; learner hasn't tried it yet)
- [x] Final kick-the-tires exploration and feedback completed — the slice 6 rehearsal on two simulators

## Final Review

- [x] Scam verdict must be an "annoying" danger alarm on the parent's phone (learner feedback) — repeated HANG UP NOW pushes every ~6 s until acknowledged, flashing full-screen red takeover with looping alarm, vibration, and voice; verified on two simulators (5 repeats, stops on I hung up).
- [x] Final review complete — feedback resolved and learner confirms ready to ship

## Code Tour and App Map

- [x] Learning activity complete — guided route, focused alternative, prior practice connected, or brief recap
- [x] Optional edit and transfer reflection addressed — offered/declined/already covered/not applicable as appropriate
- [x] `devpost/app-map.html` generated from finished code, checked, and shown, including a project-grounded practice to reuse

Activity and evidence: brief evidence-based recap (learner asked for speed): the APNs `400 TopicDisallowed` → App ID registration → `200 OK` investigation, and the silent Zoom microphone found via ffmpeg's device list (see Revisions).
Route and stops: reference route only — `AlertDetailView` → `alerts.py decide` / `push.py verdict, _repeat_scam_alarm` → `RambuApp needsHangUp` / `ScamTakeoverView`.
Edit outcome: not applicable (the scam-alarm change came from the learner's final-review feedback).
Reflection: offered in chat; optional.
Activity mode: recap.

## Revisions

- Upload rate is 8 kHz instead of 16 kHz — two 3 s audio buffers at 16 kHz don't fit next to Wi-Fi, TLS, and Bluetooth in the ESP32's RAM; a phone loudspeaker carries only ~300–3400 Hz anyway.
- Firmware logic lives in `puck_main.cpp` — Arduino's prototype generator (ctags) has no Apple Silicon build, and the replacement mangles `.ino` prototypes.
- App copy uses an in-code English/Indonesian table instead of a String Catalog — the language has to switch instantly from Profile without restarting the app.
- Physical puck recording and in-app puck pairing moved to the next hardware phase (learner decision); a Mac stand-in puck using the same API keeps the demo a real call — the learner wants the build faster and the puck integration isn't finished.
- TestFlight cut; both iPhones run the app installed from Xcode (learner decision, for speed). The demo is unchanged.
- Family routes landed with slice 1's backend commit, since the app's linking flow and the backend shipped from the same session.
- Slice 3 was committed before slice 2 — the app was verified while the stand-in puck was being redefined; nothing in slice 3 depends on slice 2.
- The stand-in pairs with the family through the parent's invite code (`POST /api/pucks/claim`) — the dev puck token belongs to no family, so its calls would never reach Ratna's phones. The backend for slice 4 (alerts, decisions, history, APNs, Live Activity pushes) landed in slice 2's commit because the claim route lives with it.
- The stand-in picks the built-in microphone by name — on this Mac input `:0` is a silent Zoom virtual device.
- iOS for slices 4 and 5 was built by two parallel agents on separate branches and merged (learner asked for parallel work to go faster).
- APNs rejected pushes with TopicDisallowed until a device build registered the `id.rambu.app` App ID with push; after that Apple accepts alert and Live Activity start pushes. Live Activity *updates* were skipped on the simulator because no activity push token reached the backend; to check on real iPhones in slice 6. In-app polling shows warnings and verdicts either way.
- Headlines and history titles use the strongest signal (secret code > transfer > app > institution > pressure) instead of the last one heard — the demo's OTP request was showing as "pressuring you".
- The demo runs on two iOS Simulators instead of two iPhones — two iPhones aren't available tonight (learner). The simulators run the same app against the same backend and receive real pushes; on screen they're labelled as simulators. No tunnel is needed since everything runs on this Mac.
- Rehearsal (26 Oct, 21:15): first warning 14 s into the call, Danger about 10 s after the OTP sentence, real APNs alerts on both simulators, verdict turned the parent's screen red. The simulators' read-aloud voice came out of the Mac speakers and the stand-in heard it as a new call; the README now says to mute read-aloud while recording on one Mac.
