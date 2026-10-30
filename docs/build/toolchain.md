# 可复现构建

本项目固定 Flutter `3.47.9`（随附 Dart `3.13.7`），以 `.flutter-version`、精确直接依赖和 `pubspec.lock` 锁定工程版本。全局环境清单唯一位置为 `D:\Workspaces\Personal\MyPCConfig\AGENT_ENVIRONMENT.md`；本文件只记录项目构建要求，不复制机器安装清单。

Flutter 官方归档：[Windows 3.47.9 stable](https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.9-stable.zip)，摘要来自 [Google 官方发布元数据](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json)。本次安装代理使用 Flutter 文档列出的 CFUG 镜像下载完整归档，并核对以下 Google 官方 SHA256 成功：

```text
d8e2b5977e09082c6440f89dc1aa887b94c8fbcc3b39222797046295a3f68a9e
```

官方 `flutter create --platforms=windows,android --org=dev.echootaku --project-name=echo_subs --no-pub .` 生成平台工程。模板固定 AGP `9.1.0`、Kotlin `2.4.0`、Gradle `9.3.1`，保留模板组合。Gradle 使用同版本官方 `-bin` 分发，wrapper 固定其 [官方 SHA256](https://services.gradle.org/distributions/gradle-9.3.1-bin.zip.sha256) `b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06`；无需下载包含源码与文档的 `-all` 包。

## 验证命令

使用既有 SDK 完整路径，运行前核验版本。命令执行于工程根目录；不依赖修改系统 PATH。

```powershell
$env:APPDATA = 'D:\SDK\cache\echosubs-20261030\flutter-appdata'
$env:JAVA_HOME = 'D:\SDK\Java\Zulu21'
$env:ANDROID_HOME = 'D:\SDK\Android'
$env:ANDROID_SDK_ROOT = 'D:\SDK\Android'
$env:PUB_CACHE = 'D:\SDK\cache\pub'
$env:NO_PROXY = 'localhost,127.0.0.1,::1'
$env:PATH = "D:\SDK\Flutter\bin;D:\SDK\Java\Zulu21\bin;D:\Software\Dev\Git\cmd;$env:PATH"
& 'D:\SDK\Flutter\bin\flutter.bat' --version
& 'D:\SDK\Flutter\bin\flutter.bat' pub get
& 'D:\SDK\Flutter\bin\flutter.bat' test
& 'D:\SDK\Flutter\bin\flutter.bat' analyze
& 'D:\SDK\Flutter\bin\flutter.bat' build windows --debug
& 'D:\SDK\Flutter\bin\flutter.bat' build apk --debug
```

Windows 目标为 Windows 10 1903+ x64。Android 最低 API 24、compile/target SDK 36、Java 17，启用 core library desugaring `2.1.4`。构建缺失 SDK 或工具时停止并报告，不以自动安装填补授权范围外的组件。Android SDK 与 Java 只在当前构建进程指定，`android/local.properties` 不提交。

Java 17 是应用字节码编译目标；本次 Gradle 运行时使用已安装的 Zulu 21，以满足生成模板的工具要求。Flutter 的 JDK 路径配置隔离于上述 APPDATA 下，不改变用户常用 Flutter 配置。若现有网络需要代理，Java 不会自动使用 HTTP_PROXY；本次 Android 构建仅在子进程 `JAVA_TOOL_OPTIONS` 中指定用户现有的 `127.0.0.1:7897` HTTP/HTTPS 代理并排除 loopback，不写全局 Gradle 或系统代理。其他机器应按自身网络配置，不能照搬此端口。

## 领域约定

金额使用非负的 64 位整数最小单位，JSON 中的 `minorUnits` 为十进制字符串；中间有理数计算使用 `BigInt`，越界拒绝，所有费用按币种分别汇总。同币种输入精度必须一致。预计月、年费用在各币种的有理数合计完成后按精度四舍五入（half up），不逐条舍入。日/周周期以一年 365 天折算，只代表估算；真实付款仅来自付款记录。

账本日期是 `0001-01-01` 到 `9999-12-31` 的公历日期，不携带时区或时刻。月/年周期始终从原始锚点计算，不把截断后的二月日期作为下一次锚点。

## 构建验证记录

2026-10-30 实际验证：Flutter `3.47.9 stable` / Dart `3.13.7`，`flutter doctor -v` 为 `No issues found`；`flutter devices` 识别 Windows 与用户已启动的 MuMu（Android 12/API32，`127.0.0.1:16384`），未另开 AVD。

- RED：领域实现前 `flutter test test/domain` 退出1，四个测试文件因领域接口尚不存在编译失败。
- GREEN：领域实现后同命令加 `--no-pub`，17项测试全部通过；加入应用空壳与自审补充的费用摘要值相等测试后，最终 `flutter test --no-pub` 为19项全部通过，`flutter analyze --no-pub` 为 `No issues found`（4.2秒）。官方 `dart format --output=none --set-exit-if-changed lib test` 检查16文件，0项变更。
- Windows：`flutter build windows --debug --no-pub` 退出0，耗时42.5秒，生成 `build/windows/x64/runner/Debug/echo_subs.exe`。最初缺少生成的插件注册文件，`flutter pub get --offline` 重新生成后通过。
- Android：实际构建准备中，结果待补齐。首次Gradle直连分发下载静默，经进程和网络检查后主动停止（144.3秒）；第二次使用上述仅进程代理与已校验的同版本bin分发，下载75MB后仍有长暂停，由协调代理裁定主动停止（317.6秒）并交工具链代理从官方源加速下载同一分发、核对完整SHA256后再恢复构建。这两次主动停止均为退出1，不能作为APK构建通过的证据。

依赖组合已完成真实解析，未降级计划直接依赖。`flutter create` 后需要重新 `flutter pub get`，生成平台插件注册文件；这些注册文件按 Flutter 模板规则管理。构建过程可能下载 Gradle、锁定插件的原生构件，以及 SQLite 3.x hook 校验的原生库；不属于应用运行时下载。真机通知与端到端同步验收属于后续任务，空壳构建通过不代表这些功能已实现。
