import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch;

/// EchoSubs surfaces and controls have their own visual language. Material
/// primitives remain an accessibility/platform adapter, rather than a style.
@immutable
class EchoColors extends ThemeExtension<EchoColors> {
  const EchoColors({
    required this.canvas,
    required this.panel,
    required this.soft,
    required this.text,
    required this.muted,
    required this.border,
    required this.controlBorder,
    required this.accent,
    required this.accentSoft,
    required this.warning,
    required this.warningSoft,
    required this.negative,
    required this.negativeSoft,
  });
  final Color canvas, panel, soft, text, muted, border, controlBorder;
  final Color accent, accentSoft, warning, warningSoft, negative, negativeSoft;

  static const light = EchoColors(
    canvas: Color(0xfff3f6f8),
    panel: Color(0xffffffff),
    soft: Color(0xfff7f9fb),
    text: Color(0xff172b36),
    muted: Color(0xff586b78),
    border: Color(0xffdce4e9),
    controlBorder: Color(0xff84949f),
    accent: Color(0xff08776f),
    accentSoft: Color(0xffe4f2ef),
    warning: Color(0xff9e5d0a),
    warningSoft: Color(0xfffff3de),
    negative: Color(0xffb6414d),
    negativeSoft: Color(0xfffbedef),
  );
  static const dark = EchoColors(
    canvas: Color(0xff101b23),
    panel: Color(0xff17252f),
    soft: Color(0xff1e2f3a),
    text: Color(0xffe6edf3),
    muted: Color(0xffa0b0bd),
    border: Color(0xff334650),
    controlBorder: Color(0xff69818e),
    accent: Color(0xff70d6c5),
    accentSoft: Color(0xff173d3b),
    warning: Color(0xffebc27a),
    warningSoft: Color(0xff3b3020),
    negative: Color(0xfffda0a8),
    negativeSoft: Color(0xff3d2630),
  );

  static EchoColors of(BuildContext context) =>
      Theme.of(context).extension<EchoColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  EchoColors copyWith({
    Color? canvas,
    Color? panel,
    Color? soft,
    Color? text,
    Color? muted,
    Color? border,
    Color? controlBorder,
    Color? accent,
    Color? accentSoft,
    Color? warning,
    Color? warningSoft,
    Color? negative,
    Color? negativeSoft,
  }) => EchoColors(
    canvas: canvas ?? this.canvas,
    panel: panel ?? this.panel,
    soft: soft ?? this.soft,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    controlBorder: controlBorder ?? this.controlBorder,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    warning: warning ?? this.warning,
    warningSoft: warningSoft ?? this.warningSoft,
    negative: negative ?? this.negative,
    negativeSoft: negativeSoft ?? this.negativeSoft,
  );
  @override
  EchoColors lerp(EchoColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return EchoColors(
      canvas: mix(canvas, other.canvas),
      panel: mix(panel, other.panel),
      soft: mix(soft, other.soft),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      border: mix(border, other.border),
      controlBorder: mix(controlBorder, other.controlBorder),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      warning: mix(warning, other.warning),
      warningSoft: mix(warningSoft, other.warningSoft),
      negative: mix(negative, other.negative),
      negativeSoft: mix(negativeSoft, other.negativeSoft),
    );
  }
}

