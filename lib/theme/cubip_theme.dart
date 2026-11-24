import 'package:material_ui/material_ui.dart';

/// Paleta Atlas de Cubip. El tema oscuro es el predeterminado.
/// El cian #14B8C8 es solo acento, no texto sobre fondos claros.
abstract final class CubipColors {
  static const Color navy = Color(0xFF0B1F3A);
  static const Color navyRaised = Color(0xFF233754);
  static const Color navySunken = Color(0xFF071422);
  static const Color cyan = Color(0xFF14B8C8);
  static const Color cyanSoft = Color(0xFF71D6E0);
  static const Color paper = Color(0xFFF5F7FA);
  static const Color steel = Color(0xFF4A5568);
  static const Color secondary = Color(0xFFA9B5CA);
  static const Color muted = Color(0xFFA0ADC0);
  static const Color border = Color(0xFF6D84A3);
  static const Color danger = Color(0xFFE85D4C);
  static const Color warning = Color(0xFFE8B400);
}

abstract final class CubipTheme {
  static const String displayFamily = 'Sora';
  static const String bodyFamily = 'IBMPlexSans';

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: CubipColors.cyan,
      onPrimary: CubipColors.navy,
      secondary: CubipColors.cyanSoft,
      onSecondary: CubipColors.navy,
      surface: CubipColors.navy,
      onSurface: CubipColors.paper,
      error: CubipColors.danger,
      onError: CubipColors.paper,
      outline: CubipColors.border,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: CubipColors.navy,
      fontFamily: bodyFamily,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        fontFamily: bodyFamily,
        bodyColor: CubipColors.paper,
        displayColor: CubipColors.paper,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: CubipColors.navy,
        foregroundColor: CubipColors.paper,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: displayFamily,
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: CubipColors.paper,
        ),
      ),
      cardTheme: CardThemeData(
        color: CubipColors.navyRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: CubipColors.border, width: 0.6),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: CubipColors.navyRaised,
        indicatorColor: Color(0x3314B8C8),
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CubipColors.cyan,
          foregroundColor: CubipColors.navy,
          textStyle: const TextStyle(
            fontFamily: displayFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CubipColors.cyanSoft,
          side: const BorderSide(color: CubipColors.border),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: CubipColors.cyan,
        thumbColor: CubipColors.cyanSoft,
      ),
      dividerColor: CubipColors.border,
    );
  }
}
