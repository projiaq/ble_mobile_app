import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../features/ota/ota_card.dart';
import '../../../features/ota/ota_service.dart';
import '../../../protocol/constants.dart';
import '../../../protocol/models.dart';
import '../../../protocol/sensor_protocol.dart';
import '../../../site/site_controller.dart';
import '../../../ble/scan_filter.dart';
import '../application/receiver_controller.dart';
import 'binding_editor.dart';
import 'binding_page.dart';

/// 接收器 8 槽管理与实时数据。
class ReceiverPage extends ConsumerWidget {
  final String deviceId;
  final String name;
  const ReceiverPage({super.key, required this.deviceId, this.name = 'AIOT-'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(receiverControllerProvider(deviceId));
    final controller = ref.read(receiverControllerProvider(deviceId).notifier);
    final isMaintainer = ref.watch(siteControllerProvider).isMaintainer;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = state.status == null
        ? name
        : receiverDisplayName(deviceId, state.status!.rid);

    if (!state.ok && !state.connecting && !state.closing && state.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ref.read(receiverControllerProvider(deviceId)).ok) {
          ref.read(receiverControllerProvider(deviceId).notifier).connect();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _connectionPill(state)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.error != null) _errorBanner(state.error!),
          if (!state.ok && !state.connecting)
            _connectCard(controller, isDark)
          else if (state.connecting)
            const _StatusCard('连接中…'),
          if (state.ok) ...[
            _headerCard(state, controller, context, isMaintainer, isDark),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.0,
              children: List.generate(
                slotCount,
                (i) =>
                    _slotCard(state, controller, context, i, isMaintainer, isDark),
              ),
            ),
            if (isMaintainer) ...[
              const SizedBox(height: 12),
              BindingPage(
                deviceId: deviceId,
                name: displayName,
                embedded: true,
              ),
              const SizedBox(height: 4),
              _OtaSection(
                state: state,
                controller: controller,
                ref: ref,
                isDark: isDark,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _connectCard(ReceiverController controller, bool isDark) {
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

  Widget _errorBanner(String error) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(error, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
    );
  }

  Widget _connectionPill(ReceiverState state) {
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

  Widget _headerCard(
    ReceiverState state,
    ReceiverController controller,
    BuildContext context,
    bool isMaintainer,
    bool isDark,
  ) {
    final status = state.status;
    final rid = status?.rid ?? 0;
    return _card(
      isDark,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '接收器 ID: $rid',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              if (isMaintainer)
                TextButton(
                  onPressed: () => _editReceiverId(context, controller),
                  child: const Text('改 ID'),
                ),
              if (isMaintainer)
                TextButton(
                  onPressed: () => _confirmClearAll(context, controller),
                  child: const Text('清全部',
                      style: TextStyle(color: AppColors.danger)),
                ),
            ],
          ),
          Row(
            children: [
              _countChip('绑定', status?.boundCount() ?? 0, isDark),
              const SizedBox(width: 8),
              _countChip('在线', status?.onlineCount() ?? 0, isDark),
              const SizedBox(width: 8),
              _countChip('有效', status?.validCount() ?? 0, isDark),
            ],
          ),
          if (isMaintainer) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => context.push(
                  '/receiver/$deviceId/bindings?name=${Uri.encodeComponent(name)}',
                ),
                child: const Text('绑定管理'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _countChip(String label, int value, bool isDark) {
    final muted = isDark ? AppColors.mineMuted : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.mineCard : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label $value', style: TextStyle(fontSize: 12, color: muted)),
    );
  }

  // ---- 槽卡片 ----
  Widget _slotCard(
    ReceiverState state,
    ReceiverController controller,
    BuildContext context,
    int slot,
    bool isMaintainer,
    bool isDark,
  ) {
    final slotState = state.slotList[slot];
    final (pillText, pillBg, pillFg) = _slotPill(state, slot, isDark);
    final value = slotState.data == null
        ? '—'
        : formatValue(
            slotState.sensorType != 0 ? slotState.sensorType : typePressure,
            slotState.data!.pressure,
          );
    final muted = isDark ? AppColors.mineMuted : AppColors.textMuted;
    final sensorNameColor = isDark ? AppColors.mineText : AppColors.text;

    return InkWell(
      onTap: () => _showSensorInfo(context, controller, slot, isDark),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.mineCard : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: isDark ? Border.all(color: AppColors.mineBorder) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('槽位 ${slot + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(pillText,
                      style:
                          TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: pillFg)),
                ),
              ],
            ),
            const Spacer(),
            // 大数值:FittedBox 缩放,避免倾角 X/Y 值溢出卡片
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            SizedBox(
              height: 30,
              child: Text(
                positionLabel(slotState.sensorType, slotState.sensorId),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w500,
                  color: sensorNameColor,
                ),
              ),
            ),
            if (slotState.sensorType == typeTilt)
              Text(
                formatDistance(
                  slotState.range?.distanceMm,
                  slotState.range?.peak,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: slotState.range == null ? muted : AppColors.primary,
                ),
              ),
            Text(
              slotState.mac,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: muted),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 26, height: 26),
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  tooltip: '切换速率',
                  icon: Icon(
                    state.rateList[slot] == 1
                        ? Icons.speed
                        : Icons.speed_outlined,
                    color: state.rateList[slot] == 1
                        ? AppColors.primary
                        : muted,
                  ),
                  onPressed: () =>
                      controller.setRate(slot, state.rateList[slot] != 1),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 26, height: 26),
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  tooltip: '读取信息',
                  icon: Icon(Icons.info_outline, color: muted),
                  onPressed: () => _showSensorInfo(context, controller, slot, isDark),
                ),
                if (isMaintainer)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 26, height: 26),
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: '绑定',
                    icon: Icon(Icons.edit_outlined, color: muted),
                    onPressed: () => _openBindingEditor(context, controller, state, slot, isDark),
                  ),
                if (isMaintainer)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 26, height: 26),
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    tooltip: '清槽',
                    icon: Icon(Icons.delete_outline, color: muted),
                    onPressed: () => _confirmClearSlot(context, controller, slot),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, Color, Color) _slotPill(ReceiverState state, int slot, bool isDark) {
    final status = state.status;
    if (status == null || !bit(status.bound, slot)) {
      return ('未绑定', AppColors.divider, AppColors.textMuted);
    }
    if (!bit(status.online, slot)) {
      return ('等待连接', AppColors.divider, AppColors.textMuted);
    }
    final timeoutMs = state.rateList[slot] == 1 ? 5000 : 15000;
    final slotState = state.slotList[slot];
    final info = state.infoList[slot];
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((info?.dataTimedOut ?? false) ||
        (slotState.last != 0 && now - slotState.last > timeoutMs)) {
      return ('数据超时', AppColors.warningBg, AppColors.warning);
    }
    if (slotState.data != null &&
        (info?.version ?? 0) >= 2 &&
        slotState.data!.readOk == false) {
      return ('采样异常', AppColors.warningBg, AppColors.warning);
    }
    if (!bit(status.valid, slot)) {
      return ('无有效数据', AppColors.warningBg, AppColors.warning);
    }
    return ('在线', AppColors.successBg, AppColors.success);
  }

  // ---- 弹窗 ----
  Future<void> _showSensorInfo(
    BuildContext context,
    ReceiverController controller,
    int slot,
    bool isDark,
  ) async {
    await controller.refreshSensorInfo(slot);
    if (!context.mounted) return;
    final info = controller.sensorInfo(slot);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('槽位 ${slot + 1} 传感器'),
        content: info == null
            ? const Text('暂无信息,可点"读取信息"刷新')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('型号',
                      typeName(info.sensorType) +
                          (info.version > 0 ? ' v${info.version}' : ''),
                      isDark),
                  _infoRow('电压', formatVoltage(info.voltageMv), isDark),
                  _infoRow('工作时长', formatDuration(info.workSeconds), isDark),
                  _infoRow('错误数', '${info.errors}', isDark),
                  if (info.rssi != null) _infoRow('RSSI', '${info.rssi} dBm', isDark),
                  if (info.missedNotifications > 0)
                    _infoRow('丢包', '${info.missedNotifications}', isDark),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _editReceiverId(
    BuildContext context,
    ReceiverController controller,
  ) async {
    final textController =
        TextEditingController(text: '${controller.currentRid ?? 0}');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改接收器 ID'),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
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
    final id = int.tryParse(value ?? '');
    if (id == null) return;
    await controller.setReceiverId(id);
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    ReceiverController controller,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空全部绑定'),
        content: const Text('将清空接收器全部 8 个槽位绑定,确定?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await controller.clearAll();
  }

  Future<void> _confirmClearSlot(
    BuildContext context,
    ReceiverController controller,
    int slot,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清空槽位 ${slot + 1}'),
        content: const Text('确定清空该槽位绑定?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await controller.clearSlot(slot);
  }

  Future<void> _openBindingEditor(
    BuildContext context,
    ReceiverController controller,
    ReceiverState state,
    int slot,
    bool isDark,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: BindingEditor(
          slot: slot,
          current: state.slotList[slot],
          onSave: (type, sid, mac) async {
            final ok = await controller.setSlotBinding(slot, type, sid, mac);
            if (ok) await controller.refreshBindings();
            return ok;
          },
          onClear: () => controller.clearSlot(slot),
          isDark: isDark,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, bool isDark) {
    final muted = isDark ? AppColors.mineMuted : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: muted)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  // ---- 通用 ----
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

class _StatusCard extends StatelessWidget {
  final String text;
  const _StatusCard(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Text(text),
    );
  }
}

/// OTA 段:封装 OtaCard 与固件加载。
class _OtaSection extends StatelessWidget {
  final ReceiverState state;
  final ReceiverController controller;
  final WidgetRef ref;
  final bool isDark;
  const _OtaSection({
    required this.state,
    required this.controller,
    required this.ref,
    required this.isDark,
  });

  Future<void> _fromFile(BuildContext context) async {
    try {
      final firmware = await ref.read(otaServiceProvider).pickFirmware();
      if (firmware.isEmpty) return;
      await controller.upgradeOta(firmware);
    } catch (e) {
      if (context.mounted) _toast(context, e.toString());
    }
  }

  Future<void> _fromUrl(BuildContext context, String url) async {
    if (url.trim().isEmpty) {
      _toast(context, '请输入固件地址');
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

  @override
  Widget build(BuildContext context) {
    return OtaCard(
      running: state.otaRunning,
      progress: state.otaProgress,
      status: state.otaStatus,
      logs: state.otaLogs,
      onPickFile: () => _fromFile(context),
      onUrl: (url) => _fromUrl(context, url),
      isDark: isDark,
    );
  }
}

