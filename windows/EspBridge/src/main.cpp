// SPDX-License-Identifier: MIT
// BandFace ESP32 bridge (експериментально): ESP32-S3 / ESP32-C3 як Bluetooth LE для BandFace на ПК без Bluetooth.
// ПК говорить текстовими рядками через USB (COM-порт), ESP32 — по BLE з браслетом:
//   HELLO                → OK BRIDGE 2, PAIRED …
//   INFO                 → PAIRED <адреса> <тип> <назва> | PAIRED -        (з яким браслетом спарена плата)
//   SCAN 1 | SCAN 0      → ADV <адреса> <тип> <rssi> <fe95 0|1> <назва>   (поки йде пошук)
//   CONN <адреса> <тип> [назва] → [PAIRED …] CONNECTED <mtu> | ERR <причина>
//   UNPAIR               → PAIRED -   (забути спарювання)
//   W <hex>              → K (записано без відповіді в 0x5F) | E <причина>
//   DISC                 → DISCONNECTED
// Самі по собі: N <hex> — сповіщення з 0x5E, DISCONNECTED — зв'язок втрачено, LOG <текст>.
// Зв'язування — LE Secure Connections «Just Works», як у Mi Fitness і BandFace для Windows.
// Ключі спарювання й браслет зберігаються у flash ESP32: повторне підключення — без підтвердження на браслеті.
// USB: вбудований USB чипа (Serial) або USB-UART міст плати (Serial0) — працюємо з тим, звідки прийшов HELLO.
// Світлодіод (лише S3-Zero): синій — пошук, жовтий — підключення, зелений — підключено, червоний — помилка.

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <algorithm>

static const NimBLEUUID SVC((uint16_t)0xFE95);
static const NimBLEUUID RX_UUID((uint16_t)0x005E);
static const NimBLEUUID TX_UUID((uint16_t)0x005F);

static SemaphoreHandle_t outLock;
static Stream* io = nullptr;  // порт, з якого прийшов HELLO
static NimBLEClient* client = nullptr;
static NimBLERemoteCharacteristic* txChar = nullptr;
static volatile bool connected = false;
static bool scanning = false;
static int scanSeen = 0, scanShown = 0;

// Спарений браслет (NVS «bridge»)
static Preferences prefs;
static String pAddr, pName;
static int pType = 0;
static String idAddr;  // справжня (identity) адреса браслета з останнього спарювання
static int idType = 0;

static void led(uint8_t r, uint8_t g, uint8_t b) {
#ifdef BRIDGE_RGB_LED
  neopixelWrite(BRIDGE_RGB_LED, r / 8, g / 8, b / 8);
#endif
}

static void out(const String& s) {
  Stream* p = io;
  if (!p) return;
  xSemaphoreTake(outLock, portMAX_DELAY);
  p->print(s);
  p->print('\n');
  xSemaphoreGive(outLock);
}

static const char HEX_DIGITS[] = "0123456789abcdef";

static void outHex(const char* prefix, const uint8_t* d, size_t n) {
  String s;
  s.reserve(strlen(prefix) + 1 + n * 2);
  s += prefix;
  s += ' ';
  for (size_t i = 0; i < n; i++) { s += HEX_DIGITS[d[i] >> 4]; s += HEX_DIGITS[d[i] & 15]; }
  out(s);
}

