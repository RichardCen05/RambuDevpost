#pragma once

#include <Arduino.h>
#include <functional>

// Bluetooth side of the puck:
//  - a peripheral service the Rambu app uses to read the puck ID and write Wi-Fi/server settings;
//  - an ANCS client on the bonded iPhone, which reports calls as notifications even when
//    the Rambu app is closed. An answered call shows up as an "ActiveCall" notification.
namespace BleLink {

enum class CallEvent { Incoming, Answered, Ended };

void begin(std::function<void(const String&)> onConfig,
           std::function<void(const String&)> onCommand,
           std::function<void(CallEvent)> onCall);

// Call from loop(): runs ANCS discovery after bonding and hands call events to onCall.
void loop();

void notifyStatus(const String& status);
bool phoneConnected();

}  // namespace BleLink
