---
doc: prd
status: approved
---

# Rambu — Product Requirements

Rambu warns older parents about scam phone calls. A puck stuck to the back of the parent's iPhone hears the call on loudspeaker, AI flags scam signals with the caller's exact words as evidence, and the parent and their caregivers (usually a grown child in another city) are warned at the same time. One caregiver decides "scam" or "safe", and that verdict reaches the parent while the call is still going.
Source: `scope.md > The Unique Kernel`, `scope.md > Who It's For`.

## The Core Journey
Source: `scope.md > The Core Loop`, `scope.md > What "Working" Looks Like`.

**Setup (once)**
1. The parent opens Rambu, picks a language (English or Bahasa Indonesia), and taps **I am the protected parent**.
2. A short tutorial explains the puck, then the parent enters their name, pairs the puck over Bluetooth, gives it the home Wi-Fi, and reads **Before you begin**: use speakerphone, family sees relevant excerpts, alerts arrive as notifications, Rambu never hangs up.
3. The parent gets a six-digit invite code to share. The caregiver installs Rambu, taps **I am a caregiver**, enters the code, their name and relationship. The parent taps **Allow** on the incoming request.
4. Each side does a practice run: the parent answers a practice call and taps the practice warning; the caregiver makes a decision on a sample alert.

**A real call**
5. A regular phone call reaches the parent's iPhone. She answers and turns on speakerphone. The puck's light turns on and it starts listening by itself.
6. While the call is low risk, nothing interrupts her. Rambu's Live Activity on the Lock Screen and Dynamic Island shows "Rambu is listening" with the call timer.
7. When the caller's words show scam signals, the parent's iPhone vibrates with an urgent sound and a warning ("The caller is asking for a secret code"), and at the same moment every caregiver gets a push: "Ratna may be getting scammed".
8. The caregiver opens the alert and sees the flagged sentences, each labeled with its signal, then taps **Scam** or **Safe**.
9. The verdict reaches the parent right away. **Scam** turns her Live Activity and app red with "Your son says this is a scam. Hang up." **Safe** shows a calm confirmation.
10. She hangs up. The puck stops. The call lands in **History** on both phones with its result and the caregiver's decision.

**Success:** the 60-second demo scene in `scope.md > What "Working" Looks Like` runs live, in English, on the real puck and two iPhones, with no mock screens.

## Screens and Layout

Bottom tab bar, floating pill style.

**Parent:** Home · History · Puck. Profile opens from the avatar at top right.
**Caregiver:** Home · History. Profile opens from the avatar.

**Onboarding (shared start)**
- **Welcome:** full-bleed photo of an older woman on a worried phone call, Rambu logo pill at top, a sample Rambu notification overlaid ("Danger: possible scam · Sent to …"), headline "Help your family recognize phone scams.", one-line explanation, a language segmented control (Bahasa Indonesia | English), and two buttons: **I am the protected parent** (filled teal) and **I am a caregiver** (white).
- Each later step: back button, segmented progress bar, large bold title, one short subtitle, one full-width primary button at the bottom.

**Parent onboarding:** Tutorial (3 swipeable cards with a speaker button to hear it read aloud, Skip) → What is your name? → Attach puck (puck image, **Find puck**) → Puck Wi-Fi → Before you begin (4 icon rows) → Invite a caregiver (six code boxes, validity countdown, incoming requests with **Allow**) → Try it (practice call).
**Caregiver onboarding:** Enter code (six boxes, number pad) → Who are you? (name + relationship chips: Child, Grandchild, Relative) → Make a decision (sample alert with **Safe** / **Scam**).

**Parent Home:** "Hi, {name}", issue banners (yellow) when something blocks protection, **Connect family** card until a caregiver joins, live call card during a call, **Latest call** card with result and the caregiver's decision.
**Caregiver Home:** "Hi, {name}", alert banner ("No new alerts" when quiet), **People you protect** card with the parent's live status ("Analysis in progress" / "No active analysis session") and "Together with {other caregivers} · Only one answer is needed".
**Alert detail (caregiver):** red or amber header with level, "{Parent} may be getting scammed", mascot holding a stop sign, call time and type, flagged caller sentences as quote cards ("Flagged by Rambu: Asks for an OTP or PIN"), recipients list, and the two big buttons **Safe** / **Scam**.
**History (both):** list of calls; each row shows a title, result badge (Safe / Danger / Could not assess), call type and time, and the caregiver decision strip ("Richard marked this call as scam").
**Call detail:** result, signals found, evidence quotes, decision, duration. The parent also sees the full masked transcript.
**Puck (parent):** puck image, connection status, Wi-Fi network, firmware version, **Pair puck** / **Puck Wi-Fi** actions.
**Profile (both):** avatar, name, role, Family (members, invite code), Alerts (Notifications status, **Read alerts aloud** toggle), Language, Name, Relationship (caregiver).
**Live Activity (parent, during a call):** Lock Screen card and Dynamic Island with mascot, level ("Danger"), headline ("The caller is asking for a secret code"), "{Name} · Call", timer.

