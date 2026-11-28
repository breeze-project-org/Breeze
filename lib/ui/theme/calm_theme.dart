import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// 活泼、轻盈、低攻击性的 6 套 Seed 主题色。
enum CalmSeed {
  sky('晴空', Color(0xFF2B8CEE)),
  mint('薄荷', Color(0xFF18A883)),
  coral('珊瑚', Color(0xFFE86655)),
  tangerine('柑橘', Color(0xFFE5811C)),
  iris('鸢尾', Color(0xFF675FEA)),
  sakura('樱粉', Color(0xFFDC5788));

  const CalmSeed(this.label, this.swatch);

  final String label;
  final Color swatch;
}

/// 信息密度档位。
enum CalmDensity {
  compact('紧凑'),
  comfortable('舒适');

  const CalmDensity(this.label);

  final String label;
}

/// 语义与表面色令牌，挂在 ThemeData.extensions 中供全量基础组件直接读取。
@immutable
class CalmColors extends ThemeExtension<CalmColors> {
  const CalmColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surfaceHover,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentFg,
    required this.accentSoft,
    required this.accentBorder,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.shadowColor,
    required this.density,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surfaceHover;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accentFg;
  final Color accentSoft;
  final Color accentBorder;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color shadowColor;
  final CalmDensity density;

  bool get isCompact => density == CalmDensity.compact;

  double get rowVPadding => isCompact ? 8 : 11;

