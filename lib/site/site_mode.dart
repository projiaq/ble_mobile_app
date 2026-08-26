/// 站点模式 / 最近设备,与 `phone_app/utils/site.js` 对齐。
library;

import 'package:shared_preferences/shared_preferences.dart';

class SiteMode {
  SiteMode._();

  static const String modeKey = 'site.mode';
  static const String mineModeKey = 'site.mineMode';
  static const String lastRxKey = 'site.lastRx';
  static const String lastSensorKey = 'site.lastSensor';

  static const String modeCustomer = 'customer';
  static const String modeMaintainer = 'maintainer';
  static const String maintainerPassword = '65222kinglong';

  static Future<String> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(modeKey) ?? modeCustomer;
  }

  static Future<String> setMode(String mode) async {
    final next = mode == modeMaintainer ? modeMaintainer : modeCustomer;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(modeKey, next);
    return next;
  }

  static bool isMaintainer(String mode) => mode == modeMaintainer;

  static bool verifyPassword(String password) =>
      password.trim() == maintainerPassword;

  static Future<bool> getMineMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(mineModeKey) ?? false;
  }

  static Future<bool> setMineMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(mineModeKey, enabled);
    return enabled;
  }

  static Future<void> saveLastDevice(
    String key, {
    required String id,
    String name = '',
    int? rssi,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, '$id|$name|${rssi ?? ''}');
  }

  /// 返回 `(id, name, rssi)`;无记录返回 null。
  static Future<(String, String, int?)?> getLastDevice(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.isEmpty) return null;
    final id = parts[0];
    final name = parts.length > 1 ? parts[1] : '';
    final rssi = parts.length > 2 ? int.tryParse(parts[2]) : null;
    return (id, name, rssi);
  }
}