Duration echoDuration(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations == true
    ? Duration.zero
    : const Duration(milliseconds: 160);

class EchoPanel extends StatelessWidget {
  const EchoPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.borderColor,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color, borderColor;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.panel,
        border: Border.all(color: borderColor ?? c.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class EchoBadge extends StatelessWidget {
  const EchoBadge(this.label, {super.key, this.color, this.background});
  final String label;
  final Color? color, background;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? c.soft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color ?? c.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class EchoChoice extends StatelessWidget {
  const EchoChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    return Semantics(
      selected: selected,
      child: TextButton(
        style:
            TextButton.styleFrom(
              foregroundColor: selected ? c.accent : c.muted,
              backgroundColor: selected ? c.accentSoft : c.panel,
              side: BorderSide(color: selected ? c.accent : c.border),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              minimumSize: const Size(48, 48),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.focused) || selected
                      ? c.accent
                      : c.border,
                  width: states.contains(WidgetState.focused) ? 2 : 1,
                ),
              ),
            ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

class EchoField extends StatelessWidget {
  const EchoField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
  });
  final String label;
  final String? hint;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
      const SizedBox(height: 8),
      Semantics(label: label, child: child),
      if (hint != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(hint!, style: Theme.of(context).textTheme.bodySmall),
        ),
    ],
  );
}

class EchoSwitchTile extends StatelessWidget {
  const EchoSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.contentPadding = EdgeInsets.zero,
  });
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    return MergeSemantics(
      child: Padding(
        padding: contentPadding,
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTap: onChanged == null ? null : () => onChanged!(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DefaultTextStyle(
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge!.copyWith(color: c.text),
                        child: title,
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: DefaultTextStyle(
                            style: Theme.of(context).textTheme.bodySmall!,
                            child: subtitle!,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 58,
                  height: 48,
                  child: CupertinoSwitch(
                    value: value,
                    onChanged: onChanged,
                    activeTrackColor: c.accent,
                    inactiveTrackColor: c.controlBorder,
                    thumbColor: c.panel,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EchoNotice extends StatelessWidget {
  const EchoNotice({
    super.key,
    required this.message,
    this.action,
    this.actionLabel,
    this.danger = false,
    this.icon = EchoSymbol.warning,
  });
  final String message;
  final VoidCallback? action;
  final String? actionLabel;
  final bool danger;
  final EchoSymbol icon;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    final color = danger ? c.negative : c.warning;
    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EchoIcon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
    final button = action == null
        ? null
        : TextButton(onPressed: action, child: Text(actionLabel ?? '查看'));
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        decoration: BoxDecoration(
          color: danger ? c.negativeSoft : c.warningSoft,
          border: Border(
            bottom: BorderSide(color: color.withValues(alpha: .18)),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth < 500 && button != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    text,
                    Align(alignment: Alignment.centerRight, child: button),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: text),
                    if (button != null) ...[const SizedBox(width: 12), button],
                  ],
                ),
        ),
      ),
    );
  }
}

enum EchoSymbol {
  overview,
  subscriptions,
  calendar,
  payments,
  settings,
  add,
  search,
  arrow,
  chevronLeft,
  check,
  cloud,
  bell,
  lock,
  backup,
  close,
  sun,
  moon,
  warning,
}

/// Small, consistent outline symbols drawn at their native vector resolution.
class EchoIcon extends StatelessWidget {
  const EchoIcon(this.symbol, {super.key, this.size = 20, this.color});
  final EchoSymbol symbol;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _EchoIconPainter(
          symbol,
          color ?? IconTheme.of(context).color ?? EchoColors.of(context).muted,
        ),
      ),
    ),
  );
}

