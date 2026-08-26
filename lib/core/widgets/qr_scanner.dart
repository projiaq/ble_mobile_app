import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 打开全屏二维码扫描,返回扫描到的文本;取消/未授权返回 null。
/// 相机权限由 mobile_scanner 自行申请,无需手动 request。
Future<String?> scanQrCode(BuildContext context) async {
  return Navigator.push<String>(
    context,
    MaterialPageRoute(builder: (_) => const _QrScannerDialog()),
  );
}

/// 把扫描文本规范化为可搜索形式:12 位十六进制无分隔 → `AA:BB:CC:DD:EE:FF`;否则原样返回。
String normalizeQrText(String text) {
  final trimmed = text.trim().toUpperCase();
  final hexOnly = trimmed.replaceAll(RegExp(r'[^0-9A-F]'), '');
  if (hexOnly.length == 12) {
    return List.generate(6, (i) => hexOnly.substring(i * 2, i * 2 + 2)).join(':');
  }
  return trimmed;
}

class _QrScannerDialog extends StatefulWidget {
  const _QrScannerDialog();
  @override
  State<_QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<_QrScannerDialog> {
  late final MobileScannerController _controller;
  bool _done = false;
  bool _torchOn = false;
  double _zoom = 0.0;

  @override
  void initState() {
    super.initState();
    // 使用高分辨率全画面扫描,小二维码不受中央窗口限制。
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      torchEnabled: false,
      cameraResolution: const Size(1920, 1080),
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 100,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final value =
        capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null || value.isEmpty) return;
    _done = true;
    Navigator.pop(context, value);
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  void _setZoom(double value) {
    setState(() => _zoom = value);
    try {
      _controller.setZoomScale(value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描二维码'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            tooltip: '手电筒',
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error, child) => Center(
                    child: Text(
                      '相机启动失败:$error',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.82,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white70, width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.zoom_in, color: Colors.white54),
                    Expanded(
                      child: Slider(
                        value: _zoom,
                        min: 0.0,
                        max: 1.0,
                        divisions: 10,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                        onChanged: _setZoom,
                      ),
                    ),
                  ],
                ),
                const Text(
                  '将二维码对准扫描框,可拉近识别小二维码',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
