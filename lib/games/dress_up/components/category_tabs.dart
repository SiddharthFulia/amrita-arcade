import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/style.dart';
import '../../../theme/app_theme.dart';

/// Chip-row that picks which category the picker swatches show.
class CategoryTabs extends StatelessWidget {
  final CategoryKind selected;
  final ValueChanged<CategoryKind> onChanged;
  const CategoryTabs({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: CategoryKind.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final k = CategoryKind.values[i];
          final isOn = k == selected;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(k);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isOn ? AppTheme.rose.withValues(alpha: 0.22) : AppTheme.surfaceElev,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isOn ? AppTheme.rose : AppTheme.border,
                  width: isOn ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(k.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    k.label,
                    style: TextStyle(
                      color: isOn ? AppTheme.text : AppTheme.textDim,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
