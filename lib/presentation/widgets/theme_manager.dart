import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class ThemeManager extends ChangeNotifier {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }

  void toggleTheme() {
    switch (_themeMode) {
      case ThemeMode.light:
        _themeMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        _themeMode = ThemeMode.system;
        break;
      case ThemeMode.system:
        _themeMode = ThemeMode.light;
        break;
    }
    notifyListeners();
  }

  IconData get themeIcon {
    switch (_themeMode) {
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
      case ThemeMode.system:
        return Icons.brightness_medium; // Half sun/moon icon for system/auto
    }
  }

  String get themeLabel {
    switch (_themeMode) {
      case ThemeMode.light:
        return 'common.light_theme'.tr();
      case ThemeMode.dark:
        return 'common.dark_theme'.tr();
      case ThemeMode.system:
        return 'common.system_theme'.tr();
    }
  }
}