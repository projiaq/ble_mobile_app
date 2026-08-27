/// 扫描结果的轻量模型,便于纯 Dart 分类与单测。
library;

class ScanDevice {
  final String id;
  final String name;
  final int? rssi;
  final List<String> serviceUuids;

  /// 厂商特定广播数据:<companyId, payload>。
  /// 与传感器/接收器固件约定一致:companyId = 0xFFFF,
  /// payload = [硬件版本BCD, 软件版本BCD, 协议版本BCD, 设备类型]。
  final Map<int, List<int>> manufacturerData;

  const ScanDevice({
    required this.id,
    this.name = '',
    this.rssi,
    this.serviceUuids = const [],
    this.manufacturerData = const {},
  });
}