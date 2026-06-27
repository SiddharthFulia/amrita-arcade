import 'package:flutter/material.dart';
import '../models/style.dart';
import '../../../theme/app_theme.dart';

/// Lists of swatches the picker shows. Each list ALWAYS has its options in
/// the same order: the first 2 of each category are the "free" defaults.
class OutfitCatalog {
  OutfitCatalog._();

  static const List<StyleOption> hair = [
    StyleOption(id: 'h_long_brown',  label: 'long brown',   emoji: '👩🏻',  color: Color(0xFF6B4226), kind: CategoryKind.hair),
    StyleOption(id: 'h_long_black',  label: 'long black',   emoji: '👩🏽',  color: Color(0xFF1A1414), kind: CategoryKind.hair),
    StyleOption(id: 'h_blonde',      label: 'blonde wave',  emoji: '👱‍♀️', color: Color(0xFFE8C275), kind: CategoryKind.hair),
    StyleOption(id: 'h_red',         label: 'red bob',      emoji: '🦰',   color: Color(0xFFB54A2E), kind: CategoryKind.hair),
    StyleOption(id: 'h_curly',       label: 'curly',        emoji: '👩‍🦱', color: Color(0xFF3A2418), kind: CategoryKind.hair),
    StyleOption(id: 'h_pink',        label: 'pink dye',     emoji: '💗',   color: AppTheme.rose,     kind: CategoryKind.hair),
    StyleOption(id: 'h_lav',         label: 'lavender',     emoji: '💜',   color: AppTheme.lavender, kind: CategoryKind.hair),
    StyleOption(id: 'h_silver',      label: 'silver',       emoji: '👩‍🦳', color: Color(0xFFD8D8E8), kind: CategoryKind.hair),
  ];

  static const List<StyleOption> top = [
    StyleOption(id: 't_rose_dress', label: 'rose dress',    emoji: '👗', color: AppTheme.rose,       kind: CategoryKind.top),
    StyleOption(id: 't_white_tee',  label: 'white tee',     emoji: '👕', color: Color(0xFFF6EEFB),   kind: CategoryKind.top),
    StyleOption(id: 't_blouse',     label: 'silk blouse',   emoji: '👚', color: AppTheme.lavender,   kind: CategoryKind.top),
    StyleOption(id: 't_blazer',     label: 'gold blazer',   emoji: '🧥', color: AppTheme.gold,       kind: CategoryKind.top),
    StyleOption(id: 't_sweater',    label: 'cozy sweater',  emoji: '🧶', color: Color(0xFFE2A4B5),   kind: CategoryKind.top),
    StyleOption(id: 't_crop',       label: 'crop top',      emoji: '🎽', color: AppTheme.pink,       kind: CategoryKind.top),
    StyleOption(id: 't_kurta',      label: 'kurta',         emoji: '🥻', color: AppTheme.sky,        kind: CategoryKind.top),
    StyleOption(id: 't_jacket',     label: 'denim jacket',  emoji: '🧥', color: Color(0xFF4F6FA5),   kind: CategoryKind.top),
  ];

  static const List<StyleOption> bottom = [
    StyleOption(id: 'b_jeans',     label: 'blue jeans',  emoji: '👖', color: Color(0xFF3B5C8C), kind: CategoryKind.bottom),
    StyleOption(id: 'b_skirt',     label: 'mini skirt',  emoji: '👗', color: AppTheme.rose,     kind: CategoryKind.bottom),
    StyleOption(id: 'b_pleated',   label: 'pleated',     emoji: '🩱', color: AppTheme.lavender, kind: CategoryKind.bottom),
    StyleOption(id: 'b_shorts',    label: 'shorts',      emoji: '🩳', color: Color(0xFFE8C275), kind: CategoryKind.bottom),
    StyleOption(id: 'b_leggings',  label: 'leggings',    emoji: '🩲', color: Color(0xFF1A1414), kind: CategoryKind.bottom),
    StyleOption(id: 'b_gown',      label: 'long gown',   emoji: '👘', color: AppTheme.pink,     kind: CategoryKind.bottom),
    StyleOption(id: 'b_sari',      label: 'sari drape',  emoji: '🥻', color: AppTheme.gold,     kind: CategoryKind.bottom),
    StyleOption(id: 'b_tulle',     label: 'tulle skirt', emoji: '✨', color: Color(0xFFF8C8DC), kind: CategoryKind.bottom),
  ];

  static const List<StyleOption> shoes = [
    StyleOption(id: 's_heels',     label: 'rose heels',  emoji: '👠', color: AppTheme.rose,     kind: CategoryKind.shoes),
    StyleOption(id: 's_sneakers',  label: 'sneakers',    emoji: '👟', color: Color(0xFFF6EEFB), kind: CategoryKind.shoes),
    StyleOption(id: 's_boots',     label: 'ankle boots', emoji: '🥾', color: Color(0xFF3A2418), kind: CategoryKind.shoes),
    StyleOption(id: 's_flats',     label: 'gold flats',  emoji: '🥿', color: AppTheme.gold,     kind: CategoryKind.shoes),
    StyleOption(id: 's_sandals',   label: 'sandals',     emoji: '👡', color: Color(0xFFE2A4B5), kind: CategoryKind.shoes),
    StyleOption(id: 's_glass',     label: 'glass slipper', emoji: '🩰', color: AppTheme.sky,    kind: CategoryKind.shoes),
  ];

  static const List<StyleOption> accessory = [
    StyleOption(id: 'a_none',      label: 'none',        emoji: '✨', color: AppTheme.textDim,  kind: CategoryKind.accessory),
    StyleOption(id: 'a_shades',    label: 'sunglasses',  emoji: '🕶️', color: Color(0xFF1A1414), kind: CategoryKind.accessory),
    StyleOption(id: 'a_bag',       label: 'tote bag',    emoji: '👜', color: AppTheme.rose,     kind: CategoryKind.accessory),
    StyleOption(id: 'a_bow',       label: 'pink bow',    emoji: '🎀', color: AppTheme.pink,     kind: CategoryKind.accessory),
    StyleOption(id: 'a_lipstick',  label: 'red lips',    emoji: '💄', color: Color(0xFFD64545), kind: CategoryKind.accessory),
    StyleOption(id: 'a_crown',     label: 'gold crown',  emoji: '👑', color: AppTheme.gold,     kind: CategoryKind.accessory),
    StyleOption(id: 'a_rose',      label: 'rose pin',    emoji: '🌹', color: AppTheme.rose,     kind: CategoryKind.accessory),
    StyleOption(id: 'a_heart',     label: 'heart',       emoji: '💖', color: AppTheme.pink,     kind: CategoryKind.accessory),
  ];

  /// Lookup helpers — never returns null; falls back to the first option.
  static StyleOption byId(CategoryKind kind, String id) {
    final list = forKind(kind);
    for (final o in list) {
      if (o.id == id) return o;
    }
    return list.first;
  }

  static List<StyleOption> forKind(CategoryKind k) {
    switch (k) {
      case CategoryKind.hair:      return hair;
      case CategoryKind.top:       return top;
      case CategoryKind.bottom:    return bottom;
      case CategoryKind.shoes:     return shoes;
      case CategoryKind.accessory: return accessory;
      case CategoryKind.backdrop:  return const [];
    }
  }

  /// Total count of all unlockable swatches across categories. Used by the
  /// AppBar "💎 N/30 unlocked" badge.
  static int get totalCount =>
      hair.length + top.length + bottom.length + shoes.length + accessory.length;
}
