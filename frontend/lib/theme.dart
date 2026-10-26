import 'package:flutter/material.dart';

/// Brand colours and shared theme for DevMate AI.
class Brand {
  static const primary = Color(0xFF6366F1); // indigo
  static const accent = Color(0xFF22D3EE); // cyan
  static const high = Color(0xFFEF4444);
  static const medium = Color(0xFFF59E0B);
  static const low = Color(0xFF3B82F6);
  static const good = Color(0xFF10B981);
  static const gradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFF22D3EE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static Color severity(String? s) => switch (s) { 'high' => high, 'medium' => medium, 'low' => low, _ => Colors.grey };

  static Color score(num? s) {
    if (s == null) return Colors.grey;
    if (s >= 85) return good;
    if (s >= 70) return const Color(0xFF84CC16);
    if (s >= 55) return medium;
    return high;
  }

  static const languageColors = [
    Color(0xFF6366F1), Color(0xFF22D3EE), Color(0xFFF59E0B), Color(0xFF10B981),
    Color(0xFFEC4899), Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF14B8A6),
  ];
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.primary,
    brightness: b,
    surface: dark ? const Color(0xFF0F1117) : const Color(0xFFF7F8FC),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF171A23) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: dark ? const Color(0xFF262A36) : const Color(0xFFE6E8F0)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF171A23) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: dark ? const Color(0xFF262A36) : const Color(0xFFE6E8F0)),
      ),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
