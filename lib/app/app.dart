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
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      services.syncLifecycle?.call(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    services.syncLifecycle?.call(false);
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
      home: LedgerNavigation(services: services),
    ),
  );
}
