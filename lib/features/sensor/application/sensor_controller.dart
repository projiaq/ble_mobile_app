import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/ble_manager.dart';
import '../../../ble/ble_providers.dart';
import '../../../features/ota/ota_service.dart';
import '../../../protocol/constants.dart';
import '../../../protocol/models.dart';
import '../../../protocol/sensor_protocol.dart';

class SensorState {
  final bool ok;
  final bool connecting;
  final bool closing;
  final bool suspendReconnect;
  final String sampleState; // waiting / ok / timeout / error
  final String? error;
  final SensorPayload? payload;
  // 倾角传感器快速模式下的测距帧(4 字节), 无测距数据时为 null。
  final ({int distanceMm, int peak})? range;
  final int rangeAt;
  final SensorInfo? info;
  final int? rate; // 0 慢 / 1 快
  final int? powerMode; // 0 普通 / 1 低功耗
  final int? offset;
  final int lastDataAt;
  final int reconnectAttempt;
  final bool otaRunning;
  final int otaProgress;
  final String otaStatus;
  final List<String> otaLogs;
  final String connectStatus;
  final List<String> connectLogs;

  const SensorState({
    this.ok = false,
    this.connecting = false,
    this.closing = false,
    this.suspendReconnect = false,
    this.sampleState = 'waiting',
    this.error,
    this.payload,
    this.range,
    this.rangeAt = 0,
    this.info,
    this.rate,
    this.powerMode,
    this.offset,
    this.lastDataAt = 0,
    this.reconnectAttempt = 0,
    this.otaRunning = false,
    this.otaProgress = 0,
    this.otaStatus = '',
    this.otaLogs = const [],
    this.connectStatus = '',
    this.connectLogs = const [],
  });

  int? get sensorType => info?.sensorType;

  SensorState copyWith({
    bool? ok,
    bool? connecting,
    bool? closing,
    bool? suspendReconnect,
    String? sampleState,
    String? error,
    bool clearError = false,
    SensorPayload? payload,
    bool clearPayload = false,
    ({int distanceMm, int peak})? range,
    bool clearRange = false,
    int? rangeAt,
    SensorInfo? info,
    int? rate,
    int? powerMode,
    int? offset,
    int? lastDataAt,
    int? reconnectAttempt,
    bool? otaRunning,
    int? otaProgress,
    String? otaStatus,
    List<String>? otaLogs,
    String? connectStatus,
    List<String>? connectLogs,
  }) {
    return SensorState(
      ok: ok ?? this.ok,
      connecting: connecting ?? this.connecting,
      closing: closing ?? this.closing,
      suspendReconnect: suspendReconnect ?? this.suspendReconnect,
      sampleState: sampleState ?? this.sampleState,
      error: clearError ? null : (error ?? this.error),
      payload: clearPayload ? null : (payload ?? this.payload),
      range: clearRange ? null : (range ?? this.range),
      rangeAt: clearRange ? 0 : (rangeAt ?? this.rangeAt),
      info: info ?? this.info,
      rate: rate ?? this.rate,
      powerMode: powerMode ?? this.powerMode,
      offset: offset ?? this.offset,
      lastDataAt: lastDataAt ?? this.lastDataAt,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      otaRunning: otaRunning ?? this.otaRunning,
      otaProgress: otaProgress ?? this.otaProgress,
      otaStatus: otaStatus ?? this.otaStatus,
      otaLogs: otaLogs ?? this.otaLogs,
      connectStatus: connectStatus ?? this.connectStatus,
      connectLogs: connectLogs ?? this.connectLogs,
    );
  }
}

class SensorController extends StateNotifier<SensorState> {
  SensorController(this._ble, this._ota, this.deviceId)
      : super(const SensorState()) {
    _watchdog =
        Timer.periodic(const Duration(seconds: 1), (_) => _checkDataAge());
  }

  final BleManager _ble;
  final OtaService _ota;
  final String deviceId;
  Timer? _watchdog;
  Timer? _reconnectTimer;
  int _lastNotifyAt = 0;
  Stopwatch? _connectWatch;

  static const int _slowNotifyIntervalMs = 700;

  void _startConnectLog({required bool silent}) {
    _connectWatch = Stopwatch()..start();
    final mode = silent ? '自动重连' : '手动/打开页面连接';
    state = state.copyWith(connectLogs: [], connectStatus: '开始连接');
    _connectLog('开始连接($mode), deviceId=$deviceId');
  }

  void _connectLog(String message) {
    if (!mounted) return;
    final elapsed = _connectWatch?.elapsedMilliseconds ?? 0;
    final line = '${elapsed}ms $message';
    debugPrint('[SensorConnect] $line');
    final logs = [...state.connectLogs, line];
    state = state.copyWith(
      connectStatus: message,
      connectLogs: logs.length > 80 ? logs.sublist(logs.length - 80) : logs,
    );
  }

