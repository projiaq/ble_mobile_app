/// 扫描结果的轻量模型,便于纯 Dart 分类与单测。
library;

class ScanDevice {
  final String id;
  final String name;
  final int? rssi;
  final List<String> serviceUuids;

  const ScanDevice({
    required this.id,
    this.name = '',
    this.rssi,
    this.serviceUuids = const [],
  });
}
