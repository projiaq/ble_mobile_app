/// 传感器协议:载荷/传感器信息解析 + 类型字典与格式化。
/// 与 `phone_app/utils/protocol.js` 对齐。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'constants.dart';
import 'models.dart';

// ---- 类型字典(V2.1)----
const Map<int, String> _pressurePts = {
  1: '立柱前左',
  2: '立柱前右',
  3: '立柱后左',
  4: '立柱后右',
  5: '一级护帮',
  6: '二级护帮',
  7: '三级护帮',
  8: '前梁',
  9: '伸缩梁',
  10: '平衡上腔',
  11: '平衡下腔',
};
const Map<int, String> _tiltPts = {
  1: '底座',
  2: '顶梁',
  3: '前连杆',
  4: '一级护帮',
  5: '二级护帮',
  6: '三级护帮',
  7: '前梁',
  8: '尾梁',
  9: '掩护梁',
};

String typeName(int type) {
  switch (type) {
    case typePressure:
      return '压力';
    case typeTilt:
      return '倾角';
    default:
      return type != 0 ? '类型$type' : '';
  }
}

String pointName(int type, int id) {
  final table = type == typePressure ? _pressurePts : _tiltPts;
  if (table.containsKey(id)) return table[id]!;
  if (type == typePressure && id >= 12 && id <= 21) return '备用压力${id - 11}';
  if (type == typeTilt && id >= 10 && id <= 19) return '备用倾角${id - 9}';
  return id != 0 ? '点$id' : '';
}

String positionLabel(int type, int sid) =>
    type != 0 && sid != 0 ? '${typeName(type)}-${pointName(type, sid)}' : '';

/// 传感器可用的类型+点位选项列表,首项为空(表示未选)。
List<({int type, int sid, String label})> sensorPositionOptions() {
  final pressure = _pressurePts.keys.map((id) => (
        type: typePressure,
        sid: id,
        label: '${typeName(typePressure)}-${_pressurePts[id]!}',
      ));
  final tilt = _tiltPts.keys.map((id) => (
        type: typeTilt,
        sid: id,
        label: '${typeName(typeTilt)}-${_tiltPts[id]!}',
      ));
  return [const (type: 0, sid: 0, label: ''), ...pressure, ...tilt];
}

// ---- 字节工具 ----
String toHex(Uint8List bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(' ');

/// 显示格式 `AA:BB:CC:DD:EE:FF`(或 `-`/空格分隔)转字节;非法返回 null。
List<int>? macToBytes(String text) {
  final parts = text
      .trim()
      .replaceAll('-', ':')
      .replaceAll(' ', ':')
      .split(':')
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length != 6) return null;
  final bytes = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p, radix: 16);
    if (v == null || v > 0xff) return null;
    bytes.add(v);
  }
  return bytes;
}

/// 倾角补偿沿用 4 字节 Offset 特征：X/Y 分别为低/高 16 位有符号小端数。
int packTiltOffsets(int x, int y) {
  final bytes = ByteData(4)
    ..setInt16(0, x, Endian.little)
    ..setInt16(2, y, Endian.little);
  return bytes.getInt32(0, Endian.little);
}

int tiltOffsetX(int packed) => (ByteData(4)..setInt32(0, packed, Endian.little))
    .getInt16(0, Endian.little);

int tiltOffsetY(int packed) => (ByteData(4)..setInt32(0, packed, Endian.little))
    .getInt16(2, Endian.little);

/// 当前上报角度已经含旧补偿，因此新补偿 = 旧补偿 - 当前上报角度。
int calculateTiltZeroOffset(int currentPacked, int currentX, int currentY) {
  final x = (tiltOffsetX(currentPacked) - currentX)
      .clamp(-32768, 32767)
      .toInt();
  final y = (tiltOffsetY(currentPacked) - currentY)
      .clamp(-32768, 32767)
      .toInt();
  return packTiltOffsets(x, y);
}

/// 解析 17 字节传感器载荷(带偏移)。
SensorPayload? parsePayload(Uint8List bytes, int off) {
  final available = bytes.length - off;
  if (available < 14) return null;
  final dv = ByteData.sublistView(bytes);
  final notifyFlags = available >= sensorPayloadLen ? dv.getUint8(off + 16) : null;
  final notifyVoltageX10 = notifyFlags == null ? null : (notifyFlags >> 2) & 0x3f;
  final legacyVoltageX10 = notifyFlags == null ? null : (notifyFlags >> 1) & 0x7f;
  final rawLength = math.min(sensorPayloadLen, available);
  return SensorPayload(
    uptime: dv.getUint32(off, Endian.little),
    uptime24: bytes[off] | (bytes[off + 1] << 8) | (bytes[off + 2] << 16),
    temp: dv.getUint8(off + 3),
    reserved4: dv.getUint8(off + 4),
    pressure: dv.getInt32(off + 5, Endian.little),
    raw: dv.getUint32(off + 9, Endian.little),
    reserved13: dv.getUint8(off + 13),
    seq: dv.getUint16(off + 14, Endian.little),
    notifyFlags: notifyFlags,
    pa5: notifyFlags == null ? null : (notifyFlags & 0x01),
    readOk: notifyFlags == null ? null : (notifyFlags & 0x02) != 0,
    voltageX10: notifyVoltageX10,
    legacyVoltageX10: legacyVoltageX10,
    xAngle: dv.getInt16(off + 5, Endian.little),
    yAngle: dv.getInt16(off + 7, Endian.little),
    xRaw: dv.getInt16(off + 9, Endian.little),
    yRaw: dv.getInt16(off + 11, Endian.little),
    zRaw: (dv.getInt8(off + 13) << 8) | dv.getUint8(off + 4),
    rawHex: toHex(Uint8List.sublistView(bytes, off, off + rawLength)),
  );
}

