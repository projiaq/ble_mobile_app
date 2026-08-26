/// 设备分类与 DFU 广告识别,与 `scan.vue` 的 `deviceKind` 和
/// `ota.js` 的 `isOtaAdvertisement` 对齐。
library;

import '../protocol/constants.dart';
import 'scan_device.dart';

enum DeviceKind { receiver, pressure, tilt, sensor, other }

String receiverDisplayName(String deviceId, int receiverId) {
  final hex = deviceId.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  final suffix = hex.length >= 4 ? hex.substring(hex.length - 4) : hex.padLeft(4, '0');
  return 'AIOT_${suffix}_#${(receiverId % 1000).toString().padLeft(3, '0')}';
}

/// 按名称前缀与服务 UUID 分类。
DeviceKind classifyDevice(ScanDevice device) {
  final name = device.name.toUpperCase();
  final uuids = device.serviceUuids.map((u) => u.toUpperCase());
  if (name.startsWith('AIOT-') ||
      name.startsWith('AIOT_') ||
      name.startsWith('RX-') ||
      name == 'MCMPDT' ||
      uuids.any((u) => u.contains('6F8A0000'))) {
    return DeviceKind.receiver;
  }
  if (name.startsWith('TILT-') || name == 'TILTNODE' || name.contains('TILT')) {
    return DeviceKind.tilt;
  }
  if (name.startsWith('PRES-') ||
      name.startsWith('PRESS-') ||
      name == 'PRESSNODE' ||
      name.contains('PRESS')) {
    return DeviceKind.pressure;
  }
  if (uuids.any((u) => u.contains('C8E21E04')) || name == 'SENSORNODE') {
    return DeviceKind.sensor;
  }
  return DeviceKind.other;
}

/// 传感器类型(压力/倾角);非传感器返回 null。
int? sensorTypeOf(DeviceKind kind) {
  switch (kind) {
    case DeviceKind.tilt:
      return typeTilt;
    case DeviceKind.pressure:
      return typePressure;
    default:
      return null;
  }
}

/// 判断是否为 DFU 模式广告(OTA/APPL/DFU 名称、OTA 服务 UUID 或设备 id 匹配)。
/// 注:原 ota.js 还按广告里 type 0x1B 的原始地址匹配,iOS 相关;
/// flutter_blue_plus 不暴露原始 adv bytes,Android 下设备 id 即 MAC,此路径可省略。
bool isOtaAdvertisement(ScanDevice device, String originalId) {
  final name = device.name.trim().toUpperCase();
  final sameId = device.id.isNotEmpty && device.id == originalId;
  final otaName = name == 'OTA' || name.contains('APPL') || name.contains('DFU');
  if (sameId && (otaName || name.isEmpty)) return true;
  final hasOtaService =
      device.serviceUuids.any((u) => u.toUpperCase().contains('1D14D6EE'));
  return otaName || hasOtaService;
}
