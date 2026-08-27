/// flutter_blue_plus 封装,对齐原 `ble.js` 的语义:
/// 整体连接超时、按特征读写、单次写入(OTA 用)、订阅分发、断连清理。
///
/// 说明:固定使用 flutter_blue_plus 1.36.8(BSD 开源)。2.x 改为商业授权。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'scan_device.dart';

class BleException implements Exception {
  final String message;
  BleException(this.message);
  @override
  String toString() => message;
}

class BleManager {
  BleManager();

  /// 已连接设备缓存:deviceId -> device。
  final Map<String, BluetoothDevice> _devices = {};
  final Map<String, StreamSubscription<List<int>>> _subs = {};

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  Future<bool> get isSupported => FlutterBluePlus.isSupported;

  Future<bool> ensureReady() async {
    if (!await FlutterBluePlus.isSupported) return false;
    // flutter_blue_plus 会按 Android SDK 版本申请正确的运行时权限:
    // Android 12+ 使用 BLUETOOTH_SCAN/CONNECT,旧版本使用定位权限。
    // adapterStateNow 首次启动时为 unknown,必须先订阅一次以读取原生状态。
    var adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn(timeout: 60);
      adapterState = await FlutterBluePlus.adapterState.first;
    }
    return adapterState == BluetoothAdapterState.on;
  }

  Future<void> startScan() async {
    await FlutterBluePlus.startScan(
      androidUsesFineLocation: false,
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  /// 扫描直到 [matcher] 命中,返回设备 id;超时返回 null。会自行启停扫描。
  Future<String?> scanForDevice(
    bool Function(ScanDevice device) matcher, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await startScan();
    try {
      final completer = Completer<String?>();
      final subscription = FlutterBluePlus.scanResults.listen((results) {
        if (completer.isCompleted) return;
        for (final result in results) {
          final device = toDevice(result);
          if (matcher(device)) {
            completer.complete(device.id);
            return;
          }
        }
      });
      final id = await completer.future
          .timeout(timeout, onTimeout: () => null);
      await subscription.cancel();
      return id;
    } finally {
      await stopScan().catchError((_) {});
    }
  }

  ScanDevice toDevice(ScanResult result) {
    final uuids = result.advertisementData.serviceUuids;
    final advertisedName = result.advertisementData.advName.trim();
    return ScanDevice(
      id: result.device.remoteId.str,
      name: advertisedName.isNotEmpty
          ? advertisedName
          : result.device.platformName,
      rssi: result.rssi,
      serviceUuids: uuids.map((g) => g.str).toList(),
      manufacturerData: result.advertisementData.manufacturerData,
    );
  }

  bool isConnected(String deviceId) => _devices.containsKey(deviceId);

  bool hasCharacteristic(String deviceId, String serviceUuid, String charUuid) {
    final device = _devices[deviceId];
    return device != null && _characteristic(device, serviceUuid, charUuid) != null;
  }

  /// 建立连接 + MTU + 服务发现。整体 [timeout] 超时,失败清理半连接。
  Future<void> connect(
    String deviceId, {
    Duration timeout = const Duration(seconds: 10),
    Duration? discoveryTimeout,
    void Function(String message)? onLog,
  }) async {
    void log(String message) => onLog?.call(message);

    if (_devices.containsKey(deviceId)) {
      log('复用已连接设备');
      return;
    }
    log('停止扫描,释放 Android BLE 连接资源');
    try {
      await stopScan().timeout(const Duration(milliseconds: 800));
    } catch (_) {}
    final scannedDevice = _findInLastScan(deviceId);
    final device = scannedDevice ?? BluetoothDevice.fromId(deviceId);
    log(scannedDevice == null ? '使用系统设备缓存' : '命中最近扫描设备');
    _devices[deviceId] = device;
    try {
      log('开始 GATT 连接');
      await device
          .connect(timeout: timeout, autoConnect: false)
          .timeout(timeout + const Duration(seconds: 2));
      log('GATT 连接完成');
      // 当前协议包小于默认 MTU,不等待 MTU 协商,缩短首次连接时间。
      final serviceTimeout = discoveryTimeout ?? timeout;
      log('开始发现 GATT 服务, timeout=${serviceTimeout.inSeconds}s');
      final services =
          await device.discoverServices().timeout(serviceTimeout);
      log('服务发现完成 ${services.length} 个服务');
    } catch (e) {
      log('连接失败: $e');
      _devices.remove(deviceId);
      await _disconnectSafely(device);
      rethrow;
    }
  }

  Future<void> disconnect(String deviceId) async {
    for (final key in _subs.keys.toList()) {
      if (key.startsWith('$deviceId|')) {
        await _subs.remove(key)?.cancel();
      }
    }
    final device = _devices.remove(deviceId);
    if (device != null) {
      await _disconnectSafely(device);
    }
  }

  Future<void> _disconnectSafely(BluetoothDevice device) async {
    try {
      await device.disconnect().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Do not let cleanup after a native BLE timeout block the next attempt.
    }
  }

  Future<Uint8List> read(
    String deviceId,
    String serviceUuid,
    String charUuid, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final characteristic = _requireCharacteristic(deviceId, serviceUuid, charUuid);
    final value = await characteristic.read().timeout(timeout);
    return Uint8List.fromList(value);
  }

  /// 带响应写(命令类)。
  Future<void> writeRequest(
    String deviceId,
    String serviceUuid,
    String charUuid,
    Uint8List value,
  ) => _write(deviceId, serviceUuid, charUuid, value, withoutResponse: false);

  /// 无响应写。
  Future<void> writeNoResponse(
    String deviceId,
    String serviceUuid,
    String charUuid,
    Uint8List value,
  ) => _write(deviceId, serviceUuid, charUuid, value, withoutResponse: true);

  /// 单次写入:按特征属性选带/无响应,失败不换方式重发(OTA 数据流用)。
  Future<void> writeOnce(
    String deviceId,
    String serviceUuid,
    String charUuid,
    Uint8List value,
  ) async {
    final characteristic = _requireCharacteristic(deviceId, serviceUuid, charUuid);
    await characteristic.write(value, withoutResponse: !characteristic.properties.write);
  }

  /// 订阅通知;重复订阅先取消旧订阅。
  Future<void> subscribe(
    String deviceId,
    String serviceUuid,
    String charUuid,
    void Function(Uint8List value) onValue,
  {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final characteristic = _requireCharacteristic(deviceId, serviceUuid, charUuid);
    await characteristic.setNotifyValue(true).timeout(timeout);
    final key = '$deviceId|${charUuid.toUpperCase()}';
    await _subs.remove(key)?.cancel();
    _subs[key] = characteristic.lastValueStream
        .listen((v) => onValue(Uint8List.fromList(v)));
  }

  Future<void> unsubscribe(
    String deviceId,
    String serviceUuid,
    String charUuid,
  ) async {
    final key = '$deviceId|${charUuid.toUpperCase()}';
    await _subs.remove(key)?.cancel();
    final device = _devices[deviceId];
    final characteristic =
        device == null ? null : _characteristic(device, serviceUuid, charUuid);
    if (characteristic != null) {
      await characteristic.setNotifyValue(false).catchError((_) => false);
    }
  }

  // ---- 内部 ----
  BluetoothDevice? _findInLastScan(String deviceId) {
    for (final result in FlutterBluePlus.lastScanResults) {
      if (result.device.remoteId.str == deviceId) return result.device;
    }
    return null;
  }

  BluetoothDevice _require(String deviceId) {
    final device = _devices[deviceId];
    if (device == null) throw BleException('未连接设备 $deviceId');
    return device;
  }

  BluetoothCharacteristic? _characteristic(
    BluetoothDevice device,
    String serviceUuid,
    String charUuid,
  ) {
    for (final service in device.servicesList) {
      if (service.uuid.str.toUpperCase() == serviceUuid.toUpperCase()) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid.str.toUpperCase() == charUuid.toUpperCase()) {
            return characteristic;
          }
        }
      }
    }
    return null;
  }

  BluetoothCharacteristic _requireCharacteristic(
    String deviceId,
    String serviceUuid,
    String charUuid,
  ) {
    final characteristic =
        _characteristic(_require(deviceId), serviceUuid, charUuid);
    if (characteristic == null) throw BleException('未发现特征 $charUuid');
    return characteristic;
  }

  Future<void> _write(
    String deviceId,
    String serviceUuid,
    String charUuid,
    Uint8List value, {
    required bool withoutResponse,
  }) async {
    final characteristic = _requireCharacteristic(deviceId, serviceUuid, charUuid);
    await characteristic.write(value, withoutResponse: withoutResponse);
  }
}
