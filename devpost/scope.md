---
doc: scope
status: approved
---

# Rambu

A small puck next to an older parent's iPhone listens to phone calls on loudspeaker, flags scam calls with the caller's own words as evidence, and lets their child in another city confirm "this is a scam" before the parent hands anything over.

## The Unique Kernel
Rambu listens to the **phone call itself**, not chats or messages. An iPhone app can't hear call audio, so a separate puck does. The scammer's own sentences become the evidence on screen. The parent and their far-away child get warned at the same moment, and the child's one tap reaches the parent **while the call is still going**, breaking the panic window that scammers depend on.

## Who It's For
**Ratna, 68**, lives alone. A caller claims to be her son after an accident, the police, or her bank's fraud team. Panic sets in, she stops thinking, and she does what the caller asks: transfer money, read out a code, install an app.

**Dimas, her son**, works in another city. He wants to protect her from digital threats but can't be next to her when the phone rings. Today he can only warn her in advance and hope she remembers mid-panic.

## The Core Loop
- **Parent:** answers calls on loudspeaker as usual, with the puck beside the phone. Nothing to open. When a call turns risky, her phone shows a warning. When her son decides, she sees his verdict.
- **Child:** gets a push the moment a call is flagged, opens it, reads the exact sentences the AI marked, and taps **scam** or **safe**. His decision goes back to his mother's phone.

They come back because it runs on every call without the parent doing anything.

## Inspiration & Identity
Uses the learner's own Rambu brand assets: the name, the mascot, and sample audio. The app is bilingual (Indonesian and English). Look and feel get settled in `3-prd`.

## Why This Matters to the Learner
Scam callers make parents panic, "pretending to be their child in an accident or the police", so they stop thinking and follow orders. The children who move away for work "want to protect them from digital threats" but can't do it from up close.

## What "Working" Looks Like
The 60-second demo scene runs for real on the app and puck in this repo, in one unbroken take, with no mock screens:

1. A regular phone call from an unknown number reaches the parent's iPhone. She answers on loudspeaker.
2. The puck starts recording on its own when she answers.
3. The caller (in English) claims to be the bank's fraud team, mentions a blocked transfer of eight million rupiah, demands the six-digit code "right now", and says "please don't hang up."
4. An early warning appears on **both** the parent's and the child's iPhone at the same time.
5. The child opens it, sees the flagged evidence sentence (e.g. "Read it to me now"), and taps confirm scam.
6. A red danger alert appears on the parent's phone. She hangs up. The code is never shared.

The real wait time from the OTP sentence to the first warning is measured and shown as is.

**The "oh, that's cool" beat:** the son's tap, made in another city, turns his mother's screen red in the middle of the scammer's sentence.

## The POC Boundary
All of this is in, tonight, built end-to-end first and then filled out:

- Puck firmware: records on call answer, streams to the backend, stops when the call ends.
- Backend: transcription → AI risk check (`low` / `needs_review` / `high_risk`) on five signals (`impersonation`, `urgency`, `secret_code`, `transfer`, `remote_app`) with evidence quotes → push to parent and child.
- Child's decision (scam / safe) sent back to the parent's phone.
- iOS app with parent and child sides: onboarding with a practice call, a family linked by a six-digit code, puck pairing over Bluetooth plus Wi-Fi setup, call history, and Indonesian/English.
- Backend running on the Mac behind a public tunnel, and the app installed on both iPhones from Xcode.
- For this submission, a Mac stand-in records the call through the same interface the puck uses; the puck firmware is written and compiles.
- The puck stays a **prototype (v3)**: ESP32 DevKit V1 (30-pin, USB-C) + round INMP441 mic on six female–female jumpers, inside a 3D-printed PETG case (Ø66 × 30 mm, body + snap-on lid with a 7-hole mic grill) stuck to the back of the iPhone below the camera, powered over USB-C. Mic wiring: VDD→3V3, GND→GND, L/R→GND, SD→GPIO32, SCK→GPIO33, WS→GPIO25.
- README covering the 3D design (STL files, print settings), components, wiring, firmware, and pairing.

## Later
The puck recording calls on its own hardware, and pairing it from the app (next hardware phase).

Smaller puck options, PopSocket-sized: ESP32-S3 SuperMini on a cable (Ø36 × 12 mm), XIAO ESP32S3 with a 200 mAh LiPo (Ø40 × 15 mm), M5Stack Atom Echo (Ø38 × 20 mm), or a custom PCB (about Ø40 × 9 mm).

## Explicitly Cut
- **Manufacturing a finished puck:** the hardware stays a working prototype plus its 3D design; product-grade hardware takes more than one night.
- **Chat and message scams:** Rambu is about calls; chat is a different product.
- **WhatsApp and other internet calls:** the demo and the product target regular phone calls.
- **TestFlight and App Store release:** both demo iPhones run the app installed from Xcode; distribution comes after the hackathon.
