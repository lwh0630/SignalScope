import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass_tokens.dart';

// ----------------------------------------------------------------- filter

/// Backdrop filter of every glass surface: a gaussian blur plus a saturation
/// boost, so the colours behind the glass stay vivid instead of turning grey.
ImageFilter glassFilter(double blur) {
  const s = 1.45; // saturation
  const r = 0.2126, g = 0.7152, b = 0.0722; // luminance weights
  final matrix = <double>[
    r * (1 - s) + s, g * (1 - s), b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s) + s, b * (1 - s), 0, 0, //
    r * (1 - s), g * (1 - s), b * (1 - s) + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
  return ImageFilter.compose(
    outer: ImageFilter.blur(
      sigmaX: blur,
      sigmaY: blur,
      tileMode: TileMode.clamp,
    ),
    inner: ColorFilter.matrix(matrix),
  );
}

// ----------------------------------------------------------------- motion

/// Tells the glass below it that its page is currently being slid in or out by a
/// route transition. While that is true every [BackdropFilter] is switched off
/// (`enabled: false`: no offscreen layer, no blur pass) and only the translucent
/// fill is drawn. A page full of cards would otherwise re-blur a screen-sized
/// area a dozen times per frame during the slide, which makes it stutter.
///
/// The widget tree is unchanged by the flag, so no state is lost.
class GlassMotionScope extends InheritedWidget {
  const GlassMotionScope({
    super.key,
    required this.moving,
    required super.child,
  });

  final bool moving;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassMotionScope>()?.moving ??
      false;

  @override
  bool updateShouldNotify(GlassMotionScope old) => old.moving != moving;
}