  List<BoxShadow> get shadowSm => [
    BoxShadow(
      color: shadowColor.withValues(alpha: 0.045),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: shadowColor.withValues(alpha: 0.03),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];

  List<BoxShadow> get shadowMd => [
    BoxShadow(
      color: shadowColor.withValues(alpha: 0.11),
      blurRadius: 28,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: shadowColor.withValues(alpha: 0.05),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static CalmColors resolve({
    required Brightness brightness,
    CalmSeed seed = CalmSeed.sky,
    Color? seedColor,
    bool isAmoled = false,
    CalmDensity density = CalmDensity.compact,
  }) {
    final isDark = brightness == Brightness.dark;
    final palette = _resolvePalette(
      seed: seed,
      seedColor: seedColor,
      isDark: isDark,
    );
    // AMOLED 纯黑仅在深色下生效：底色压到 #000，浮层仍保留一档极夜蓝灰，
    // 避免卡片与画布糊成一片。
    final amoled = isDark && isAmoled;
    final bg = amoled ? Colors.black : palette.bg;
    final surface = amoled
        ? const Color(0xFF10131A)
        : isDark
        ? const Color(0xFF1B202E)
        : Colors.white;
    final surface2 = amoled ? const Color(0xFF191E2A) : palette.surface2;

    if (isDark) {
      return CalmColors(
        bg: bg,
        surface: surface,
        surface2: surface2,
        surfaceHover: Color.alphaBlend(
          Colors.white.withValues(alpha: 0.06),
          surface2,
        ),
        border: Colors.white.withValues(alpha: 0.07),
        borderStrong: Colors.white.withValues(alpha: 0.14),
        text: const Color(0xFFF1F5F9),
        text2: const Color(0xFFA5B4CB),
        text3: const Color(0xFF6E7F99),
        accent: palette.accent,
        accentFg: palette.accentFg,
        accentSoft: palette.accent.withValues(alpha: 0.16),
        accentBorder: palette.accent.withValues(alpha: 0.30),
        success: const Color(0xFF4ADE80),
        successSoft: const Color(0xFF4ADE80).withValues(alpha: 0.15),
        warning: const Color(0xFFFBBF24),
        warningSoft: const Color(0xFFFBBF24).withValues(alpha: 0.16),
        danger: const Color(0xFFFB7185),
        dangerSoft: const Color(0xFFFB7185).withValues(alpha: 0.16),
        shadowColor: Colors.black,
        density: density,
      );
    }

    return CalmColors(
      bg: bg,
      surface: surface,
      surface2: surface2,
      surfaceHover: Color.alphaBlend(
        const Color(0xFF0F172A).withValues(alpha: 0.045),
        surface2,
      ),
      border: const Color(0xFF0F172A).withValues(alpha: 0.06),
      borderStrong: const Color(0xFF0F172A).withValues(alpha: 0.12),
      text: const Color(0xFF1E293B),
      text2: const Color(0xFF52627A),
      text3: const Color(0xFF8C9BB0),
      accent: palette.accent,
      accentFg: palette.accentFg,
      accentSoft: palette.accent.withValues(alpha: 0.11),
      accentBorder: palette.accent.withValues(alpha: 0.24),
      success: const Color(0xFF10B981),
      successSoft: const Color(0xFF10B981).withValues(alpha: 0.12),
      warning: const Color(0xFFD97706),
      warningSoft: const Color(0xFFF59E0B).withValues(alpha: 0.15),
      danger: const Color(0xFFE11D48),
      dangerSoft: const Color(0xFFF43F5E).withValues(alpha: 0.12),
      shadowColor: const Color(0xFF0F172A),
      density: density,
    );
  }

  /// 选择调色板：优先精调预设，其次按任意主色派生同一套通透视感。
  static _SeedToken _resolvePalette({
    required CalmSeed seed,
    required bool isDark,
    Color? seedColor,
  }) {
    if (seedColor == null) return _seedTokens(seed, isDark);
    // 动态取色常常正好落在某套内置 Seed 上，此时直接用人工调过的预设。
    for (final candidate in CalmSeed.values) {
      if (candidate.swatch.toARGB32() == seedColor.toARGB32()) {
        return _seedTokens(candidate, isDark);
      }
    }
    return _deriveTokens(seedColor, isDark);
  }

  /// 任意主色派生：保留色相，只钳制饱和度与亮度，保证轻盈通透且不刺眼。
  ///
  /// 只做「上限压制」而不拉高饱和度：用户选的低饱和/近灰色主色不会被
  /// 凭空造出鲜艳色相（灰主色保持中性），高饱和主色则收敛到柔和一档。
  static _SeedToken _deriveTokens(Color seedColor, bool isDark) {
    final hsl = HSLColor.fromColor(seedColor);
    if (isDark) {
      final accent = hsl
          .withSaturation(hsl.saturation.clamp(0.0, 0.62).toDouble())
          .withLightness(hsl.lightness.clamp(0.66, 0.74).toDouble())
          .toColor();
      final accentFg = HSLColor.fromColor(accent)
          .withSaturation((hsl.saturation * 0.7).clamp(0.0, 0.55).toDouble())
          .withLightness(0.12)
          .toColor();
      return _SeedToken(
        bg: Color.alphaBlend(
          accent.withValues(alpha: 0.06),
          const Color(0xFF131720),
        ),
        surface2: Color.alphaBlend(
          accent.withValues(alpha: 0.09),
          const Color(0xFF212736),
        ),
        accent: accent,
        accentFg: accentFg,
      );
    }

    final accent = hsl
        .withSaturation(hsl.saturation.clamp(0.0, 0.72).toDouble())
        .withLightness(hsl.lightness.clamp(0.42, 0.50).toDouble())
        .toColor();
    // 浅色主按钮默认配纯白字（与 6 套精调 CalmSeed 预设保持一致，避免蓝/绿/橙色
    // 因纯数学对比度偏向深墨字而显得发暗发脏）；仅极亮黄/浅柠等高亮度色才切深墨字。
    final useDarkFg = accent.computeLuminance() >= 0.52;
    return _SeedToken(
      bg: Color.alphaBlend(accent.withValues(alpha: 0.04), Colors.white),
      surface2: Color.alphaBlend(accent.withValues(alpha: 0.09), Colors.white),
      accent: accent,
      accentFg: useDarkFg ? const Color(0xFF0B1929) : Colors.white,
    );
  }

  static _SeedToken _seedTokens(CalmSeed seed, bool isDark) {
    switch (seed) {
      case CalmSeed.sky:
        return isDark
            ? const _SeedToken(
                bg: Color(0xFF131823),
                surface2: Color(0xFF232B3E),
                accent: Color(0xFF68B5FF),
                accentFg: Color(0xFF0B1929),
              )
            : const _SeedToken(
                bg: Color(0xFFF6F9FD),
                surface2: Color(0xFFEDF3FA),
                accent: Color(0xFF2B8CEE),
                accentFg: Colors.white,
              );
      case CalmSeed.mint:
        return isDark
            ? const _SeedToken(
                bg: Color(0xFF121B1A),
                surface2: Color(0xFF20302E),
                accent: Color(0xFF4FD8B2),
                accentFg: Color(0xFF0A1F19),
              )
            : const _SeedToken(
                bg: Color(0xFFF5FBF9),
                surface2: Color(0xFFEAF5F1),
                accent: Color(0xFF18A883),
                accentFg: Colors.white,
              );
      case CalmSeed.coral:
        return isDark
            ? const _SeedToken(
                bg: Color(0xFF1D1517),
                surface2: Color(0xFF312327),
                accent: Color(0xFFFF9688),
                accentFg: Color(0xFF29100D),
              )
            : const _SeedToken(
                bg: Color(0xFFFDF8F7),
                surface2: Color(0xFFF9EFEA),
                accent: Color(0xFFE86655),
                accentFg: Colors.white,
              );
      case CalmSeed.tangerine:
        return isDark
            ? const _SeedToken(
                bg: Color(0xFF1C1712),
                surface2: Color(0xFF30271E),
                accent: Color(0xFFFFB562),
                accentFg: Color(0xFF261706),
              )
            : const _SeedToken(
                bg: Color(0xFFFDF9F4),
                surface2: Color(0xFFF8F1E7),
                accent: Color(0xFFE5811C),
                accentFg: Colors.white,
              );
      case CalmSeed.iris:
        return isDark
            ? const _SeedToken(
                bg: Color(0xFF151624),
                surface2: Color(0xFF25273D),
                accent: Color(0xFFA19BFF),
                accentFg: Color(0xFF13112B),
              )
            : const _SeedToken(
                bg: Color(0xFFF7F7FE),
                surface2: Color(0xFFEFEFFA),
                accent: Color(0xFF675FEA),
                accentFg: Colors.white,
              );
      case CalmSeed.sakura:
        return isDark
            ? const _SeedToken(
                bg: Color(0xFF1D141A),
                surface2: Color(0xFF31212B),
                accent: Color(0xFFFF92B9),
                accentFg: Color(0xFF290D18),
              )
            : const _SeedToken(
                bg: Color(0xFFFDF7FA),
                surface2: Color(0xFFF9EEF3),
                accent: Color(0xFFDC5788),
                accentFg: Colors.white,
              );
    }
  }

  @override
  CalmColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surfaceHover,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accentFg,
    Color? accentSoft,
    Color? accentBorder,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? shadowColor,
    CalmDensity? density,
  }) {
    return CalmColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      accent: accent ?? this.accent,
      accentFg: accentFg ?? this.accentFg,
      accentSoft: accentSoft ?? this.accentSoft,
      accentBorder: accentBorder ?? this.accentBorder,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      shadowColor: shadowColor ?? this.shadowColor,
      density: density ?? this.density,
    );
  }

