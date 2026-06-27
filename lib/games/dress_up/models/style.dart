import 'package:flutter/material.dart';

/// Category of customisation a swatch belongs to.
enum CategoryKind { hair, top, bottom, shoes, accessory, backdrop }

extension CategoryKindX on CategoryKind {
  String get label {
    switch (this) {
      case CategoryKind.hair:      return 'hair';
      case CategoryKind.top:       return 'top';
      case CategoryKind.bottom:    return 'bottom';
      case CategoryKind.shoes:     return 'shoes';
      case CategoryKind.accessory: return 'accessory';
      case CategoryKind.backdrop:  return 'backdrop';
    }
  }

  String get emoji {
    switch (this) {
      case CategoryKind.hair:      return '💇‍♀️';
      case CategoryKind.top:       return '👚';
      case CategoryKind.bottom:    return '👖';
      case CategoryKind.shoes:     return '👠';
      case CategoryKind.accessory: return '👜';
      case CategoryKind.backdrop:  return '🌆';
    }
  }
}

/// A picker option — one swatch in the bottom sheet row.
@immutable
class StyleOption {
  final String id;
  final String label;
  final String emoji;       // small glyph shown on swatch / doll layer
  final Color color;        // the dominant tint used to paint that layer
  final CategoryKind kind;
  const StyleOption({
    required this.id,
    required this.label,
    required this.emoji,
    required this.color,
    required this.kind,
  });
}

/// A whole backdrop is a named gradient.
@immutable
class Backdrop {
  final String id;
  final String label;
  final String emoji;
  final List<Color> colors;
  const Backdrop({
    required this.id,
    required this.label,
    required this.emoji,
    required this.colors,
  });

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      );
}

/// Immutable snapshot of a single doll's look. Selecting `null` for a slot
/// means the doll wears the default for that layer.
@immutable
class AvatarStyle {
  final String hairId;
  final String topId;
  final String bottomId;
  final String shoesId;
  final String accessoryId;
  final Color skin;

  const AvatarStyle({
    required this.hairId,
    required this.topId,
    required this.bottomId,
    required this.shoesId,
    required this.accessoryId,
    required this.skin,
  });

  AvatarStyle copyWith({
    String? hairId,
    String? topId,
    String? bottomId,
    String? shoesId,
    String? accessoryId,
    Color? skin,
  }) {
    return AvatarStyle(
      hairId: hairId ?? this.hairId,
      topId: topId ?? this.topId,
      bottomId: bottomId ?? this.bottomId,
      shoesId: shoesId ?? this.shoesId,
      accessoryId: accessoryId ?? this.accessoryId,
      skin: skin ?? this.skin,
    );
  }

  AvatarStyle withSlot(CategoryKind k, String id) {
    switch (k) {
      case CategoryKind.hair:      return copyWith(hairId: id);
      case CategoryKind.top:       return copyWith(topId: id);
      case CategoryKind.bottom:    return copyWith(bottomId: id);
      case CategoryKind.shoes:     return copyWith(shoesId: id);
      case CategoryKind.accessory: return copyWith(accessoryId: id);
      case CategoryKind.backdrop:  return this; // backdrop isn't per-doll
    }
  }

  String slot(CategoryKind k) {
    switch (k) {
      case CategoryKind.hair:      return hairId;
      case CategoryKind.top:       return topId;
      case CategoryKind.bottom:    return bottomId;
      case CategoryKind.shoes:     return shoesId;
      case CategoryKind.accessory: return accessoryId;
      case CategoryKind.backdrop:  return '';
    }
  }

  Map<String, dynamic> toJson() => {
        'hair': hairId,
        'top': topId,
        'bottom': bottomId,
        'shoes': shoesId,
        'accessory': accessoryId,
        'skin': skin.toARGB32(),
      };

  static AvatarStyle fromJson(Map<String, dynamic> j, AvatarStyle fallback) {
    return AvatarStyle(
      hairId: (j['hair'] as String?) ?? fallback.hairId,
      topId: (j['top'] as String?) ?? fallback.topId,
      bottomId: (j['bottom'] as String?) ?? fallback.bottomId,
      shoesId: (j['shoes'] as String?) ?? fallback.shoesId,
      accessoryId: (j['accessory'] as String?) ?? fallback.accessoryId,
      skin: j['skin'] is int ? Color(j['skin'] as int) : fallback.skin,
    );
  }
}
