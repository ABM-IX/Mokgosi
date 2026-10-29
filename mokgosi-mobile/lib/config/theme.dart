import 'package:flutter/material.dart';

/// Colours shared with the responder console: warm neutrals, a deep blue taken from the flag of
/// Botswana, and a red kept for SOS and destructive actions only.
class MokgosiColors {
  static const background = Color(0xFFF6F5F1);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFEFEDE7);
  static const border = Color(0xFFE1DED6);
  static const ink = Color(0xFF1B1E22);
  static const inkMuted = Color(0xFF575D64);
  static const inkFaint = Color(0xFF878C92);
  static const accent = Color(0xFF245E8C);
  static const accentSoft = Color(0xFFE6EEF5);
  static const danger = Color(0xFFB3261E);
  static const dangerSoft = Color(0xFFFBECEB);
  static const success = Color(0xFF2D6A4C);
  static const successSoft = Color(0xFFE6F1EB);
  static const warning = Color(0xFF7A520C);
  static const warningSoft = Color(0xFFFBF3DD);
}

ThemeData buildMokgosiTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: MokgosiColors.accent,
    onPrimary: Colors.white,
    primaryContainer: MokgosiColors.accentSoft,
    onPrimaryContainer: MokgosiColors.accent,
    secondary: MokgosiColors.inkMuted,
    onSecondary: Colors.white,
    secondaryContainer: MokgosiColors.surfaceMuted,
    onSecondaryContainer: MokgosiColors.ink,
    error: MokgosiColors.danger,
    onError: Colors.white,
    errorContainer: MokgosiColors.dangerSoft,
    onErrorContainer: MokgosiColors.danger,
    surface: MokgosiColors.surface,
    onSurface: MokgosiColors.ink,
    onSurfaceVariant: MokgosiColors.inkMuted,
    surfaceContainerLowest: MokgosiColors.surface,
    surfaceContainerLow: MokgosiColors.surface,
    surfaceContainer: MokgosiColors.surfaceMuted,
    surfaceContainerHigh: MokgosiColors.surfaceMuted,
    surfaceContainerHighest: MokgosiColors.surfaceMuted,
    outline: MokgosiColors.border,
    outlineVariant: MokgosiColors.border,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  // Start from Material's type scale so overrides keep the platform font family.
  final type = ThemeData(useMaterial3: true, colorScheme: scheme).textTheme;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: MokgosiColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: MokgosiColors.background,
      foregroundColor: MokgosiColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: type.titleLarge?.copyWith(color: MokgosiColors.ink, fontSize: 20, fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: MokgosiColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: MokgosiColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: shape,
        textStyle: type.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: shape,
        foregroundColor: MokgosiColors.ink,
        side: const BorderSide(color: Color(0xFFCBC7BD)),
        textStyle: type.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MokgosiColors.accent,
        textStyle: type.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MokgosiColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFCBC7BD)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: MokgosiColors.accent, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(color: MokgosiColors.border, thickness: 1, space: 1),
    listTileTheme: const ListTileThemeData(iconColor: MokgosiColors.inkMuted),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: MokgosiColors.surface,
      indicatorColor: MokgosiColors.accentSoft,
      surfaceTintColor: Colors.transparent,
      height: 68,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MokgosiColors.ink,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: MokgosiColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
