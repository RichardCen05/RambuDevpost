#include "recorder.h"

#include <ESP_I2S.h>

#include "puck_config.h"

namespace {

I2SClass i2s;
QueueHandle_t freeBuffers = nullptr;
std::function<void(uint8_t*, size_t)> pieceHandler;
std::function<void()> endHandler;
volatile bool wantRecording = false;
volatile bool isRecording = false;

void writeWavHeader(uint8_t* p, uint32_t dataBytes) {
  auto put32 = [&](size_t at, uint32_t v) { for (int i = 0; i < 4; i++) p[at + i] = (v >> (8 * i)) & 0xFF; };
  auto put16 = [&](size_t at, uint16_t v) { p[at] = v & 0xFF; p[at + 1] = v >> 8; };
  memcpy(p, "RIFF", 4);
  put32(4, 36 + dataBytes);
  memcpy(p + 8, "WAVEfmt ", 8);
  put32(16, 16);
  put16(20, 1);                // PCM
  put16(22, 1);                // mono
  put32(24, UPLOAD_RATE);
  put32(28, UPLOAD_RATE * 2);  // byte rate
  put16(32, 2);                // block align
  put16(34, 16);               // bits per sample
  memcpy(p + 36, "data", 4);
  put32(40, dataBytes);
}

inline int16_t toPcm16(int32_t raw) {
  // 24-bit sample, left-aligned in a 32-bit slot. >>14 keeps 4x gain for a phone across the table.
  int32_t v = raw >> 14;
  return (int16_t)constrain(v, -32768, 32767);
}

void recordTask(void*) {
  static int32_t frames[512];
  uint8_t* piece = nullptr;
  size_t filled = 0;  // samples written into the current piece
  uint32_t dropped = 0;

  for (;;) {
    if (!wantRecording && !isRecording) {
      vTaskDelay(pdMS_TO_TICKS(20));
      continue;
    }
    if (wantRecording && !isRecording) {
      isRecording = true;
      dropped = 0;
      Serial.println("[rec] start");
    }

    if (!piece && xQueueReceive(freeBuffers, &piece, 0) != pdTRUE) piece = nullptr;

    size_t got = i2s.readBytes((char*)frames, sizeof(frames));
    size_t count = got / sizeof(int32_t);
    int16_t* pcm = piece ? (int16_t*)(piece + WAV_HEADER_BYTES) : nullptr;
    for (size_t i = 0; i + 1 < count; i += 2) {  // 16 kHz → 8 kHz: average sample pairs
      int16_t sample = (int16_t)(((int32_t)toPcm16(frames[i]) + toPcm16(frames[i + 1])) / 2);
      if (!pcm) {
        dropped++;
        continue;
      }
      pcm[filled++] = sample;
      if (filled == PIECE_SAMPLES) {
        writeWavHeader(piece, filled * 2);
        pieceHandler(piece, WAV_HEADER_BYTES + filled * 2);
        piece = nullptr;
        filled = 0;
        if (xQueueReceive(freeBuffers, &piece, 0) != pdTRUE) piece = nullptr;
        pcm = piece ? (int16_t*)(piece + WAV_HEADER_BYTES) : nullptr;
      }
    }

    if (!wantRecording) {
      if (piece && filled > UPLOAD_RATE / 4) {  // send the tail if it has at least 0.25 s
        writeWavHeader(piece, filled * 2);
        pieceHandler(piece, WAV_HEADER_BYTES + filled * 2);
      } else if (piece) {
        xQueueSend(freeBuffers, &piece, 0);
      }
      piece = nullptr;
      filled = 0;
      isRecording = false;
      Serial.printf("[rec] stop, dropped %lu samples\n", (unsigned long)dropped);
      endHandler();
    }
  }
}

}  // namespace

namespace Recorder {

bool begin(std::function<void(uint8_t*, size_t)> onPiece, std::function<void()> onEnd) {
  pieceHandler = onPiece;
  endHandler = onEnd;
  freeBuffers = xQueueCreate(2, sizeof(uint8_t*));
  for (int i = 0; i < 2; i++) {
    uint8_t* buffer = (uint8_t*)heap_caps_malloc(PIECE_BYTES, MALLOC_CAP_8BIT);
    if (!buffer) {
      Serial.printf("[rec] could not allocate audio buffer %d (free heap %u)\n", i, ESP.getFreeHeap());
      return false;
    }
    xQueueSend(freeBuffers, &buffer, 0);
  }
  i2s.setPins(PIN_MIC_SCK, PIN_MIC_WS, -1, PIN_MIC_SD);
  if (!i2s.begin(I2S_MODE_STD, MIC_RATE, I2S_DATA_BIT_WIDTH_32BIT, I2S_SLOT_MODE_MONO, I2S_STD_SLOT_LEFT)) {
    Serial.println("[rec] I2S init failed");
    return false;
  }
  xTaskCreatePinnedToCore(recordTask, "record", 4096, nullptr, 3, nullptr, 1);
  return true;
}

void start() { wantRecording = true; }
void stop() { wantRecording = false; }
bool recording() { return isRecording; }
void release(uint8_t* wav) { xQueueSend(freeBuffers, &wav, 0); }

}  // namespace Recorder
