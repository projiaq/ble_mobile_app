import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ble_manager.dart';

/// 全局单例 BLE 管理器。
final bleManagerProvider = Provider<BleManager>((ref) => BleManager());
