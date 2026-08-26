import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 通用 OTA 升级卡:URL 输入 + 文件选择 + 进度/日志。持有自己的输入框 controller。
class OtaCard extends StatefulWidget {
  final bool running;
  final int progress;
  final String status;
  final List<String> logs;
  final Future<void> Function() onPickFile;
  final Future<void> Function(String url) onUrl;
  final bool isDark;

  const OtaCard({
    super.key,
    required this.running,
    required this.progress,
    required this.status,
    required this.logs,
    required this.onPickFile,
    required this.onUrl,
    required this.isDark,
  });

  @override
  State<OtaCard> createState() => _OtaCardState();
}

class _OtaCardState extends State<OtaCard> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.running;
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
          if (running || widget.progress > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: widget.progress / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 6),
            Text(widget.status, style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 6),
            for (final line in widget.logs.length > 12
                ? widget.logs.sublist(widget.logs.length - 12)
                : widget.logs)
              Text(line, style: TextStyle(fontSize: 11, color: muted)),
          ],
        ],
      ),
    );
  }
}