static int hexVal(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

// MARK: Пошук

class ScanCb : public NimBLEAdvertisedDeviceCallbacks {
  void onResult(NimBLEAdvertisedDevice* d) override {
    scanSeen++;
    String name = d->haveName() ? String(d->getName().c_str()) : String("");
    bool fe95 = d->isAdvertisingService(SVC);
    if (name.length() == 0 && !fe95) return;
    scanShown++;
    name.replace("\n", " ");
    name.replace("\r", " ");
    out("ADV " + String(d->getAddress().toString().c_str()) + " " + String(d->getAddress().getType()) + " " +
        String(d->getRSSI()) + " " + String(fe95 ? 1 : 0) + " " + name);
  }
};
static ScanCb scanCb;

static void startScan() {
  NimBLEScan* s = NimBLEDevice::getScan();
  s->setAdvertisedDeviceCallbacks(&scanCb, false);
  s->setActiveScan(true);
  s->setInterval(100);
  s->setWindow(90);
  scanSeen = scanShown = 0;
  s->start(0, nullptr, false);
  scanning = true;
  led(0, 0, 255);
}

static void stopScan() {
  if (scanning) out("LOG scan: " + String(scanSeen) + " devices heard, " + String(scanShown) + " with a name or Xiaomi service");
  NimBLEDevice::getScan()->stop();
  NimBLEDevice::getScan()->clearResults();
  scanning = false;
  if (connected) led(0, 255, 0); else led(20, 20, 20);
}

// MARK: З'єднання

class ClientCb : public NimBLEClientCallbacks {
  void onDisconnect(NimBLEClient* c) override {
    bool was = connected;
    connected = false;
    txChar = nullptr;
    led(255, 0, 0);
    if (was) out("DISCONNECTED");
  }
  uint32_t onPassKeyRequest() override { return 0; }
  bool onConfirmPIN(uint32_t pin) override { return true; }
  void onAuthenticationComplete(ble_gap_conn_desc* desc) override {
    NimBLEAddress id(desc->peer_id_addr);
    idAddr = String(id.toString().c_str());
    idType = id.getType();
    out("LOG auth encrypted=" + String(desc->sec_state.encrypted) + " bonded=" + String(desc->sec_state.bonded) +
        " key=" + String(desc->sec_state.key_size) + " id=" + idAddr);
  }
};
static ClientCb clientCb;

static void onNotify(NimBLERemoteCharacteristic* c, uint8_t* data, size_t len, bool isNotify) {
  outHex("N", data, len);
}

static void reportPaired() {
  if (pAddr.length() == 0) out("PAIRED -");
  else out("PAIRED " + pAddr + " " + String(pType) + " " + pName);
}

static void loadPaired() {
  prefs.begin("bridge", true);
  pAddr = prefs.getString("addr", "");
  pType = prefs.getInt("type", 0);
  pName = prefs.getString("name", "");
  prefs.end();
}

static void savePaired() {
  prefs.begin("bridge", false);
  prefs.putString("addr", pAddr);
  prefs.putInt("type", pType);
  prefs.putString("name", pName);
  prefs.end();
}

static void fail(const char* why) {
  connected = false;
  txChar = nullptr;
  if (client && client->isConnected()) client->disconnect();
  led(255, 0, 0);
  out(String("ERR ") + why);
}

static void doConnect(const char* addr, int type, const char* name) {
  if (scanning) stopScan();
  if (client && client->isConnected()) { connected = false; client->disconnect(); delay(300); }
  led(255, 160, 0);
  if (!client) {
    client = NimBLEDevice::createClient();
    client->setClientCallbacks(&clientCb, false);
    client->setConnectionParams(12, 24, 0, 400);
    client->setConnectTimeout(15);
  }
  NimBLEAddress a(std::string(addr), (uint8_t)type);
  bool bonded = NimBLEDevice::isBonded(a);
  idAddr = "";
  out(String("LOG connecting ") + addr + (bonded ? " (paired before)" : " (new pairing)"));
  if (!client->connect(a, true)) return fail("connect");
  out("LOG link up, mtu=" + String(client->getMTU()) + (bonded ? ", encrypting with saved keys" : ", pairing"));
  if (!client->secureConnection()) {
    if (!bonded) return fail("pairing");
    // браслет не прийняв збережені ключі (його скинули або спарили з іншим) — спарюємось наново
    out("LOG saved keys rejected, pairing again");
    if (client->isConnected()) client->disconnect();
    delay(600);
    NimBLEDevice::deleteBond(a);
    if (!client->connect(a, true)) return fail("connect");
    if (!client->secureConnection()) return fail("pairing");
  }
  NimBLERemoteService* s = client->getService(SVC);
  if (!s) return fail("service");
  NimBLERemoteCharacteristic* rx = s->getCharacteristic(RX_UUID);
  NimBLERemoteCharacteristic* tx = s->getCharacteristic(TX_UUID);
  if (!rx || !tx) return fail("characteristic");
  if (!rx->subscribe(true, onNotify, true)) return fail("notify");
  txChar = tx;
  connected = true;
  led(0, 255, 0);
  // запам'ятовуємо спарений браслет; попередній (якщо інший) забуваємо
  String saveA = idAddr.length() ? idAddr : String(addr);
  int saveT = idAddr.length() ? idType : type;
  if (pAddr.length() && !pAddr.equalsIgnoreCase(saveA) && !pAddr.equalsIgnoreCase(String(addr)))
    NimBLEDevice::deleteBond(NimBLEAddress(std::string(pAddr.c_str()), (uint8_t)pType));
  if (!pAddr.equalsIgnoreCase(saveA) || pType != saveT || (name[0] && pName != name)) {
    pAddr = saveA;
    pType = saveT;
    if (name[0]) pName = name;
    savePaired();
  }
  reportPaired();
  out("CONNECTED " + String(client->getMTU()));
}

// MARK: Запис

static uint8_t wbuf[1200];

static void doWrite(const char* hex) {
  size_t n = 0;
  while (hex[0] && hex[1] && n < sizeof(wbuf)) {
    int hi = hexVal(hex[0]), lo = hexVal(hex[1]);
    if (hi < 0 || lo < 0) { out("E hex"); return; }
    wbuf[n++] = (uint8_t)(hi << 4 | lo);
    hex += 2;
  }
  if (!connected || !txChar) { out("E disconnected"); return; }
  size_t chunk = client->getMTU() > 23 ? client->getMTU() - 3 : 20;
  for (size_t off = 0; off < n; off += chunk) {
    size_t len = std::min(chunk, n - off);
    bool ok = false;
    // запис без відповіді: якщо буфери стеку зайняті — трохи чекаємо
    for (int attempt = 0; attempt < 300 && !ok; attempt++) {
      ok = txChar->writeValue(wbuf + off, len, false);
      if (!ok) { if (!connected) break; delay(3); }
    }
    if (!ok) { out("E write"); return; }
  }
  out("K");
}

// MARK: Команди

static void handle(Stream* from, char* l) {
  if (strcmp(l, "HELLO") == 0) { io = from; out("OK BRIDGE 2"); reportPaired(); return; }
  if (from != io) return;  // поки ПК не привітався — нічого не робимо
  if (strncmp(l, "SCAN ", 5) == 0) { if (l[5] == '1') startScan(); else stopScan(); return; }
  if (strncmp(l, "CONN ", 5) == 0) {
    char addr[32] = {0};
    int type = 0, used = 0;
    if (sscanf(l + 5, "%31s %d %n", addr, &type, &used) < 1) { out("ERR args"); return; }
    const char* name = used > 0 ? l + 5 + used : "";
    doConnect(addr, type, name);
    return;
  }
  if (strcmp(l, "INFO") == 0) { reportPaired(); return; }
  if (strcmp(l, "UNPAIR") == 0) {
    bool was = connected;
    connected = false;
    txChar = nullptr;
    if (client && client->isConnected()) client->disconnect();
    NimBLEDevice::deleteAllBonds();
    pAddr = ""; pName = ""; pType = 0;
    savePaired();
    led(20, 20, 20);
    if (was) out("DISCONNECTED");
    reportPaired();
    return;
  }
  if (strncmp(l, "W ", 2) == 0) { doWrite(l + 2); return; }
  if (strcmp(l, "DISC") == 0) {
    connected = false;
    txChar = nullptr;
    if (client && client->isConnected()) client->disconnect();
    led(20, 20, 20);
    out("DISCONNECTED");
    return;
  }
  out("LOG unknown command");
}

struct LineReader {
  Stream* port;
  char buf[2600];
  size_t len;
  explicit LineReader(Stream* p) : port(p), len(0) {}
  void poll() {
    while (port->available()) {
      int c = port->read();
      if (c < 0) break;
      if (c == '\r') continue;
      if (c == '\n') {
        buf[len] = 0;
        if (len > 0) handle(port, buf);
        len = 0;
      } else if (len < sizeof(buf) - 1) {
        buf[len++] = (char)c;
      }
    }
  }
};

static LineReader usbReader(&Serial);    // вбудований USB (S3-Zero, C3 Super Mini)
static LineReader uartReader(&Serial0);  // USB-UART міст на платі (CH340 / CP2102)

void setup() {
  outLock = xSemaphoreCreateMutex();
  Serial.setRxBufferSize(8192);
  Serial.begin(115200);
  Serial0.setRxBufferSize(8192);
  Serial0.begin(921600);  // для CH340 / CP2102; вбудованому USB швидкість байдужа
  led(20, 20, 20);
  NimBLEDevice::init("BandFace bridge");
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  NimBLEDevice::setMTU(247);
  NimBLEDevice::setSecurityAuth(true, false, true);  // зв'язування, без MITM, Secure Connections
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);
  loadPaired();
}

void loop() {
  usbReader.poll();
  uartReader.poll();
  delay(1);
}
