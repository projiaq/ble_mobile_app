import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/ble_manager.dart';
import '../../../ble/ble_providers.dart';
import '../../../ble/scan_device.dart';
import '../../../ble/scan_filter.dart';
import '../../../protocol/constants.dart';

/// 扫描页状态。
class ScanState {
  final bool scanning;
  final bool ready;
  final String? error;
  final List<ScanDevice> receivers;
  final List<ScanDevice> sensors;
  final String query;
  final int rssiThreshold;
  final bool sortDescending;

  const ScanState({
    this.scanning = false,
    this.ready = false,
    this.error,
    this.receivers = const [],
    this.sensors = const [],
    this.query = '',
    this.rssiThreshold = -100,
    this.sortDescending = true,
  });

  ScanState copyWith({
    bool? scanning,
    bool? ready,
    String? error,
    bool clearError = false,
    List<ScanDevice>? receivers,
    List<ScanDevice>? sensors,
    String? query,
    int? rssiThreshold,
    bool? sortDescending,
  }) {
    return ScanState(
      scanning: scanning ?? this.scanning,
      ready: ready ?? this.ready,
      error: clearError ? null : (error ?? this.error),
      receivers: receivers ?? this.receivers,
      sensors: sensors ?? this.sensors,
      query: query ?? this.query,
      rssiThreshold: rssiThreshold ?? this.rssiThreshold,
      sortDescending: sortDescending ?? this.sortDescending,
    );
  }
}

/// 扫描:权限/适配器、扫描、按名称与服务 UUID 分类、过滤。
class ScanController extends StateNotifier<ScanState> {
  ScanController(this._ble) : super(const ScanState());

  final BleManager _ble;
  StreamSubscription<List<ScanResult>>? _sub;

  void setQuery(String query) => state = state.copyWith(query: query);

  void setRssiThreshold(int value) =>
      state = state.copyWith(rssiThreshold: value);

  void toggleSort() => state = state.copyWith(sortDescending: !state.sortDescending);

  Future<void> start() async {
    if (state.scanning) return;
    state = state.copyWith(clearError: true);
    try {
      if (!state.ready) {
        final ok = await _ble.ensureReady();
        if (!ok) {
          state = state.copyWith(error: '设备不支持 BLE 或蓝牙未开启');
          return;
        }
        state = state.copyWith(ready: true);
      }
      await _ble.startScan();
      _sub = _ble.scanResults.listen(_onResults);
      state = state.copyWith(scanning: true);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _ble.stopScan();
    } catch (_) {}
    state = state.copyWith(scanning: false);
  }

  Future<void> toggle() => state.scanning ? stop() : start();

  void _onResults(List<ScanResult> results) {
    final receivers = <ScanDevice>[];
    final sensors = <ScanDevice>[];
    for (final result in results) {
      final device = _ble.toDevice(result);
      switch (classifyDevice(device)) {
        case DeviceKind.receiver:
          _upsert(receivers, device);
        case DeviceKind.pressure:
        case DeviceKind.tilt:
        case DeviceKind.sensor:
          _upsert(sensors, device);
        case DeviceKind.other:
          break;
      }
    }
    state = state.copyWith(receivers: receivers, sensors: sensors);
  }

  void _upsert(List<ScanDevice> list, ScanDevice device) {
    final index = list.indexWhere((d) => d.id == device.id);
    if (index >= 0) {
      list[index] = device;
    } else {
      list.add(device);
    }
  }

  // ---- 过滤与分组(与原 scan.vue 一致)----
  List<ScanDevice> filter(List<ScanDevice> list) {
    final query = state.query.trim().toUpperCase();
    return list
        .where((d) => (d.rssi ?? -200) >= state.rssiThreshold)
        .where((d) =>
            query.isEmpty ||
            d.name.toUpperCase().contains(query) ||
            d.id.toUpperCase().contains(query))
        .toList()
      ..sort((a, b) => state.sortDescending
          ? (b.rssi ?? -200).compareTo(a.rssi ?? -200)
          : (a.rssi ?? -200).compareTo(b.rssi ?? -200));
  }

  List<ScanDevice> get shownReceivers => filter(state.receivers);
  List<ScanDevice> get shownSensors => filter(state.sensors);
  List<ScanDevice> get shownPressure => shownSensors
      .where((d) => sensorTypeOf(classifyDevice(d)) == typePressure)
      .toList();
  List<ScanDevice> get shownTilt => shownSensors
      .where((d) => sensorTypeOf(classifyDevice(d)) == typeTilt)
      .toList();
  List<ScanDevice> get shownOther => shownSensors
      .where((d) => sensorTypeOf(classifyDevice(d)) == null)
      .toList();
  int get strongestRssi {
    var strongest = -200;
    for (final d in [...shownReceivers, ...shownSensors]) {
      final rssi = d.rssi ?? -200;
      if (rssi > strongest) strongest = rssi;
    }
    return strongest;
  }
}

final scanControllerProvider =
    StateNotifierProvider<ScanController, ScanState>(
  (ref) => ScanController(ref.watch(bleManagerProvider)),
);
