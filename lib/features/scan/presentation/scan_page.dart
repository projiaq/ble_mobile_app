import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../ble/scan_device.dart';
import '../../../ble/scan_filter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/qr_scanner.dart';
import '../../../core/widgets/rssi_bars.dart';
import '../../../protocol/constants.dart';
import '../../../site/site_controller.dart';
import '../../../site/site_mode.dart';
import '../application/scan_controller.dart';

/// 现场总览:扫描、分类、RSSI 过滤、设置、维护模式、井下高对比。
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  static const _rssiKey = 'scan.rssi';
  final _searchController = TextEditingController();
  (String, String, int?)? _lastReceiver;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPersisted());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final threshold = prefs.getInt(_rssiKey) ?? -100;
    ref.read(scanControllerProvider.notifier).setRssiThreshold(threshold);
    final last = await SiteMode.getLastDevice(SiteMode.lastRxKey);
    if (mounted) setState(() => _lastReceiver = last);
    // 打开软件自动扫描
    ref.read(scanControllerProvider.notifier).start();
  }

  Future<void> _scanQrSearch() async {
    final text = await scanQrCode(context);
    if (text == null || text.isEmpty) return;
    final normalized = normalizeQrText(text);
    _searchController.text = normalized;
    ref.read(scanControllerProvider.notifier).setQuery(normalized);
  }

  void _go(String path) {
    final router = GoRouter.of(context);
    router.push(path);
    unawaited(ref.read(scanControllerProvider.notifier).stop());
  }

  Future<void> _toggleMode() async {
    final site = ref.read(siteControllerProvider);
    final controller = ref.read(siteControllerProvider.notifier);
    if (site.isMaintainer) {
      await controller.setMode(SiteMode.modeCustomer);
      _toast('已切客户模式');
      return;
    }
    final password = await _promptPassword();
    if (password == null) return;
    if (!SiteMode.verifyPassword(password)) {
      _toast('维护密码错误');
      return;
    }
    await controller.setMode(SiteMode.modeMaintainer);
    _toast('已进入维护模式');
  }

  Future<String?> _promptPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('进入维护模式'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: '维护密码'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('进入'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }

  Future<void> _openSettings() async {
    final scan = ref.read(scanControllerProvider);
    final controller = ref.read(scanControllerProvider.notifier);
    final site = ref.read(siteControllerProvider);
    final siteController = ref.read(siteControllerProvider.notifier);
    final sliderController = ValueNotifier<double>(scan.rssiThreshold.toDouble());

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('扫描设置', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            ValueListenableBuilder<double>(
              valueListenable: sliderController,
              builder: (context, value, _) {
                final rssi = value.round();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('信号强度 ≥ $rssi dBm${rssi <= -100 ? ' (全部)' : ''}'),
                    Slider(
                      min: -100,
                      max: -40,
                      divisions: 12,
                      value: value.clamp(-100.0, -40.0).toDouble(),
                      onChanged: (v) => sliderController.value = v,
                    ),
                  ],
                );
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('井下高对比模式'),
              value: site.mineMode,
              onChanged: (v) => siteController.setMineMode(v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final rssi = sliderController.value.round();
                  controller.setRssiThreshold(rssi);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt(_rssiKey, rssi);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('完 成'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(scanControllerProvider);
    final site = ref.watch(siteControllerProvider);
    final controller = ref.read(scanControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final receivers = controller.shownReceivers;
    final pressure = controller.shownPressure;
    final tilt = controller.shownTilt;
    final other = controller.shownOther;
    final hasDevices = receivers.isNotEmpty ||
        pressure.isNotEmpty ||
        tilt.isNotEmpty ||
        other.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('现场总览'),
            Text('v$appVersion', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _headerCard(scan, site, controller),
          const SizedBox(height: 12),
          _summaryGrid(controller, isDark),
          if (_lastReceiver != null) ...[
            const SizedBox(height: 12),
            _lastReceiverCard(),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: controller.setQuery,
            decoration: InputDecoration(
              hintText: '搜索名称或 MAC',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: '扫描二维码',
                onPressed: _scanQrSearch,
              ),
              filled: true,
              fillColor: isDark ? AppColors.mineCard : AppColors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (receivers.isNotEmpty) _section('接收器', receivers, isDark, isReceiver: true),
          if (pressure.isNotEmpty) _section('压力传感器', pressure, isDark),
          if (tilt.isNotEmpty) _section('倾角传感器', tilt, isDark),
          if (other.isNotEmpty) _section('其他传感器', other, isDark),
          if (!hasDevices) _emptyState(scan, isDark),
        ],
      ),
    );
  }

  Widget _headerCard(ScanState scan, SiteSnapshot site, ScanController controller) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _modePill(site),
              const Spacer(),
              IconButton(
                tooltip: scan.sortDescending ? '信号由强到弱' : '信号由弱到强',
                icon: const Icon(Icons.signal_cellular_alt),
                onPressed: controller.toggleSort,
              ),
              FilledButton.tonal(
                onPressed: controller.toggle,
                child: Text(scan.scanning ? '停止' : '扫描'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${scan.scanning ? '正在靠近识别…' : '扫描已停止'} · '
            '接收器 ${scan.receivers.length} · 传感器 ${scan.sensors.length}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.mineMuted
                  : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modePill(SiteSnapshot site) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = site.isMaintainer
        ? AppColors.warningBg
        : (isDark ? AppColors.mineCard : const Color(0xFFF3F4F6));
    final foreground = site.isMaintainer
        ? AppColors.warning
        : (isDark ? AppColors.mineText : const Color(0xFF374151));
    return InkWell(
      onTap: _toggleMode,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          site.isMaintainer ? '维护模式' : '客户模式',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground),
        ),
      ),
    );
  }

  Widget _summaryGrid(ScanController controller, bool isDark) {
    final cellBg = isDark ? AppColors.mineCard : const Color(0xFFF8FAFC);
    final cellBorder = isDark ? AppColors.mineBorder : const Color(0xFFE5E7EB);
    Widget cell(String value, String label) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: cellBg,
            border: Border.all(color: cellBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.mineMuted : AppColors.textMuted)),
            ],
          ),
        );
    return Row(
      children: [
        Expanded(
            child: cell('${controller.shownReceivers.length}', '接收器')),
        const SizedBox(width: 8),
        Expanded(child: cell('${controller.shownPressure.length}', '压力')),
        const SizedBox(width: 8),
        Expanded(child: cell('${controller.shownTilt.length}', '倾角')),
        const SizedBox(width: 8),
        Expanded(
            child: cell(
                controller.strongestRssi > -200
                    ? '${controller.strongestRssi}'
                    : '--',
                '最强dBm')),
      ],
    );
  }

  Widget _lastReceiverCard() {
    final last = _lastReceiver!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () => _go('/receiver/${last.$1}?name=${Uri.encodeComponent(last.$2.isEmpty ? 'AIOT-' : last.$2)}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.mineCard : const Color(0xFFF8FAFC),
          border: Border.all(color: isDark ? AppColors.mineBorder : const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('最近接收器',
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.mineMuted : AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(last.$2.isEmpty ? 'AIOT-' : last.$2,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(last.$1,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.mineMuted : AppColors.textMuted)),
                ],
              ),
            ),
            FilledButton.tonal(onPressed: () => _go('/receiver/${last.$1}'), child: const Text('进入')),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<ScanDevice> devices, bool isDark,
      {bool isReceiver = false}) {
    final iconColor = isReceiver ? AppColors.primary : AppColors.teal;
    final iconText = isReceiver ? '收' : (title.startsWith('压力') ? '压' : (title.startsWith('倾角') ? '倾' : '感'));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 2),
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.mineMuted : AppColors.textMuted)),
          ),
          Container(
            decoration: _cardDecoration(),
            child: Column(
              children: [
                for (var i = 0; i < devices.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: isDark ? AppColors.mineBorder : AppColors.divider),
                  _deviceRow(devices[i], iconColor, iconText, isReceiver),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceRow(ScanDevice device, Color iconColor, String iconText,
      bool isReceiver) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = device.name.isEmpty
        ? (isReceiver ? 'AIOT-' : _defaultSnName(device))
        : device.name;
    final info = parseAdvInfo(device);
    final version = info == null
        ? ''
        : '${formatVersion(info.hwVer)}/${formatVersion(info.swVer)}';
    final subtitle = [
      if (version.isNotEmpty) version,
      device.id,
      if (isReceiver) '靠近优先' else '靠近后点入读取',
    ].join(' · ');
    return InkWell(
      onTap: () => _go(
        isReceiver
            ? '/receiver/${device.id}?name=${Uri.encodeComponent(device.name.isEmpty ? 'AIOT-' : device.name)}'
            : '/sensor/${device.id}?name=${Uri.encodeComponent(name)}&type=${sensorTypeOf(classifyDevice(device)) ?? typePressure}',
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(iconText,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.mineMuted : AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            RssiBars(rssi: device.rssi),
          ],
        ),
      ),
    );
  }

  String _defaultSnName(ScanDevice device) {
    final type = sensorTypeOf(classifyDevice(device));
    if (type == typeTilt) return 'TILT-SN';
    if (type == typePressure) return 'PRES-SN';
    return 'SensorNode';
  }

  Widget _emptyState(ScanState scan, bool isDark) {
    String text;
    if (scan.scanning) {
      text = '正在搜索…';
    } else if (scan.error != null) {
      text = '${scan.error}';
    } else if (scan.receivers.isNotEmpty || scan.sensors.isNotEmpty) {
      text = '全部被筛选隐藏,放宽条件';
    } else {
      text = '点击扫描搜索设备';
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Text(text,
          style: TextStyle(
              color: isDark ? AppColors.mineMuted : AppColors.textMuted)),
    );
  }

  BoxDecoration _cardDecoration() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? AppColors.mineCard : AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: isDark ? Border.all(color: AppColors.mineBorder) : null,
    );
  }
}
