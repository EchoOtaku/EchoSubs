# 验收证据与边界

## 2026-11-02 自定义界面验收

应用源码提交 `b350468e6d6a691fb122c5221f535ffb9373e7cc`，版本 `1.0.0+2`。本轮覆盖自定义视觉、桌面与手机布局、列表/日历交互、表单、提示、图标及可访问性，不改变存储、同步协议、加密或权限。

- 最终完整自动测试 363 项通过；最终 analyze 无问题；格式检查 110 文件、0 变化，diff 检查通过。新增 7 项测试覆盖浅深色对比度、跨导航搜索/月份保留、320px 窄屏、大字、横屏、日历最小触达区域及减少动画。原有界面回归保留，对详情分栏显示的标签与日期分别断言。
- Windows 原生 offline_flow 4 项通过；MuMu Android 12/API32 隔离包同一流程 4 项通过，包含实际界面录入、归档、删除确认、编辑、付款、赠送权益、SQLite 重开与独立恢复。Android 经实际 AAPT 包名核验且始终使用 --no-uninstall，测试后再次核验隔离身份并停止该包。
- 双端正常 release 重建成功。Windows 完整 19 文件、ZIP 每项哈希，APK 主包 ID/版本/签名及复制一致性均已核对；产物与 SHA256 见 release.md。既有主包同签名更新成功，安装身份保持，正常启动且进程存活。
- 预览由当前源码、系统字体和虚构临时账本经 Flutter 渲染生成，分别人工检查了浅色桌面、深色桌面、手机总览、列表与设置。它们是 widget 渲染，不能当成原生桌面截图；没有使用真实业务数据。
- 首次大字回归暴露日历高度不足，已按字号和宽度调整单元格；极窄手机标题溢出已修正。预览发现按钮中文字体回退缺失，已统一主题字体回退。上述修正均包含在最终完整测试与固定源码的双端原生验收内。
- 首次 Android release 使用 --no-pub 导致测试插件注册残留而编译失败；已依据本机 Flutter 官方生成流程诊断并使用正常 release 命令重建。跟踪源码与依赖版本保持，失败日志仍保留。

本次测试创建的单条 ADB 调试转发已移除，两个构建守护进程按 PID 和创建时间确认归属后停止；用户 MuMu、必要 ADB 和新版主程序保留。没有新增重启、预约或后台服务。底层 native Vault/双通道 smoke 未在纯界面改造中重复运行，完整自动回归仍覆盖相应业务。Android 13+/OEM 真机、实际通知送达、物理 LAN/相机、厂商 WebDAV、Windows OS 文件选择器和生产签名仍沿用下方明确的验收边界。

## 2026-11-02 冷启动恢复补充验证

用户关闭 MuMu 后明确要求重新启动既有实例 0。本次通过官方 CLI 正常启动；在手动打开任何 EchoSubs Activity 之前，已取得新 boot_id、`sys.boot_completed=1`、系统事件日志中的 `ScheduledNotificationBootReceiver` 广播进程启动记录，以及 AlarmManager 中三条恢复后的活动 RTC_WAKEUP。

三条预约的 PendingIntent requestCode 仍为 1、2、3，原定 UTC 时间与 10 月 30 日预置记录逐一相同。隔离 checkpoint 当时仍为 `seeded`，没有因打开测试页面而重新安排，因此证据包含真实系统预约，不只依赖插件缓存。随后才打开隔离页面，正常核对原 ID、取消本次预约；最终 checkpoint 为 `complete`、SharedPreferences 为 `[]`、系统无该包活动预约，隔离包已停止。主程序重新打开成功，UID 与首次安装时间保持，代理保持原值；没有读取真实账本、密钥或截取主界面。

结论限于 MuMu Android 12/API32 隔离 debug 包的冷启动预约恢复与清理，不代表 Android 13+/OEM 真机、通知实际送达或正式签名 release 已通过相同验收。10 月 30 日那次获准重启后 ADB 失联，原五分钟内没有取得恢复证据；本次补充结果不改写那次失败记录。补测未修改应用源码、重新构建交付包或重复运行已有测试。

## 2026-10-30 本地验收结果

应用源码提交 `51a545a4367bc4e083fa64b842792ada7b2a08dc`，版本 `1.0.0+1`。旧 `b673122` 产物仅为历史预览；本次两端已重新构建。

