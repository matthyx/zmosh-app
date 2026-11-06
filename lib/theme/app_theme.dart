import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('theme_mode') ?? 'dark';
      _themeMode = mode == 'light' ? ThemeMode.light : ThemeMode.dark;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', isDark ? 'dark' : 'light');
    } catch (_) {}
  }
}

const darkTerminalTheme = TerminalTheme(
  cursor: Color(0xFFFFFFFF),
  selection: Color(0x40FFFFFF),
  foreground: Color(0xFFFFFFFF),
  background: Color(0xFF000000),
  black: Color(0xFF000000),
  red: Color(0xFFCD3131),
  green: Color(0xFF0DBC79),
  yellow: Color(0xFFE5E510),
  blue: Color(0xFF2472C8),
  magenta: Color(0xFFBC3FBC),
  cyan: Color(0xFF11A8CD),
  white: Color(0xFFE5E5E5),
  brightBlack: Color(0xFF666666),
  brightRed: Color(0xFFF14C4C),
  brightGreen: Color(0xFF23D18B),
  brightYellow: Color(0xFFF5F543),
  brightBlue: Color(0xFF3B8EEA),
  brightMagenta: Color(0xFFD670D6),
  brightCyan: Color(0xFF29B8DB),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFF404000),
  searchHitBackgroundCurrent: Color(0xFF804000),
  searchHitForeground: Color(0xFFFFFFFF),
);

/// High-contrast light / E-ink terminal theme
const lightTerminalTheme = TerminalTheme(
  cursor: Color(0xFF000000),
  selection: Color(0x30000000),
  foreground: Color(0xFF000000),
  background: Color(0xFFFFFFFF),
  black: Color(0xFF000000),
  red: Color(0xFFB00020),
  green: Color(0xFF007A33),
  yellow: Color(0xFF7A6800),
  blue: Color(0xFF003F9E),
  magenta: Color(0xFF7E1689),
  cyan: Color(0xFF00757E),
  white: Color(0xFFD0D0D0),
  brightBlack: Color(0xFF555555),
  brightRed: Color(0xFFD32F2F),
  brightGreen: Color(0xFF198754),
  brightYellow: Color(0xFF997A00),
  brightBlue: Color(0xFF0D6EFD),
  brightMagenta: Color(0xFF9C27B0),
  brightCyan: Color(0xFF0AA2C0),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFEB3B),
  searchHitBackgroundCurrent: Color(0xFFFF9800),
  searchHitForeground: Color(0xFF000000),
);
