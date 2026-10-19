import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/ble_manager.dart';
import '../../../ble/ble_providers.dart';
import '../../../features/ota/ota_service.dart';
import '../../../protocol/constants.dart';
import '../../../protocol/models.dart';
import '../../../protocol/receiver_protocol.dart';
import '../../../protocol/sensor_protocol.dart';

/// 单个槽的运行状态。
class SlotState {
  final int sensorType;
  final int sensorId;
  final String mac;
  final bool bound;
  final SensorPayload? data;
  final RangeSample? range; // 最近一次测距流帧, 无有效测距数据时为 null
  final int rangeAt; // 最近测距帧时间戳(ms), 独立于倾角数据时间
  final int last; // 最近数据时间戳(ms)
  const SlotState({
    this.sensorType = 0,
    this.sensorId = 0,
    this.mac = '',
    this.bound = false,
    this.data,
    this.range,
    this.rangeAt = 0,
    this.last = 0,
  });

  SlotState copyWith({
    int? sensorType,
    int? sensorId,
    String? mac,
    bool? bound,
    SensorPayload? data,
    RangeSample? range,
    bool clearRange = false,
    int? rangeAt,
    int? last,
  }) {
    return SlotState(
      sensorType: sensorType ?? this.sensorType,
      sensorId: sensorId ?? this.sensorId,
      mac: mac ?? this.mac,
      bound: bound ?? this.bound,
      data: data ?? this.data,
      range: clearRange ? null : (range ?? this.range),
      rangeAt: clearRange ? 0 : (rangeAt ?? this.rangeAt),
      last: last ?? this.last,
    );
  }
}

class ReceiverState {
  final bool ok;
  final bool connecting;
  final bool closing;
  final bool suspendReconnect;
  final String? error;
  final int reconnectAttempt;
  final ReceiverStatus? status;
  final List<SlotState> slots;
  final List<SensorInfo?> sensorInfos;
  final List<int> rates;
  final int lastStreamAt;
  final bool otaRunning;
  final int otaProgress;
  final String otaStatus;
  final List<String> otaLogs;

  const ReceiverState({
    this.ok = false,
    this.connecting = false,
    this.closing = false,
    this.suspendReconnect = false,
    this.error,
    this.reconnectAttempt = 0,
    this.status,
    this.slots = const [],
    this.sensorInfos = const [],
    this.rates = const [],
    this.lastStreamAt = 0,
    this.otaRunning = false,
    this.otaProgress = 0,
    this.otaStatus = '',
    this.otaLogs = const [],
  });

  List<SlotState> get slotList => slots.length == slotCount ? slots : List.filled(slotCount, const SlotState());
  List<SensorInfo?> get infoList => sensorInfos.length == slotCount ? sensorInfos : List.filled(slotCount, null);
  List<int> get rateList => rates.length == slotCount ? rates : List.filled(slotCount, 0);

  ReceiverState copyWith({
    bool? ok,
    bool? connecting,
    bool? closing,
    bool? suspendReconnect,
    String? error,
    bool clearError = false,
    int? reconnectAttempt,
    ReceiverStatus? status,
    List<SlotState>? slots,
    List<SensorInfo?>? sensorInfos,
    List<int>? rates,
    int? lastStreamAt,
    bool? otaRunning,
    int? otaProgress,
    String? otaStatus,
    List<String>? otaLogs,
  }) {
    return ReceiverState(
      ok: ok ?? this.ok,
      connecting: connecting ?? this.connecting,
      closing: closing ?? this.closing,
      suspendReconnect: suspendReconnect ?? this.suspendReconnect,
      error: clearError ? null : (error ?? this.error),
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      status: status ?? this.status,
      slots: slots ?? this.slots,
      sensorInfos: sensorInfos ?? this.sensorInfos,
      rates: rates ?? this.rates,
      lastStreamAt: lastStreamAt ?? this.lastStreamAt,
      otaRunning: otaRunning ?? this.otaRunning,
      otaProgress: otaProgress ?? this.otaProgress,
      otaStatus: otaStatus ?? this.otaStatus,
      otaLogs: otaLogs ?? this.otaLogs,
    );
  }
}

class ReceiverController extends StateNotifier<ReceiverState> {
  ReceiverController(this._ble, this._ota, this.deviceId)
      : super(const ReceiverState()) {
    _watchdog =
        Timer.periodic(const Duration(seconds: 1), (_) => _checkDataAge());
  }

