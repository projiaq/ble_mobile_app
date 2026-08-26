// 站点模式与最近设备单测。
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/site/site_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认客户模式,setMode 切换', () async {
    expect(await SiteMode.getMode(), SiteMode.modeCustomer);
    final next = await SiteMode.setMode(SiteMode.modeMaintainer);
    expect(next, SiteMode.modeMaintainer);
    expect(await SiteMode.getMode(), SiteMode.modeMaintainer);
    expect(SiteMode.isMaintainer(await SiteMode.getMode()), isTrue);
  });

  test('非法模式回退客户模式', () async {
    await SiteMode.setMode('bogus');
    expect(await SiteMode.getMode(), SiteMode.modeCustomer);
  });

  test('维护密码', () {
    expect(SiteMode.verifyPassword(SiteMode.maintainerPassword), isTrue);
    expect(SiteMode.verifyPassword('  ${SiteMode.maintainerPassword}  '), isTrue);
    expect(SiteMode.verifyPassword('wrong'), isFalse);
  });

  test('井下高对比模式', () async {
    expect(await SiteMode.getMineMode(), isFalse);
    await SiteMode.setMineMode(true);
    expect(await SiteMode.getMineMode(), isTrue);
  });

  test('最近设备存取', () async {
    await SiteMode.saveLastDevice(SiteMode.lastRxKey, id: 'MAC-1', name: 'AIOT-1', rssi: -60);
    final last = await SiteMode.getLastDevice(SiteMode.lastRxKey);
    expect(last, isNotNull);
    expect(last!.$1, 'MAC-1');
    expect(last.$2, 'AIOT-1');
    expect(last.$3, -60);
  });

  test('无最近设备返回 null', () async {
    expect(await SiteMode.getLastDevice(SiteMode.lastSensorKey), isNull);
  });
}
