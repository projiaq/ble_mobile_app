import 'package:go_router/go_router.dart';

import '../../features/receiver/presentation/binding_page.dart';
import '../../features/receiver/presentation/receiver_page.dart';
import '../../features/scan/presentation/scan_page.dart';
import '../../features/sensor/presentation/sensor_page.dart';
import '../../protocol/constants.dart';

/// 应用路由表。
abstract final class AppRouter {
  static GoRouter config() {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          name: 'scan',
          builder: (context, state) => const ScanPage(),
        ),
        GoRoute(
          path: '/receiver/:id',
          name: 'receiver',
          builder: (context, state) => ReceiverPage(
            deviceId: state.pathParameters['id'] ?? '',
            name: state.uri.queryParameters['name'] ?? 'AIOT-',
          ),
        ),
        GoRoute(
          path: '/receiver/:id/bindings',
          name: 'bindings',
          builder: (context, state) => BindingPage(
            deviceId: state.pathParameters['id'] ?? '',
            name: state.uri.queryParameters['name'] ?? 'AIOT-',
          ),
        ),
        GoRoute(
          path: '/sensor/:id',
          name: 'sensor',
          builder: (context, state) => SensorPage(
            deviceId: state.pathParameters['id'] ?? '',
            name: state.uri.queryParameters['name'] ?? 'SensorNode',
            type: int.tryParse(state.uri.queryParameters['type'] ?? '') ??
                typePressure,
          ),
        ),
      ],
    );
  }
}
