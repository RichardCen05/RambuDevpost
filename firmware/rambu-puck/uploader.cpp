#include "uploader.h"

#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>

#include "ble_link.h"
#include "recorder.h"

namespace {

enum class Kind : uint8_t { Hello, Start, Piece, End };

struct Job {
  Kind kind;
  uint8_t* data;
  size_t length;
};

QueueHandle_t jobs = nullptr;
SemaphoreHandle_t settingsLock = nullptr;
PuckSettings current;
String sessionId;

PuckSettings snapshot() {
  xSemaphoreTake(settingsLock, portMAX_DELAY);
  PuckSettings copy = current;
  xSemaphoreGive(settingsLock);
  return copy;
}

// One request; returns the HTTP status (negative on transport errors) and fills `body`.
int post(const PuckSettings& s, const String& path, const uint8_t* data, size_t length, const char* type,
         String* body = nullptr) {
  static WiFiClientSecure secure;
  static WiFiClient plain;
  static bool secureReady = false;
  if (!secureReady) {
    secure.setInsecure();  // prototype: the quick tunnel's certificate changes with its address
    secureReady = true;
  }
  HTTPClient http;
  http.setReuse(true);
  http.setTimeout(10000);
  String url = s.url + path;
  bool ok = url.startsWith("https://") ? http.begin(secure, url) : http.begin(plain, url);
  if (!ok) return -1;
  http.addHeader("Authorization", "Bearer " + s.token);
  http.addHeader("Content-Type", type);
  int code = http.POST((uint8_t*)data, length);
  if (body && code > 0) *body = http.getString();
  http.end();
  return code;
}

int postJson(const PuckSettings& s, const String& path, const String& json, String* body = nullptr) {
  return post(s, path, (const uint8_t*)json.c_str(), json.length(), "application/json", body);
}

void uploadTask(void*) {
  Job job;
  for (;;) {
    if (xQueueReceive(jobs, &job, portMAX_DELAY) != pdTRUE) continue;
    PuckSettings s = snapshot();
    bool online = WiFi.status() == WL_CONNECTED && s.hasServer();

    switch (job.kind) {
      case Kind::Hello: {
        if (!online) break;
        int code = postJson(s, "/api/puck/hello", "{\"firmware\":\"" FIRMWARE_VERSION "\"}");
        Serial.printf("[net] hello %d\n", code);
        BleLink::notifyStatus(code == 200 ? "online" : "server_fail");
        break;
      }
      case Kind::Start: {
        sessionId = "";
        if (!online) {
          Serial.println("[net] call started but the puck is offline");
          break;
        }
        String body;
        int code = postJson(s, "/api/puck/sessions", "{}", &body);
        if (code == 201) {
          JsonDocument doc;
          if (!deserializeJson(doc, body)) sessionId = doc["sessionId"].as<String>();
        }
        Serial.printf("[net] session %d %s\n", code, sessionId.c_str());
        break;
      }
      case Kind::Piece: {
        if (online && sessionId.length()) {
          String path = "/api/puck/sessions/" + sessionId + "/chunks";
          int code = post(s, path, job.data, job.length, "audio/wav");
          if (code < 0) code = post(s, path, job.data, job.length, "audio/wav");  // one retry
          Serial.printf("[net] chunk %d (%u bytes, heap %u)\n", code, (unsigned)job.length, ESP.getFreeHeap());
        }
        Recorder::release(job.data);
        break;
      }
      case Kind::End: {
        if (online && sessionId.length()) {
          int code = postJson(s, "/api/puck/sessions/" + sessionId + "/end", "{}");
          Serial.printf("[net] session end %d\n", code);
        }
        sessionId = "";
        break;
      }
    }
  }
}

void enqueue(Kind kind, uint8_t* data = nullptr, size_t length = 0) {
  Job job{kind, data, length};
  if (xQueueSend(jobs, &job, pdMS_TO_TICKS(100)) != pdTRUE && data) Recorder::release(data);
}

}  // namespace

namespace Uploader {

void begin(const PuckSettings& settings) {
  settingsLock = xSemaphoreCreateMutex();
  current = settings;
  jobs = xQueueCreate(8, sizeof(Job));
  xTaskCreatePinnedToCore(uploadTask, "upload", 8192, nullptr, 2, nullptr, 0);
}

void updateSettings(const PuckSettings& settings) {
  xSemaphoreTake(settingsLock, portMAX_DELAY);
  current = settings;
  xSemaphoreGive(settingsLock);
}

void hello() { enqueue(Kind::Hello); }
void startSession() { enqueue(Kind::Start); }
void sendPiece(uint8_t* wav, size_t length) { enqueue(Kind::Piece, wav, length); }
void endSession() { enqueue(Kind::End); }

}  // namespace Uploader
