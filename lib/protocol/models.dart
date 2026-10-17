/// BLE 协议解析出的不可变数据模型,与 `phone_app/utils/protocol.js` 逐字节对齐。
library;

import 'dart:typed_data';

/// 6 字节地址转 `AA:BB:CC:DD:EE:FF` 显示格式。
String bytesToMac(Uint8List bytes) => bytes
    .map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

/// 位图按位判断。
bool bit(int map, int i) => ((map >> i) & 1) != 0;

/// 位图中置 1 的位数。
int popcount(int value) {
  var v = value;
  var count = 0;
  while (v != 0) {
    count += v & 1;
    v >>= 1;
  }
  return count;
}

/// 接收器状态(8 字节)。
class ReceiverStatus {
  final int ver;
  final int rid;
  final int bound;
  final int online;
  final int valid;
  final int slots;
  final int fast;

  const ReceiverStatus({
    required this.ver,
    required this.rid,
    required this.bound,
    required this.online,
    required this.valid,
    required this.slots,
    required this.fast,
  });

  bool boundAt(int i) => bit(bound, i);
  bool onlineAt(int i) => bit(online, i);
  bool validAt(int i) => bit(valid, i);
  bool fastAt(int i) => bit(fast, i);
  int boundCount() => popcount(bound);
  int onlineCount() => popcount(online);
  int validCount() => popcount(valid);
}

/// 接收器命令响应(15 字节 + 可选 Sensor Info)。
class CommandResponse {
  final int ver;
  final int opcode;
  final int status;
  final int slot;
  final int rid;
  final int type;
  final int sensorId;
  final String mac;
  final bool online;
  final SensorInfo? sensorInfo;

  const CommandResponse({
    required this.ver,
    required this.opcode,
    required this.status,
    required this.slot,
    required this.rid,
    required this.type,
    required this.sensorId,
    required this.mac,
    required this.online,
    this.sensorInfo,
  });
}

/// 传感器 17 字节载荷。
class SensorPayload {
  final int uptime;
  final int uptime24;
  final int temp;
  final int reserved4;
  final int pressure;
  final int raw;
  final int reserved13;
  final int seq;
  final int? notifyFlags;

  // notifyFlags 派生(载荷不足 17 字节时为 null)
  final int? pa5;
  final bool? readOk;
  final int? voltageX10;
  final int? legacyVoltageX10;

  // 倾角字段(始终存在)
  final int xAngle;
  final int yAngle;
  final int xRaw;
  final int yRaw;
  final int zRaw;

  final String rawHex;

  const SensorPayload({
    required this.uptime,
    required this.uptime24,
    required this.temp,
    required this.reserved4,
    required this.pressure,
    required this.raw,
    required this.reserved13,
    required this.seq,
    required this.notifyFlags,
    required this.pa5,
    required this.readOk,
    required this.voltageX10,
    required this.legacyVoltageX10,
    required this.xAngle,
    required this.yAngle,
    required this.xRaw,
    required this.yRaw,
    required this.zRaw,
    required this.rawHex,
  });

  double? get voltageV => voltageX10 == null ? null : voltageX10! / 10;
  double? get legacyVoltageV =>
      legacyVoltageX10 == null ? null : legacyVoltageX10! / 10;
}

/// 接收器数据流样本(1 字节 slot + 17 字节载荷)。
class StreamSample {
  final int slot;
  final SensorPayload payload;

  const StreamSample({required this.slot, required this.payload});
}

/// 接收器测距流帧(5 字节): slot + 距离 mm LE16 + Peak LE16。
///
/// 与 18 字节数据流帧共用接收器数据流特征, 按长度区分; 仅当槽位绑定倾角
/// 传感器且该传感器处于快速模式并取到有效 XM123 测量时才会上报。
class RangeSample {
  final int slot;
  final int distanceMm;
  final int peak;

  const RangeSample({
    required this.slot,
    required this.distanceMm,
    required this.peak,
  });
}

/// 传感器 Sensor Info(最长 24 字节)。
class SensorInfo {
  final int workSeconds;
  final int bootSeconds;
  final int voltageMv;
  final bool online;
  final int rate;
  final int errors;
  final int version;
  final int sensorType;
  final int? pa5;
  final int powerMode;
  final int? rssi;

  // 接收器附加标志(第 20 字节,载荷 >=20 字节时才有)
  final bool? infoValid;
  final bool? dataTimedOut;
  final bool? sampleVersion2;
  final bool? lastSampleReadOk;
  final bool? dataReceived;

  final int invalidSamples;
  final int missedNotifications;
  final String rawHex;

  const SensorInfo({
    required this.workSeconds,
    required this.bootSeconds,
    required this.voltageMv,
    required this.online,
    required this.rate,
    required this.errors,
    required this.version,
    required this.sensorType,
    required this.pa5,
    required this.powerMode,
    required this.rssi,
    required this.infoValid,
    required this.dataTimedOut,
    required this.sampleVersion2,
    required this.lastSampleReadOk,
    required this.dataReceived,
    required this.invalidSamples,
    required this.missedNotifications,
    required this.rawHex,
  });

  bool get receiverFlagsPresent => infoValid != null;
}
