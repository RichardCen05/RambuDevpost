---
doc: checklist
status: approved
---

# Build Checklist

Build mode: fast

## Slices

- [ ] **1. A recorded scam call gets flagged with the caller's exact words**
  Becomes usable: Running the backend and feeding it an English test call (the demo's bank-OTP script) prints `high_risk` with "Read it to me now" quoted as evidence; a friendly call stays `low`.
  Why now: This is the kernel's brain and the two riskiest services (local Whisper, the OpenRouter model). Everything else just carries its result around.
  PRD ref: `prd.md > Scam analysis`, `prd.md > Call listening`
  Spec ref: `spec.md > Call pipeline (backend)`, `spec.md > Scam analyzer`, `spec.md > Backend API`, `spec.md > Data Model`, `spec.md > External Services and Dependencies`
  Build: Scaffold `backend/` with uv (FastAPI, faster-whisper, httpx, PyJWT), `.env.example`, SQLite schema, puck session endpoints (start/chunks/end with a dev puck token), masking, transcription, analyzer with strict schema + quote validation + keyword safety net, `scripts/make_samples.sh` (English scam + safe calls via `say`), `scripts/fake_puck.py` (uploads a WAV in 3 s pieces like the puck).
  Verify (mechanical): `uv run pytest` passes (masking, validation, safety net); `fake_puck.py` on the scam sample ends `high_risk` with a verbatim `secret_code` quote containing "Read it to me now"; on the safe sample ends `low` with no evidence.
  Learner check: Run the fake-puck command on both samples and read the result: does the evidence look like what Dimas should see?
  Commit: `Add backend call pipeline with scam analysis`

- [ ] **2. The real puck records a real phone call by itself**
  Becomes usable: With the puck bonded to the parent's iPhone, answering a call on speaker turns the blue LED on, the backend receives audio and builds a transcript, and hanging up ends the session.
  Why now: ANCS call detection and ESP32 memory are the biggest unknowns in the spec; if either fails, the plan changes, so it has to be known before the app is built around it.
  PRD ref: `prd.md > Call listening`
  Spec ref: `spec.md > Puck firmware`, `spec.md > Where It Runs and How Someone Tries It`, `spec.md > Decisions and Open Issues`
  Build: `firmware/rambu-puck/` (BLE peripheral + bonding, ANCS client, I2S double buffer, HTTPS uploader, LED, `Preferences`), temporary USB-serial `config` command for Wi-Fi/server/token until slice 5, quick-tunnel note, install `arduino-cli` + `cloudflared`.
  Verify (mechanical): `arduino-cli compile` succeeds; serial log on a real call shows `ActiveCall added → recording → chunk 200 … → ActiveCall removed → session end`; backend shows the session with a transcript.
  Learner check: Call the parent iPhone, answer on speaker, watch the LED, say the OTP line, hang up, then read the transcript the backend printed.
  Commit: `Add puck firmware with call detection and audio upload`

- [ ] **3. Parent and caregiver can set up and link in the app**
  Becomes usable: On two simulators, one person finishes parent onboarding and gets a code; the other joins as caregiver; the parent taps Allow; both Homes show each other, in English or Indonesian.
  Why now: The warning loop needs two linked devices with tokens; this also sets up the design system everything else reuses.
  PRD ref: `prd.md > The Core Journey` (steps 1–3), `prd.md > Screens and Layout`, `prd.md > Look and Feel`, `prd.md > Family linking`, `prd.md > Language`
  Spec ref: `spec.md > iOS app — Onboarding`, `spec.md > iOS app — Parent`, `spec.md > iOS app — Caregiver`, `spec.md > Look and Feel`, `spec.md > Backend API`, `spec.md > File Structure`
  Build: XcodeGen project (app, widget, tests), Brand tokens, components, assets (logo, mascot poses, photos, sound), String Catalog en/id, APIClient + Keychain, Welcome (language, roles, Server link), parent steps (tutorial, name, before you begin, invite with countdown + Allow), caregiver steps (code, who are you), Homes, tab bars; backend family/invite/join/allow routes.
  Verify (mechanical): `xcodebuild build test` passes; backend pytest for families passes; two simulators complete the link flow against the local backend; screenshots of each screen captured and compared with `prd.md > Screens and Layout`.
  Learner check: Look at the screenshots (or run the simulators): welcome through both Homes. Does it look and read the way you want?
  Commit: `Add onboarding and family linking`

- [ ] **4. A warning reaches both phones mid-call and the caregiver's Scam turns the parent red**
  Becomes usable: Running the scam sample through the fake puck makes the parent simulator get the urgent warning and a Live Activity, the caregiver simulator get "Ratna may be getting scammed" with the evidence, and tapping Scam turns the parent's screen and Live Activity red.
  Why now: This is the kernel's "oh, that's cool" beat; it comes right after the devices can be linked.
  PRD ref: `prd.md > Warnings`, `prd.md > Caregiver decision`, `prd.md > The Core Journey` (steps 5–10)
  Spec ref: `spec.md > Push sender`, `spec.md > Live Activity widget`, `spec.md > iOS app — Caregiver`, `spec.md > iOS app — Shared`, `spec.md > Backend API`
  Build: APNs sender (alert + Live Activity start/update/end, localized copy), push token routes, alerts + decision routes (first wins), PushService, LiveActivityService, widget extension UI, alert detail with Safe confirm/Scam, parent warning + verdict views, Read alerts aloud speech.
  Verify (mechanical): pytest for decision race and push payloads; with the APNs key, fake-puck run delivers pushes to both simulators; screenshots of warning, alert detail, red verdict, Live Activity; second caregiver sees locked state.
  Learner check: Run the fake call yourself, tap Scam on the caregiver simulator, and watch the parent simulator turn red.
  Commit: `Add live warnings, caregiver decision, and Live Activity`

- [ ] **5. The parent pairs the puck from the app**
  Becomes usable: In onboarding or the Puck tab, Find puck pairs the real puck, sends it Wi-Fi and the server address, and the tab shows it online; changing the Server address re-sends it.
  Why now: Replaces slice 2's serial setup with the real experience once the puck protocol is proven.
  PRD ref: `prd.md > Puck pairing and Wi-Fi`
  Spec ref: `spec.md > Puck firmware`, `spec.md > iOS app — Parent`
  Build: PuckManager (scan, bond, config write, status notify, command fallback), Attach puck + Puck Wi-Fi steps, Puck tab, backend puck registration/hello, server-address re-send.
  Verify (mechanical): device build installs on the parent iPhone; pairing completes; backend logs `/api/puck/hello`; Puck tab shows online; a real call still records.
  Learner check: Forget the puck in Bluetooth settings, pair it again from the app, then make a test call.
  Commit: `Add puck pairing and Wi-Fi setup from the app`

- [ ] **6. History, profile, practice, and every failure state**
  Becomes usable: Both sides can browse History and call details, change language/name/read-aloud in Profile, do the practice runs, and see clear states for speaker off, no speech, analysis failed, puck offline, no internet, and call ended.
  Why now: Fills out the supporting features after the end-to-end loop works.
  PRD ref: `prd.md > History`, `prd.md > Practice call (onboarding)`, `prd.md > Issue banners`, `prd.md > States and Boundaries`, `prd.md > Language`
  Spec ref: `spec.md > iOS app — Shared`, `spec.md > iOS app — Parent`, `spec.md > Important Failure Modes`, `spec.md > Backend API`
  Build: history routes + list/detail views, Profile, practice call + sample alert, issue banners, no-speech/failed/ended/locked states, Indonesian strings complete.
  Verify (mechanical): pytest for history and failure states; `xcodebuild test`; String Catalog compiles with no missing `en`/`id`; screenshots of each state in both languages.
  Learner check: Switch the language in Profile, open History, and try the practice call on a fresh install.
  Commit: `Add history, profile, practice, and protection states`

- [ ] **7. Both iPhones run the TestFlight build and the demo scene works for real**
  Becomes usable: The TestFlight build on Richard's and Zahra's iPhones runs the full 60-second demo with the real puck; the README documents setup, the puck's 3D design, parts, wiring, firmware, and pairing.
  Why now: Last, because it packages everything; the rehearsal is the finish line from `scope.md > What "Working" Looks Like`.
  PRD ref: `prd.md > What We're Building`, `prd.md > The Core Journey`
  Spec ref: `spec.md > Where It Runs and How Someone Tries It`, `spec.md > External Services and Dependencies`
  Build: production APNs setting, app icon/version, archive + upload, internal testers, README + `hardware/` files, final pass on copy.
  Verify (mechanical): archive and upload succeed; build appears in TestFlight; rehearsal measures the OTP-to-warning time and both screens behave as in the demo script.
  Learner check: Do one full take of the demo script with Zahra and the puck.
  Commit: `Prepare TestFlight build and README`

## Hands-on Checkpoints

- [ ] Early usable behavior explored — after slice 4: the full warning → Scam → red loop on simulators
- [ ] Final kick-the-tires exploration and feedback completed — the slice 7 rehearsal on real devices

## Final Review

- [ ] Final review complete — feedback resolved and learner confirms ready to ship

## Code Tour and App Map

- [ ] Learning activity complete — guided route, focused alternative, prior practice connected, or brief recap
- [ ] Optional edit and transfer reflection addressed — offered/declined/already covered/not applicable as appropriate
- [ ] `devpost/app-map.html` generated from finished code, checked, and shown, including a project-grounded practice to reuse

Activity and evidence:
Route and stops:
Edit outcome:
Reflection:
Activity mode:

## Revisions
