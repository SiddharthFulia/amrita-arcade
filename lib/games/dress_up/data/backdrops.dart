import 'package:flutter/material.dart';
import '../models/style.dart';
import '../../../theme/app_theme.dart';

/// Named gradient backdrops that sit behind both dolls.
class BackdropCatalog {
  BackdropCatalog._();

  static const List<Backdrop> all = [
    Backdrop(
      id: 'rose_sunset',
      label: 'rose sunset',
      emoji: '🌹',
      colors: [Color(0xFFFFB7D2), AppTheme.rose, AppTheme.lavender],
    ),
    Backdrop(
      id: 'beach_blue',
      label: 'beach',
      emoji: '🏖️',
      colors: [AppTheme.sky, Color(0xFF60A5FA), Color(0xFFFCD9A8)],
    ),
    Backdrop(
      id: 'cafe_warm',
      label: 'café',
      emoji: '☕',
      colors: [Color(0xFF6B4226), Color(0xFFB07A4B), Color(0xFFF1D9A5)],
    ),
    Backdrop(
      id: 'picnic_green',
      label: 'picnic',
      emoji: '🧺',
      colors: [Color(0xFF7BCB8A), Color(0xFFB7E4A5), Color(0xFFFFF3B0)],
    ),
    Backdrop(
      id: 'movie_noir',
      label: 'movie noir',
      emoji: '🎬',
      colors: [Color(0xFF1A0F22), Color(0xFF35224A), AppTheme.lavender],
    ),
    Backdrop(
      id: 'night_roses',
      label: 'night roses',
      emoji: '🌙',
      colors: [Color(0xFF1A0F22), AppTheme.rose, AppTheme.pink],
    ),
  ];

  static Backdrop byId(String id) {
    for (final b in all) {
      if (b.id == id) return b;
    }
    return all.first;
  }
}
