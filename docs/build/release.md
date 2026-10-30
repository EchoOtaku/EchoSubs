# 本地构建与交付

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

最终产物置于新的唯一 `.local/releases/<时间与版本>/`，清单记录源码提交、版本、文件名、字节数、SHA256、签名身份和构建命令。不交付中间版本 `app-debug.apk`，不把本机报告、账本、密钥、导出或截图提交 Git。安装正常主 APK 是新建空账本，不代表恢复旧设备身份。

本地交付不自动推送、建 PR、合并、公开 Release、调用付费 CI 或上传应用商店。
