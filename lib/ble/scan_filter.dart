/// 设备分类与 DFU 广告识别,与 `scan.vue` 的 `deviceKind` 和
/// `ota.js` 的 `isOtaAdvertisement` 对齐。
library;

import '../protocol/constants.dart';
import 'scan_device.dart';

enum DeviceKind { receiver, pressure, tilt, sensor, other }

/// 广播厂商数据约定(与传感器/接收器固件一致): companyId = 0xFFFF,
/// payload = [0xA5, 0x5A, 硬件BCD, 软件BCD, 协议BCD, 设备类型]。
const int advCompanyId = 0xFFFF;
const int advMagic0 = 0xA5;
const int advMagic1 = 0x5A;
const int advTypePressure = 0; // 压力传感器
const int advTypeReceiver = 1; // 接收器
const int advTypeTilt = 2; // 倾角传感器

/// 从广播厂商数据中解析出的设备附加信息。
class AdvInfo {
  final int hwVer; // BCD: 高 4 位主版本, 低 4 位次版本
  final int swVer;
  final int protoVer;
  final int devType; // advTypePressure / advTypeReceiver / advTypeTilt

  const AdvInfo({
    required this.hwVer,
    required this.swVer,
    required this.protoVer,
    required this.devType,
  });
}

/// 解析广播厂商数据;未携带或不完整时返回 null。
AdvInfo? parseAdvInfo(ScanDevice device) {
  final data = device.manufacturerData[advCompanyId];
  if (data == null || data.length < 6) return null;
  if (data[0] != advMagic0 || data[1] != advMagic1) return null;
  if (!_isBcd(data[2]) || !_isBcd(data[3]) || !_isBcd(data[4])) {
    return null;
  }
  if (data[5] != advTypePressure &&
      data[5] != advTypeReceiver &&
      data[5] != advTypeTilt) {
    return null;
  }
  return AdvInfo(
    hwVer: data[2],
    swVer: data[3],
    protoVer: data[4],
    devType: data[5],
  );
}

bool _isBcd(int value) =>
    value >= 0 && value <= 0xFF && (value >> 4) <= 9 && (value & 0x0F) <= 9;

/// BCD 版本号 → 如 "V1.0"。
String formatVersion(int bcd) => 'V${bcd >> 4}.${bcd & 0xF}';

String receiverDisplayName(String deviceId, int receiverId) {
  final hex = deviceId.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  final suffix = hex.length >= 4 ? hex.substring(hex.length - 4) : hex.padLeft(4, '0');
  return 'AIOT_${suffix}_#${(receiverId % 1000).toString().padLeft(3, '0')}';
}

/// 按广播厂商数据中的设备类型分类,缺失时回退名称前缀与服务 UUID。
DeviceKind classifyDevice(ScanDevice device) {
  final info = parseAdvInfo(device);
  if (info != null) {
    switch (info.devType) {
      case advTypeReceiver:
        return DeviceKind.receiver;
      case advTypeTilt:
        return DeviceKind.tilt;
      case advTypePressure:
        return DeviceKind.pressure;
    }
  }
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
