#include <Arduino.h>
#include <WiFi.h>

#include "ble_link.h"
#include "puck_config.h"
#include "recorder.h"
#include "uploader.h"

PuckSettings settings;
bool callActive = false;
uint32_t lastWifiAttempt = 0;
bool helloSent = false;

void connectWifi() {
  if (!settings.hasWifi()) return;
  WiFi.disconnect();
  WiFi.begin(settings.ssid.c_str(), settings.pass.c_str());
  lastWifiAttempt = millis();
  helloSent = false;
  Serial.printf("[wifi] connecting to %s\n", settings.ssid.c_str());
}

void applyConfig(const String& json) {
  PuckSettings next = settings;
  if (!mergeConfigJson(json, next)) {
    Serial.println("[cfg] invalid JSON");
    BleLink::notifyStatus("config_invalid");
    return;
  }
  bool wifiChanged = next.ssid != settings.ssid || next.pass != settings.pass;
  settings = next;
  saveSettings(settings);
  Uploader::updateSettings(settings);
  Serial.println("[cfg] saved");
  BleLink::notifyStatus("config_saved");
  if (wifiChanged || WiFi.status() != WL_CONNECTED) {
    connectWifi();
  } else {
    Uploader::hello();
  }
}

void beginCall() {
  if (callActive) return;
  callActive = true;
  Uploader::startSession();
  Recorder::start();
  BleLink::notifyStatus("recording");
}

void endCall() {
  if (!callActive) return;
  callActive = false;
  Recorder::stop();  // the recorder flushes its last piece, then Uploader::endSession() runs
  BleLink::notifyStatus("online");
}

void handleCommand(const String& raw) {
  String command = raw;
  command.trim();
  if (command == "start") {
    beginCall();
  } else if (command == "stop") {
    endCall();
  } else if (command.startsWith("config ")) {
    applyConfig(command.substring(7));
  } else if (command == "status") {
    Serial.printf("wifi=%s ip=%s url=%s token=%s puckId=%s phone=%d recording=%d heap=%u\n",
                  WiFi.status() == WL_CONNECTED ? "up" : "down", WiFi.localIP().toString().c_str(),
                  settings.url.c_str(), settings.token.length() ? "set" : "missing", settings.puckId.c_str(),
                  BleLink::phoneConnected(), Recorder::recording(), ESP.getFreeHeap());
  } else if (command.length()) {
    Serial.printf("unknown command: %s\n", command.c_str());
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, LOW);
  Serial.println("\nRambu puck " FIRMWARE_VERSION);

  settings = loadSettings();
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);

  BleLink::begin(applyConfig, handleCommand, [](BleLink::CallEvent event) {
    switch (event) {
      case BleLink::CallEvent::Incoming: Serial.println("[call] ringing"); break;
      case BleLink::CallEvent::Answered: Serial.println("[call] answered"); beginCall(); break;
      case BleLink::CallEvent::Ended: Serial.println("[call] ended"); endCall(); break;
    }
  });
  Uploader::begin(settings);
  if (!Recorder::begin(Uploader::sendPiece, Uploader::endSession)) {
    Serial.println("[rec] recorder unavailable");
  }
  connectWifi();
  Serial.printf("ready, free heap %u\n", ESP.getFreeHeap());
}

void loop() {
  BleLink::loop();

  static String line;
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (line.length()) handleCommand(line);
      line = "";
    } else {
      line += c;
    }
  }

  bool wifiUp = WiFi.status() == WL_CONNECTED;
  static uint32_t lastHello = 0;
  if (wifiUp && !helloSent) {
    Serial.printf("[wifi] connected, ip %s\n", WiFi.localIP().toString().c_str());
    Uploader::hello();
    helloSent = true;
    lastHello = millis();
  } else if (wifiUp && !callActive && millis() - lastHello > 60000) {
    Uploader::hello();  // heartbeat: the app shows the puck as online
    lastHello = millis();
  }
  if (!wifiUp && settings.hasWifi() && millis() - lastWifiAttempt > 20000) connectWifi();

  // LED: steady while recording, slow blink while Wi-Fi is down, off otherwise.
  if (Recorder::recording()) {
    digitalWrite(PIN_LED, HIGH);
  } else if (!wifiUp) {
    digitalWrite(PIN_LED, (millis() / 700) % 2);
  } else {
    digitalWrite(PIN_LED, LOW);
  }
  delay(10);
}
