import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'site/site_controller.dart';

class AiotApp extends ConsumerWidget {
  const AiotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mineMode = ref.watch(siteControllerProvider).mineMode;
    return MaterialApp.router(
      title: 'AIOT BLE 工具',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mineMode ? ThemeMode.dark : ThemeMode.light,
      routerConfig: AppRouter.config(),
    );
  }
}
