import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'navigation.dart';
import 'services.dart';
import 'theme.dart';

class EchoSubsApp extends StatelessWidget {
  const EchoSubsApp({super.key, required this.services});
  final AppServices services;
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
