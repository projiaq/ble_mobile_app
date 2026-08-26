/// OTA 升级服务,移植 `phone_app/utils/ota.js`。
/// 关键语义保留:固件数据块**单次写入,失败禁止重发**(重发会错位损坏固件)。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ble/ble_manager.dart';
import '../../ble/ble_providers.dart';
import '../../ble/scan_filter.dart';
import '../../protocol/constants.dart';

/// 全局 OTA 服务。
final otaServiceProvider =
    Provider<OtaService>((ref) => OtaService(ref.watch(bleManagerProvider)));

class OtaService {
  OtaService(this._ble);

  final BleManager _ble;

  void Function(int? progress, String message)? _onProgress;

  void _log(String message) => _onProgress?.call(null, message);

  /// 读取设备固件版本(Device Information / Firmware Revision)。
  Future<String> readFirmwareVersion(String deviceId) async {
    final value = await _ble.read(
      deviceId,
      deviceInfoServiceUuid,
      firmwareRevisionUuid,
      timeout: const Duration(seconds: 3),
    );
    return utf8.decode(value).replaceAll(RegExp(r'\0+$'), '');
  }

  /// 从本地 .gbl 文件读取固件。
  Future<Uint8List> pickFirmware() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gbl'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      throw BleException('未选择固件文件');
    }
    return bytes;
  }

  /// 从 HTTP URL 下载固件(带进度)。
  Future<Uint8List> downloadFirmware(
    String url, {
    void Function(int percent, String message)? onProgress,
  }) async {
    final response = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes, followRedirects: true),
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(
            (received * 100 / total).floor(),
            '下载中 $received/$total 字节',
          );
        }
      },
    );
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300 ||
        response.data == null) {
      throw BleException('固件下载失败 HTTP ${response.statusCode ?? 0}');
    }
    return Uint8List.fromList(response.data!);
  }

  /// 完整升级流程:进 DFU → 扫 DFU 设备 → 传固件 → 写完成 → 回连校验。
  /// 返回升级后的固件版本(未回连成功时返回 null)。
  Future<String?> upgrade({
    required String deviceId,
    required Uint8List firmware,
    void Function(int? progress, String message)? onProgress,
  }) async {
    _onProgress = onProgress;
    try {
      return await _doUpgrade(deviceId, firmware);
    } finally {
      _onProgress = null;
    }
  }

  Future<String?> _doUpgrade(String deviceId, Uint8List firmware) async {
    // 1. 进入 DFU
    _log('写入 OTA Control=0x00');
    try {
      await _ble.writeRequest(
        deviceId,
        otaServiceUuid,
        otaControlUuid,
        Uint8List.fromList([0]),
      );
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 800));
    await _ble.disconnect(deviceId).catchError((_) {});

    // 2. 扫描 DFU 广告
    _log('扫描 OTA 设备');
    final dfuId = await _ble.scanForDevice(
      (d) => isOtaAdvertisement(d, deviceId),
      timeout: const Duration(seconds: 30),
    );
    if (dfuId == null) throw BleException('未找到进入 DFU 的设备');
    _log('OTA 设备 $dfuId');
    await _ble.connect(dfuId);

    // 3. 校验 OTA 服务存在
    if (!_ble.hasCharacteristic(dfuId, otaServiceUuid, otaControlUuid) ||
        !_ble.hasCharacteristic(dfuId, otaServiceUuid, otaDataUuid)) {
      throw BleException('进入 DFU 后未发现 OTA 服务');
    }

    // 4. 开始固件传输
    _log('写入 OTA Control=0xEE');
    await _ble.writeRequest(
      dfuId,
      otaServiceUuid,
      otaControlUuid,
      Uint8List.fromList([otaBegin]),
    );
    await Future.delayed(const Duration(milliseconds: 200));

    const chunkSize = 20;
    for (var offset = 0; offset < firmware.length; offset += chunkSize) {
      final end = offset + chunkSize < firmware.length
          ? offset + chunkSize
          : firmware.length;
      final chunk = Uint8List.sublistView(firmware, offset, end);
      try {
        await _ble.writeOnce(dfuId, otaServiceUuid, otaDataUuid, chunk);
      } catch (e) {
        throw BleException(
            '固件块写失败(offset=$offset) $e;中止 OTA 防止固件损坏');
      }
      _onProgress?.call(
        5 + (end * 90 / firmware.length).floor(),
        '传输中 $end/${firmware.length} 字节',
      );
    }

    // 5. 完成并等待重启
    _log('写入 OTA Control=0x03');
    try {
      await _ble.writeRequest(
        dfuId,
        otaServiceUuid,
        otaControlUuid,
        Uint8List.fromList([3]),
      );
    } catch (_) {}
    await _ble.disconnect(dfuId).catchError((_) {});
    await Future.delayed(const Duration(seconds: 2));

    // 6. 回连正常模式读取版本校验
    _log('等待设备恢复');
    final normalId = await _ble.scanForDevice(
      (d) => d.id == deviceId && !isOtaAdvertisement(d, deviceId),
      timeout: const Duration(seconds: 30),
    );
    if (normalId == null) return null;
    await _ble.connect(normalId);
    try {
      return await readFirmwareVersion(normalId);
    } finally {
      await _ble.disconnect(normalId).catchError((_) {});
    }
  }
}
