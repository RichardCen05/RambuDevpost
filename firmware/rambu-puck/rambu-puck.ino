// Rambu puck: listens to a loudspeaker phone call and sends it to the Rambu backend.
//
// Board: ESP32 DevKit V1 (esp32:esp32:esp32, PartitionScheme=huge_app) + INMP441 mic.
// Recording starts when the bonded iPhone reports an answered call over ANCS and stops when
// the call ends. The Rambu app writes Wi-Fi and server settings over Bluetooth; for bench
// testing, the same settings can be typed on the USB serial console (115200 baud):
//   config {"ssid":"…","pass":"…","url":"https://….trycloudflare.com","token":"…"}
//   start | stop | status

//
// setup() and loop() live in puck_main.cpp.
