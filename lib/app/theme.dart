import 'package:flutter/material.dart';

ThemeData ledgerTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xff3557a5),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    brightness: brightness,
    fontFamily: 'Segoe UI',
    fontFamilyFallback: const [
      'Microsoft YaHei UI',
      'Noto Sans CJK SC',
      'sans-serif',
    ],
    scaffoldBackgroundColor: dark
        ? const Color(0xff131720)
        : const Color(0xfff5f6fa),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xff1d2330) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
  );
}
