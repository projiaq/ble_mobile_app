import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'site_mode.dart';

class SiteSnapshot {
  final String mode;
  final bool mineMode;

  const SiteSnapshot({
    this.mode = SiteMode.modeCustomer,
    this.mineMode = false,
  });

  bool get isMaintainer => SiteMode.isMaintainer(mode);

  SiteSnapshot copyWith({String? mode, bool? mineMode}) => SiteSnapshot(
        mode: mode ?? this.mode,
        mineMode: mineMode ?? this.mineMode,
      );
}

/// 站点模式(客户/维护)与井下高对比模式的全局状态。
class SiteController extends StateNotifier<SiteSnapshot> {
  SiteController() : super(const SiteSnapshot()) {
    _load();
  }

  Future<void> _load() async {
    final mode = await SiteMode.getMode();
    final mineMode = await SiteMode.getMineMode();
    state = SiteSnapshot(mode: mode, mineMode: mineMode);
  }

  Future<void> setMode(String mode) async {
    final next = await SiteMode.setMode(mode);
    state = state.copyWith(mode: next);
  }

  Future<void> setMineMode(bool enabled) async {
    final mineMode = await SiteMode.setMineMode(enabled);
    state = state.copyWith(mineMode: mineMode);
  }
}

final siteControllerProvider =
    StateNotifierProvider<SiteController, SiteSnapshot>(
  (ref) => SiteController(),
);
