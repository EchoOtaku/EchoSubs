# EchoSubs 订阅簿

面向 Windows 与 Android 的本地优先个人订阅账本。

当前工程提供可测试的日期、金额、费用估算与不可变领域模型，以及可构建的双端应用空壳。空壳中的“本地账本准备就绪”仅表示应用启动；目前尚未接入持久化账本、订阅录入、同步、系统通知或备份恢复。这些属于已批准计划中的后续任务。

## 开发与验证

Flutter 固定版本见 [`.flutter-version`](.flutter-version)，直接依赖为精确版本，传递依赖见 `pubspec.lock`。项目构建要求、进程环境和验证结果见 [构建说明](docs/build/toolchain.md)。

```text
flutter pub get
flutter test
flutter analyze
flutter build windows --debug
flutter build apk --debug
```

领域金额使用非负整数最小单位，按币种分别汇总；预计费用与实际付款分开。按日、周的费用预测以一年365天折算，只代表估算。自动续费标记不生成实际付款或延长确认权益。

仓库只保存源码、构建配置、文档与虚构测试数据。真实账本、数据库、导出、凭据、恢复密钥和签名文件应保存在版本控制之外。
