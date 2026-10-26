#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>
#include <Preferences.h>

#define FIRMWARE_VERSION "1.0.0"

// INMP441 wiring from the v3 assembly guide. L/R goes to GND, so the mic is the left slot.
constexpr int PIN_MIC_SD = 32;
constexpr int PIN_MIC_SCK = 33;
constexpr int PIN_MIC_WS = 25;
constexpr int PIN_LED = 2;  // on-board blue LED of the ESP32 DevKit V1

// The mic is read at 16 kHz and sent at 8 kHz: a loudspeaker call only carries ~300–3400 Hz,
// and half the rate halves the RAM each audio piece needs next to Wi-Fi, TLS, and Bluetooth.
constexpr uint32_t MIC_RATE = 16000;
constexpr uint32_t UPLOAD_RATE = 8000;
constexpr uint32_t PIECE_SECONDS = 3;
constexpr size_t WAV_HEADER_BYTES = 44;
constexpr size_t PIECE_SAMPLES = UPLOAD_RATE * PIECE_SECONDS;
constexpr size_t PIECE_BYTES = WAV_HEADER_BYTES + PIECE_SAMPLES * 2;

struct PuckSettings {
  String ssid;
  String pass;
  String url;  // e.g. https://example.trycloudflare.com (no trailing slash)
  String puckId;
  String token;

  bool hasWifi() const { return ssid.length() > 0; }
  bool hasServer() const { return url.length() > 0 && token.length() > 0; }
};

inline PuckSettings loadSettings() {
  Preferences prefs;
  prefs.begin("rambu", true);
  PuckSettings s{prefs.getString("ssid", ""), prefs.getString("pass", ""), prefs.getString("url", ""),
                 prefs.getString("puckId", ""), prefs.getString("token", "")};
  prefs.end();
  return s;
}

inline void saveSettings(const PuckSettings& s) {
  Preferences prefs;
  prefs.begin("rambu", false);
  prefs.putString("ssid", s.ssid);
  prefs.putString("pass", s.pass);
  prefs.putString("url", s.url);
  prefs.putString("puckId", s.puckId);
  prefs.putString("token", s.token);
  prefs.end();
}

// Merges {"ssid","pass","url","puckId","token"} into `s`; missing keys keep their value.
inline bool mergeConfigJson(const String& json, PuckSettings& s) {
  JsonDocument doc;
  if (deserializeJson(doc, json)) return false;
  if (doc["ssid"].is<const char*>()) s.ssid = doc["ssid"].as<const char*>();
  if (doc["pass"].is<const char*>()) s.pass = doc["pass"].as<const char*>();
  if (doc["url"].is<const char*>()) {
    s.url = doc["url"].as<const char*>();
    while (s.url.endsWith("/")) s.url.remove(s.url.length() - 1);
  }
  if (doc["puckId"].is<const char*>()) s.puckId = doc["puckId"].as<const char*>();
  if (doc["token"].is<const char*>()) s.token = doc["token"].as<const char*>();
  return true;
}