  final BleManager _ble;
  final OtaService _ota;
  final String deviceId;
  Timer? _watchdog;
  Timer? _reconnectTimer;
  final Map<String, Completer<CommandResponse?>> _waiters = {};

  // ---- 连接 ----
  Future<void> connect({bool silent = false}) async {
    if (state.closing || state.connecting) return;
    if (!silent) state = state.copyWith(suspendReconnect: false);
    _cancelReconnect();
    state = state.copyWith(connecting: true, clearError: true);
    try {
      await _ble.connect(
        deviceId,
        timeout: const Duration(seconds: 10),
        discoveryTimeout: const Duration(seconds: 5),
      );
      await _ble.subscribe(deviceId, rxServiceUuid, rxStatusUuid, _onStatus,
          timeout: const Duration(seconds: 3));
      await _ble.subscribe(deviceId, rxServiceUuid, rxStreamUuid, _onStream,
          timeout: const Duration(seconds: 3));
      await _ble.subscribe(deviceId, rxServiceUuid, rxRespUuid, _onResponse,
          timeout: const Duration(seconds: 3));
      state = state.copyWith(
        ok: true,
        connecting: false,
        reconnectAttempt: 0,
        lastStreamAt: DateTime.now().millisecondsSinceEpoch,
      );
      final status = await _ble
          .read(deviceId, rxServiceUuid, rxStatusUuid,
              timeout: const Duration(milliseconds: 1200))
          .catchError((_) => Uint8List(0));
      if (status.isNotEmpty) _onStatus(status);
      await refreshBindings();
      await refreshAllSensorInfo();
    } catch (e) {
      state = state.copyWith(ok: false, connecting: false, error: e.toString());
      await _ble.disconnect(deviceId).catchError((_) {});
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    state = state.copyWith(closing: true);
    _cancelReconnect();
    await _ble.disconnect(deviceId).catchError((_) {});
    state = state.copyWith(ok: false);
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _scheduleReconnect({bool immediate = false}) {
    if (state.closing ||
        state.suspendReconnect ||
        state.ok ||
        state.connecting ||
        _reconnectTimer != null) {
      return;
    }
    const delays = [1000, 2000, 4000, 8000, 15000];
    final index =
        state.reconnectAttempt >= delays.length ? delays.length - 1 : state.reconnectAttempt;
    final delay = immediate ? 0 : delays[index];
    if (!immediate) {
      state = state.copyWith(reconnectAttempt: state.reconnectAttempt + 1);
    }
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      _reconnectTimer = null;
      connect(silent: true);
    });
  }

  // ---- 事件回调 ----
  void _onStatus(Uint8List value) {
    final status = parseStatus(value);
    if (status == null) return;
    final rates = List.generate(
      slotCount,
      (i) => bit(status.fast, i) ? 1 : 0,
    );
    state = state.copyWith(status: status, rates: rates);
  }

  void _onStream(Uint8List value) {
    final now = DateTime.now().millisecondsSinceEpoch;
    // 数据流特征上按长度区分两种帧: 18 字节倾角/压力载荷, 5 字节测距。
    if (value.length == rangeStreamLen) {
      final range = parseRangeStream(value);
      if (range == null || range.slot >= slotCount) return;
      final slots = List<SlotState>.of(state.slotList);
      slots[range.slot] = slots[range.slot].copyWith(
        range: range,
        rangeAt: now,
      );
      state = state.copyWith(slots: slots);
      return;
    }
    final sample = parseStream(value);
    if (sample == null || sample.slot >= slotCount) return;
    final slots = List<SlotState>.of(state.slotList);
    slots[sample.slot] = slots[sample.slot].copyWith(
      data: sample.payload,
      last: now,
    );
    state = state.copyWith(
      slots: slots,
      lastStreamAt: now,
    );
  }

