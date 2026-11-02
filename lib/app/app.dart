import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'navigation.dart';
import 'services.dart';
import 'theme.dart';

class EchoSubsApp extends StatefulWidget {
  const EchoSubsApp({super.key, required this.services});
  final AppServices services;
  @override
  State<EchoSubsApp> createState() => _EchoSubsAppState();
}

class _EchoSubsAppState extends State<EchoSubsApp> with WidgetsBindingObserver {
  AppServices get services => widget.services;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      services.syncLifecycle?.call(true);
      services.remindersForeground(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      services.syncLifecycle?.call(false);
      services.remindersForeground(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    services.syncLifecycle?.call(false);
    services.remindersForeground(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: services,
    builder: (context, _) => MaterialApp(
      title: 'EchoSubs 订阅簿',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ledgerTheme(Brightness.light),
      darkTheme: ledgerTheme(Brightness.dark),
      themeMode: services.themeMode,
      builder: (context, child) => ValueListenableBuilder<String?>(
        valueListenable: services.inAppReminders?.banner ?? _emptyBanner,
        builder: (context, message, _) => Column(
          children: [
            if (message != null)
              Material(
                child: SafeArea(
                  bottom: false,
                  child: MaterialBanner(
                    content: Text(message),
                    actions: [
                      TextButton(
                        onPressed: services.inAppReminders?.dismiss,
                        child: const Text('知道了'),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
      ),
      home: LedgerNavigation(services: services),
    ),
  );
}

final _emptyBanner = ValueNotifier<String?>(null);
