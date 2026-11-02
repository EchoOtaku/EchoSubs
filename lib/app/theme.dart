import 'package:flutter/material.dart';
import 'design_system.dart';

ThemeData ledgerTheme(Brightness brightness, {bool reduceMotion = false}) {
  final dark = brightness == Brightness.dark;
  final c = dark ? EchoColors.dark : EchoColors.light;
  final onAccent = dark ? c.canvas : Colors.white;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: onAccent,
    primaryContainer: c.accentSoft,
    onPrimaryContainer: c.accent,
    secondary: c.accent,
    onSecondary: onAccent,
    secondaryContainer: c.accentSoft,
    onSecondaryContainer: c.accent,
    error: c.negative,
    onError: dark ? c.canvas : Colors.white,
    errorContainer: c.negativeSoft,
    onErrorContainer: c.negative,
    surface: c.panel,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    outline: c.controlBorder,
    outlineVariant: c.border,
    surfaceContainerLowest: c.panel,
    surfaceContainerLow: c.soft,
    surfaceContainer: c.soft,
    surfaceContainerHigh: c.soft,
    surfaceContainerHighest: c.border,
    inverseSurface: c.text,
    onInverseSurface: c.panel,
  );
  final text =
      TextTheme(
        displaySmall: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -.9,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        headlineMedium: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: -.6,
        ),
        headlineSmall: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.3,
          letterSpacing: -.4,
        ),
        titleLarge: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        titleMedium: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
        titleSmall: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        bodyLarge: const TextStyle(fontSize: 15, height: 1.6),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.55),
        bodySmall: TextStyle(fontSize: 12, height: 1.5, color: c.muted),
        labelLarge: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        labelMedium: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        labelSmall: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: c.muted,
        ),
      ).apply(
        fontFamily: 'Segoe UI',
        fontFamilyFallback: const [
          'Microsoft YaHei UI',
          'Noto Sans CJK SC',
          'sans-serif',
        ],
        bodyColor: c.text,
        displayColor: c.text,
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  ButtonStyle focus(ButtonStyle style, {Color? ring}) => style.copyWith(
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(color: ring ?? c.accent, width: 2)
          : style.side?.resolve(states),
    ),
    animationDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 140),
  );
  final primary = focus(
    FilledButton.styleFrom(
      foregroundColor: onAccent,
      backgroundColor: c.accent,
      disabledForegroundColor: c.muted,
      disabledBackgroundColor: c.soft,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      shape: shape,
      textStyle: text.labelLarge,
      elevation: 0,
    ),
    ring: onAccent,
  );
  final secondary = focus(
    OutlinedButton.styleFrom(
      foregroundColor: c.text,
      backgroundColor: c.panel,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      side: BorderSide(color: c.controlBorder),
      shape: shape,
      textStyle: text.labelLarge,
    ),
  );
  final quiet = focus(
    TextButton.styleFrom(
      foregroundColor: c.accent,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: shape,
      textStyle: text.labelLarge,
    ),
  );
  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: width),
      );
  return ThemeData(
    useMaterial3: false,
    extensions: [c],
    colorScheme: scheme,
    brightness: brightness,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: EchoPageTransitions(),
        TargetPlatform.windows: EchoPageTransitions(),
        TargetPlatform.linux: EchoPageTransitions(),
        TargetPlatform.macOS: EchoPageTransitions(),
        TargetPlatform.iOS: EchoPageTransitions(),
      },
    ),
    fontFamily: 'Segoe UI',
    fontFamilyFallback: const [
      'Microsoft YaHei UI',
      'Noto Sans CJK SC',
      'sans-serif',
    ],
    textTheme: text,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.panel,
    dividerColor: c.border,
    disabledColor: c.muted.withValues(alpha: .55),
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: c.accent.withValues(alpha: .08),
    hoverColor: c.accent.withValues(alpha: .05),
    focusColor: c.accent.withValues(alpha: .14),
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge?.copyWith(
        fontFamily: 'Segoe UI',
        color: c.text,
      ),
      titleSpacing: 20,
      toolbarHeight: 64,
      shape: Border(bottom: BorderSide(color: c.border)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: c.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: inputBorder(c.controlBorder),
      enabledBorder: inputBorder(c.controlBorder),
      focusedBorder: inputBorder(c.accent, 2),
      errorBorder: inputBorder(c.negative),
      focusedErrorBorder: inputBorder(c.negative, 2),
      hintStyle: text.bodyMedium?.copyWith(color: c.muted),
      labelStyle: text.bodyMedium?.copyWith(color: c.muted),
      floatingLabelStyle: text.labelMedium?.copyWith(color: c.accent),
      errorStyle: text.bodySmall?.copyWith(color: c.negative),
      prefixIconColor: c.muted,
      suffixIconColor: c.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(style: primary),
    elevatedButtonTheme: ElevatedButtonThemeData(style: primary),
    outlinedButtonTheme: OutlinedButtonThemeData(style: secondary),
    textButtonTheme: TextButtonThemeData(style: quiet),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        foregroundColor: WidgetStatePropertyAll(c.muted),
        shape: WidgetStatePropertyAll(shape),
      ),
    ),
    iconTheme: IconThemeData(color: c.muted, size: 20),
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: 12,
      horizontalTitleGap: 12,
      minLeadingWidth: 24,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      iconColor: c.muted,
      textColor: c.text,
      selectedColor: c.accent,
      selectedTileColor: c.accentSoft,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.border),
      ),
      titleTextStyle: text.titleLarge?.copyWith(color: c.text),
      contentTextStyle: text.bodyMedium?.copyWith(color: c.text),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.panel,
      elevation: 4,
      surfaceTintColor: Colors.transparent,
      textStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.panel,
      selectedColor: c.accentSoft,
      labelStyle: text.labelMedium,
      side: BorderSide(color: c.border),
      shape: shape,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.text,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.panel),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: shape,
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(5),
      thumbColor: WidgetStatePropertyAll(c.muted.withValues(alpha: .4)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: c.controlBorder, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? c.accent
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(onAccent),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.text,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: text.bodySmall?.copyWith(color: c.panel),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    ),
  );
}
