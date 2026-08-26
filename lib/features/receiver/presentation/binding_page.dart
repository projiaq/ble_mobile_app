import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../ble/scan_device.dart';
import '../../../ble/scan_filter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/qr_scanner.dart';
import '../../../protocol/constants.dart';
import '../../../protocol/sensor_protocol.dart';
import '../application/receiver_controller.dart';
import 'nearby_sensor_picker.dart';

/// 维护模式绑定管理,对齐 phone_app 接收器页的八槽常驻编辑布局。
class BindingPage extends ConsumerStatefulWidget {
  final String deviceId;
  final String name;
  final bool embedded;
  const BindingPage({super.key, required this.deviceId, this.name = 'AIOT-', this.embedded = false});

  @override
  ConsumerState<BindingPage> createState() => _BindingPageState();
}

class _BindingDraft {
  int type = 0;
  int sid = 0;
  final TextEditingController mac;
  _BindingDraft({String mac = ''})
      : mac = TextEditingController(text: mac);

  void dispose() => mac.dispose();
}

class _BindingPageState extends ConsumerState<BindingPage> {
  late final List<_BindingDraft> _drafts;
  bool _loaded = false;
  bool _saving = false;

  static const double _slotColWidth = 26;
  static const double _positionColWidth = 82;
  static const double _scanColWidth = 64;
  static const double _rowGap = 5;
  static const double _rowHeight = 40;

  @override
  void initState() {
    super.initState();
    _drafts = List.generate(slotCount, (_) => _BindingDraft());
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _loadFromState(ReceiverState state) {
    for (var i = 0; i < slotCount; i++) {
      final slot = state.slotList[i];
      _drafts[i].type = slot.bound ? slot.sensorType : 0;
      _drafts[i].sid = slot.bound ? slot.sensorId : 0;
      _drafts[i].mac.text = slot.bound ? slot.mac : '';
    }
    _loaded = true;
  }

  Future<void> _readConfig(ReceiverController controller) async {
    await controller.refreshBindings();
    if (!mounted) return;
    _loadFromState(ref.read(receiverControllerProvider(widget.deviceId)));
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已读取配置')));
  }

  Future<void> _scanSlot(int slot) async {
    final text = await scanQrCode(context);
    if (!mounted || text == null || text.isEmpty) return;
    _drafts[slot].mac.text = normalizeQrText(text);
    setState(() {});
  }

  Future<void> _selectNearbySensor(int slot) async {
    final ScanDevice? device = await showNearbySensorPicker(context);
    if (!mounted || device == null) return;

    final draft = _drafts[slot];
    final inferredType = sensorTypeOf(classifyDevice(device));
    draft.mac.text = normalizeQrText(device.id);
    if (inferredType != null) {
      draft.type = inferredType;
      final validPositions = sensorPositionOptions()
          .where((option) => option.type == inferredType)
          .toList();
      if (!validPositions.any((option) => option.sid == draft.sid) &&
          validPositions.isNotEmpty) {
        draft.sid = validPositions.first.sid;
      }
    }
    setState(() {});
  }

  Future<void> _scanNextSlot() async {
    final slot = _drafts.indexWhere((draft) => draft.mac.text.trim().isEmpty);
    await _scanSlot(slot < 0 ? 0 : slot);
  }

  Future<void> _editReceiverId(ReceiverController controller) async {
    final textController = TextEditingController(
      text: '${controller.currentRid ?? 0}',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改接收器 ID'),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'ID (0~255)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, textController.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    textController.dispose();
    final rid = int.tryParse(value ?? '');
    if (rid == null || rid < 0 || rid > 255) return;
    final ok = await controller.setReceiverId(rid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '接收器 ID 已更新' : '接收器 ID 修改失败')),
    );
  }

