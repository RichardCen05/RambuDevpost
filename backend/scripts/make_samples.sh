#!/usr/bin/env bash
# Builds synthetic test calls with macOS text-to-speech, filtered to sound like a phone
# loudspeaker (300–3400 Hz), as 16 kHz mono WAV in samples/test-calls/.
# Usage: backend/scripts/make_samples.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/samples/test-calls"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

# line <file> <voice> <text>
line() { say -v "$2" -r 175 -o "$WORK/$1.aiff" "$3"; }

build() {  # build <name> <part>...
  local name="$1"; shift
  local list="$WORK/$name.txt"; : > "$list"
  ffmpeg -loglevel error -y -f lavfi -i anullsrc=r=22050:cl=mono -t 0.5 "$WORK/gap.aiff"
  for part in "$@"; do
    printf "file '%s'\nfile '%s'\n" "$WORK/$part.aiff" "$WORK/gap.aiff" >> "$list"
  done
  ffmpeg -loglevel error -y -f concat -safe 0 -i "$list" \
    -af "highpass=f=300,lowpass=f=3400,volume=0.8" -ar 16000 -ac 1 -c:a pcm_s16le "$OUT/$name.wav"
  echo "wrote $OUT/$name.wav"
}

CALLER="Daniel"
PARENT="Samantha"

# The demo scene: a caller posing as the bank's fraud team asks for the OTP.
line s1 "$PARENT" "Hello?"
line s2 "$CALLER" "Good afternoon, ma'am. This is Kevin from the fraud team at your bank."
line s3 "$CALLER" "We just stopped a transfer of eight million rupiah from your account. Was that you?"
line s4 "$PARENT" "What? No, that wasn't me!"
line s5 "$CALLER" "Then we need to block it right now. I'm sending a six-digit code to your phone. Read it to me now, before the money leaves. Please don't hang up."
line s6 "$PARENT" "Hold on a moment."
line s7 "$CALLER" "Ma'am? The code, please. We don't have much time."
build bank-otp-en s1 s2 s3 s4 s5 s6 s7

# A friendly neighbour: should stay safe.
line n1 "$PARENT" "Hello?"
line n2 "Karen" "Hi Ratna, it's Wati from next door. Just a reminder that the community meeting starts at ten tomorrow at Sari's house."
line n3 "Karen" "I'll bring some snacks. See you tomorrow!"
line n4 "$PARENT" "Okay, thank you, Wati. See you."
build neighbour-safe-en n1 n2 n3 n4

# Indonesian: bank impersonation asking for the OTP.
line i1 "Damayanti" "Halo?"
line i2 "Damayanti" "Selamat siang, Bu. Saya dari bagian keamanan bank. Rekening Ibu akan diblokir hari ini."
line i3 "Damayanti" "Saya kirim kode OTP ke HP Ibu. Tolong sebutkan kodenya sekarang ya, Bu. Jangan tutup teleponnya."
build bank-otp-id i1 i2 i3
