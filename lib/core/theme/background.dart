import 'dart:io';

import 'package:flutter/material.dart';

import 'glass_tokens.dart';

/// What sits at the very bottom of the app, below the glass.
enum BackgroundStyle {
  /// The default soft blue / violet / teal glow.
  aurora,
  sunset,
  ocean,
  forest,
  graphite,

  /// A picture the user picked (Android; the Windows shell has no picker).
  image;

  bool get isPreset => this != image;

  static BackgroundStyle fromName(Object? name) => BackgroundStyle.values
      .firstWhere((s) => s.name == name, orElse: () => BackgroundStyle.aurora);
}

/// Base colour plus three light pools for one preset and brightness.
@immutable
class BackgroundPalette {
  const BackgroundPalette({
    required this.base,
    required this.a,
    required this.b,
    required this.c,
  });

  final Color base;
  final Color a;
  final Color b;
  final Color c;

  @override
  bool operator ==(Object other) =>
      other is BackgroundPalette &&
      other.base == base &&
      other.a == a &&
      other.b == b &&
      other.c == c;

  @override
  int get hashCode => Object.hash(base, a, b, c);

  /// Palette of [style] for the brightness of [g]. [BackgroundStyle.aurora] is
  /// the theme's own glow, so the default look stays defined in one place
  /// ([GlassColors]); a picture falls back to it when it cannot be shown.
  static BackgroundPalette of(BackgroundStyle style, GlassColors g) {
    final dark = g.isDark;
    return switch (style) {
      BackgroundStyle.aurora || BackgroundStyle.image => BackgroundPalette(
        base: g.base,
        a: g.glowA,
        b: g.glowB,
        c: g.glowC,
      ),
      BackgroundStyle.sunset =>
        dark
            ? const BackgroundPalette(
                base: Color(0xFF160E12),
                a: Color(0xFFFF6B4A),
                b: Color(0xFFD6336C),
                c: Color(0xFFFFA94D),
              )
            : const BackgroundPalette(
                base: Color(0xFFF8EDE8),
                a: Color(0xFFFFA07A),
                b: Color(0xFFFF8FB1),
                c: Color(0xFFFFD27F),
              ),
      BackgroundStyle.ocean =>
        dark
            ? const BackgroundPalette(
                base: Color(0xFF08131A),
                a: Color(0xFF0EA5E9),
                b: Color(0xFF2563EB),
                c: Color(0xFF06B6D4),
              )
            : const BackgroundPalette(
                base: Color(0xFFE6F1F8),
                a: Color(0xFF6CC4FF),
                b: Color(0xFF7C9BFF),
                c: Color(0xFF7EE6E0),
              ),
      BackgroundStyle.forest =>
        dark
            ? const BackgroundPalette(
                base: Color(0xFF0B140F),
                a: Color(0xFF22C55E),
                b: Color(0xFF65A30D),
                c: Color(0xFF14B8A6),
              )
            : const BackgroundPalette(
                base: Color(0xFFE9F3EA),
                a: Color(0xFF86E0A0),
                b: Color(0xFFC6E97F),
                c: Color(0xFF7FD9C4),
              ),
      BackgroundStyle.graphite =>
        dark
            ? const BackgroundPalette(
                base: Color(0xFF0E0F12),
                a: Color(0xFF52576B),
                b: Color(0xFF3B3F52),
                c: Color(0xFF6B7280),
              )
            : const BackgroundPalette(
                base: Color(0xFFECEDF0),
                a: Color(0xFFB8BDCB),
                b: Color(0xFFD3D6DF),
                c: Color(0xFFC4C9D4),
              ),
    };
  }
}

/// The picture at [path], decoded at no more than [maxSide] px on its long
/// side, or `null` for an empty path. The file name is new for every pick (the
/// native side writes a fresh name), so the image cache never serves a stale
/// picture.
ImageProvider? backgroundImageProvider(String path, {int maxSide = 2560}) {
  if (path.isEmpty) return null;
  return ResizeImage(
    FileImage(File(path)),
    width: maxSide,
    height: maxSide,
    policy: ResizeImagePolicy.fit,
    allowUpscaling: false,
  );
}
