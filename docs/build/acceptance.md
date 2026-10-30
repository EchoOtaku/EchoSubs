# 首版验收证据边界

自动化场景使用虚构影音月卡、域名年费、永久许可、按量存储与独立临时 SQLite。`test/release/scenario_test.dart` 贯穿实际 AppServices、Repository、同步协调器、LAN 双方确认及固定证书 TLS、受控 HTTPS WebDAV、冲突解决、删除、付款幂等、提醒核对与独立备份恢复。WebDAV 上传后关闭 LAN 监听，再由另一副本下载，验证两通道可独立使用。

缺能力红灯可用：

```powershell
flutter test test/release/scenario_test.dart --dart-define=ECHOSUBS_MISSING_DAV=true
```

它必须在 WebDAV 独立成功断言失败；正常运行不传该选项。此 fixture 不切换或回滚共享工作树。历史依赖、配置隔离与恢复的负面边界仍由已有 `test/backup`、`test/sync` 回归覆盖，不重新制造 genesis 绕过校验。

| 证据类别 | 范围与边界 |
| --- | --- |
| 自动化测试 | 完整单元/widget 回归、analyze、format 为硬门槛；每次最终运行结果与日志记入本机报告 |
| Windows 原生 | offline_flow 原生 Flutter 界面录入/编辑/付款、SQLite 重开及独立恢复；release_smoke 验证唯一测试槽真实 secure storage 与真实 loopback TLS 流程 |
| Android 模拟器原生 | 仅用户指定的 MuMu Android 12/API32 隔离集成包；不把模拟器型号字符串当实际手机，不自动改权限/代理/时钟 |
| Windows 文件对话框 | 真实文件 IO 与 Flutter 流程分别记录；OS 文件选择器自动化未获得可靠 UI 证据，保留人工待验证 |
| Android 真机与重启 | Android 13+ 权限提示、OEM 后台、实际设备重启仍需独立条件与用户许可；flutter test 即使 no-uninstall 也会 force-stop，不能据此证明 BOOT 接收 |
| 厂商 WebDAV | 受控 TLS/条件写入不等于厂商互操作；未提供真实测试端点/凭据时明确未验证 |
| 物理局域网 | loopback/NAT 通道证据不等于物理 mDNS、防火墙、相机扫码兼容性 |

Drift 2.35.3 的 debug 多实例警告按数据库 runtimeType 的实例数量触发，未检测是否实际共享 QueryExecutor。项目 `AppDatabase.open` 每次创建独立 NativeDatabase，副本使用不同文件，并发测试刻意使用同文件的独立连接以验证事务互斥。保留这些检查和日志，不关闭真实并发测试、不全局隐藏其他警告。

本机报告须记录失败与修正、准确命令/PID/期限/退出码、最终产物哈希和未验证项。widget 渲染不是桌面截图。真实 secure-storage 测试仅使用唯一自建测试槽并删除该槽；不访问既有 root、device.id、active.ledger。关闭本次监听、应用和构建进程，保留用户模拟器；ADB 保留时说明原因。不留测试预约或无人监管通知。