  Future<void> _submit(ReceiverController controller) async {
    if (_saving) return;
    final positions = <String, int>{};
    final macs = <String, int>{};
    for (var i = 0; i < slotCount; i++) {
      final draft = _drafts[i];
      final mac = draft.mac.text.trim();
      if (mac.isEmpty) continue;
      if (draft.type == 0 || draft.sid == 0 || macToBytes(mac) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('槽位 ${i + 1} 类型、点位或 MAC 格式错误')),
        );
        return;
      }
      final positionKey = '${draft.type}|${draft.sid}';
      final normalizedMac = normalizeQrText(mac);
      if (positions.containsKey(positionKey)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('槽位 ${i + 1} 与槽位 ${positions[positionKey]! + 1} 点位重复')),
        );
        return;
      }
      if (macs.containsKey(normalizedMac)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('槽位 ${i + 1} 与槽位 ${macs[normalizedMac]! + 1} MAC 重复')),
        );
        return;
      }
      positions[positionKey] = i;
      macs[normalizedMac] = i;
    }

    setState(() => _saving = true);
    var success = true;
    try {
      for (var i = 0; i < slotCount; i++) {
        final draft = _drafts[i];
        final mac = draft.mac.text.trim();
        final current = ref.read(receiverControllerProvider(widget.deviceId)).slotList[i];
        final ok = mac.isEmpty
            ? (!current.bound || await controller.clearSlot(i))
            : await controller.setSlotBinding(i, draft.type, draft.sid, mac);
        success = success && ok;
      }
      await controller.refreshBindings();
      if (mounted) {
        _loadFromState(ref.read(receiverControllerProvider(widget.deviceId)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '绑定下发成功' : '部分槽位下发失败')),
        );
      }
    }
  }

  Future<void> _clearAll(ReceiverController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清除全部绑定'),
        content: const Text('所有槽位将清空并断开传感器,确定?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (await controller.clearAll() && mounted) {
      _loadFromState(ref.read(receiverControllerProvider(widget.deviceId)));
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiverControllerProvider(widget.deviceId));
    final controller = ref.read(receiverControllerProvider(widget.deviceId).notifier);
    if (!_loaded && state.status != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loaded) {
          _loadFromState(state);
          setState(() {});
        }
      });
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.mineMuted : AppColors.textMuted;
    final options = sensorPositionOptions();

    final appBar = AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/receiver/${widget.deviceId}?name=${Uri.encodeComponent(widget.name)}');
            }
          },
        ),
        title: const Text('绑定管理'),
      );
    final body = ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
        padding: widget.embedded
            ? EdgeInsets.zero
            : const EdgeInsets.fromLTRB(8, 12, 8, 12),
        children: [
          if (!widget.embedded) ...[
            Text('接收器 ${widget.name}', style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 12),
          ],
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('绑定管理', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _readConfig(controller),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('读取配置'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _scanNextSlot,
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: const Text('扫码下一槽'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _editReceiverId(controller),
                        icon: const Icon(Icons.tag, size: 18),
                        label: const Text('修改 ID'),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : () => _submit(controller),
                        icon: const Icon(Icons.publish, size: 18),
                        label: Text(_saving ? '下发中' : '下发'),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  _draftHeader(muted),
                  const SizedBox(height: 4),
                  for (var i = 0; i < slotCount; i++)
                    _draftRow(i, options, isDark ? AppColors.mineText : AppColors.text),
                  const SizedBox(height: 8),
                  Text('每行对应固定槽位,空行表示清除该槽位。', style: TextStyle(color: muted, fontSize: 12)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: _saving ? null : () => _clearAll(controller),
                      child: const Text('清除全部绑定', style: TextStyle(color: AppColors.danger)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    if (widget.embedded) return body;
    return Scaffold(appBar: appBar, body: body);
  }

  Widget _draftHeader(Color muted) {
    return Row(
      children: [
        SizedBox(
          width: _slotColWidth,
          child: Text(
            '槽',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ),
        const SizedBox(width: _rowGap),
        SizedBox(
          width: _positionColWidth,
          child: Text(
            '传感器位置',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ),
        const SizedBox(width: _rowGap),
        Expanded(child: Text('MAC 地址', style: TextStyle(fontSize: 11, color: muted))),
        const SizedBox(width: _rowGap),
        SizedBox(
          width: _scanColWidth,
          child: Text(
            '操作',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ),
      ],
    );
  }

  Widget _draftRow(
    int slot,
    List<({int type, int sid, String label})> options,
    Color textColor,
  ) {
    final draft = _drafts[slot];
    final selected =
        options.indexWhere((o) => o.type == draft.type && o.sid == draft.sid);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDark ? AppColors.mineCard : const Color(0xFFF8FAFC);
    final borderColor = isDark ? AppColors.mineBorder : const Color(0xFFE5E7EB);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: borderColor),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: _rowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _slotColWidth,
              child: Text(
                '${slot + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: textColor),
              ),
            ),
            const SizedBox(width: _rowGap),
            SizedBox(
              width: _positionColWidth,
              height: _rowHeight,
              child: Container(
                padding: const EdgeInsets.only(left: 8, right: 2),
                decoration: BoxDecoration(
                  color: fillColor,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: selected >= 0 ? selected : 0,
                    isExpanded: true,
                    isDense: true,
                    iconSize: 16,
                    style: TextStyle(fontSize: 13, color: textColor),
                    selectedItemBuilder: (context) => [
                      for (final option in options)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              option.label.isEmpty ? '选择' : option.label,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(fontSize: 13, color: textColor),
                            ),
                          ),
                        ),
                    ],
                    items: [
                      for (var i = 0; i < options.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            options[i].label.isEmpty ? '选择' : options[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: textColor),
                          ),
                        ),
                    ],
                    onChanged: (index) {
                      if (index == null) return;
                      setState(() {
                        draft.type = options[index].type;
                        draft.sid = options[index].sid;
                      });
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: _rowGap),
            Expanded(
              child: SizedBox(
                height: _rowHeight,
                child: TextField(
                  controller: draft.mac,
                  maxLines: 1,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'AA:BB:CC:DD:EE:FF',
                    isDense: true,
                    filled: true,
                    fillColor: fillColor,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
                    border: border,
                    enabledBorder: border,
                    focusedBorder: border.copyWith(
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: _rowGap),
            SizedBox(
              width: _scanColWidth,
              height: _rowHeight,
              child: Row(
                children: [
                  IconButton(
                    tooltip: '扫描二维码',
                    constraints: const BoxConstraints.tightFor(
                      width: _scanColWidth / 2,
                      height: _rowHeight,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                    onPressed: _saving ? null : () => _scanSlot(slot),
                  ),
                  IconButton(
                    tooltip: '选择附近传感器',
                    constraints: const BoxConstraints.tightFor(
                      width: _scanColWidth / 2,
                      height: _rowHeight,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.cell_tower, size: 20),
                    onPressed:
                        _saving ? null : () => _selectNearbySensor(slot),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
