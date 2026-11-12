#ifndef ROBOT_SHARED_CONFIG_H
#define ROBOT_SHARED_CONFIG_H
// Change these for YOUR robot before uploading. No sender credentials included.
static const char ROBOT_AP_SSID[]="UOB_Square_Teammate";
static const char ROBOT_AP_PASSWORD[]="CHANGE_ME_BEFORE_FLASH";
static const char ROBOT_MDNS_HOST[]="square-teammate";
static const char PRIMARY_WIFI_SSID[]="YOUR_PRIMARY_WIFI";
static const char BACKUP_WIFI_SSID[]="YOUR_BACKUP_WIFI";
static_assert(sizeof(ROBOT_AP_SSID)<=33,"SSID must be at most 32 bytes");
static_assert(sizeof(ROBOT_MDNS_HOST)<=33,"Use a short unique hostname");
#endif