- 最终提交 `8e900a2` 整树完整自动测试 356 项通过，包含新增的全账本共享设备身份撤销回归；`flutter analyze` 无问题；最终格式检查 108 文件、0 变化。该次完整运行在新增测试后执行，日志和历史定向结果分别保留。
- Windows 原生离线界面与 SQLite 重开/恢复 4 项、真实 Vault/loopback 加密双通道 2 项通过；固定提交再次执行 Windows offline 后完成 release 构建。完整 Release 目录 19 文件打包，ZIP 每项解压内容哈希与原文件一致。
- 用户指定的 MuMu Android 12/API32：固定修复源码的隔离原生离线流程 4 项、Vault/loopback 双通道 2 项通过。新正常主包 release APK 经实际包名与签名核验后按同签名 `install -r` 更新成功，UID/首次安装时间保持，正常启动 Status ok。本次未读取业务数据或恢复密钥，未假设主包仍为空，未截取主界面。本进程 crash buffer 为空；保留了 MuMu linker/nativebridge/Vulkan 等平台 E 级日志，不将其描述成所有错误日志为空。
- 后续用户允许一次 MuMu 重启。新隔离夹具预置三条未来虚构预约后执行一次 `adb reboot`，但原五分钟内 ADB 一直离线，未能取得 BOOT 后系统证据或立即取消新预约，不能据此宣称通过。11 月 2 日重新启动、恢复核验与预约清理见上节。
- 主程序是本机测试签名，尚无生产签名批准。Windows OS 文件对话框、Android 13+ 权限提示/OEM 真机、物理 LAN 发现/相机以及真实厂商 WebDAV 仍未验证。

本地详细日志、截图、临时账本和本机报告均留在忽略目录；没有提交真实数据、秘密或截图。当前 MuMu 与正常主程序保留供试用，隔离包已停止且测试预约已清空。补测没有创建 ADB 转发；10 月 30 日既有转发随连接离线自然消失，未显式删除或重建。构建守护进程已关闭。

自动化场景使用虚构影音月卡、域名年费、永久许可、按量存储与独立临时 SQLite。`test/release/scenario_test.dart` 贯穿实际 AppServices、Repository、同步协调器、LAN 双方确认及固定证书 TLS、受控 HTTPS WebDAV、冲突解决、删除、付款幂等、提醒核对与独立备份恢复。WebDAV 上传后关闭 LAN 监听，再由另一副本下载，验证两通道可独立使用。

本轮新增回归覆盖：旧 root 不可用时通过实际启动页面校验备份、独立导入并由用户明确选择新账本；完整快照失败的切换回滚；冲突详情与两种表单的安全入口；必需配置不可删除与缺失配置提醒不就绪；归档/恢复旧视图不能覆盖远端字段；合成过期身份经用户确认更新，key/cert/active 指针三个安全存储写入故障的保留与重试；两个已注册账本共用设备身份时重建 Vault 后旧入站/出站令牌均失效。账本密钥与历史保持不变。

Windows 同 profile 排他由真正独立 Dart 进程验证：持有者存活时第二进程在业务存储访问前被拒，不同目录独立可用，持有进程退出后原失败进程重试成功。锁句柄覆盖失败、重试、恢复及服务释放，不在后台写入尚可能继续时提前释放。此证据限定 Windows 独立 OS 进程，不宣称 Linux advisory 锁或跨 isolate 有相同语义。

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
| Android 真机与重启 | MuMu/API32 隔离包冷启动已取得应用打开前的 BOOT 接收与系统预约恢复证据；Android 13+ 权限提示、OEM 后台与真机重启仍待验证。flutter test 即使 no-uninstall 也会 force-stop，其 teardown 不能证明 BOOT 接收 |
| 厂商 WebDAV | 受控 TLS/条件写入不等于厂商互操作；未提供真实测试端点/凭据时明确未验证 |
| 物理局域网 | loopback/NAT 通道证据不等于物理 mDNS、防火墙、相机扫码兼容性 |

Drift 2.35.3 的 debug 多实例警告按数据库 runtimeType 的实例数量触发，未检测是否实际共享 QueryExecutor。项目 `AppDatabase.open` 每次创建独立 NativeDatabase，副本使用不同文件，并发测试刻意使用同文件的独立连接以验证事务互斥。保留这些检查和日志，不关闭真实并发测试、不全局隐藏其他警告。

本机报告须记录失败与修正、准确命令/PID/期限/退出码、最终产物哈希和未验证项。widget 渲染不是桌面截图。真实 secure-storage 测试仅使用唯一自建测试槽并删除该槽；不访问既有 root、device.id、active.ledger。关闭本次监听、应用和构建进程，保留用户模拟器；ADB 保留时说明原因。不留测试预约或无人监管通知。
