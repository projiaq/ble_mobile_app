// 扫描分类与 DFU 广告识别单测。
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/ble/scan_device.dart';
import 'package:mobile_app/ble/scan_filter.dart';
import 'package:mobile_app/protocol/constants.dart';

ScanDevice device(String id,
        {String name = '', List<String>? uuids, int? rssi, Map<int, List<int>>? manuf}) =>
    ScanDevice(
        id: id,
        name: name,
        serviceUuids: uuids ?? const [],
        rssi: rssi,
        manufacturerData: manuf ?? const {},
    );
void main() {
  group('classifyDevice', () {
    test('接收器:名称前缀 / MCMPDT / 服务 UUID', () {
      expect(classifyDevice(device('a', name: 'AIOT-001')), DeviceKind.receiver);
      expect(classifyDevice(device('b', name: 'RX-9')), DeviceKind.receiver);
      expect(classifyDevice(device('c', name: 'MCMPDT')), DeviceKind.receiver);
      expect(
        classifyDevice(device('d', uuids: ['6F8A0000-7D4B-4A8E-9B21-3C5D7E9F1000'])),
        DeviceKind.receiver,
      );
    });
    test('倾角 / 压力 / 传感器', () {
      expect(classifyDevice(device('e', name: 'TILT-01')), DeviceKind.tilt);
      expect(classifyDevice(device('f', name: 'TILTNODE')), DeviceKind.tilt);
      expect(classifyDevice(device('g', name: 'PRES-02')), DeviceKind.pressure);
      expect(classifyDevice(device('h', name: 'PRESSNODE')), DeviceKind.pressure);
      expect(classifyDevice(device('i', name: 'SENSORNODE')), DeviceKind.sensor);
      expect(
        classifyDevice(device('j', uuids: ['C8E21E04-2D3A-4C65-B9D6-8E1A4B0F2C7D'])),
        DeviceKind.sensor,
      );
    });
    test('未知设备', () {
      expect(classifyDevice(device('k', name: 'Unknown')), DeviceKind.other);
    });
    test('广播厂商数据优先分类', () {
      final manuf = {0xFFFF: [0xA5, 0x5A, 0x10, 0x10, 0x01, 0x00]};
      expect(classifyDevice(device('a1', name: 'XYZ-P', manuf: manuf)),
          DeviceKind.pressure);
      final manufTilt = {0xFFFF: [0xA5, 0x5A, 0x10, 0x10, 0x01, 0x02]};
      expect(classifyDevice(device('a2', name: 'XYZ-T', manuf: manufTilt)),
          DeviceKind.tilt);
      final manufRx = {0xFFFF: [0xA5, 0x5A, 0x10, 0x10, 0x01, 0x01]};
      expect(classifyDevice(device('a3', name: 'XYZ-R', manuf: manufRx)),
          DeviceKind.receiver);
      // 名称前缀仍可识别无广播数据的旧设备
      expect(classifyDevice(device('a4', name: 'TILT-01')), DeviceKind.tilt);
    });
    test('parseAdvInfo / formatVersion', () {
      final info = parseAdvInfo(
          device('m', name: 'X', manuf: {
        0xFFFF: [0xA5, 0x5A, 0x12, 0x34, 0x01, 0x02]
      }));
      expect(info, isNotNull);
      expect(info!.hwVer, 0x12);
      expect(info.swVer, 0x34);
      expect(info.protoVer, 0x01);
      expect(info.devType, 0x02);
      expect(formatVersion(0x12), 'V1.2');
      expect(formatVersion(0x10), 'V1.0');
      expect(parseAdvInfo(device('n', name: 'X')), isNull);
      expect(parseAdvInfo(device('o', name: 'X', manuf: {0x1234: [1, 2, 3, 4]})),
          isNull);
      expect(parseAdvInfo(device('p', name: 'X', manuf: {0xFFFF: [1, 2, 3]})),
          isNull);
      expect(
          parseAdvInfo(device('q', name: 'X', manuf: {
            0xFFFF: [0x00, 0x00, 0x12, 0x34, 0x01, 0x02]
          })),
          isNull);
      expect(
          parseAdvInfo(device('r', name: 'X', manuf: {
            0xFFFF: [0xA5, 0x5A, 0x1A, 0x34, 0x01, 0x02]
          })),
          isNull);
      expect(
          parseAdvInfo(device('s', name: 'X', manuf: {
            0xFFFF: [0xA5, 0x5A, 0x12, 0x34, 0x01, 0x7F]
          })),
          isNull);
    });
    test('sensorTypeOf', () {
      expect(sensorTypeOf(DeviceKind.pressure), typePressure);
      expect(sensorTypeOf(DeviceKind.tilt), typeTilt);
      expect(sensorTypeOf(DeviceKind.receiver), isNull);
      expect(sensorTypeOf(DeviceKind.other), isNull);
    });
  });

  group('isOtaAdvertisement', () {
    const originalId = 'AA:BB:CC:DD:EE:01';
    test('同名设备 + OTA 名称', () {
      expect(
        isOtaAdvertisement(device(originalId, name: 'OTA'), originalId),
        isTrue,
      );
    });
    test('APPL / DFU 名称', () {
      expect(
        isOtaAdvertisement(device(originalId, name: 'APPL'), originalId),
        isTrue,
      );
      expect(
        isOtaAdvertisement(device(originalId, name: 'DFU'), originalId),
        isTrue,
      );
    });
    test('OTA 服务 UUID', () {
      expect(
        isOtaAdvertisement(
          device('other', name: 'X', uuids: [otaServiceUuid]),
          originalId,
        ),
        isTrue,
      );
    });
    test('无关设备返回 false', () {
      expect(
        isOtaAdvertisement(device('other', name: 'AIOT-1'), originalId),
        isFalse,
      );
    });
    test('同名但名称非 OTA 且非空 → 依赖服务 UUID', () {
      expect(
        isOtaAdvertisement(device(originalId, name: 'AIOT-1'), originalId),
        isFalse,
      );
    });
  });
}
