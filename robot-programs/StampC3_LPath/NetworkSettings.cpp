#include "NetworkSettings.h"
#include "RobotSharedConfig.h"
#include <Preferences.h>
#include <ESPmDNS.h>
#include "RemoteControl.h"
#include <cstring>

namespace {
bool due(unsigned long now, unsigned long deadline) {
  return static_cast<int32_t>(now - deadline) >= 0;
}
String jsonString(const char *value) {
  String result = "\"";
  for (const unsigned char *p = reinterpret_cast<const unsigned char *>(value); *p; ++p) {
    if (*p == '"' || *p == '\\') { result += '\\'; result += static_cast<char>(*p); }
    else if (*p < 32) { char escaped[7]; snprintf(escaped, sizeof(escaped), "\\u%04x", *p); result += escaped; }
    else result += static_cast<char>(*p);
  }
  return result + '"';
}
const char PAGE[] PROGMEM = R"HTML(<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LPath Wi-Fi</title>
<style>body{font:16px system-ui;max-width:680px;margin:30px auto;padding:16px;background:#f4f6f8;color:#172337}section{background:white;padding:20px;margin:14px 0;border-radius:12px}input{box-sizing:border-box;width:100%;padding:10px;margin:6px 0 12px}button{padding:10px 18px;cursor:pointer}pre{white-space:pre-wrap;overflow-wrap:anywhere}small{color:#46586d}</style>
<h1>Robot Wi-Fi</h1><p>Automatic priority: Resident first, phone second. The robot hotspot stays available. Network changes and priority checks wait until the robot is stopped.</p><section><h2>Status</h2><pre id="status">Loading...</pre><button id="retry">Search again</button></section>
<section><h2>1. Resident</h2><form data-profile="0"><label>Wi-Fi name<input name="ssid" maxlength="32" required></label><label>Password<input name="password" type="password" maxlength="63" autocomplete="new-password" placeholder="Leave blank to keep saved password"></label><button>Save</button><small class="saved"></small></form></section>
<section><h2>2. Phone hotspot</h2><form data-profile="1"><label>Wi-Fi name<input name="ssid" maxlength="32" required></label><label>Password<input name="password" type="password" maxlength="63" autocomplete="new-password" placeholder="Leave blank to keep saved password"></label><button>Save</button><small class="saved"></small></form></section><p id="message" role="status"></p>
<p>Use the connected network's robot IP on TCP port 80 in the Digital Twin. Configuration is available through the robot hotspot on port 8080. A connected status does not establish Internet access or peer-to-peer access on the upstream network.</p>
<script>
const statusEl=document.getElementById('status'),message=document.getElementById('message');let initial=true;
async function refresh(){try{const r=await fetch('/api/network',{cache:'no-store'});if(!r.ok)throw Error('Status '+r.status);const d=await r.json();statusEl.textContent='Policy: Resident > phone\nState: '+d.state+'\nConnected network: '+(d.connected_ssid||'none')+'\nUpstream robot IP: '+d.upstream_ip+'\nRobot hotspot IP: '+d.ap_ip+'\nTelemetry: TCP 80';for(const p of d.profiles){const f=document.querySelector('form[data-profile="'+p.id+'"]');if(initial)f.elements.ssid.value=p.ssid;f.querySelector('.saved').textContent=p.configured?' Password saved':' Password needed';}initial=false;}catch(e){statusEl.textContent='Reconnect to the robot hotspot and refresh. Settings are unavailable while the robot is moving.';}}
async function post(path,data){const r=await fetch(path,{method:'POST',headers:{'X-Robot-Config':'1','Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams(data)});const text=await r.text();if(!r.ok)throw Error(text);return text;}
document.querySelectorAll('form').forEach(f=>f.addEventListener('submit',async e=>{e.preventDefault();try{message.textContent=await post('/api/profile',{profile:f.dataset.profile,ssid:f.elements.ssid.value,password:f.elements.password.value});f.elements.password.value='';}catch(err){message.textContent=err.message;}}));
document.getElementById('retry').onclick=async()=>{try{message.textContent=await post('/api/rescan',{});}catch(e){message.textContent=e.message;}};refresh();setInterval(refresh,3000);
</script></html>)HTML";
}

NetworkSettings_c::NetworkSettings_c(RobotWifiAP_c &server, const char *password)
    : transport(server), apPassword(password) {}

bool NetworkSettings_c::configured(int p) const {
  return p >= 0 && p < 2 && config.ssid[p][0] && strlen(config.password[p]) >= 8;
}

bool NetworkSettings_c::load() {
  Preferences preferences;
  if (!preferences.begin("lpathnet", true)) return false;
  Config stored{};
  const bool read = preferences.getBytesLength("profiles") == sizeof(stored) &&
      preferences.getBytes("profiles", &stored, sizeof(stored)) == sizeof(stored);
  preferences.end();
  if (!read || stored.magic != MAGIC) return false;
  for (int p = 0; p < 2; ++p) {
    if (!memchr(stored.ssid[p], 0, sizeof(stored.ssid[p])) ||
        !memchr(stored.password[p], 0, sizeof(stored.password[p]))) return false;
    size_t n = strlen(stored.password[p]);
    if (n && n < 8) return false;
  }
  config = stored;
  return true;
}

bool NetworkSettings_c::save(const Config &candidate) {
  Preferences preferences;
  if (!preferences.begin("lpathnet", false)) return false;
  const bool ok = preferences.putBytes("profiles", &candidate, sizeof(candidate)) == sizeof(candidate);
  preferences.end();
  if (ok) config = candidate;
  return ok;
}

bool NetworkSettings_c::setProfile(int p, const String &ssid, const String &password) {
  if (p < 0 || p > 1 || ssid.length() == 0 || ssid.length() > 32 ||
      ssid.indexOf('\t') >= 0 || ssid.indexOf('\n') >= 0 || ssid.indexOf('\r') >= 0 ||
      password.length() < 8 || password.length() > 63 || password.indexOf('\t') >= 0 ||
      password.indexOf('\n') >= 0 || password.indexOf('\r') >= 0) return false;
  Config candidate = config;
  ssid.toCharArray(candidate.ssid[p], sizeof(candidate.ssid[p]));
  password.toCharArray(candidate.password[p], sizeof(candidate.password[p]));
  return save(candidate);
}

void NetworkSettings_c::begin() {
  config.magic = MAGIC;
  strcpy(config.ssid[0], PRIMARY_WIFI_SSID);
  strcpy(config.ssid[1], BACKUP_WIFI_SSID);
  load(); // No upstream password is embedded in distributable source.
  if (MDNS.begin(ROBOT_MDNS_HOST)) MDNS.addService("lpath-telemetry", "tcp", 80);
  const char *headers[] = {"X-Robot-Config"};
  web.collectHeaders(headers, 1);
  web.on("/", HTTP_GET, [this]() {
    if (allowRequest()) web.send_P(200, "text/html; charset=utf-8", PAGE);
  });
  web.on("/api/network", HTTP_GET, [this]() {
    if (allowRequest()) web.send(200, "application/json", statusJson());
  });
  web.on("/api/profile", HTTP_POST, [this]() { handleSave(); });
  web.on("/api/rescan", HTTP_POST, [this]() {
    if (!allowRequest(true)) return;
    restartPending = true; restartAt = millis() + 500;
    web.send(202, "text/plain", "Automatic network search scheduled.");
  });
  web.onNotFound([this]() { web.send(404, "text/plain", "Not found"); });
  web.begin();
  scanAt = millis() + 1000;
  Serial.println("WIFI configuration: http://192.168.4.1:8080 user=robot; password=same as robot hotspot");
  report();
}

bool NetworkSettings_c::allowRequest(bool mutation) {
  web.sendHeader("Cache-Control", "no-store");
  // Never expose credentials configuration through a shared upstream LAN.
  if (web.client().localIP() != WiFi.softAPIP()) {
    web.send(403, "text/plain", "Join the robot hotspot to configure Wi-Fi."); return false;
  }
  if (!web.authenticate("robot", apPassword)) { web.requestAuthentication(); return false; }
  if (!stopped) { web.send(409, "text/plain", "Stop the robot first."); return false; }
  if (mutation && web.header("X-Robot-Config") != "1") {
    web.send(403, "text/plain", "Use the robot configuration page."); return false;
  }
  return true;
}

void NetworkSettings_c::handleSave() {
  if (!allowRequest(true)) return;
  const String profile = web.arg("profile");
  if (profile != "0" && profile != "1") { web.send(400, "text/plain", "Invalid profile."); return; }
  const int p = profile.toInt();
  String password = web.arg("password");
  if (password.isEmpty()) password = config.password[p];
  if (!setProfile(p, web.arg("ssid"), password)) {
    web.send(400, "text/plain", "Save failed. Use a 1-32 byte name and 8-63 byte password."); return;
  }
  restartPending = true; restartAt = millis() + 500;
  web.send(202, "text/plain", "Saved. Automatic priority remains Resident first, phone second.");
}

void NetworkSettings_c::serialInput() {
  for (int budget = 0; budget < 24 && Serial.available(); ++budget) {
    char ch = static_cast<char>(Serial.read());
    if (ch == '\r') continue;
    if (ch == '\n') {
      if (!commandOverflow && command.length()) executeCommand(command);
      else if (commandOverflow) Serial.println("WIFI error=command_too_long");
      command = ""; commandOverflow = false;
    } else if (command.length() < 160 && !commandOverflow) command += ch;
    else commandOverflow = true;
  }
}

void NetworkSettings_c::executeCommand(const String &line) {
  if (line == "NET STATUS") { if (stopped) report(); return; }
  if (!stopped) { Serial.println("WIFI error=robot_must_be_stopped"); return; }
  if (line == "NET CONTROLTEST") {
    Serial.printf("CONTROL_SELFTEST %s\n", remoteControlSelfTest() ? "PASS" : "FAIL"); return;
  }
  if (line.startsWith("NET CONTROLKEY ")) {
    String key = line.substring(15); key.toLowerCase();
    if (!RemoteControl_c::isHex(key.c_str(), 32)) { Serial.println("CONTROL invalid_key"); return; }
    Preferences preferences;
    if (!preferences.begin("lpathnet", false)) { Serial.println("CONTROL storage_failed"); return; }
    bool saved = preferences.putString("ctrlkey", key) == 32;
    preferences.end();
    Serial.println(saved ? "CONTROL key_saved_restart_required" : "CONTROL storage_failed");
    return;
  }
  if (line == "NET RESCAN") {
    restartPending = true; restartAt = millis() + 500;
    Serial.println("WIFI automatic_rescan_scheduled"); return;
  }
  if (line.startsWith("NET SET 0 ") || line.startsWith("NET SET 1 ")) {
    const int p = line.charAt(8) - '0';
    const int separator = line.indexOf('\t', 10);
    if (separator > 10 && setProfile(p, line.substring(10, separator), line.substring(separator + 1))) {
      Serial.printf("WIFI saved profile=%d\n", p);
      restartPending = true; restartAt = millis() + 1000;
    } else Serial.println("WIFI error=invalid_profile_or_storage_failure");
    return;
  }
  Serial.println("WIFI error=unknown_command");
}

void NetworkSettings_c::report() {
  const bool connected = WiFi.status() == WL_CONNECTED;
  Serial.printf("WIFI state=%s profile=%d sta_ip=%s ap_ip=%s configured_0=%d configured_1=%d tcp_port=80 gpio3=%d\n",
      connected ? "connected" : (connecting ? "connecting" : (scanning ? "scanning" : "disconnected")),
      connected ? connectedProfile : trying, WiFi.localIP().toString().c_str(),
      WiFi.softAPIP().toString().c_str(), configured(0), configured(1), digitalRead(3));
}

String NetworkSettings_c::statusJson() const {
  const bool connected = WiFi.status() == WL_CONNECTED;
  String result = "{\"policy\":\"resident_then_phone\",\"state\":";
  result += jsonString(connected ? "connected" : (connecting ? "connecting" : (scanning ? "scanning" : "searching")));
  result += ",\"connected_ssid\":" + jsonString(connected ? WiFi.SSID().c_str() : "");
  result += ",\"upstream_ip\":" + jsonString(WiFi.localIP().toString().c_str());
  result += ",\"ap_ip\":" + jsonString(WiFi.softAPIP().toString().c_str());
  result += ",\"profiles\":[";
  for (int p = 0; p < 2; ++p) {
    if (p) result += ',';
    result += "{\"id\":" + String(p) + ",\"ssid\":" + jsonString(config.ssid[p]) +
        ",\"configured\":" + (configured(p) ? "true" : "false") + '}';
  }
  return result + "]}";
}

void NetworkSettings_c::restart(unsigned long now) {
  transport.disconnectClient();
  WiFi.disconnect(false, false);
  if (scanning) WiFi.scanDelete();
  scanning = false; connecting = false; trying = -1; connectedProfile = -1;
  failedMask = 0; reportedIp = ""; residentRetryAt = now; scanAt = now + 250;
  restartPending = false;
}

void NetworkSettings_c::startScan(unsigned long now) {
  // Async scan: no blocking wait in the controller loop.
  const int result = WiFi.scanNetworks(true, false, false, 120);
  if (result == WIFI_SCAN_FAILED) { scanAt = now + RETRY_MS; return; }
  scanning = true; failedMask = 0;
}

void NetworkSettings_c::finishScan(unsigned long now) {
  const int count = WiFi.scanComplete();
  if (count == WIFI_SCAN_RUNNING) return;
  visible[0] = visible[1] = false;
  for (int i = 0; i < count; ++i) {
    for (int p = 0; p < 2; ++p) {
      if (configured(p) && WiFi.SSID(i) == config.ssid[p]) visible[p] = true;
    }
  }
  WiFi.scanDelete(); scanning = false;
  if (WiFi.status() == WL_CONNECTED) {
    if (connectedProfile == 1 && visible[0] && due(now, residentRetryAt)) connectProfile(0, now);
    else scanAt = now + PRIORITY_CHECK_MS;
  } else connectNext(now);
}

void NetworkSettings_c::connectNext(unsigned long now) {
  for (int p = 0; p < 2; ++p) {
    if (visible[p] && configured(p) && !(failedMask & (1 << p))) {
      connectProfile(p, now); return;
    }
  }
  trying = -1; connecting = false; scanAt = now + RETRY_MS;
  Serial.println("WIFI no_reachable_configured_network; robot_hotspot_retained");
}

void NetworkSettings_c::connectProfile(int p, unsigned long now) {
  transport.disconnectClient();
  WiFi.disconnect(false, false);
  trying = p; connectedProfile = -1; reportedIp = "";
  connecting = true; attemptAt = now;
  WiFi.begin(config.ssid[p], config.password[p]);
  Serial.printf("WIFI connecting profile=%d ssid=%s\n", p, config.ssid[p]);
}

void NetworkSettings_c::update(bool isStopped) {
  stopped = isStopped;
  serialInput();
  if (!stopped) return; // No HTTP processing, scans, retries or switches in motion.
  web.handleClient();
  const unsigned long now = millis();
  if (restartPending && due(now, restartAt)) restart(now);
  if (WiFi.status() == WL_CONNECTED) {
    if (connecting) {
      connectedProfile = trying; connecting = false; trying = -1;
      scanAt = now + PRIORITY_CHECK_MS;
    }
    const String address = WiFi.localIP().toString();
    if (reportedIp != address) { reportedIp = address; report(); }
    if (scanning) finishScan(now);
    else if (connectedProfile == 1 && due(now, scanAt) && due(now, residentRetryAt)) startScan(now);
    return;
  }
  if (!reportedIp.isEmpty()) {
    reportedIp = ""; connectedProfile = -1; scanAt = now + 250;
    Serial.println("WIFI upstream_lost; automatic_fallback_pending");
  }
  if (connecting) {
    if (now - attemptAt >= CONNECT_TIMEOUT_MS) {
      failedMask |= (1 << trying);
      if (trying == 0) residentRetryAt = now + 2 * PRIORITY_CHECK_MS;
      Serial.printf("WIFI connection_timeout profile=%d\n", trying);
      WiFi.disconnect(false, false); connecting = false;
      connectNext(now);
    }
  } else if (scanning) finishScan(now);
  else if (due(now, scanAt) && (configured(0) || configured(1))) startScan(now);
}
