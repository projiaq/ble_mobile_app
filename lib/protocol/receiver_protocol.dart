/// 接收器协议:命令构造 + 状态/响应解析。与 `phone_app/utils/protocol.js` 对齐。
library;

import 'dart:typed_data';

import 'constants.dart';
import 'models.dart';
import 'sensor_protocol.dart';

/// 命令构造(首字节协议版本,第二字节 opcode)。
Uint8List cmdSetId(int id) => Uint8List.fromList([
      protocolVer,
      opSetId,
      id & 0xff,
      (id >> 8) & 0xff,
    ]);

Uint8List cmdSetSlot(int slot, int type, int sid, List<int> mac) =>
    Uint8List.fromList([protocolVer, opSetSlot, slot, type, sid, ...mac]);

Uint8List cmdClearSlot(int slot) =>
    Uint8List.fromList([protocolVer, opClearSlot, slot]);

Uint8List cmdClearAll() => Uint8List.fromList([protocolVer, opClearAll]);

Uint8List cmdGetSlot(int slot) =>
    Uint8List.fromList([protocolVer, opGetSlot, slot]);

Uint8List cmdSetRate(int slot, bool fast) =>
    Uint8List.fromList([protocolVer, opSetRate, slot, fast ? 1 : 0]);

Uint8List cmdGetSensorInfo(int slot) =>
    Uint8List.fromList([protocolVer, opGetSensorInfo, slot]);

/// 解析 8 字节接收器状态。
ReceiverStatus? parseStatus(Uint8List bytes) {
  if (bytes.length < 8) return null;
  return ReceiverStatus(
    ver: bytes[0],
    rid: bytes[1] | (bytes[2] << 8),
    bound: bytes[3],
    online: bytes[4],
    valid: bytes[5],
    slots: bytes[6],
    fast: bytes[7] | 0,
  );
}

/// 解析 15+ 字节命令响应;GET_SENSOR_INFO 时附带的 Sensor Info 一并解析。
CommandResponse? parseResponse(Uint8List bytes) {
  if (bytes.length < 15) return null;
  final opcode = bytes[1];
  final SensorInfo? sensorInfo = (opcode == opGetSensorInfo && bytes.length > 15)
      ? parseSensorInfo(Uint8List.sublistView(bytes, 15))
      : null;
  return CommandResponse(
    ver: bytes[0],
    opcode: opcode,
    status: bytes[2],
    slot: bytes[3],
    rid: bytes[4] | (bytes[5] << 8),
    type: bytes[6],
    sensorId: bytes[7],
    mac: bytesToMac(bytes.sublist(8, 14)),
    online: bytes[14] != 0,
    sensorInfo: sensorInfo,
  );
}
