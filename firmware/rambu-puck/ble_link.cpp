#include "ble_link.h"

#include <NimBLEDevice.h>

#include "puck_config.h"

namespace {

// Rambu puck service
const char* PUCK_SERVICE = "6b1f0001-5a3e-4c8e-9d2a-7a0c52b1e001";
const char* INFO_CHAR = "6b1f0002-5a3e-4c8e-9d2a-7a0c52b1e001";     // read: {"puckId","firmware"}
const char* CONFIG_CHAR = "6b1f0003-5a3e-4c8e-9d2a-7a0c52b1e001";   // encrypted write: settings JSON
const char* STATUS_CHAR = "6b1f0004-5a3e-4c8e-9d2a-7a0c52b1e001";   // read/notify: status word
const char* COMMAND_CHAR = "6b1f0005-5a3e-4c8e-9d2a-7a0c52b1e001";  // encrypted write: start/stop

// Apple Notification Center Service
const NimBLEUUID ANCS_SERVICE("7905F431-B5CE-4E99-A40F-4B1E122D00D0");
const NimBLEUUID ANCS_NOTIFICATION_SOURCE("9FBF120D-6301-42D9-8C58-25E699A21DBD");
// ANCS service UUID, little-endian, as an advertising "service solicitation" entry. iOS
// reconnects on its own to a bonded accessory that solicits ANCS.
const uint8_t ANCS_SOLICITATION[] = {17,   0x15, 0xD0, 0x00, 0x2D, 0x12, 0x1E, 0x4B, 0x0F,
                                     0xA4, 0x99, 0x4E, 0xCE, 0xB5, 0x31, 0xF4, 0x05, 0x79};

constexpr uint8_t EVENT_ADDED = 0;
constexpr uint8_t EVENT_REMOVED = 2;
constexpr uint8_t CATEGORY_INCOMING_CALL = 1;
constexpr uint8_t CATEGORY_ACTIVE_CALL = 12;

struct AncsEvent {
  uint8_t event;
  uint8_t flags;
  uint8_t category;
  uint32_t uid;
};

NimBLEServer* server = nullptr;
NimBLECharacteristic* statusChar = nullptr;
std::function<void(const String&)> configHandler;
std::function<void(const String&)> commandHandler;
std::function<void(BleLink::CallEvent)> callHandler;

volatile uint16_t phoneHandle = BLE_HS_CONN_HANDLE_NONE;
volatile bool ancsSetupPending = false;
volatile uint16_t ancsSourceHandle = 0;
QueueHandle_t ancsEvents = nullptr;
ble_gap_event_listener gapListener;

uint32_t activeCallUid = 0;
bool activeCall = false;

// Notifications from the iPhone arrive on the NimBLE host task. The server-side client doesn't
// route them to a callback, so catch them at the GAP level and pass them to loop().
int onGapEvent(ble_gap_event* event, void*) {
  if (event->type != BLE_GAP_EVENT_NOTIFY_RX || ancsSourceHandle == 0 ||
      event->notify_rx.attr_handle != ancsSourceHandle) {
    return 0;
  }
  uint8_t data[8];
  if (OS_MBUF_PKTLEN(event->notify_rx.om) < sizeof(data)) return 0;
  os_mbuf_copydata(event->notify_rx.om, 0, sizeof(data), data);
  AncsEvent e{data[0], data[1], data[2],
              (uint32_t)data[4] | (uint32_t)data[5] << 8 | (uint32_t)data[6] << 16 | (uint32_t)data[7] << 24};
  xQueueSend(ancsEvents, &e, 0);
  return 0;
}

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo& info) override {
    phoneHandle = info.getConnHandle();
    Serial.printf("[ble] connected %s\n", info.getAddress().toString().c_str());
    NimBLEDevice::startSecurity(info.getConnHandle());
  }

  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int reason) override {
    Serial.printf("[ble] disconnected (reason %d)\n", reason);
    phoneHandle = BLE_HS_CONN_HANDLE_NONE;
    ancsSourceHandle = 0;
  }

  void onAuthenticationComplete(NimBLEConnInfo& info) override {
    Serial.printf("[ble] encrypted=%d bonded=%d\n", info.isEncrypted(), info.isBonded());
    if (info.isEncrypted()) ancsSetupPending = true;
  }
};

class WriteCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* characteristic, NimBLEConnInfo&) override {
    String value = characteristic->getValue().c_str();
    if (characteristic->getUUID() == NimBLEUUID(CONFIG_CHAR)) {
      if (configHandler) configHandler(value);
    } else if (commandHandler) {
      commandHandler(value);
    }
  }
};

void setupAncs() {
  ancsSetupPending = false;
  uint16_t handle = phoneHandle;
  if (handle == BLE_HS_CONN_HANDLE_NONE) return;
  NimBLEClient* client = server->getClient(handle);
  NimBLERemoteService* ancs = client ? client->getService(ANCS_SERVICE) : nullptr;
  if (!ancs) {
    Serial.println("[ancs] service not found (is the puck bonded?)");
    return;
  }
  NimBLERemoteCharacteristic* source = ancs->getCharacteristic(ANCS_NOTIFICATION_SOURCE);
  if (!source) {
    Serial.println("[ancs] notification source not found");
    return;
  }
  ancsSourceHandle = source->getHandle();
  bool ok = source->subscribe(true);
  Serial.printf("[ancs] subscribed=%d\n", ok);
  BleLink::notifyStatus(ok ? "ancs_ok" : "ancs_fail");
}

void handleAncs(const AncsEvent& e) {
  Serial.printf("[ancs] event=%u category=%u uid=%lu flags=0x%02x\n", e.event, e.category,
                (unsigned long)e.uid, e.flags);
  if (e.category == CATEGORY_INCOMING_CALL && e.event == EVENT_ADDED) {
    callHandler(BleLink::CallEvent::Incoming);
  } else if (e.category == CATEGORY_ACTIVE_CALL && e.event == EVENT_ADDED && !activeCall) {
    activeCall = true;
    activeCallUid = e.uid;
    callHandler(BleLink::CallEvent::Answered);
  } else if (e.event == EVENT_REMOVED && activeCall && e.uid == activeCallUid) {
    activeCall = false;
    callHandler(BleLink::CallEvent::Ended);
  }
}

}  // namespace

namespace BleLink {

void begin(std::function<void(const String&)> onConfig, std::function<void(const String&)> onCommand,
           std::function<void(CallEvent)> onCall) {
  configHandler = onConfig;
  commandHandler = onCommand;
  callHandler = onCall;
  ancsEvents = xQueueCreate(16, sizeof(AncsEvent));

  NimBLEDevice::init("Rambu Puck");
  NimBLEDevice::setSecurityAuth(true, false, true);  // bond, no MITM (no screen), secure connections
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);
  ble_gap_event_listener_register(&gapListener, onGapEvent, nullptr);

  server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  NimBLEService* service = server->createService(PUCK_SERVICE);
  static WriteCallbacks writes;

  PuckSettings settings = loadSettings();
  NimBLECharacteristic* info = service->createCharacteristic(INFO_CHAR, NIMBLE_PROPERTY::READ);
  info->setValue(String("{\"puckId\":\"") + settings.puckId + "\",\"firmware\":\"" FIRMWARE_VERSION "\"}");

  NimBLECharacteristic* config =
      service->createCharacteristic(CONFIG_CHAR, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC);
  config->setCallbacks(&writes);

  statusChar = service->createCharacteristic(STATUS_CHAR, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  statusChar->setValue("starting");

  NimBLECharacteristic* command =
      service->createCharacteristic(COMMAND_CHAR, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC);
  command->setCallbacks(&writes);

  service->start();
  server->start();

  NimBLEAdvertisementData advertisement;
  advertisement.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  advertisement.addData(ANCS_SOLICITATION, sizeof(ANCS_SOLICITATION));
  NimBLEAdvertisementData scanResponse;
  scanResponse.addServiceUUID(PUCK_SERVICE);
  scanResponse.setName("Rambu Puck");
  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->setAdvertisementData(advertisement);
  advertising->setScanResponseData(scanResponse);
  advertising->start();
  Serial.println("[ble] advertising as Rambu Puck");
}

void loop() {
  if (ancsSetupPending) setupAncs();
  AncsEvent e;
  while (xQueueReceive(ancsEvents, &e, 0) == pdTRUE) handleAncs(e);
}

void notifyStatus(const String& status) {
  if (!statusChar) return;
  statusChar->setValue(status);
  statusChar->notify();
}

bool phoneConnected() { return phoneHandle != BLE_HS_CONN_HANDLE_NONE; }

}  // namespace BleLink
