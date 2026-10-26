#pragma once

#include <Arduino.h>
#include <functional>

// Records the INMP441 into ~3 s WAV pieces on its own FreeRTOS task, using two buffers:
// one fills while the other is being uploaded. If both are busy, audio is dropped, never queued.
namespace Recorder {

// `onPiece` receives a full WAV (header included); give the buffer back with release().
// `onEnd` fires once after the last piece of a recording.
bool begin(std::function<void(uint8_t* wav, size_t length)> onPiece, std::function<void()> onEnd);
void start();
void stop();
bool recording();
void release(uint8_t* wav);

}  // namespace Recorder