  void _onResponse(Uint8List value) {
    final response = parseResponse(value);
    if (response == null) return;
    if (response.opcode == opGetSensorInfo &&
        response.slot < slotCount &&
        response.sensorInfo != null) {
      final infos = state.infoList;
      infos[response.slot] = response.sensorInfo;
      state = state.copyWith(sensorInfos: infos);
    }
    if (response.opcode == opGetSlot && response.slot < slotCount) {
      _applyBinding(response.slot, response.type, response.sensorId, response.mac,
          response.status == 0);
    }
    final key = '${response.opcode}|${response.slot}';
    final waiter = _waiters.remove(key) ??
        _waiters.remove('${response.opcode}');
    if (waiter != null && !waiter.isCompleted) waiter.complete(response);
  }

  void _applyBinding(int slot, int type, int sid, String mac, bool bound) {
    final slots = List<SlotState>.of(state.slotList);
    slots[slot] = slots[slot].copyWith(
      sensorType: type,
      sensorId: sid,
      mac: mac,
      // 未绑定 = 类型与编号都为 0
      bound: bound && !(type == 0 && sid == 0),
      // 非倾角传感器不会上报测距, 清掉可能残留的旧距离。
      clearRange: type != typeTilt,
    );
    state = state.copyWith(slots: slots);
  }

