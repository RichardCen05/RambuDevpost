"""Speech to text with faster-whisper on this Mac. Audio never leaves the machine."""

import io
import threading
import wave
from dataclasses import dataclass

import numpy as np

SAMPLE_RATE = 16000


@dataclass
class Segment:
    start: float
    end: float
    text: str


def decode_wav(data: bytes) -> np.ndarray:
    """16-bit PCM WAV (any rate, any channel count) → mono float32 at 16 kHz."""
    with wave.open(io.BytesIO(data)) as wav:
        if wav.getsampwidth() != 2:
            raise ValueError("expected 16-bit PCM WAV")
        rate = wav.getframerate()
        channels = wav.getnchannels()
        frames = wav.readframes(wav.getnframes())
    pcm = np.frombuffer(frames, dtype="<i2").astype(np.float32) / 32768.0
    if channels > 1:
        pcm = pcm[: len(pcm) - len(pcm) % channels].reshape(-1, channels).mean(axis=1)
    if rate != SAMPLE_RATE and len(pcm):
        target = int(round(len(pcm) * SAMPLE_RATE / rate))
        pcm = np.interp(np.linspace(0, len(pcm), target, endpoint=False), np.arange(len(pcm)), pcm)
    return pcm.astype(np.float32)


def rms(pcm: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(pcm)))) if len(pcm) else 0.0


def normalize(pcm: np.ndarray) -> np.ndarray:
    """Lift quiet loudspeaker audio picked up across the room; never more than 20x."""
    peak = float(np.max(np.abs(pcm))) if len(pcm) else 0.0
    if peak <= 0:
        return pcm
    gain = min(0.6 / peak, 20.0)
    return pcm * gain if gain > 1 else pcm


class WhisperTranscriber:
    def __init__(self, model_name: str):
        self.model_name = model_name
        self._model = None
        self._lock = threading.Lock()

    def _load(self):
        if self._model is None:
            from faster_whisper import WhisperModel

            self._model = WhisperModel(self.model_name, device="cpu", compute_type="int8")
        return self._model

    def warm_up(self) -> None:
        with self._lock:
            self._load()

    def transcribe(self, pcm: np.ndarray, language: str) -> list[Segment]:
        with self._lock:
            model = self._load()
            segments, _ = model.transcribe(
                normalize(pcm),
                language=language,
                beam_size=1,
                vad_filter=True,
                condition_on_previous_text=False,
            )
            return [Segment(s.start, s.end, s.text.strip()) for s in segments if s.text.strip()]
