# 构建要求

本项目由 `.flutter-version` 固定 Flutter 版本，直接依赖使用精确版本，传递依赖由 `pubspec.lock` 锁定。不要自动升级 SDK、依赖、签名或全局配置。

## 工具链

| 目标 | 要求 |
| --- | --- |
| Flutter | 3.47.9 stable，随附 Dart 3.13.7 |
| Windows | x64；具备 Windows SDK 与 C++ 桌面构建工具的 Visual Studio；实际验收环境为 Windows 11 |
| Android | minSdk 24，compile/targetSdk 36；Java 字节码目标 17，已验证的 Gradle 运行时为 JDK 21 |
| Android 原生组件 | 与锁定 Flutter/插件要求匹配的 NDK、CMake；用 `flutter doctor -v` 检查现有环境 |

本机安装路径、账号状态及代理由仓库外的唯一环境清单维护，本文不复制机器目录或个人配置。其他开发机器应按自身 SDK 布局配置进程环境。缺少工具时先停止并确认，不擅自安装环境或更改系统代理。

Android 平台工程锁定 AGP 9.1.0、Kotlin 2.4.0、Gradle 9.3.1。wrapper 使用官方 `-bin` 分发，其 SHA256 为 `b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06`，来源见 [Gradle 官方摘要](https://services.gradle.org/distributions/gradle-9.3.1-bin.zip.sha256)。不要因为本机 PATH 缺少 Gradle 而另装全局版本。

## 常规验证与构建

在项目根目录执行，先确认 `flutter --version` 与固定版本一致：

```sh
flutter doctor -v
flutter pub get
flutter test
flutter analyze
flutter build windows --release
flutter build apk --release
```

Windows 交付必须包含整个 Release 目录，不能只复制 exe。Android 当前仍使用本机测试签名；生产密钥的生成、保存与迁移需要单独安排，私钥与 `android/key.properties` 不进入 Git。

`scripts/verify.ps1` 提供 unit、windows、android 与 all 阶段，包含进度、硬超时和日志；用 `-TimeoutSeconds` 覆盖单阶段预算。Android 原生集成测试必须使用 `integration_test/support/run_native.ps1`：隔离 `.integration` 包、构建后实际包名核验、`--no-uninstall`，不能清空主程序。

## 生成文件与依赖

正常 `flutter pub get` 和构建会准备平台生成文件与 wrapper。构建可能取得 Gradle、锁定插件原生组件和 SQLite hook 验证的原生库，这些属于构建依赖。

不要在集成测试后直接用 `flutter build apk --release --no-pub`：在已验证的 Flutter 版本中，该选项也跳过 release 插件重生成，会保留开发插件注册项。保留正常 release 入口，由 Flutter 过滤开发依赖；不要手改注册文件或 SDK。

## 数据约定与验收

金额使用整数最小单位，同币种按精度分别累计；不同币种不做隐式换算。日/周周期的预测以一年 365 天折算，预测不是付款历史。权益日期为不带时刻的公历日期，月/年周期从原始锚点计算。

当前实现与最终结果以 [验收记录](acceptance.md) 和 [交付记录](release.md) 为准；历史计划保留其制定时快照，不应当作当前待办或最终构建状态。