class _EchoIconPainter extends CustomPainter {
  _EchoIconPainter(this.symbol, this.color);
  final EchoSymbol symbol;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double x2, double y2) =>
        canvas.drawLine(Offset(x, y), Offset(x2, y2), p);
    void box(double x, double y, double w, double h, [double r = 2]) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            Radius.circular(r),
          ),
          p,
        );
    void path(List<Offset> points, {bool close = false}) {
      final value = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        value.lineTo(point.dx, point.dy);
      }
      if (close) value.close();
      canvas.drawPath(value, p);
    }

    switch (symbol) {
      case EchoSymbol.overview:
        box(3, 3, 7, 7);
        box(14, 3, 7, 11);
        box(3, 14, 7, 7);
        box(14, 18, 7, 3, 1);
      case EchoSymbol.subscriptions:
        box(3, 7, 18, 14);
        line(6, 3, 18, 3);
        line(5, 5, 19, 5);
        line(7, 12, 17, 12);
        line(7, 16, 13, 16);
      case EchoSymbol.calendar:
        box(3, 5, 18, 16);
        line(7, 3, 7, 7);
        line(17, 3, 17, 7);
        line(3, 10, 21, 10);
        line(7, 14, 9, 14);
        line(14, 14, 16, 14);
        line(7, 17, 9, 17);
      case EchoSymbol.payments:
        box(3, 5, 18, 15);
        line(3, 10, 21, 10);
        line(7, 15, 10, 15);
        line(14, 15, 17, 15);
      case EchoSymbol.settings:
        line(3, 6, 8, 6);
        line(12, 6, 21, 6);
        canvas.drawCircle(const Offset(10, 6), 2, p);
        line(3, 12, 13, 12);
        line(17, 12, 21, 12);
        canvas.drawCircle(const Offset(15, 12), 2, p);
        line(3, 18, 6, 18);
        line(10, 18, 21, 18);
        canvas.drawCircle(const Offset(8, 18), 2, p);
      case EchoSymbol.add:
        line(5, 12, 19, 12);
        line(12, 5, 12, 19);
      case EchoSymbol.search:
        canvas.drawCircle(const Offset(10.5, 10.5), 6.5, p);
        line(16, 16, 21, 21);
      case EchoSymbol.arrow:
        path(const [Offset(9, 5), Offset(16, 12), Offset(9, 19)]);
      case EchoSymbol.chevronLeft:
        path(const [Offset(15, 5), Offset(8, 12), Offset(15, 19)]);
      case EchoSymbol.check:
        path(const [Offset(4, 12), Offset(9, 17), Offset(20, 6)]);
      case EchoSymbol.close:
        line(6, 6, 18, 18);
        line(18, 6, 6, 18);
      case EchoSymbol.cloud:
        final cloud = Path()
          ..moveTo(7, 18)
          ..cubicTo(0, 18, 1, 8, 8, 9)
          ..cubicTo(8, 1, 20, 2, 19, 10)
          ..cubicTo(25, 11, 23, 18, 18, 18)
          ..close();
        canvas.drawPath(cloud, p);
      case EchoSymbol.bell:
        path(const [Offset(4, 17), Offset(6, 14), Offset(6, 9)]);
        canvas.drawArc(const Rect.fromLTWH(6, 3, 12, 12), 3.14, 3.14, false, p);
        path(const [
          Offset(18, 9),
          Offset(18, 14),
          Offset(20, 17),
          Offset(4, 17),
        ]);
        canvas.drawArc(const Rect.fromLTWH(9, 17, 6, 5), 0, 3.14, false, p);
      case EchoSymbol.lock:
        box(4, 10, 16, 11);
        canvas.drawArc(const Rect.fromLTWH(7, 2, 10, 15), 3.14, 3.14, false, p);
        line(7, 7, 7, 10);
        line(17, 7, 17, 10);
        line(12, 15, 12, 17);
      case EchoSymbol.backup:
        box(3, 12, 18, 9);
        line(12, 3, 12, 15);
        path(const [Offset(7, 8), Offset(12, 3), Offset(17, 8)]);
      case EchoSymbol.sun:
        canvas.drawCircle(const Offset(12, 12), 4, p);
        line(12, 2, 12, 4);
        line(12, 20, 12, 22);
        line(2, 12, 4, 12);
        line(20, 12, 22, 12);
        line(5, 5, 6.5, 6.5);
        line(17.5, 17.5, 19, 19);
        line(5, 19, 6.5, 17.5);
        line(17.5, 6.5, 19, 5);
      case EchoSymbol.moon:
        final moon = Path()
          ..moveTo(20, 15)
          ..cubicTo(8, 21, 3, 9, 10, 3)
          ..cubicTo(-1, 5, 1, 24, 15, 21)
          ..cubicTo(18, 20, 20, 18, 20, 15);
        canvas.drawPath(moon, p);
      case EchoSymbol.warning:
        path(const [Offset(12, 3), Offset(22, 20), Offset(2, 20)], close: true);
        line(12, 9, 12, 13);
        canvas.drawCircle(const Offset(12, 17), .6, p);
    }
  }

  @override
  bool shouldRepaint(_EchoIconPainter oldDelegate) =>
      oldDelegate.symbol != symbol || oldDelegate.color != color;
}

class EchoPageTransitions extends PageTransitionsBuilder {
  const EchoPageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) return child;
    final eased = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.018, 0),
          end: Offset.zero,
        ).animate(eased),
        child: child,
      ),
    );
  }
}

class EchoMark extends StatelessWidget {
  const EchoMark({super.key, this.size = 34});
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = EchoColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.accent,
          borderRadius: BorderRadius.circular(size * .26),
        ),
        padding: EdgeInsets.all(size * .23),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: size * .075, color: c.panel),
            const Spacer(),
            FractionallySizedBox(
              widthFactor: .66,
              child: Container(height: size * .075, color: c.panel),
            ),
            const Spacer(),
            Container(height: size * .075, color: c.panel),
          ],
        ),
      ),
    );
  }
}