  @override
  CalmColors lerp(ThemeExtension<CalmColors>? other, double t) {
    if (other is! CalmColors) return this;
    return CalmColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentFg: Color.lerp(accentFg, other.accentFg, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      accentBorder: Color.lerp(accentBorder, other.accentBorder, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      density: t < 0.5 ? density : other.density,
    );
  }
}

class _SeedToken {
  const _SeedToken({
    required this.bg,
    required this.surface2,
    required this.accent,
    required this.accentFg,
  });

  final Color bg;
  final Color surface2;
  final Color accent;
  final Color accentFg;
}

class CalmTheme {
  const CalmTheme._();

  static (String?, List<String>) _platformFontConfig() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return (
          'Microsoft YaHei UI',
          const ['Microsoft YaHei', 'Segoe UI', 'Noto Sans CJK SC'],
        );
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
        return (
          'PingFang SC',
          const ['.SF Pro Text', 'Hiragino Sans GB', 'Noto Sans CJK SC'],
        );
      case TargetPlatform.linux:
        return (
          'Noto Sans CJK SC',
          const ['WenQuanYi Micro Hei', 'Droid Sans Fallback'],
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return (
          null,
          const ['Noto Sans CJK SC', 'HarmonyOS Sans SC', 'MiSans'],
        );
    }
  }