## Look and Feel
- Calm, trustworthy, friendly. Big bold rounded-sans headlines, short sentences, large tap targets for older users.
- Palette: teal brand `#006F63` (bright `#00937F`, deep `#054F47`, soft `#E2F2EF`); ink `#0F2A29` / `#3B5250` / `#5B716F`; canvas `#F2F6F5`; hairline `#DCE7E4`; signal amber `#F4B400` (soft `#FFF3C7`); danger red `#D2372C` (soft `#FDE6E3`); safe green `#1E8259` (soft `#E4F3EC`); puck cream `#F4F0E6`.
- White rounded cards on the pale canvas, pill-shaped buttons, SF Symbols icons in teal rounded squares.
- The Rambu mascot (green character with a yellow light) appears in alerts and holds a sign that matches the level: calm when safe, a raised hand or stop sign when risky.
- Risk colors are consistent everywhere: green = safe, amber = needs a look, red = danger, grey = could not assess.
- Assets: Rambu logo, mascot, puck render, urgent alert sound, and the welcome photo (AI-generated).

## Features and Behavior

### Language
- The app runs fully in English or Bahasa Indonesia, chosen on Welcome and changeable in Profile without losing family or history. A fresh install follows the iPhone's language when it is one of the two.
- Analysis, warnings, and pushes follow each person's language, so a parent and caregiver can use different languages. Names and caller transcripts are never translated.
  - [ ] Switching Profile → Language changes every visible label immediately and keeps history.
  - [ ] An English call yields English warnings and evidence; an Indonesian call yields Indonesian ones.

### Family linking
- The parent creates the family. The invite code is six digits, valid for a limited time with a visible countdown, and can be renewed.
- A caregiver who enters a valid code appears as an incoming request; the parent taps **Allow**. Several caregivers can join.
  - [ ] Entering the parent's code on the second iPhone shows the request on the parent's phone; after **Allow**, both Homes show each other.
  - [ ] An expired or wrong code shows an inline error and the caregiver stays on Enter code.

### Puck pairing and Wi-Fi
- **Find puck** scans over Bluetooth for the Rambu puck and pairs it. The app then sends it the Wi-Fi network and password plus what it needs to reach Rambu and the family.
- The Puck tab shows whether it is connected and online.
  - [ ] After pairing and Wi-Fi setup, the Puck tab shows the puck as connected and online.
  - [ ] With Bluetooth off, **Find puck** explains how to turn it on instead of spinning forever.

### Call listening
Source: `scope.md > The POC Boundary`.
- When the parent answers a regular phone call, the app tells the puck, and the puck starts recording; its light stays on while recording. When the call ends, the puck stops.
- The puck only hears what comes out of the loudspeaker. If speaker is off, the parent gets "Turn on speakerphone. Rambu cannot hear the call yet."
- Audio is analyzed in short pieces during the call, so warnings arrive mid-call, and once more in full at the end.
- Sensitive values (digits of codes, PINs, account and card numbers) are masked in every transcript and quote. Raw audio is not kept.
  - [ ] Answering a call on speaker turns on the puck light within a few seconds, without touching the app.
  - [ ] Hanging up turns the light off and the call appears in History.

### Scam analysis
- Each call gets a level: **low** (Safe), **needs_review** (amber, "worth a look"), or **high_risk** (red, Danger).
- Five signals, each with a parent-friendly headline: `impersonation` (claims to be from an institution), `urgency` (pressures you), `secret_code` (asks for an OTP, PIN or password, including "read me the SMS you just got"), `transfer` (asks for a money transfer), `remote_app` (tells you to install an app).
- Every non-low result carries evidence: exact sentences from the transcript, each tagged with the signals it proves. Warnings and protective talk ("never share your OTP") are not counted as requests.
- Rambu never says someone is definitely a scammer.
  - [ ] The demo line "I'm sending a six-digit code to your phone. Read it to me now" is flagged `secret_code` and appears word for word as evidence.
  - [ ] A friendly reminder call ("the meeting starts at ten tomorrow") stays Safe with no alert.

### Warnings
- On needs_review or high_risk, the parent gets an urgent notification (custom sound, vibration) and the Live Activity turns amber or red with the headline of the latest signal. If **Read alerts aloud** is on, Rambu speaks the warning.
- At the same moment, every caregiver gets a push: "{Parent} may be getting scammed", showing the strongest evidence line. Only flagged caller sentences go to caregivers; the full transcript stays on the parent's phone.
- The parent sees who was warned ("Sent to Dimas").
  - [ ] Both iPhones show the warning within the measured wait time after the OTP sentence, while the call is still going.
  - [ ] Tapping the caregiver push opens that alert's detail.