  // ---- 连接 / 重连 ----
  Future<void> connect({bool silent = false}) async {
    if (state.closing || state.connecting) return;
    if (!silent) {
      state = state.copyWith(suspendReconnect: false);
    }
    _cancelReconnect();
    _lastNotifyAt = 0;
    state = state.copyWith(
      connecting: true,
      sampleState: 'waiting',
      lastDataAt: 0,
      clearError: true,
      clearPayload: true,
      clearRange: true,
    );
    _startConnectLog(silent: silent);
    try {
      await _ble.connect(
        deviceId,
        timeout: const Duration(seconds: 8),
        discoveryTimeout: const Duration(seconds: 4),
        onLog: _connectLog,
      );
      state = state.copyWith(
        ok: true,
        connecting: false,
        sampleState: 'waiting',
        reconnectAttempt: 0,
      );
      try {
        _connectLog('开始订阅实时数据通知, timeout=3s');
        await _ble.subscribe(
          deviceId,
          snDataSvcUuid,
          snDataUuid,
          _onData,
          timeout: const Duration(seconds: 3),
        );
        _connectLog('实时数据通知订阅完成, 等待首包数据');
      } catch (e) {
        _connectLog('通知订阅失败: $e');
        state = state.copyWith(ok: false, error: e.toString());
        await _ble.disconnect(deviceId).catchError((_) {});
        _scheduleReconnect();
        return;
      }
      // 首屏先显示连接状态，配置和设备信息在后台并行读取，避免倾角页等待多次 BLE read。
      _connectLog('连接首屏完成,后台读取配置和设备信息');
      unawaited(_warmUpAfterConnect());
    } catch (e) {
      _connectLog('连接流程失败: $e');
      state = state.copyWith(
        ok: false,
        connecting: false,
        error: e.toString(),
      );
      await _ble.disconnect(deviceId).catchError((_) {});
      _scheduleReconnect();
    }
  }

  Future<void> _warmUpAfterConnect() async {
    _connectLog('开始加载配置和传感器信息');
    try {
      await Future.wait<void>([
        _readCfgWithConnectLog(),
        _readSensorInfoWithConnectLog(),
      ]);
      if (state.ok) _connectLog('后台初始化完成, 开始接收数据');
    } catch (e) {
      _connectLog('后台加载失败: $e');
    }
  }

  Future<void> _readCfgWithConnectLog() async {
    _connectLog('开始读取采样/电源/偏移配置');
    await readCfg();
    final rate = state.rate?.toString() ?? '--';
    final power = state.powerMode?.toString() ?? '--';
    final offset = state.offset?.toString() ?? '--';
    _connectLog('配置读取完成 rate=$rate power=$power offset=$offset');
  }

