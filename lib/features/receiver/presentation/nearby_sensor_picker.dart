import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ble/ble_manager.dart';
import '../../../ble/ble_providers.dart';
import '../../../ble/scan_device.dart';
import '../../../ble/scan_filter.dart';
import '../../../protocol/constants.dart';

Future<ScanDevice?> showNearbySensorPicker(BuildContext context) {
  return showModalBottomSheet<ScanDevice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.72,
      child: _NearbySensorPicker(),
    ),
  );
}

class _NearbySensorPicker extends ConsumerStatefulWidget {
  const _NearbySensorPicker();

  @override
  ConsumerState<_NearbySensorPicker> createState() =>
      _NearbySensorPickerState();
}

class _NearbySensorPickerState extends ConsumerState<_NearbySensorPicker> {
  StreamSubscription<List<ScanResult>>? _subscription;
  final Map<String, ScanDevice> _devices = {};
  bool _scanning = false;
  String? _error;

  BleManager get _ble => ref.read(bleManagerProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      if (!await _ble.ensureReady()) {
        throw BleException('蓝牙未开启或设备不支持 BLE');
      }
      await _subscription?.cancel();
      _subscription = _ble.scanResults.listen(_onResults);
      await _ble.startScan();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _scanning = false;
        });
      }
    }
  }

  void _onResults(List<ScanResult> results) {
    var changed = false;
    for (final result in results) {
      final device = _ble.toDevice(result);
      if (classifyDevice(device) == DeviceKind.receiver ||
          classifyDevice(device) == DeviceKind.other) {
        continue;
      }
      _devices[device.id] = device;
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _ble.stopScan().catchError((_) {});
    if (mounted) setState(() => _scanning = false);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_ble.stopScan().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((a, b) => (b.rssi ?? -200).compareTo(a.rssi ?? -200));
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('选择附近传感器',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      Text('列表按信号强度实时排序',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _scanning ? '停止扫描' : '重新扫描',
                  onPressed: _scanning ? _stop : _start,
                  icon: Icon(_scanning ? Icons.stop_circle_outlined : Icons.refresh),
                ),
              ],
            ),
          ),
          if (_scanning) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Text(_scanning ? '正在搜索附近传感器...' : '未发现传感器'),
                  )
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final kind = classifyDevice(device);
                      final type = sensorTypeOf(kind);
                      final typeLabel = type == typeTilt
                          ? '倾角'
                          : type == typePressure
                              ? '压力'
                              : '传感器';
                      return ListTile(
                        leading: const Icon(Icons.sensors),
                        title: Text(
                          device.name.isEmpty ? typeLabel : device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: SelectableText(
                          device.id,
                          maxLines: 1,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            letterSpacing: 0,
                          ),
                        ),
                        trailing: SizedBox(
                          width: 76,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(typeLabel,
                                  style: const TextStyle(fontSize: 12)),
                              Text('${device.rssi ?? '--'} dBm',
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                        onTap: () => Navigator.pop(context, device),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
