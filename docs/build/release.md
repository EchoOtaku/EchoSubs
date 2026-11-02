# 本地构建与交付

## 2026-11-02 自定义界面版本

应用源码提交 `b350468e6d6a691fb122c5221f535ffb9373e7cc`，版本 `1.0.0+2`。交付目录为 `.local/releases/20261102-125034-b350468/`，与下方首版产物分别保留。后续验收文档提交不改变该应用源码。

| 产物 | 字节 | SHA256 |
| --- | ---: | --- |
| EchoSubs-1.0.0+2-windows-x64.zip | 14696165 | `69255aaba3fa50a7584c0128af89bed975a596214b0b3cb9b3a76813f36214e6` |
| EchoSubs-1.0.0+2-android-local-test-signed.apk | 84418715 | `be6918391b4672cca2b1ed5887b8c4e4b04920e6cea7d4ee8fcd14fc5d0c16be` |

Windows 完整 19 文件已复制至交付目录的 `windows-x64/`，ZIP 中每一项的长度及解压内容 SHA256 均与构建目录一致；CompanyName、ProductName 和 exe basename 保持原值。Android 实际主包名 `dev.echootaku.echo_subs`、versionCode 2，签名验证通过，证书 SHA256 与下方首版本机测试签名相同。交付 APK 的复制前后 SHA256 也已核对。

在安装前读取既有主包二进制并核验同一证书后，已对 MuMu 执行 `adb install -r`。安装 UID 及首次安装时间保持，主 Activity 启动 Status ok，随后进程仍运行，该 PID 的 crash buffer 没有记录。没有卸载、清空、读取真实账本或恢复密钥；没有截取主应用界面。MuMu 与更新后的主程序保留供试用。

构建使用正常 `flutter build windows --release` 与 `flutter build apk --release`。集成测试之后首次 Android 构建使用 `--no-pub`，因其跳过 release 插件重生成而保留 integration_test 注册项并失败；核对本机 Flutter 官方源码后，按正常 release 入口重新生成，测试插件已过滤，双端重建成功。没有手改生成代码、SDK 或依赖版本。

本版本仍为本机测试签名 APK；不是生产签名交付。自动与原生验收、预览性质及外部边界见 `acceptance.md`，界面约定见 `../design/ui-refresh.md`。

## 2026-10-30 首版

2026-10-30 已从干净的修复后应用源码提交 `51a545a4367bc4e083fa64b842792ada7b2a08dc` 重建 `1.0.0+1`，本次交付位于 `.local/releases/20261030-213311-51a545a/`。后续新增全账本身份撤销测试与验收文档不改变这些二进制的应用源码。旧 `b673122` 产物仅为历史预览版本。

| 产物 | 字节 | SHA256 |
| --- | ---: | --- |
| EchoSubs-1.0.0-windows-x64.zip | 14731781 | `29a67b80aa2a3921cdced3d8719f222c242f3974ffda99784bee16f0d611aa03` |
| EchoSubs-1.0.0-android-local-test-signed.apk | 84664983 | `8d776843889919e527e6b712867604dc12641bdb204f043857a317e3ed6e1a4d` |

Windows ZIP 包含完整 19 文件（exe、DLL、data），已逐项核对解压内容哈希。Android 实际包名 `dev.echootaku.echo_subs`、显示名「EchoSubs 订阅簿」、minSdk24/targetSdk36，包含 arm64-v8a/armeabi-v7a/x86_64；APK Signature Scheme v2 验证通过，证书 `CN=Android Debug`，证书 SHA256 `24ecefc8fef9d384d71e17f616f8488b65a2c03cf3c8223aa18ddf8532f6dae6`。它是**本机测试签名**，已按同签名 `adb install -r` 更新用户模拟器中的现有主包，安装成功、UID 与首次安装时间保持，正常启动成功。本次没有清空数据、录入测试业务、读取真实账本或恢复密钥，也没有截取可能包含用户内容的主界面。

此轮修复包含独立启动恢复、切换完整快照与匹配写锁、冲突详情/配置保护、过期局域网身份的明确更新与全账本重新配对，以及 Windows 同应用数据目录的进程生命周期排他。旧配对撤销不等于远程清除其他设备已有数据；不自动更新过期证书。Windows 进程排他在打开默认数据库和安全存储前生效，不修改原支持目录身份。

2026-11-02 补充验收：用户关闭后重新启动的 MuMu/API32 隔离 debug 包，在手动打开应用前由 BOOT 接收器恢复三条原 ID、原时间的系统预约；随后正常核对、取消，并验证缓存为空、系统无活动测试预约。主程序已重新打开，安装身份和代理保持。此结果单独记录为冷启动恢复证据，不覆盖 10 月 30 日重启后 ADB 失联的未完成记录，也不等同真机或正式签名 release 验收。应用源码与上述交付包未变，完整自动测试的最终结果为 `8e900a2` 整树 356 项通过；详细边界见 `acceptance.md`。

版本来自 `pubspec.yaml`。使用项目锁定的 Flutter 与依赖，不自动升级工具链；本机路径仅从全局环境清单读取，本文不复制本机配置。

```powershell
./scripts/verify.ps1 -Stage unit
./scripts/verify.ps1 -Stage windows
./scripts/verify.ps1 -Stage android
```

`-Stage all` 依次执行三阶段。`-TimeoutSeconds` 覆盖每阶段总硬限（默认 unit 300 秒、windows/android 各 900 秒；0 使用默认值）。每条命令共享该阶段剩余预算，输出 PID、期限、工具输出、耗时和退出码；非零/超时停止后续阶段，无自动重试。超时只结束本次启动的进程树。日志保留在新的 `.local/verify/` 目录；不删除历史日志或修改全局 PATH/代理。

Windows 阶段先运行隔离虚构 SQLite 的 `offline_flow_test.dart --no-uninstall`，再生成 release。交付须压缩完整 `build/windows/x64/runner/Release/`，包含 exe、DLL、data 和所有插件依赖，不能单独拷贝 exe。保留 runner 的 CompanyName、ProductName 和 exe basename，以保持既有应用数据目录身份。

Android release 命令使用正常主入口；集成测试只能经 `integration_test/support/run_native.ps1`，使用 `.integration` 包、`ECHOSUBS_INTEGRATION_TEST=1`、安装前 AAPT 包名核对及 `--no-uninstall`。每次构建后重核 APK ID，不凭目标文件名判断身份。集成测试启动器显示「EchoSubs 集成测试」，主程序显示「EchoSubs 订阅簿」。

当前 release 构建仍采用模板的本机 debug 签名，仅可标为**本机测试签名 APK**。生产签名的生成位置、长期保存及独立备份必须由用户批准后另行配置；当前没有生成生产 keystore 或改变签名引用。不得把 release 编译模式等同于正式签名或上架就绪。

最终产物置于新的唯一 `.local/releases/<时间与版本>/`，清单记录源码提交、版本、文件名、字节数、SHA256、签名身份和构建命令。不交付中间版本 `app-debug.apk`，不把本机报告、账本、密钥、导出或截图提交 Git。更新既有主包必须使用相同签名并保留应用数据；不能以卸载重装替代更新。

本地交付不自动推送、建 PR、合并、公开 Release、调用付费 CI 或上传应用商店。