### Caregiver decision
- The caregiver taps **Scam** or **Safe** (Safe asks for confirmation). The first answer wins: other caregivers see it locked with who decided, and their buttons are disabled.
- The verdict is pushed to the parent at once. **Scam**: red alert "{Caregiver} says this is a scam. Hang up and call the number on the back of your card.", Live Activity turns red. **Safe**: calm green "{Caregiver} checked: this looks safe."
- When the call ends before a decision, the alert shows "Call ended" and can still be marked.
  - [ ] Tapping **Scam** on the caregiver's phone turns the parent's screen red within a few seconds, mid-call.
  - [ ] A second caregiver opening the same alert sees "Marked as scam by {name}" with locked buttons.

### History
- Both sides list past calls, newest first, with level badge, call type, time, duration, and decision strip. Tapping opens the call detail.
- History persists across app restarts.
  - [ ] After the demo call, both phones show it in History as Danger with "{Caregiver} marked this call as scam".

### Practice call (onboarding)
- The parent's practice is clearly labeled **PRACTICE** with **End practice**: an incoming "Unknown number" screen with an instruction bubble, then a sample warning to tap. The caregiver's practice is a sample alert marked **Example**.
- Practice never contacts the family or creates history.
  - [ ] Finishing practice leads to Home with no new History entry and no push to the caregiver.

### Issue banners
- Parent Home shows a yellow banner for anything that stops protection: notifications off (**Turn on**), no internet ("Caregivers cannot be notified yet"), Bluetooth off (**Settings**), puck disconnected (**Connect**).
  - [ ] Turning off Wi-Fi and cellular shows the no-internet banner; restoring it clears the banner.

## States and Boundaries
- **First launch:** Welcome screen; nothing works until onboarding finishes.
- **No caregiver yet:** parent Home shows **Connect family**; warnings still reach the parent.
- **Quiet:** caregiver Home shows "No new alerts"; parent Home shows the latest call or nothing yet ("No calls yet").
- **Speaker off:** no analysis; the parent is told to turn on speakerphone.
- **No speech heard:** the call is saved as "Could not assess: no speech the puck could analyze."
- **Analysis failed or server unreachable:** "Call analysis failed. The Rambu server could not be reached." The call is saved as Could not assess, and caregivers see "Analysis stopped without confirming that the call was safe." It never falls back to Safe.
- **Puck offline:** parent sees the puck banner; a call during that time is not analyzed.
- **Who sees what:** caregivers see only flagged caller sentences; the parent sees the full masked transcript. Only family members can see the family's calls.
- **Persists:** profile, language, family, puck pairing, history. **Does not persist:** raw audio.

## Product Decisions
- **English everywhere in the demo, Indonesian fully supported** — the demo dialog and subtitles are English; the story starts in Indonesia, where parents are frequent targets, and from the learner's own mother.
- **The parent never has to open the app during a call** — warnings arrive as notifications and the Live Activity, because the phone screen belongs to the call.
- **Caregiver confirms, Rambu never hangs up** — "You stay in control"; the decision is human.
- **First caregiver answer wins** — one clear verdict instead of conflicting ones.
- **Caregivers only see evidence lines** — privacy for the parent's full conversation.
- **Failures are shown, never hidden** — a call that couldn't be analyzed is never shown as safe.
- **No demo/simulation mode, no Mac stand-in puck, no WhatsApp path** — the real puck exists, and internet calls are cut in scope.
- **Puck is USB-C powered in this phase** — the Puck tab shows connection, not battery. A battery comes in a later hardware phase.

## What We're Building
Everything in **Features and Behavior** above, on both roles, in English and Indonesian; plus the puck firmware that records on answer and stops on hang-up; a deployed backend; a TestFlight build installed on both iPhones; and a README covering the puck's 3D design, components, wiring, firmware, and pairing.

## Deferred From the POC
- **Smaller puck hardware** (PopSocket-sized options) — needs new parts and soldering; see `scope.md > Later`.
- **Puck battery** — phase 1 runs on USB-C power; a battery-powered puck is the next hardware phase, after this submission.

## Possible Later Enhancements
- A sound on the puck itself for warnings (needs a speaker part).
- Weekly family summary of calls checked.

## Non-Goals
- **Chat and message scams** — Rambu is about calls (`scope.md > Explicitly Cut`).
- **WhatsApp and other internet calls** — cut in scope.
- **Hanging up or blocking calls automatically** — the parent stays in control.
- **Public App Store release** — TestFlight only.
- **Manufacturing a finished puck** — prototype plus 3D design only.

## Open Questions
- Measured wait time from the OTP sentence to the first warning — measured during the build and in the rehearsal; doesn't block spec.
