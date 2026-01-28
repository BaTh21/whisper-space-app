import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isDarkMode = false;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _isDarkMode = brightness == Brightness.dark;
    _themeMode = ThemeMode.system;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;

    if (mode == ThemeMode.light) {
      _isDarkMode = false;
    } else if (mode == ThemeMode.dark) {
      _isDarkMode = true;
    } else {
      final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      _isDarkMode = brightness == Brightness.dark;
    }

    notifyListeners();
  }

  void toggleTheme(bool isDark) {
    _isDarkMode = isDark;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  ThemeData get currentTheme {
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;

    if (_themeMode == ThemeMode.system) {
      return brightness == Brightness.dark ? _buildDarkTheme() : _buildLightTheme();
    }

    return _isDarkMode ? _buildDarkTheme() : _buildLightTheme();
  }

  // ── Light Theme ───────────────────────────────────────────────────────────────
  ThemeData _buildLightTheme() {
    const double radius = 16.0;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: const Color(0xFF7C3AED),
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFEDE9FE),
        onPrimaryContainer: const Color(0xFF1E0F4F),
        secondary: const Color(0xFF10B981),
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFD1FAE5),
        surface: const Color(0xFFF9FAFB),
        onSurface: const Color(0xFF111827),
        error: const Color(0xFFEF4444),
        onError: Colors.white,
        surfaceContainerHighest: const Color(0xFFF3F4F6),
      ),
      scaffoldBackgroundColor: const Color(0xFFF9FAFB),

      // Cards
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: const Color(0x0F000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ).copyWith(
          elevation: WidgetStateProperty.all(0),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF7C3AED),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF7C3AED),
          side: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),

      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 2.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2.2),
        ),
      ),

      // Chips
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        backgroundColor: const Color(0xFFF3F4F6),
        selectedColor: const Color(0xFF7C3AED),
        labelStyle: const TextStyle(color: Color(0xFF374151)),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        checkmarkColor: Colors.white,
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF111827),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFF111827),
        ),
        iconTheme: IconThemeData(color: Color(0xFF111827)),
      ),

      // Navigation Bar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFEDE9FE),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF7C3AED),
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6B7280),
          );
        }),
      ),

      // FAB
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        shape: CircleBorder(),
      ),

      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: Color(0xFFF3F4F6),
        thickness: 1,
        space: 0,
      ),
    );
  }

  // ── Dark Theme ────────────────────────────────────────────────────────────────
  ThemeData _buildDarkTheme() {
    const double radius = 16.0;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFFA78BFA),
        onPrimary: const Color(0xFF111827),
        primaryContainer: const Color(0xFF4C1D95),
        onPrimaryContainer: const Color(0xFFE9D5FF),
        secondary: const Color(0xFF34D399),
        onSecondary: const Color(0xFF111827),
        secondaryContainer: const Color(0xFF065F46),
        surface: const Color(0xFF111827),
        onSurface: Colors.white,
        error: const Color(0xFFF87171),
        onError: const Color(0xFF111827),
        surfaceContainerHighest: const Color(0xFF374151),
      ),
      scaffoldBackgroundColor: const Color(0xFF111827),

      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF1F2937),
        surfaceTintColor: const Color(0xFF1F2937),
        shadowColor: const Color(0x1AFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFA78BFA),
          foregroundColor: const Color(0xFF111827),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFFA78BFA),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFA78BFA),
          side: const BorderSide(color: Color(0xFFA78BFA)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1F2937),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFF374151), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFF374151), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFFA78BFA), width: 2.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFFF87171), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: Color(0xFFF87171), width: 2.2),
        ),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        backgroundColor: const Color(0xFF374151),
        selectedColor: const Color(0xFFA78BFA),
        labelStyle: const TextStyle(color: Color(0xFFD1D5DB)),
        secondaryLabelStyle: const TextStyle(color: Color(0xFF111827)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        checkmarkColor: const Color(0xFF111827),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1F2937),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Color(0xFF1F2937),
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF1F2937),
        indicatorColor: const Color(0xFF4C1D95).withValues(alpha: 0.3),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFA78BFA),
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF9CA3AF),
          );
        }),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFFA78BFA),
        foregroundColor: Color(0xFF111827),
        shape: CircleBorder(),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1F2937),
        surfaceTintColor: const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),

      dividerTheme: const DividerThemeData(
        color: Color(0xFF374151),
        thickness: 1,
        space: 0,
      ),
    );
  }
}