  // ---- 命令 ----
  Future<CommandResponse?> _command(
    Uint8List command,
    String key, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final completer = Completer<CommandResponse?>();
    _waiters[key] = completer;
    final timer = Timer(timeout, () {
      if (_waiters[key] == completer) _waiters.remove(key);
      if (!completer.isCompleted) completer.complete(null);
    });
    try {
      await _ble.writeRequest(deviceId, rxServiceUuid, rxCmdUuid, command);
    } catch (_) {
      timer.cancel();
      if (_waiters[key] == completer) _waiters.remove(key);
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  Future<void> refreshBindings() async {
    if (!state.ok) return;
    final futures = <Future<CommandResponse?>>[];
    for (var slot = 0; slot < slotCount; slot++) {
      futures.add(_command(cmdGetSlot(slot), '$opGetSlot|$slot'));
    }
    final results = await Future.wait(futures);
    for (var slot = 0; slot < slotCount; slot++) {
      final response = results[slot];
      if (response != null && response.slot < slotCount) {
        _applyBinding(response.slot, response.type, response.sensorId,
            response.mac, response.status == 0);
      }
    }
  }

  Future<void> refreshAllSensorInfo() async {
    if (!state.ok) return;
    for (var slot = 0; slot < slotCount; slot++) {
      final shouldRead = _ble.isConnected(deviceId) &&
          (bit(state.status?.online ?? 0, slot) ||
              state.slotList[slot].data != null);
      if (shouldRead) {
        await refreshSensorInfo(slot);
      }
    }
  }

  /// 读取指定槽的 Sensor Info(供 UI 读取,避免直接访问受保护的 state)。
  SensorInfo? sensorInfo(int slot) =>
      slot >= 0 && slot < slotCount ? state.infoList[slot] : null;

  /// 当前接收器 ID(供 UI 读取)。
  int? get currentRid => state.status?.rid;

  /// 读取指定槽的 Sensor Info;响应经 [_onResponse] 更新 infoList。
  Future<void> refreshSensorInfo(int slot) async {
    if (!state.ok || slot >= slotCount) return;
    await _command(
      cmdGetSensorInfo(slot),
      '$opGetSensorInfo|$slot',
      timeout: const Duration(milliseconds: 1500),
    );
  }

  Future<bool> setSlotBinding(int slot, int type, int sid, String mac) async {
    final macBytes = macToBytes(mac);
    if (macBytes == null || type == 0 || sid == 0) return false;
    final response = await _command(
      cmdSetSlot(slot, type, sid, macBytes),
      '$opSetSlot|$slot',
      timeout: const Duration(seconds: 3),
    );
    return response != null && response.status == 0;
  }

  Future<bool> clearSlot(int slot) async {
    final response = await _command(
      cmdClearSlot(slot),
      '$opClearSlot|$slot',
    );
    final ok = response != null && response.status == 0;
    if (ok) {
      final slots = List<SlotState>.of(state.slotList);
      slots[slot] = const SlotState();
      state = state.copyWith(slots: slots);
    }
    return ok;
  }

  Future<bool> clearAll() async {
    final response = await _command(cmdClearAll(), '$opClearAll');
    if (response != null && response.status == 0) {
      state = state.copyWith(slots: List.filled(slotCount, const SlotState()));
    }
    return response != null && response.status == 0;
  }

  Future<bool> setReceiverId(int rid) async {
    final response = await _command(cmdSetId(rid), '$opSetId');
    final ok = response != null && response.status == 0;
    if (ok && state.ok) {
      // 固件修改 ID 后会更新广播名；立即读取状态，让页面名称同步刷新，
      // 不必等待下一次扫描或重新连接。
      final status = await _ble
          .read(deviceId, rxServiceUuid, rxStatusUuid,
              timeout: const Duration(seconds: 2))
          .catchError((_) => Uint8List(0));
      if (status.isNotEmpty) _onStatus(status);
    }
    return ok;
  }

  Future<bool> setRate(int slot, bool fast) async {
    final response = await _command(
      cmdSetRate(slot, fast),
      '$opSetRate|$slot',
    );
    final ok = response != null && response.status == 0;
    if (ok) {
      final rates = state.rateList;
      rates[slot] = fast ? 1 : 0;
      state = state.copyWith(rates: rates);
    } else if (fast && state.ok) {
      final fallback = await _command(cmdSetRate(slot, false), '$opSetRate|$slot');
      if (fallback?.status == 0) {
        final rates = state.rateList;
        rates[slot] = 0;
        state = state.copyWith(rates: rates, error: '快速切换超时,已回退慢速');
      }
    }
    return ok;
  }

  // ---- 数据停滞看门狗 ----
  void _checkDataAge() {
    if (!state.ok) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final slots = List<SlotState>.of(state.slotList);
    var cleared = false;
    for (var i = 0; i < slots.length; i++) {
      if (slots[i].range != null && now - slots[i].rangeAt > 2000) {
        slots[i] = slots[i].copyWith(clearRange: true);
        cleared = true;
      }
    }
    if (cleared) state = state.copyWith(slots: slots);
    if (state.lastStreamAt == 0) return;
    final online = state.status != null &&
        List.generate(slotCount, (i) => bit(state.status!.online, i))
            .any((v) => v);
    if (!online) return;
    final hasFast = state.rateList.any((r) => r == 1);
    final timeout = hasFast ? 10000 : 25000;
    final age = DateTime.now().millisecondsSinceEpoch - state.lastStreamAt;
    if (age > timeout) _handleStall();
  }

  Future<void> _handleStall() async {
    if (state.closing || state.suspendReconnect || !state.ok || state.connecting) {
      return;
    }
    state = state.copyWith(ok: false, connecting: true);
    await _ble.disconnect(deviceId).catchError((_) {});
    state = state.copyWith(connecting: false);
    _scheduleReconnect();
  }

  // ---- OTA ----
  Future<void> upgradeOta(
    Uint8List firmware, {
    void Function(int? progress, String message)? onProgress,
  }) async {
    if (state.otaRunning) return;
    state = state.copyWith(
      otaRunning: true,
      otaProgress: 0,
      otaStatus: '准备升级',
      otaLogs: [],
      suspendReconnect: true,
    );
    void log(int? progress, String message) {
      final logs = [...state.otaLogs, message];
      state = state.copyWith(
        otaProgress: progress ?? state.otaProgress,
        otaStatus: message,
        otaLogs: logs.length > 200 ? logs.sublist(200) : logs,
      );
      onProgress?.call(progress, message);
    }

    try {
      final version = await _ota.upgrade(
        deviceId: deviceId,
        firmware: firmware,
        onProgress: log,
      );
      state = state.copyWith(
        otaRunning: false,
        otaStatus: version == null ? '升级完成,设备未恢复' : '升级完成,版本=$version',
      );
    } catch (e) {
      state = state.copyWith(
        otaRunning: false,
        otaStatus: '升级失败: $e',
        otaLogs: [...state.otaLogs, '升级失败: $e'],
      );
    } finally {
      state = state.copyWith(suspendReconnect: false);
      if (!state.ok) _scheduleReconnect();
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _reconnectTimer?.cancel();
    for (final waiter in _waiters.values) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    _waiters.clear();
    unawaited(_ble.disconnect(deviceId).catchError((_) {}));
    super.dispose();
  }
}

final receiverControllerProvider =
    StateNotifierProvider.autoDispose.family<ReceiverController, ReceiverState, String>(
  (ref, deviceId) => ReceiverController(
    ref.watch(bleManagerProvider),
    ref.watch(otaServiceProvider),
    deviceId,
  ),
);