  Future<void> _readSensorInfoWithConnectLog() async {
    _connectLog('开始读取传感器信息');
    await readSensorInfo();
    final info = state.info;
    _connectLog(
      info == null
          ? '传感器信息未读取到'
          : '传感器信息完成 type=${info.sensorType} version=${info.version}',
    );
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

  // ---- 数据 ----
  void _onData(Uint8List value) {
    // 测距帧(4 字节)与 17 字节倾角帧共用同一通知特征, 按长度区分。
    if (value.length == sensorRangeLen) {
      final range = parseSensorRange(value);
      if (range != null) {
        state = state.copyWith(
          range: range,
          rangeAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
      return;
    }
    if (value.length < sensorPayloadLen) return;
    final payload = parsePayload(value, 0);
    if (payload == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final notifyInterval = _lastNotifyAt == 0 ? 0 : now - _lastNotifyAt;
    _lastNotifyAt = now;
    if (state.lastDataAt == 0) _connectLog('收到首包实时数据, length=${value.length}');
    final sampleState = (state.info != null &&
            state.info!.version >= 2 &&
            payload.readOk == false)
        ? 'error'
        : 'ok';
    state = state.copyWith(
      payload: payload,
      sampleState: sampleState,
      lastDataAt: now,
      rate: state.rate == 1 && notifyInterval >= _slowNotifyIntervalMs ? 0 : state.rate,
    );
  }

  // ---- 配置 ----
  Future<void> readCfg() async {
    try {
      final rate = await _ble.read(deviceId, snCfgSvcUuid, snRateUuid);
      if (rate.isNotEmpty) {
        state = state.copyWith(rate: rate[0] != 0 ? 1 : 0);
      }
    } catch (_) {}
    try {
      final power = await _ble.read(deviceId, snCfgSvcUuid, snPowerModeUuid);
      if (power.isNotEmpty) {
        state = state.copyWith(powerMode: power[0] != 0 ? 1 : 0);
      }
    } catch (_) {}
    try {
      final offset = await _ble.read(deviceId, snCfgSvcUuid, snOffsetUuid);
      if (offset.length >= 4) {
        final dv = ByteData.sublistView(offset);
        state = state.copyWith(offset: dv.getInt32(0, Endian.little));
      }
    } catch (_) {
      state = state.copyWith(offset: 0);
    }
  }

  Future<void> readSensorInfo() async {
    if (!state.ok) return;
    try {
      final value = await _ble.read(deviceId, snCfgSvcUuid, snInfoUuid);
      final info = parseSensorInfo(value);
      if (info != null) state = state.copyWith(info: info);
    } catch (_) {}
  }

  Future<bool> writeOffset(int value) async {
    final bytes = ByteData(4)..setInt32(0, value, Endian.little);
    try {
      await _ble.writeRequest(
        deviceId,
        snCfgSvcUuid,
        snOffsetUuid,
        bytes.buffer.asUint8List(),
      );
      state = state.copyWith(offset: value);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> markZero() async {
    final payload = state.payload;
    if (payload == null) return false;
    final current = state.offset ?? 0;
    final offset = calculateTiltZeroOffset(
      current,
      payload.xAngle,
      payload.yAngle,
    );
    return writeOffset(offset);
  }

  Future<bool> clearZero() => writeOffset(packTiltOffsets(0, 0));

  Future<bool> setRate(bool fast) async {
    try {
      await _ble.writeRequest(
        deviceId,
        snCfgSvcUuid,
        snRateUuid,
        Uint8List.fromList([fast ? 1 : 0]),
      );
      state = state.copyWith(rate: fast ? 1 : 0, clearRange: !fast);
      return true;
    } catch (e) {
      if (fast && state.ok) {
        try {
          await _ble.writeRequest(
            deviceId,
            snCfgSvcUuid,
            snRateUuid,
            Uint8List.fromList([0]),
          );
          state = state.copyWith(rate: 0, clearRange: true, error: '快速切换超时,已回退慢速');
          return false;
        } catch (_) {}
      }
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  Future<bool> setPowerMode(int mode) async {
    try {
      await _ble.writeRequest(
        deviceId,
        snCfgSvcUuid,
        snPowerModeUuid,
        Uint8List.fromList([mode]),
      );
      state = state.copyWith(powerMode: mode);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// 写 MAC:写入后设备复位,连接预期断开,暂停自动重连。
  Future<bool> writeMac(String mac) async {
    final bytes = macToBytes(mac);
    if (bytes == null) return false;
    state = state.copyWith(suspendReconnect: true);
    try {
      await _ble.writeRequest(
        deviceId,
        snCfgSvcUuid,
        snMacUuid,
        Uint8List.fromList(bytes),
      );
      return true;
    } catch (_) {
      state = state.copyWith(suspendReconnect: false);
      return false;
    }
  }

  /// 进入 EM4 休眠:Data Rate=0x02 保存运行时间并进入 EM4,连接预期断开。
  Future<bool> enterEm4() async {
    state = state.copyWith(suspendReconnect: true);
    try {
      await _ble.writeRequest(
        deviceId,
        snCfgSvcUuid,
        snRateUuid,
        Uint8List.fromList([2]),
      );
      state = state.copyWith(ok: false, sampleState: 'waiting');
      return true;
    } catch (_) {
      state = state.copyWith(suspendReconnect: false);
      return false;
    }
  }

  // ---- 数据停滞看门狗 ----
  void _checkDataAge() {
    if (!state.ok) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (state.range != null && now - state.rangeAt > 2000) {
      state = state.copyWith(clearRange: true);
    }
    if (state.lastDataAt == 0) return;
    final timeout = (state.powerMode != null &&
            state.powerMode != 0 &&
            state.rate != 1)
        ? 15000
        : 5000;
    final age = DateTime.now().millisecondsSinceEpoch - state.lastDataAt;
    if (age > timeout) state = state.copyWith(sampleState: 'timeout');
    if (age > timeout + 3000) _handleStall();
  }

  Future<void> _handleStall() async {
    if (state.closing || state.suspendReconnect || !state.ok || state.connecting) {
      return;
    }
    state = state.copyWith(ok: false, connecting: true, sampleState: 'timeout');
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
      state = state.copyWith(
        otaProgress: progress ?? state.otaProgress,
        otaStatus: message,
        otaLogs: [...state.otaLogs, message].length > 200
            ? [...state.otaLogs, message].sublist(200)
            : [...state.otaLogs, message],
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
    unawaited(_ble.disconnect(deviceId).catchError((_) {}));
    super.dispose();
  }
}

final sensorControllerProvider =
    StateNotifierProvider.autoDispose.family<SensorController, SensorState, String>(
  (ref, deviceId) => SensorController(
    ref.watch(bleManagerProvider),
    ref.watch(otaServiceProvider),
    deviceId,
  ),
);
