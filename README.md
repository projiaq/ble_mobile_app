# AIOT BLE 工具(Flutter)

井下 BLE 接收器 / 传感器管理端。功能对齐原 uni-app 版 `phone_app/`,用 Flutter 重写,可在 GitHub Actions 纯 CI 构建出可安装的 Android APK。

## 功能(规划)

- **现场总览**:BLE 扫描,按名称前缀 / 服务 UUID 分类(接收器 / 压力 / 倾角 / 其他),RSSI 阈值过滤 + 搜索 + 排序
- **接收器**:8 槽实时数据面板、绑定编辑器(槽位 = 类型 + 点位 + MAC)、清槽/清全部、改 receiver ID、单槽快慢速、每槽 Sensor Info、OTA 升级、数据停滞看门狗
- **传感器**:直连实时数据、读配置(速率/电源/偏移)、写偏移校准、写 MAC、电源模式(普通/休眠/EM4)、OTA
- **客户/维护模式**、井下高对比深色主题

> 协议契约(GATT UUID、命令 opcode、17 字节传感器帧、8 字节状态、Sensor Info)逐字节对齐 `phone_app/utils/protocol.js`,以 `test/protocol/` 单测锁定。
>
> **测距扩展(V1.0.5)**:倾角传感器快速模式下新增 4 字节测距帧(距离 mm LE16 + Peak LE16),与 17 字节帧共用传感器 `sensor_data` 特征;接收器在手机数据流特征上新增 5 字节帧(槽位 + 距离 + Peak),原 18 字节帧不变。字节布局见 `sensor/RANGE_PROTOCOL.md`。

## 本地开发

```bash
cd mobile_app
flutter pub get
flutter run                # 连真机
flutter test               # 单测
flutter build apk --release
```

## 构建产物:GitHub Actions

推送到 GitHub 后,`mobile_app/**` 或 `.github/workflows/build_apk.yml` 变化即触发;也可在 Actions 页手动 `workflow_dispatch`。

产物在 workflow 的 **Upload APK** 步骤 artifact(`aiot-ble-apk`),下载 `app-release.apk` 即可装到 Android 真机。

### 首次使用步骤

1. 把本仓库推送到 GitHub(新建仓库后 `git remote add origin <url> && git push -u origin master`)。
2. Actions → build-apk → Run workflow(或直接 push 触发)。
3. 等待构建绿后,下载 artifact 安装。

### 正式签名(可选,后续再做)

当前 release 构建用 **debug 签名**(可安装,不适合上架/分发)。要正式签名:

1. 本地生成 keystore:
   ```bash
   keytool -genkey -v -keystore aiot-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. 在 GitHub 仓库 Settings → Secrets and variables → Actions 添加:
   - `ANDROID_KEYSTORE_B64`:keystore 文件的 base64(`base64 -w0 aiot-upload.jks`)
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS`
   - `ANDROID_KEY_PASSWORD`
3. 在 `.github/workflows/build_apk.yml` 的 Build 步骤前增加"解码 keystore + 写 `android/key.properties` + 切换 `android/app/build.gradle` 的 release signingConfig",并去掉 `signingConfig = signingConfigs.debug`。

## 目录

```
lib/
  core/        主题/路由/通用组件/存储
  ble/         BLE 封装 + 扫描分类 + DFU 广告识别
  protocol/    接收器/传感器协议 + 数据模型
  site/        客户/维护模式 + 最近设备
  features/    scan / receiver / sensor / ota 各功能模块
test/          协议/分类/页面 widget 测试
```

## 里程碑

- [x] M1 脚手架 + CI 绿灯(本目录 + `.github/workflows/build_apk.yml`)
- [x] M2 协议层 + BLE 层 + 单测
- [x] M3 扫描页(扫描/分类/RSSI 过滤/维护模式/井下深色主题)
- [x] M4 传感器页(直连/实时数据/配置/校准/写MAC/休眠/OTA/数据停滞看门狗)
- [x] M5 接收器页(8槽实时面板/绑定编辑器/速率/清槽清全部/改ID/Sensor Info/OTA/看门狗)
- [x] M6 收尾(空态/错误态、README、真机冒烟清单)

## 真机冒烟清单(Android)

> 与现有 uni-app 在同一批真机上同场景对照;数据一致性以 `test/protocol/` 单测为准。

1. **首次启动**:点击"扫描"→ 授权 BLE + 定位权限 → 出现接收器/传感器列表,信号格与 RSSI 随靠近变化。
2. **扫描设置**:RSSI 阈值滑杆过滤生效;井下高对比模式切换深色主题;进入维护模式(密码)后出现维护操作。
3. **传感器直连**:进入压力/倾角传感器 → 实时读数刷新(压力 bar / 倾角 X/Y 角)、电压/序号/工作时长正确;切换快/慢速;倾角当前位置标零后 X/Y 接近 0，重连后仍生效，清除标零后恢复原始角度;压力偏移写入后读回一致。
4. **传感器维护**:写 MAC → 设备复位断链(不误触发自动重连);进入 EM4 休眠后无数据。
5. **接收器 8 槽**:连接后在线槽位实时刷新;绑定编辑器(类型+点位+MAC)保存后立即生效;清槽/清全部/改 ID 生效;每槽 Sensor Info 弹窗正确。
6. **数据停滞看门狗**:拔掉某传感器电源或遮挡,对应槽/页面在阈值内显示"数据超时"并自动重连。
7. **OTA**:文件 + URL 两种源各一次;传输进度推进;完成后版本号变化;升级期间不断链误重连。
8. **稳定性**:连续运行 30 分钟,8 槽 + 手机并发不卡死、事件不丢。
