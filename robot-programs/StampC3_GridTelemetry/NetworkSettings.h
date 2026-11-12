#ifndef LPATH_NETWORK_SETTINGS_H
#define LPATH_NETWORK_SETTINGS_H
#include <WebServer.h>
#include "RobotWifiAP.h"

// Priority is fixed: Resident first, phone second. No motion commands exist here.
class NetworkSettings_c {
 public:
  explicit NetworkSettings_c(RobotWifiAP_c &transport, const char *apPassword);
  void begin();
  void update(bool stopped);
 private:
  struct Config {
    uint32_t magic;
    char ssid[2][33];
    char password[2][64];
  } config{};
  static constexpr uint32_t MAGIC = 0x4c503201;
  static constexpr unsigned long CONNECT_TIMEOUT_MS = 15000;
  static constexpr unsigned long RETRY_MS = 15000;
  static constexpr unsigned long PRIORITY_CHECK_MS = 60000;
  RobotWifiAP_c &transport;
  const char *apPassword;
  WebServer web{8080};
  bool stopped = true;
  bool scanning = false;
  bool connecting = false;
  bool visible[2] = {false, false};
  uint8_t failedMask = 0;
  int trying = -1;
  int connectedProfile = -1;
  unsigned long attemptAt = 0;
  unsigned long scanAt = 0;
  unsigned long residentRetryAt = 0;
  String reportedIp;
  String command;
  bool commandOverflow = false;
  bool restartPending = false;
  unsigned long restartAt = 0;
  bool load();
  bool save(const Config &candidate);
  bool configured(int profile) const;
  bool setProfile(int profile, const String &ssid, const String &password);
  void serialInput();
  void executeCommand(const String &line);
  void startScan(unsigned long now);
  void finishScan(unsigned long now);
  void connectNext(unsigned long now);
  void connectProfile(int profile, unsigned long now);
  void restart(unsigned long now);
  void report();
  String statusJson() const;
  bool allowRequest(bool mutation = false);
  void handleSave();
};
#endif
