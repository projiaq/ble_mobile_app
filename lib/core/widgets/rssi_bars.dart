import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// RSSI 信号格(4 格)。
class RssiBars extends StatelessWidget {
  final int? rssi;
  const RssiBars({super.key, this.rssi});

  int _level() {
    final value = rssi;
    if (value == null) return 1;
    if (value >= -55) return 4;
    if (value >= -67) return 3;
    if (value >= -80) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final level = _level();
    final barColor = Theme.of(context).brightness == Brightness.dark
        ? AppColors.mineAccent
        : AppColors.success;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (i) {
            final on = i < level;
            return Container(
              width: 6,
              height: (i + 1) * 7.0,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                color: on ? barColor : AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Text(
          rssi == null ? '--' : '$rssi dBm',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.mineMuted
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