/// 解析 18 字节接收器数据流样本。
StreamSample? parseStream(Uint8List bytes) {
  if (bytes.length < streamSampleLen) return null;
  final payload = parsePayload(bytes, 1);
  if (payload == null) return null;
  return StreamSample(slot: bytes[0], payload: payload);
}

/// 解析 5 字节接收器测距流帧: slot + 距离 mm LE16 + Peak LE16。
/// 距离为 0xFFFF 时视为该槽暂无有效测距数据, 返回 null。
RangeSample? parseRangeStream(Uint8List bytes) {
  if (bytes.length < rangeStreamLen) return null;
  final dv = ByteData.sublistView(bytes);
  final distance = dv.getUint16(1, Endian.little);
  if (distance == 0xFFFF) return null;
  return RangeSample(
    slot: bytes[0],
    distanceMm: distance,
    peak: dv.getUint16(3, Endian.little),
  );
}

/// 解析传感器直连上报的 4 字节测距帧: 距离 mm LE16 + Peak LE16。
({int distanceMm, int peak})? parseSensorRange(Uint8List bytes) {
  if (bytes.length != sensorRangeLen) return null;
  final dv = ByteData.sublistView(bytes);
  return (
    distanceMm: dv.getUint16(0, Endian.little),
    peak: dv.getUint16(2, Endian.little),
  );
}

/// 解析传感器 Sensor Info(>=10 字节;接收器附加标志在第 20 字节)。
SensorInfo? parseSensorInfo(Uint8List bytes) {
  if (bytes.length < 10) return null;
  final dv = ByteData.sublistView(bytes);
  final receiverFlags = bytes.length >= 20 ? dv.getUint8(19) : null;
  return SensorInfo(
    workSeconds: dv.getUint32(0, Endian.little),
    bootSeconds: bytes.length >= 8 ? dv.getUint32(4, Endian.little) : 0,
    voltageMv: dv.getUint16(8, Endian.little),
    online: bytes.length >= 11 ? dv.getUint8(10) != 0 : false,
    rate: bytes.length >= 12 ? dv.getUint8(11) : 0,
    errors: bytes.length >= 14 ? dv.getUint16(12, Endian.little) : 0,
    version: bytes.length >= 15 ? dv.getUint8(14) : 0,
    sensorType: bytes.length >= 16 ? dv.getUint8(15) : 0,
    pa5: bytes.length >= 17 ? dv.getUint8(16) : null,
    powerMode: bytes.length >= 18 ? dv.getUint8(17) : 0,
    rssi: bytes.length >= 19 ? dv.getInt8(18) : null,
    infoValid: receiverFlags == null ? null : (receiverFlags & 0x01) != 0,
    dataTimedOut: receiverFlags == null ? null : (receiverFlags & 0x02) != 0,
    sampleVersion2: receiverFlags == null ? null : (receiverFlags & 0x04) != 0,
    lastSampleReadOk: receiverFlags == null ? null : (receiverFlags & 0x08) != 0,
    dataReceived: receiverFlags == null ? null : (receiverFlags & 0x10) != 0,
    invalidSamples: bytes.length >= 22 ? dv.getUint16(20, Endian.little) : 0,
    missedNotifications: bytes.length >= 24 ? dv.getUint16(22, Endian.little) : 0,
    rawHex: toHex(bytes),
  );
}

// ---- 电压版本歧义:V1 用 bit1..7,V2 用 bit2..7,V1/V2 由 Sensor Info 的 version 区分。
double? notifyVoltageV(SensorPayload? payload, SensorInfo? info) {
  if (payload == null || payload.notifyFlags == null) return null;
  return info != null && info.version == 1
      ? payload.legacyVoltageV
      : payload.voltageV;
}

// ---- 格式化 ----
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  if (d > 0) return '$d天 $h小时';
  if (h > 0) return '$h小时 $m分钟';
  return '$m分钟';
}

String formatVoltage(int mv) {
  if (mv <= 0) return '--';
  return '${(mv / 1000).toStringAsFixed(2)} V';
}

String formatAngles(int x, int y) =>
    'X ${(x / 10).toStringAsFixed(1)}°  Y ${(y / 10).toStringAsFixed(1)}°';

/// 按类型格式化数据值:倾角按高低 16 位拆 X/Y;压力为 bar 整数。
String formatValue(int type, int val) {
  if (type == typeTilt) {
    var x = val & 0xffff;
    var y = (val >>> 16) & 0xffff;
    if (x >= 0x8000) x -= 0x10000;
    if (y >= 0x8000) y -= 0x10000;
    return formatAngles(x, y);
  }
  return '$val bar';
}

String formatRaw(int type, SensorPayload? payload) {
  if (payload == null) return '--';
  if (type == typeTilt) {
    return 'X ${payload.xRaw}  Y ${payload.yRaw}  Z ${payload.zRaw}';
  }
  final raw = payload.raw;
  return '$raw (0x${raw.toRadixString(16).padLeft(8, '0').toUpperCase()})';
}

/// 测距显示: 距离 mm + Peak 幅值; 无有效测距数据返回 `--`。
String formatDistance(int? distanceMm, [int? peak]) {
  if (distanceMm == null) return '--';
  if (peak == null) return '$distanceMm mm';
  return '$distanceMm mm  Peak $peak';
}
