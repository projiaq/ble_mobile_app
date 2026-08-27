/// 扫描结果的轻量模型,便于纯 Dart 分类与单测。
library;

class ScanDevice {
  final String id;
  final String name;
  final int? rssi;
  final List<String> serviceUuids;

  /// 厂商特定广播数据，键为 companyId，值为 payload 字节列表。
  /// 与传感器/接收器固件约定一致:companyId = 0xFFFF,
  /// payload = [0xA5, 0x5A, 硬件BCD, 软件BCD, 协议BCD, 设备类型]。
  final Map<int, List<int>> manufacturerData;

  const ScanDevice({
    required this.id,
    this.name = '',
    this.rssi,
    this.serviceUuids = const [],
    this.manufacturerData = const {},
  });
}