/// Feeds [GlassMotionScope] from the animations of one route: moving while either
/// the route's own push / pop or the covering route's push / pop is running.
/// Listens to status changes only, so it does not rebuild every frame.
class GlassMotionTracker extends StatefulWidget {
  const GlassMotionTracker({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  State<GlassMotionTracker> createState() => _GlassMotionTrackerState();
}

class _GlassMotionTrackerState extends State<GlassMotionTracker> {
  bool _moving = false;

  static bool _running(Animation<double> a) =>
      a.status == AnimationStatus.forward ||
      a.status == AnimationStatus.reverse;

  @override
  void initState() {
    super.initState();
    _moving = _running(widget.animation) || _running(widget.secondaryAnimation);
    widget.animation.addStatusListener(_onStatus);
    widget.secondaryAnimation.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(GlassMotionTracker old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      old.animation.removeStatusListener(_onStatus);
      widget.animation.addStatusListener(_onStatus);
    }
    if (old.secondaryAnimation != widget.secondaryAnimation) {
      old.secondaryAnimation.removeStatusListener(_onStatus);
      widget.secondaryAnimation.addStatusListener(_onStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    widget.secondaryAnimation.removeStatusListener(_onStatus);
    super.dispose();
  }

  void _onStatus(AnimationStatus _) {
    final moving =
        _running(widget.animation) || _running(widget.secondaryAnimation);
    if (moving != _moving) setState(() => _moving = moving);
  }

  @override
  Widget build(BuildContext context) =>
      GlassMotionScope(moving: _moving, child: widget.child);
}

// --------------------------------------------------------------- painters

/// Soft drop shadow drawn only *outside* the shape, so it does not darken the
/// translucent glass above it.
class _OuterShadowPainter extends CustomPainter {
  const _OuterShadowPainter({
    required this.radius,
    required this.color,
    required this.elevation,
  });

  final double radius;
  final Color color;

  /// 0 = flat, 1 = resting card, 2 = floating chrome.
  final double elevation;

  @override
  void paint(Canvas canvas, Size size) {
    if (elevation <= 0 || size.isEmpty) return;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final blur = 10.0 + elevation * 14;
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(blur * 3 + 40))
      ..addRRect(rrect);
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRRect(
      rrect.shift(Offset(0, 4.0 + elevation * 6)),
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
    );
    // Tight contact shadow.
    canvas.drawRRect(
      rrect.shift(const Offset(0, 1)),
      Paint()
        ..color = color.withValues(alpha: color.a * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.radius != radius || old.color != color || old.elevation != elevation;
}

/// 1 px gradient edge (bright top-left, dim bottom-right) plus a faint inner
/// sheen along the top: the "lit glass" rim.
class _RimPainter extends CustomPainter {
  const _RimPainter({
    required this.radius,
    required this.light,
    required this.dark,
    required this.sheen,
    required this.focus,
  });

  final double radius;
  final Color light;
  final Color dark;
  final Color sheen;
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius - 0.5),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, dark],
        ).createShader(rect),
    );
    // Sheen: a short bright gradient hugging the top edge, inside the rim.
    final sheenRect = Rect.fromLTWH(
      0,
      0,
      size.width,
      (size.height * 0.5).clamp(0, 56),
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    canvas.drawRect(
      sheenRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [sheen, sheen.withValues(alpha: 0)],
        ).createShader(sheenRect),
    );
    canvas.restore();
    final f = focus;
    if (f != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), Radius.circular(radius - 1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = f,
      );
    }
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius ||
      old.light != light ||
      old.dark != dark ||
      old.sheen != sheen ||
      old.focus != focus;
}

// ----------------------------------------------------------------- surface

/// Chrome-level glass: a real backdrop blur under a translucent fill, a lit
/// rim and a floating shadow. Use it sparingly (navigation bar, dialogs): every
/// instance costs a blur pass. Scrolling content should use [GlassCard].
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = Rd.xl,
    this.blur = 26,
    this.padding,
    this.fill,
    this.elevation = 2,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final Color? fill;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final shape = BorderRadius.circular(radius);
    Widget content = child;
    if (padding != null) content = Padding(padding: padding!, child: content);
    return CustomPaint(
      painter: _OuterShadowPainter(
        radius: radius,
        color: g.shadow,
        elevation: elevation,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          enabled: !GlassMotionScope.of(context),
          filter: glassFilter(blur),
          child: CustomPaint(
            foregroundPainter: _RimPainter(
              radius: radius,
              light: g.edgeLight,
              dark: g.edgeDark,
              sheen: g.highlight.withValues(alpha: g.highlight.a * 0.35),
              focus: null,
            ),
            child: ColoredBox(
              color: fill ?? g.fillStrong,
              child: Material(type: MaterialType.transparency, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- pressable

/// Hover / press / keyboard-focus behaviour shared by every interactive glass
/// element: a pointer cursor, a tiny press-down scale and a focus ring, with no
/// Material ripple.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.scale = 0.985,
    this.cursor,
    this.focusNode,
    this.semanticLabel,
  });

  /// Builds the content for the current interaction state.
  final Widget Function(
    BuildContext context,
    bool hovered,
    bool pressed,
    bool focused,
  )
  builder;
  final VoidCallback? onTap;
  final double scale;
  final MouseCursor? cursor;
  final FocusNode? focusNode;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(context, _hovered, _pressed, _focused);
    if (!_enabled) return content;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        mouseCursor: widget.cursor ?? SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? widget.scale : 1,
            duration: Motion.of(context, Motion.fast),
            curve: Motion.curve,
            child: content,
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- card

/// Card-level glass: translucent fill over a *light* backdrop blur ([blur],
/// smaller than chrome's), lit rim and soft shadow. Pass `blur: 0` when the
/// card already sits on another glass surface. When [onTap] is set it dips on
/// press. [tint] washes the fill with a status colour (warnings, errors).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.radius = Rd.lg,
    this.blur = 14,
    this.tint,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final Color? tint;

  Widget _maybeBlur(BuildContext context, Widget child) => blur <= 0
      ? child
      : BackdropFilter(
          enabled: !GlassMotionScope.of(context),
          filter: glassFilter(blur),
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final accent = Theme.of(context).colorScheme.primary;
    final fill = tint == null
        ? g.fill
        : Color.alphaBlend(
            tint!.withValues(alpha: g.isDark ? 0.16 : 0.12),
            g.fill,
          );
    Widget build(bool focused) {
      final shape = BorderRadius.circular(radius);
      final content = padding == null
          ? child
          : Padding(padding: padding!, child: child);
      return CustomPaint(
        painter: _OuterShadowPainter(
          radius: radius,
          color: g.shadow,
          elevation: 1,
        ),
        foregroundPainter: _RimPainter(
          radius: radius,
          light: tint == null ? g.edgeLight : tint!.withValues(alpha: 0.55),
          dark: tint == null ? g.edgeDark : tint!.withValues(alpha: 0.15),
          sheen: g.highlight.withValues(alpha: g.highlight.a * 0.18),
          focus: focused ? accent.withValues(alpha: 0.7) : null,
        ),
        child: ClipRRect(
          borderRadius: shape,
          // A transparent Material under the tinted fill keeps ListTile / InkWell
          // children from painting their ink behind the fill.
          child: _maybeBlur(
            context,
            ColoredBox(
              color: fill,
              child: Material(type: MaterialType.transparency, child: content),
            ),
          ),
        ),
      );
    }

    if (onTap == null) return build(false);
    return Pressable(
      onTap: onTap,
      builder: (context, _, _, focused) => build(focused),
    );
  }
}

// ------------------------------------------------------------------ dialog

/// Glass dialog with the same slots as [AlertDialog].
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
  });

  final Widget? title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = context.glass;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Sp.x6,
        vertical: Sp.x6,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassSurface(
          radius: Rd.xl,
          blur: 32,
          fill: g.panel.withValues(alpha: g.isDark ? 0.78 : 0.86),
          padding: const EdgeInsets.fromLTRB(Sp.x6, Sp.x6, Sp.x6, Sp.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                DefaultTextStyle(
                  style: theme.textTheme.titleLarge!.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  child: title!,
                ),
              if (title != null && content != null)
                const SizedBox(height: Sp.x4),
              if (content != null)
                Flexible(
                  child: SingleChildScrollView(
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      child: content!,
                    ),
                  ),
                ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: Sp.x5),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: Sp.x2,
                  runSpacing: Sp.x2,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Like `showDialog`, with a soft blurred scrim and a scale-fade entrance.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: Motion.of(context, Motion.base),
    pageBuilder: (ctx, _, _) => SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.curve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}
