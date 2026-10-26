#pragma once

#include <Arduino.h>

#include "puck_config.h"

// Talks to the Rambu backend on its own task, in order: hello, session start, audio pieces, end.
namespace Uploader {

void begin(const PuckSettings& settings);
void updateSettings(const PuckSettings& settings);

void hello();
void startSession();
void sendPiece(uint8_t* wav, size_t length);  // the buffer goes back to the Recorder afterwards
void endSession();

}  // namespace Uploader
