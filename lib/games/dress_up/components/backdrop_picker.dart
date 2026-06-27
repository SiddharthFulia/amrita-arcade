import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/backdrops.dart';
import '../models/style.dart';
import '../../../theme/app_theme.dart';

/// Backdrop chip-row — same shape as OutfitPicker but specialised so
/// the gradient preview shows on the swatch.
class BackdropPicker extends StatelessWidget {
  final String selectedId;
  final ValueChanged<Backdrop> onPick;
  const BackdropPicker({
    super.key,
    required this.selectedId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: BackdropCatalog.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final b = BackdropCatalog.all[i];
          final isOn = b.id == selectedId;
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onPick(b);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 76,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: b.gradient,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isOn ? AppTheme.gold : AppTheme.border,
                      width: isOn ? 2.2 : 1.0,
                    ),
                    boxShadow: isOn
                        ? [
                            BoxShadow(
                              color: AppTheme.gold.withValues(alpha: 0.35),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(b.emoji, style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 80,
                  child: Text(
                    b.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
