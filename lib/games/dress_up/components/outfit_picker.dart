import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/style.dart';
import '../data/outfits.dart';
import '../../../theme/app_theme.dart';

/// Horizontal swatch row for the currently-selected category. Locked items
/// render greyed with 🔒 — tapping them is a no-op.
class OutfitPicker extends StatelessWidget {
  final CategoryKind kind;
  final String selectedId;
  final Set<String> unlocked;
  final void Function(StyleOption option) onPick;

  const OutfitPicker({
    super.key,
    required this.kind,
    required this.selectedId,
    required this.unlocked,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final options = OutfitCatalog.forKind(kind);
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final o = options[i];
          final isLocked = !unlocked.contains(o.id);
          final isOn = o.id == selectedId;
          return _Swatch(
            option: o,
            selected: isOn,
            locked: isLocked,
            onTap: () {
              if (isLocked) return;
              HapticFeedback.selectionClick();
              onPick(o);
            },
          );
        },
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final StyleOption option;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  const _Swatch({
    required this.option,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final base = locked ? AppTheme.textMuted : option.color;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: base.withValues(alpha: locked ? 0.25 : 0.85),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppTheme.gold : AppTheme.border,
                width: selected ? 2.2 : 1.0,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppTheme.gold.withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              locked ? '🔒' : option.emoji,
              style: const TextStyle(fontSize: 24),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: locked ? AppTheme.textMuted : AppTheme.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
