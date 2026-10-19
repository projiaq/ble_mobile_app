/// GATT UUID 与协议常量,与 `phone_app/utils/protocol.js` 逐字节对齐。
library;

// ---- 接收器 GATT ----
const String rxServiceUuid = '6F8A0000-7D4B-4A8E-9B21-3C5D7E9F1000';
const String rxCmdUuid = '6F8A0001-7D4B-4A8E-9B21-3C5D7E9F1000';
const String rxRespUuid = '6F8A0002-7D4B-4A8E-9B21-3C5D7E9F1000';
const String rxStreamUuid = '6F8A0003-7D4B-4A8E-9B21-3C5D7E9F1000';
const String rxStatusUuid = '6F8A0004-7D4B-4A8E-9B21-3C5D7E9F1000';

// ---- 传感器 GATT ----
const String snDataSvcUuid = 'C8E21E04-2D3A-4C65-B9D6-8E1A4B0F2C7D';
const String snDataUuid = 'C8E21E05-2D3A-4C65-B9D6-8E1A4B0F2C7D';
const String snCfgSvcUuid = 'D6E1F204-3A1B-4C72-B9A5-5E1F6C308D2A';
const String snOffsetUuid = 'D6E1F205-3A1B-4C72-B9A5-5E1F6C308D2A';
const String snRateUuid = 'D6E1F206-3A1B-4C72-B9A5-5E1F6C308D2A';
const String snMacUuid = 'D6E1F207-3A1B-4C72-B9A5-5E1F6C308D2A';
const String snInfoUuid = 'D6E1F208-3A1B-4C72-B9A5-5E1F6C308D2A';
const String snPowerModeUuid = 'D6E1F209-3A1B-4C72-B9A5-5E1F6C308D2A';

// ---- OTA / 设备信息服务 ----
const String otaServiceUuid = '1D14D6EE-FD63-4FA1-BFA4-8F47B42119F0';
const String otaControlUuid = 'F7BF3564-FB6D-4E53-88A4-5E37E0326063';
const String otaDataUuid = '984227F3-34FC-4045-A5D0-2C581F81A153';
const int otaBegin = 0xEE;
const String deviceInfoServiceUuid = '0000180A-0000-1000-8000-00805F9B34FB';
const String firmwareRevisionUuid = '00002A26-0000-1000-8000-00805F9B34FB';

// ---- 协议 ----
const int protocolVer = 1;
const int slotCount = 8;
const String appVersion = '1.0.3.003';
const int typePressure = 1;
const int typeTilt = 2;

// 接收器命令 opcode
const int opSetId = 1;
const int opSetSlot = 2;
const int opClearSlot = 3;
const int opClearAll = 4;
const int opGetSlot = 5;
const int opSetRate = 6;
const int opGetSensorInfo = 7;

// 传感器帧/状态长度
const int sensorPayloadLen = 17;
const int streamSampleLen = 18; // 1 字节 slot + 17 字节载荷
const int rangeStreamLen = 5; // 1 字节 slot + 距离 mm LE16 + Peak LE16
const int sensorRangeLen = 4; // 距离 mm LE16 + Peak LE16 (传感器直连)
