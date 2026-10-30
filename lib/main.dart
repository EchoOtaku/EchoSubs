import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app/app.dart';
import 'app/services.dart';
import 'app/theme.dart';

export 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EchoSubsBootstrapApp());
}

/// A failed unlock remains visible and retryable; no destructive recovery.
class EchoSubsBootstrapApp extends StatefulWidget {
  const EchoSubsBootstrapApp({super.key, this.bootstrap});
  final Future<AppServices> Function()? bootstrap;
  @override
  State<EchoSubsBootstrapApp> createState() => _EchoSubsBootstrapAppState();
}

class _EchoSubsBootstrapAppState extends State<EchoSubsBootstrapApp> {
  late Future<AppServices?> pending;
  Object? failure;
  @override
  void initState() {
    super.initState();
    pending = load();
  }

  Future<AppServices?> load() async {
    failure = null;
    try {
      return await (widget.bootstrap ?? AppServices.bootstrap)();
    } on Object catch (e) {
      failure = e;
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppServices?>(
    future: pending,
    builder: (context, state) {
      if (state.hasData) return EchoSubsApp(services: state.data!);
      return MaterialApp(
        title: 'EchoSubs 订阅簿',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ledgerTheme(Brightness.light),
        darkTheme: ledgerTheme(Brightness.dark),
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.subscriptions_outlined, size: 48),
                      const SizedBox(height: 24),
                      Text(
                        'EchoSubs 订阅簿',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      if (failure != null) ...[
                        const Text(
                          '暂时无法打开本地账本',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Text(safeError(failure!), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        const Text(
                          '原有数据库与密钥不会被清空或替换。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          key: const ValueKey('bootstrap.retry'),
                          onPressed: () => setState(() {
                            pending = load();
                          }),
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试打开'),
                        ),
                      ] else
                        const CircularProgressIndicator(
                          semanticsLabel: '正在打开本地账本',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
