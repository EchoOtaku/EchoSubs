# 本地构建与交付

2026-10-30 已从干净的修复后应用源码提交 `51a545a4367bc4e083fa64b842792ada7b2a08dc` 重建 `1.0.0+1`，本次交付位于 `.local/releases/20261030-213311-51a545a/`。后续新增全账本身份撤销测试与验收文档不改变这些二进制的应用源码。旧 `b673122` 产物仅为历史预览版本。

| 产物 | 字节 | SHA256 |
| --- | ---: | --- |
| EchoSubs-1.0.0-windows-x64.zip | 14731781 | `29a67b80aa2a3921cdced3d8719f222c242f3974ffda99784bee16f0d611aa03` |
| EchoSubs-1.0.0-android-local-test-signed.apk | 84664983 | `8d776843889919e527e6b712867604dc12641bdb204f043857a317e3ed6e1a4d` |

Windows ZIP 包含完整 19 文件（exe、DLL、data），已逐项核对解压内容哈希。Android 实际包名 `dev.echootaku.echo_subs`、显示名「EchoSubs 订阅簿」、minSdk24/targetSdk36，包含 arm64-v8a/armeabi-v7a/x86_64；APK Signature Scheme v2 验证通过，证书 `CN=Android Debug`，证书 SHA256 `24ecefc8fef9d384d71e17f616f8488b65a2c03cf3c8223aa18ddf8532f6dae6`。它是**本机测试签名**，已按同签名 `adb install -r` 更新用户模拟器中的现有主包，安装成功、UID 与首次安装时间保持，正常启动成功。本次没有清空数据、录入测试业务、读取真实账本或恢复密钥，也没有截取可能包含用户内容的主界面。

此轮修复包含独立启动恢复、切换完整快照与匹配写锁、冲突详情/配置保护、过期局域网身份的明确更新与全账本重新配对，以及 Windows 同应用数据目录的进程生命周期排他。旧配对撤销不等于远程清除其他设备已有数据；不自动更新过期证书。Windows 进程排他在打开默认数据库和安全存储前生效，不修改原支持目录身份。

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
