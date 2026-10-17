import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/ota/ota_service.dart';
import '../../../protocol/constants.dart';
import '../../../protocol/sensor_protocol.dart';
import '../../../site/site_controller.dart';
import '../application/sensor_controller.dart';

/// 传感器直连:实时数据 / 配置 / 校准 / 写 MAC / 休眠 / OTA。
class SensorPage extends ConsumerWidget {
  final String deviceId;
  final String name;
  final int type;
  const SensorPage({
    super.key,
    required this.deviceId,
    this.name = 'SensorNode',
    this.type = typePressure,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sensorControllerProvider(deviceId));
    final controller = ref.read(sensorControllerProvider(deviceId).notifier);
    final isMaintainer = ref.watch(siteControllerProvider).isMaintainer;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!state.ok && !state.connecting && !state.closing && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ref.read(sensorControllerProvider(deviceId)).ok) {
          ref.read(sensorControllerProvider(deviceId).notifier).connect();
        }
      });
    }
    final connecting = !state.ok && state.connecting;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _connectionPill(state)),
          ),
        ],
      ),
      body: connecting
          ? _connectingView(state, isDark)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (state.error != null) _connectionError(state.error!),
                if (!state.ok) _connectCard(controller, isDark),
                if (state.ok) ...[
            _liveDataCard(state, isDark),
            _configCard(state, controller, context, isMaintainer, isDark),
            _infoCard(state, isDark),
            if (isMaintainer) _maintainerCard(controller, context, isDark),
            if (isMaintainer)
              _OtaCard(
                state: state,
                onPickFile: () => _runOtaFromFile(ref, controller),
                onUrl: (url) => _runOtaFromUrl(url, ref, controller),
                isDark: isDark,
              ),
                ],
              ],
            ),
    );
  }

  Widget _connectingView(SensorState state, bool isDark) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      children: [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        const Center(
          child: Text('正在连接传感器',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(state.connectStatus.isEmpty ? '请稍候…' : state.connectStatus,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.mineMuted : AppColors.textMuted,
              )),
        ),
        const SizedBox(height: 20),
        _connectionLogCard(state, isDark),
      ],
    );
  }

  Widget _connectCard(SensorController controller, bool isDark) {
    return _card(
      isDark,
      child: Column(
        children: [
          Text('已断开', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => controller.connect(),
            child: const Text('连 接'),
          ),
        ],
      ),
    );
  }

  Widget _connectionError(String error) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '连接失败：$error',
        style: const TextStyle(fontSize: 12, color: AppColors.danger),
      ),
    );
  }

  Widget _connectionPill(SensorState state) {
    final String text;
    final Color background;
    final Color foreground;
    if (!state.ok && state.connecting) {
      text = '连接中';
      background = AppColors.warningBg;
      foreground = AppColors.warning;
    } else if (!state.ok) {
      text = '已断开';
      background = AppColors.dangerBg;
      foreground = AppColors.danger;
    } else if (state.sampleState == 'waiting') {
      text = '等待数据';
      background = AppColors.warningBg;
      foreground = AppColors.warning;
    } else if (state.sampleState == 'error') {
      text = '采样异常';
      background = AppColors.warningBg;
      foreground = AppColors.warning;
    } else if (state.sampleState == 'timeout') {
      text = '数据超时';
      background = AppColors.warningBg;
      foreground = AppColors.warning;
    } else {
      text = '已连接';
      background = AppColors.successBg;
      foreground = AppColors.success;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground)),
    );
  }

  Widget _connectionLogCard(SensorState state, bool isDark) {
    final muted = isDark ? AppColors.mineMuted : AppColors.textMuted;
    final logs = state.connectLogs;
    return _card(
      isDark,
      title: '连接日志',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.connectStatus.isNotEmpty)
            Text(
              state.connectStatus,
              style: TextStyle(fontSize: 12, color: muted),
            ),
          const SizedBox(height: 6),
          for (final line in logs)
            SelectableText(
              line,
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: muted,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }

  // ---- 实时数据 ----
  Widget _liveDataCard(SensorState state, bool isDark) {
    final payload = state.payload;
    final sensorType = state.sensorType ?? type;
    final value = payload == null
        ? '--'
        : sensorType == typeTilt
            ? formatAngles(payload.xAngle, payload.yAngle)
            : formatValue(sensorType, payload.pressure);
    final voltage = notifyVoltageV(payload, state.info);
    return _card(
      isDark,
      title: '实时数据',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (payload == null)
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.connectStatus.contains('订阅')
                          ? state.connectStatus
                          : '已连接，等待实时数据…',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.mineMuted
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (payload != null)
            Row(
              children: [
                _stat('电压', voltage == null ? '--' : '${voltage.toStringAsFixed(1)}V', isDark),
                _stat('序号', '${payload.seq}', isDark),
              ],
            ),
          if (payload != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _stat('运行', formatDuration(payload.uptime), isDark),
                if (sensorType == typeTilt)
                  _stat('原始', 'X${payload.xRaw} Y${payload.yRaw} Z${payload.zRaw}', isDark),
              ],
            ),
          ],
          if (sensorType == typeTilt && state.range != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _stat('距离', '${state.range!.distanceMm} mm', isDark),
                _stat('Peak', '${state.range!.peak}', isDark),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, bool isDark) {
    final muted = isDark ? AppColors.mineMuted : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: muted)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ---- 配置 ----
  Widget _configCard(
    SensorState state,
    SensorController controller,
    BuildContext context,
    bool isMaintainer,
    bool isDark,
  ) {
    final sensorType = state.sensorType ?? type;
    return _card(
      isDark,
      title: '配置',
      child: Column(
        children: [
          if (sensorType == typeTilt && isMaintainer)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('倾角标零'),
              subtitle: Text(
                state.offset == null
                    ? '正在读取传感器补偿…'
                    : '补偿 X ${(tiltOffsetX(state.offset!) / 10).toStringAsFixed(1)}°  '
                        'Y ${(tiltOffsetY(state.offset!) / 10).toStringAsFixed(1)}°',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '清除标零',
                    onPressed: state.offset == null || state.offset == 0
                        ? null
                        : () => _clearZero(context, controller),
                    icon: const Icon(Icons.restart_alt),
                  ),
                  FilledButton(
                    onPressed: state.payload == null || state.offset == null
                        ? null
                        : () => _markZero(context, controller),
                    child: const Text('当前位置标零'),
                  ),
                ],
              ),
            ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('采样速率'),
            trailing: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('慢速')),
                ButtonSegment(value: true, label: Text('快速')),
              ],
              selected: {state.rate == 1},
              onSelectionChanged: (s) => controller.setRate(s.first),
            ),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('低功耗模式'),
            trailing: Switch(
              value: state.powerMode == 1,
              onChanged: (v) => controller.setPowerMode(v ? 1 : 0),
            ),
          ),
          if (isMaintainer && sensorType == typePressure)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('校准偏移'),
              subtitle: Text('${state.offset ?? '--'}'),
              trailing: TextButton(
                onPressed: () => _editOffset(context, controller, state),
                child: const Text('修改'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _markZero(
    BuildContext context,
    SensorController controller,
  ) async {
    final ok = await controller.markZero();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '当前位置已写入传感器零点' : '标零失败，请重试')),
    );
  }

  Future<void> _clearZero(
    BuildContext context,
    SensorController controller,
  ) async {
    final ok = await controller.clearZero();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已清除传感器零点' : '清除失败，请重试')),
    );
  }

  Future<void> _editOffset(
    BuildContext context,
    SensorController controller,
    SensorState state,
  ) async {
    final textController = TextEditingController(text: '${state.offset ?? 0}');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('校准偏移'),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(hintText: '有符号整数'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    textController.dispose();
    final parsed = int.tryParse(value ?? '');
    if (parsed == null) return;
    await controller.writeOffset(parsed);
  }

  // ---- Sensor Info ----
  Widget _infoCard(SensorState state, bool isDark) {
    final info = state.info;
    if (info == null) {
      return _card(isDark, title: '传感器信息', child: const Text('未读取'));
    }
    return _card(
      isDark,
      title: '传感器信息',
      child: Column(
        children: [
          _infoRow('型号', typeName(info.sensorType) + (info.version > 0 ? ' v${info.version}' : ''), isDark),
          _infoRow('电压', formatVoltage(info.voltageMv), isDark),
          _infoRow('工作时长', formatDuration(info.workSeconds), isDark),
          _infoRow('启动时长', formatDuration(info.bootSeconds), isDark),
          _infoRow('错误数', '${info.errors}', isDark),
          if (info.rssi != null) _infoRow('RSSI', '${info.rssi} dBm', isDark),
          if (info.missedNotifications > 0) _infoRow('丢包', '${info.missedNotifications}', isDark),
          if (info.invalidSamples > 0) _infoRow('无效样本', '${info.invalidSamples}', isDark),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, bool isDark) {
    final muted = isDark ? AppColors.mineMuted : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: muted)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  // ---- 维护操作(仅维护模式) ----
  Widget _maintainerCard(
    SensorController controller,
    BuildContext context,
    bool isDark,
  ) {
    return _card(
      isDark,
      title: '维护操作',
      child: Column(
        children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('写入 MAC(写入后设备复位)'),
            trailing: TextButton(
              onPressed: () => _editMac(context, controller),
              child: const Text('写 MAC'),
            ),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('进入 EM4 休眠'),
            trailing: FilledButton.tonal(
              onPressed: () => controller.enterEm4(),
              child: const Text('休眠'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editMac(BuildContext context, SensorController controller) async {
    final textController = TextEditingController();
    final mac = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('写入 MAC'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(hintText: 'AA:BB:CC:DD:EE:FF'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: const Text('写入'),
          ),
        ],
      ),
    );
    textController.dispose();
    if (mac == null || mac.trim().isEmpty) return;
    final ok = await controller.writeMac(mac.trim());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '已写入,设备复位中' : 'MAC 格式无效或写入失败')),
      );
    }
  }

  // ---- OTA ----
  Future<void> _runOtaFromFile(WidgetRef ref, SensorController controller) async {
    final context = ref.context;
    try {
      final firmware = await ref.read(otaServiceProvider).pickFirmware();
      if (firmware.isEmpty) return;
      await controller.upgradeOta(firmware);
    } catch (e) {
      if (context.mounted) _toast(context, e.toString());
    }
  }

  Future<void> _runOtaFromUrl(
    String url,
    WidgetRef ref,
    SensorController controller,
  ) async {
    final context = ref.context;
    if (url.trim().isEmpty) {
      if (context.mounted) _toast(context, '请输入固件地址');
      return;
    }
    try {
      final firmware = await ref.read(otaServiceProvider).downloadFirmware(url.trim());
      await controller.upgradeOta(firmware);
    } catch (e) {
      if (context.mounted) _toast(context, e.toString());
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  // ---- 通用卡片 ----
  Widget _card(bool isDark, {String? title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.mineCard : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: AppColors.mineBorder) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

/// OTA 升级卡片:持有 URL 输入框 controller,避免重建泄漏。
class _OtaCard extends StatefulWidget {
  final SensorState state;
  final Future<void> Function() onPickFile;
  final Future<void> Function(String url) onUrl;
  final bool isDark;
  const _OtaCard({
    required this.state,
    required this.onPickFile,
    required this.onUrl,
    required this.isDark,
  });

  @override
  State<_OtaCard> createState() => _OtaCardState();
}

class _OtaCardState extends State<_OtaCard> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final running = state.otaRunning;
    final muted = widget.isDark ? AppColors.mineMuted : AppColors.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.mineCard : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: widget.isDark ? Border.all(color: AppColors.mineBorder) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('OTA 升级', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: '固件 HTTP 地址(或选择本地 .gbl)',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: running ? null : widget.onPickFile,
                  child: const Text('选择文件升级'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: running
                      ? null
                      : () => widget.onUrl(_urlController.text.trim()),
                  child: const Text('URL 升级'),
                ),
              ),
            ],
          ),
          if (running || state.otaProgress > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: state.otaProgress / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 6),
            Text(state.otaStatus, style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 6),
            for (final line in state.otaLogs.length > 12
                ? state.otaLogs.sublist(state.otaLogs.length - 12)
                : state.otaLogs)
              Text(line, style: TextStyle(fontSize: 11, color: muted)),
          ],
        ],
      ),
    );
  }
}
