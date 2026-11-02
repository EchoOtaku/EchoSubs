# EchoSubs 订阅簿

**简体中文** | [English](README.en.md)

面向 Windows 与 Android 的本地优先个人订阅账本。把域名、服务器、对象存储、影音会员等订阅放在一起管理，看清到期日、续费周期与实际付款。

无需注册 EchoSubs 账号或部署专用应用服务器。局域网直连与加密 WebDAV 同步可分别启用，也可同时使用。当前应用界面为简体中文。

## 功能

- **订阅管理**：名称、分类、来源、价格、币种、续费方式、周期、权益日期、备注与归档。
- **总览与日历**：优先展示到期、逾期和同步风险，支持搜索与分类筛选。
- **费用与付款**：支持固定费用、按量计费和买断；预计月/年支出与实际付款分开显示，不同币种分别统计。
- **续费记录**：付款与赠送权益分别记录，保留权益到期日和下次续费日。
- **双通道同步**：局域网双方确认配对、HTTPS WebDAV 加密同步、并发冲突提示与处理。
- **备份与恢复**：加密备份、恢复密钥、独立恢复为新账本；明文导出需明确确认。
- **双端界面**：桌面侧栏、手机导航、浅深色主题、大字体与键盘适配。

自动续费标记仅用于记录，不会替你付款，也不会自动生成付款历史或延长已确认权益。按量与价格未知的条目不计入固定周期预测。

## 下载与安装

从 [Releases](https://github.com/EchoOtaku/EchoSubs/releases) 下载。私有仓库需要具有访问权限的 GitHub 账号。

| 平台 | 安装 | 提醒行为 |
| --- | --- | --- |
| Windows x64 | 完整解压 ZIP，运行 `echo_subs.exe`，保留同目录 DLL 与 `data` | 应用运行且处于前台时显示应用内提醒；关闭后不驻留、不推送系统通知 |
| Android 7.0 / API 24 及以上 | 安装 APK；更新时使用同签名覆盖安装 | 需允许系统通知；省电限制、强行停止等可能延迟或阻止提醒 |

当前 APK 使用**本机测试签名**，不是生产签名或商店发行版。后续更新需要相同证书；不要通过卸载重装更新已有账本。Windows 运行环境若提示缺少 MSVC 运行库，请按 [Flutter Windows 部署说明](https://docs.flutter.dev/platform-integration/windows/building#distributing-windows-apps) 配置。

## 开始使用

1. 启动应用，添加订阅，填写价格、币种、周期、权益日期及来源。
2. 在“付款”或订阅详情中记录实际付款；赠送时长与付款分开记录。
3. 在“设置 → 备份与恢复”保存恢复密钥并导出加密备份。密钥与备份应分开妥善保存。
4. 按需启用同步。局域网配对需要两端运行并核对双方短码；WebDAV 需要自行提供 HTTPS 服务地址与凭据。
5. 在提醒设置中核对账本时区、规则和权限。同步状态与提醒预约状态分别显示。

同步不能替代备份。另一台设备尚未收到的修改不会影响其本地提醒。所有设备及恢复密钥同时丢失时，加密备份也无法解密。

## 数据与隐私

- 业务数据保存在本机 SQLite；密钥与凭据使用操作系统安全存储。
- 同步对象与加密备份使用应用层加密；这**不等于本地 SQLite 全库加密**，设备账户与磁盘仍需自行保护。
- 数据库、恢复密钥、签名私钥、凭据、私人导出及本机日志均不应提交仓库或加入 Release。
- 测试使用虚构数据。发布前会核查当前文件、Git 历史及安装包；规则扫描不能证明所有可能的泄漏均不存在。

本次审查范围与处理结果见 [发布核查记录](docs/security/release-audit.md)。

## 开发

Flutter 版本由 [`.flutter-version`](.flutter-version) 固定，依赖由 `pubspec.lock` 锁定。准备 Flutter、Windows C++ 构建工具或 Android SDK 后，在项目根目录执行：

```sh
flutter pub get
flutter test
flutter analyze
flutter build windows --release
flutter build apk --release
```

也可使用 `scripts/verify.ps1 -Stage unit` 分阶段验证，将阶段改为 `windows` 或 `android` 可验证对应平台。Android 集成测试必须通过 [隔离测试入口](integration_test/support/run_native.ps1)，使用独立 `.integration` 包，不能卸载或清空主应用。

运行 release 构建时保留默认依赖与插件生成步骤：刚执行过集成测试时，`--no-pub` 可能留下开发插件注册项。详见 [构建要求](docs/build/toolchain.md)。

## 文档与验证

- [构建与安装包校验](docs/build/release.md)
- [验收证据与已知边界](docs/build/acceptance.md)
- [界面设计约定](docs/design/ui-refresh.md)
- [密文信封协议](docs/protocol/envelope-v1.md) / [合并与冲突规则](docs/protocol/merge-v1.md)
- [历史产品设计](docs/superpowers/specs/2026-10-19-echosubs-design.md) / [历史实施计划](docs/superpowers/plans/2026-10-30-echosubs-v1.md)

当前已完成 363 项自动测试，Windows 与 MuMu Android 12/API32 原生离线流程各 4 项通过。实际通知送达、Android 13+/OEM 真机、物理局域网与相机、厂商 WebDAV、Windows OS 文件选择器仍有独立验收边界；不把模拟器或受控测试等同于这些环境全部通过。