  static ThemeData build({
    required Brightness brightness,
    CalmSeed seed = CalmSeed.sky,
    CalmDensity density = CalmDensity.compact,
    Color? seedColor,
    bool isAmoled = false,
    InteractiveInkFeatureFactory? splashFactory = NoSplash.splashFactory,
    TextTheme Function(TextTheme)? textThemeTransform,
  }) {
    final (fontFamily, fontFamilyFallback) = _platformFontConfig();
    final calm = CalmColors.resolve(
      brightness: brightness,
      seed: seed,
      seedColor: seedColor,
      isAmoled: isAmoled,
      density: density,
    );
    final baseScheme =
        ColorScheme.fromSeed(
          seedColor: seedColor ?? seed.swatch,
          brightness: brightness,
        ).copyWith(
          primary: calm.accent,
          onPrimary: calm.accentFg,
          surface: calm.bg,
          onSurface: calm.text,
          onSurfaceVariant: calm.text2,
          outline: calm.borderStrong,
          outlineVariant: calm.border,
          error: calm.danger,
        );

    final textTheme = TextTheme(
      titleLarge: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: calm.text,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: calm.text,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: calm.text,
      ),
      bodyMedium: TextStyle(fontSize: 12.5, color: calm.text, height: 1.45),
      bodySmall: TextStyle(fontSize: 11.5, color: calm.text2, height: 1.4),
      labelSmall: TextStyle(fontSize: 10.5, color: calm.text3),
    ).apply(fontFamily: fontFamily, fontFamilyFallback: fontFamilyFallback);

    final theme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: calm.bg,
      cardColor: calm.surface,
      canvasColor: calm.surface,
      dividerColor: calm.border,
      dialogTheme: DialogThemeData(backgroundColor: calm.surface),
      chipTheme: ChipThemeData(backgroundColor: calm.surface2),
      appBarTheme: AppBarTheme(
        backgroundColor: calm.bg,
        foregroundColor: calm.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      tabBarTheme: const TabBarThemeData(dividerColor: Colors.transparent),
      // 默认去掉水波纹：墨水屏不会糊残影，其他平台也更克制。
      splashFactory: splashFactory,
      highlightColor: Colors.transparent,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: calm.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: calm.borderStrong),
          boxShadow: calm.shadowMd,
        ),
        textStyle: TextStyle(
          fontSize: 11.5,
          color: calm.text,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
      ),
      extensions: [calm],
      textTheme: textTheme,
    );

    if (textThemeTransform == null) return theme;
    // 挂载宿主应用的自定义字体（如 Breeze 的 FontProfileController）：
    // 必须对 ThemeData 合并后的字阶做变换，否则只会作用到预设的 6 个样式。
    return theme.copyWith(
      textTheme: textThemeTransform(theme.textTheme),
      primaryTextTheme: textThemeTransform(theme.primaryTextTheme),
    );
  }
}

extension CalmThemeContextX on BuildContext {
  CalmColors get calm =>
      Theme.of(this).extension<CalmColors>() ??
      CalmColors.resolve(brightness: Brightness.light, seed: CalmSeed.sky);
}

/// 统一 CJK / 拉丁混排的居中行高配置，避免 Windows 微软雅黑在胶囊内偏下。
const TextHeightBehavior kCalmTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
  leadingDistribution: TextLeadingDistribution.even,
);

StrutStyle calmStrut(double fontSize, {double height = 1.2}) {
  return StrutStyle(
    fontSize: fontSize,
    height: height,
    leadingDistribution: TextLeadingDistribution.even,
    forceStrutHeight: true,
  );
}
