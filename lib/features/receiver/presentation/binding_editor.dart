import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/qr_scanner.dart';
import '../../../protocol/constants.dart';
import '../../../protocol/sensor_protocol.dart';
import '../application/receiver_controller.dart';

/// 槽位绑定编辑器(类型 + 点位 + MAC,支持手动输入与二维码扫描)。
class BindingEditor extends StatefulWidget {
  final int slot;
  final SlotState current;
  final Future<bool> Function(int type, int sid, String mac) onSave;
  final Future<bool> Function() onClear;
  final bool isDark;
  const BindingEditor({
    super.key,
    required this.slot,
    required this.current,
    required this.onSave,
    required this.onClear,
    required this.isDark,
  });

  @override
  State<BindingEditor> createState() => _BindingEditorState();
}

class _BindingEditorState extends State<BindingEditor> {
  late int _type;
  late int _sid;
  late final TextEditingController _macController;

  List<({int type, int sid, String label})> get _options =>
      sensorPositionOptions().where((o) => o.type == _type).toList();

  int _defaultSid(int type) {
    final options = sensorPositionOptions().where((o) => o.type == type).toList();
    return options.isEmpty ? 1 : options.first.sid;
  }

  Future<void> _scanMac() async {
    final text = await scanQrCode(context);
    if (text == null || text.isEmpty) return;
    _macController.text = normalizeQrText(text);
  }

  @override
  void initState() {
    super.initState();
    _type = widget.current.sensorType == typeTilt ? typeTilt : typePressure;
    _sid = widget.current.sensorId != 0
        ? widget.current.sensorId
        : _defaultSid(_type);
    _macController = TextEditingController(text: widget.current.mac);
  }

  @override
  void dispose() {
    _macController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = widget.isDark ? AppColors.mineMuted : AppColors.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('槽位 ${widget.slot + 1} 绑定',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: typePressure, label: Text('压力')),
            ButtonSegment(value: typeTilt, label: Text('倾角')),
          ],
          selected: {_type},
          onSelectionChanged: (s) {
            setState(() {
              _type = s.first;
              _sid = _defaultSid(_type);
            });
          },
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(labelText: '点位', isDense: true),
          child: DropdownButton<int>(
            value: _sid,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: _options
                .map((o) => DropdownMenuItem(value: o.sid, child: Text(o.label)))
                .toList(),
            onChanged: (v) => setState(() => _sid = v ?? _sid),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _macController,
          decoration: InputDecoration(
            labelText: 'MAC',
            hintText: 'AA:BB:CC:DD:EE:FF',
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: '扫描二维码',
              onPressed: _scanMac,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  if (await widget.onClear()) {
                    navigator.pop();
                  }
                },
                child: Text('清空', style: TextStyle(color: muted)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final mac = _macController.text.trim();
                  if (mac.isEmpty) {
                    messenger.showSnackBar(
                        const SnackBar(content: Text('请输入 MAC')));
                    return;
                  }
                  final ok = await widget.onSave(_type, _sid, mac);
                  if (context.mounted) navigator.pop();
                  messenger.showSnackBar(SnackBar(
                      content: Text(ok ? '绑定成功' : '绑定失败,检查 MAC 或重试')));
                },
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
