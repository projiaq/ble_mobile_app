// 协议层字节级单测:与 phone_app/utils/protocol.js 逐字节对齐。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/protocol/constants.dart';
import 'package:mobile_app/protocol/models.dart';
import 'package:mobile_app/protocol/receiver_protocol.dart';
import 'package:mobile_app/protocol/sensor_protocol.dart';

void main() {
  group('命令构造', () {
    test('cmdSetId', () {
      expect(cmdSetId(0x0102), [1, opSetId, 0x02, 0x01]);
    });
    test('cmdSetSlot', () {
      expect(
        cmdSetSlot(2, typePressure, 3, [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]),
        [1, opSetSlot, 2, 1, 3, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff],
      );
    });
    test('cmdClearSlot / cmdClearAll / cmdGetSlot', () {
      expect(cmdClearSlot(5), [1, opClearSlot, 5]);
      expect(cmdClearAll(), [1, opClearAll]);
      expect(cmdGetSlot(0), [1, opGetSlot, 0]);
    });
    test('cmdSetRate / cmdGetSensorInfo', () {
      expect(cmdSetRate(3, true), [1, opSetRate, 3, 1]);
      expect(cmdSetRate(3, false), [1, opSetRate, 3, 0]);
      expect(cmdGetSensorInfo(7), [1, opGetSensorInfo, 7]);
    });
  });

  group('parseStatus', () {
    test('解析 8 字节状态与位图', () {
      final status = parseStatus(
        Uint8List.fromList([1, 0x34, 0x12, 0x55, 0x0f, 0x03, 0x00, 0x01]),
      );
      expect(status, isNotNull);
      expect(status!.ver, 1);
      expect(status.rid, 0x1234);
      expect(status.boundAt(0), isTrue);
      expect(status.boundAt(1), isFalse);
      expect(status.boundAt(2), isTrue);
      expect(status.onlineCount(), 4);
      expect(status.validCount(), 2);
      expect(status.fastAt(0), isTrue);
    });
    test('不足 8 字节返回 null', () {
      expect(parseStatus(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('parseResponse', () {
    test('解析 15 字节命令响应', () {
      final response = parseResponse(Uint8List.fromList([
        1, opGetSlot, 0, 2, 0x34, 0x12, 1, 3, //
        0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 1,
      ]));
      expect(response, isNotNull);
      expect(response!.opcode, opGetSlot);
      expect(response.status, 0);
      expect(response.slot, 2);
      expect(response.rid, 0x1234);
      expect(response.type, typePressure);
      expect(response.sensorId, 3);
      expect(response.mac, 'AA:BB:CC:DD:EE:FF');
      expect(response.online, isTrue);
      expect(response.sensorInfo, isNull);
    });
    test('GET_SENSOR_INFO 附带 Sensor Info', () {
      final bytes = Uint8List.fromList([
        1, opGetSensorInfo, 0, 0, 0, 0, 1, 0, //
        0, 0, 0, 0, 0, 0, 1, // 15 字节头
        0x04, 0x03, 0x02, 0x01, // workSeconds
        0x0d, 0x0c, 0x0b, 0x0a, // bootSeconds
        0xe4, 0x0c, // voltageMv
      ]);
      final response = parseResponse(bytes);
      expect(response, isNotNull);
      expect(response!.sensorInfo, isNotNull);
      expect(response.sensorInfo!.workSeconds, 0x01020304);
      expect(response.sensorInfo!.voltageMv, 3300);
    });
  });

  group('parsePayload(17 字节传感器帧)', () {
    test('字段逐字节解析', () {
      final payload = parsePayload(Uint8List.fromList([
        0x04, 0x03, 0x02, 0x2a, // uptime24 + temp/u32 high byte
        0x11, // reserved4
        0xf4, 0x01, 0x00, 0x00, // pressure i32 LE = 500
        0x44, 0x33, 0x22, 0x11, // raw u32 LE = 0x11223344
        0x7e, // reserved13
        0xff, 0x00, // seq u16 LE = 0x00ff
        0x2a, // notifyFlags
      ]), 0);
      expect(payload, isNotNull);
      expect(payload!.uptime, 0x2a020304);
      expect(payload.uptime24, 0x020304);
      expect(payload.temp, 0x2a);
      expect(payload.pressure, 500);
      expect(payload.raw, 0x11223344);
      expect(payload.seq, 0x00ff);
      expect(payload.notifyFlags, 0x2a);
      // 0x2a = 0010_1010
      expect(payload.pa5, 0);
      expect(payload.readOk, isTrue); // bit1
      expect(payload.voltageX10, 10); // (0x2a>>2)&0x3f
      expect(payload.legacyVoltageX10, 21); // (0x2a>>1)&0x7f
      expect(payload.voltageV, 1.0);
      expect(payload.legacyVoltageV, 2.1);
      // 倾角字段(与 raw 字节重叠的视图)
      expect(payload.xAngle, 0x01f4); // bytes[5..6]
      expect(payload.yAngle, 0);
      expect(payload.xRaw, 0x3344); // bytes[9..10]
      expect(payload.yRaw, 0x1122); // bytes[11..12]
      expect(payload.zRaw, (0x7e << 8) | 0x11);
    });
    test('载荷不足 14 字节返回 null', () {
      expect(parsePayload(Uint8List.fromList([0, 1, 2]), 0), isNull);
    });
    test('notifyVoltageV 依 Sensor Info 版本切换', () {
      final bytes = Uint8List.fromList(List.filled(17, 0));
      bytes[16] = 0x2a;
      final payload = parsePayload(bytes, 0);
      expect(notifyVoltageV(payload, null), 1.0);
      expect(notifyVoltageV(payload, _info(version: 2)), 1.0);
      expect(notifyVoltageV(payload, _info(version: 1)), 2.1);
    });
  });

  group('倾角补偿编解码', () {
    test('按 X/Y 有符号 int16 小端打包', () {
      final packed = packTiltOffsets(-123, 456);
      expect(tiltOffsetX(packed), -123);
      expect(tiltOffsetY(packed), 456);
      final bytes = ByteData(4)..setInt32(0, packed, Endian.little);
      expect(bytes.buffer.asUint8List(), [0x85, 0xff, 0xc8, 0x01]);
    });

    test('标零计算会合并设备已有补偿', () {
      final current = packTiltOffsets(-100, 50);
      final next = calculateTiltZeroOffset(current, 20, -30);
      expect(tiltOffsetX(next), -120);
      expect(tiltOffsetY(next), 80);

      final repeated = calculateTiltZeroOffset(next, 0, 0);
      expect(repeated, next);
    });

    test('零补偿', () {
      final packed = packTiltOffsets(0, 0);
      expect(packed, 0);
      expect(tiltOffsetX(packed), 0);
      expect(tiltOffsetY(packed), 0);
    });
  });

  group('parseStream', () {
    test('解析 18 字节样本(slot + 17 字节载荷)', () {
      final bytes = Uint8List.fromList(List.filled(18, 0));
      bytes[0] = 3; // slot
      bytes[17] = 0x02; // notifyFlags(载荷偏移 16 = 整体索引 17)→ readOk
      final sample = parseStream(bytes);
      expect(sample, isNotNull);
      expect(sample!.slot, 3);
      expect(sample.payload.readOk, isTrue);
    });
    test('不足 18 字节返回 null', () {
      expect(parseStream(Uint8List.fromList([0, 1])), isNull);
    });
  });

  group('parseSensorInfo', () {
    test('24 字节完整解析', () {
      final info = parseSensorInfo(Uint8List.fromList([
        0x04, 0x03, 0x02, 0x01, // workSeconds
        0x0d, 0x0c, 0x0b, 0x0a, // bootSeconds
        0xe4, 0x0c, // voltageMv = 3300
        1, // online
        1, // rate
        0x02, 0x01, // errors = 0x0102
        2, // version
        1, // sensorType
        1, // pa5
        0, // powerMode
        0xd3, // rssi = -45
        0x07, // receiverFlags: infoValid|dataTimedOut|sampleVersion2
        0x03, 0x00, // invalidSamples = 3
        0x05, 0x00, // missedNotifications = 5
      ]));
      expect(info, isNotNull);
      expect(info!.workSeconds, 0x01020304);
      expect(info.bootSeconds, 0x0a0b0c0d);
      expect(info.voltageMv, 3300);
      expect(info.online, isTrue);
      expect(info.rate, 1);
      expect(info.errors, 0x0102);
      expect(info.version, 2);
      expect(info.sensorType, typePressure);
      expect(info.pa5, 1);
      expect(info.powerMode, 0);
      expect(info.rssi, -45);
      expect(info.infoValid, isTrue);
      expect(info.dataTimedOut, isTrue);
      expect(info.sampleVersion2, isTrue);
      expect(info.lastSampleReadOk, isFalse);
      expect(info.dataReceived, isFalse);
      expect(info.invalidSamples, 3);
      expect(info.missedNotifications, 5);
    });
    test('不足 10 字节返回 null', () {
      expect(parseSensorInfo(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('类型字典与格式化', () {
    test('typeName / pointName', () {
      expect(typeName(typePressure), '压力');
      expect(typeName(typeTilt), '倾角');
      expect(typeName(0), '');
      expect(pointName(typePressure, 1), '立柱前左');
      expect(pointName(typeTilt, 3), '前连杆');
      expect(pointName(typePressure, 15), '备用压力4');
      expect(pointName(typeTilt, 12), '备用倾角3');
    });
    test('positionLabel / sensorPositionOptions', () {
      expect(positionLabel(typePressure, 5), '压力-一级护帮');
      expect(positionLabel(0, 0), '');
      final options = sensorPositionOptions();
      expect(options.first.type, 0);
      expect(options.length, 1 + 11 + 9);
    });
    test('formatValue 压力与倾角', () {
      expect(formatValue(typePressure, 500), '500 bar');
      final tilt = (0x0014 << 16) | 0x0032; // y=20, x=50 → 2.0° / 5.0°
      expect(formatValue(typeTilt, tilt), 'X 5.0°  Y 2.0°');
    });
    test('formatDuration / formatVoltage', () {
      expect(formatDuration(90), '1分钟');
      expect(formatDuration(5400), '1小时 30分钟');
      expect(formatVoltage(3300), '3.30 V');
      expect(formatVoltage(0), '--');
    });
    test('macToBytes / bytesToMac', () {
      expect(bytesToMac(Uint8List.fromList([0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])),
          'AA:BB:CC:DD:EE:FF');
      expect(macToBytes('AA:BB:CC:DD:EE:FF'), [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]);
      expect(macToBytes('AA-BB-CC-DD-EE-FF'), [0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]);
      expect(macToBytes('not-a-mac'), isNull);
    });
  });
}

SensorInfo _info({required int version}) {
  return SensorInfo(
    workSeconds: 0,
    bootSeconds: 0,
    voltageMv: 0,
    online: false,
    rate: 0,
    errors: 0,
    version: version,
    sensorType: 0,
    pa5: null,
    powerMode: 0,
    rssi: null,
    infoValid: null,
    dataTimedOut: null,
    sampleVersion2: null,
    lastSampleReadOk: null,
    dataReceived: null,
    invalidSamples: 0,
    missedNotifications: 0,
    rawHex: '',
  );
}
