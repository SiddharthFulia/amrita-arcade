import 'package:flutter/material.dart';
import '../models/style.dart';
import '../data/outfits.dart';
import '../../../theme/app_theme.dart';

/// The actual paper-doll. Rendered as a Stack so we get crisp emoji
/// overlays + custom-painted body shapes, with no PNG assets needed.
class AvatarDoll extends StatelessWidget {
  final AvatarStyle style;
  final bool isActive;
  final Color accent; // gold for "you", rose for "her"
  final String name;
  final VoidCallback onTap;

  const AvatarDoll({
    super.key,
    required this.style,
    required this.isActive,
    required this.accent,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hair      = OutfitCatalog.byId(CategoryKind.hair,      style.hairId);
    final top       = OutfitCatalog.byId(CategoryKind.top,       style.topId);
    final bottom    = OutfitCatalog.byId(CategoryKind.bottom,    style.bottomId);
    final shoes     = OutfitCatalog.byId(CategoryKind.shoes,     style.shoesId);
    final accessory = OutfitCatalog.byId(CategoryKind.accessory, style.accessoryId);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? accent : AppTheme.border,
            width: isActive ? 2.4 : 1.0,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
          color: AppTheme.surface.withValues(alpha: 0.35),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The doll canvas itself — fixed aspect, scales to width.
            AspectRatio(
              aspectRatio: 0.62,
              child: CustomPaint(
                painter: _DollPainter(
                  skin: style.skin,
                  hair: hair.color,
                  top: top.color,
                  bottom: bottom.color,
                  shoes: shoes.color,
                ),
                child: Stack(
                  children: [
                    // accessory overlay — near the head
                    Align(
                      alignment: const Alignment(0, -0.65),
                      child: Text(
                        accessory.id == 'a_none' ? '' : accessory.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                    // tiny sparkle near feet to feel cute
                    const Align(
                      alignment: Alignment(0.55, 0.95),
                      child: Text('✨', style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: accent.withValues(alpha: 0.5)),
              ),
              child: Text(
                name,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter for the actual body silhouette: head + hair wig + torso
/// (top) + legs (bottom) + shoes. Kept intentionally minimal so each color
/// swap is instantly visible.
class _DollPainter extends CustomPainter {
  final Color skin, hair, top, bottom, shoes;
  _DollPainter({
    required this.skin,
    required this.hair,
    required this.top,
    required this.bottom,
    required this.shoes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final skinPaint   = Paint()..color = skin;
    final hairPaint   = Paint()..color = hair;
    final topPaint    = Paint()..color = top;
    final bottomPaint = Paint()..color = bottom;
    final shoesPaint  = Paint()..color = shoes;

    // ─── neck (drawn first so torso covers its base) ─────────────────────
    final neckRect = Rect.fromCenter(
      center: Offset(cx, h * 0.30),
      width: w * 0.14,
      height: h * 0.08,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(neckRect, const Radius.circular(6)),
      skinPaint,
    );

    // ─── hair "back" — a wider blob behind the head ─────────────────────
    final hairBackRect = Rect.fromCenter(
      center: Offset(cx, h * 0.20),
      width: w * 0.62,
      height: h * 0.34,
    );
    canvas.drawOval(hairBackRect, hairPaint);

    // ─── head (skin oval) ───────────────────────────────────────────────
    final headRect = Rect.fromCenter(
      center: Offset(cx, h * 0.20),
      width: w * 0.42,
      height: h * 0.28,
    );
    canvas.drawOval(headRect, skinPaint);

    // ─── face details: simple eyes + smile ──────────────────────────────
    final eyePaint = Paint()..color = const Color(0xFF1A1414);
    canvas.drawCircle(Offset(cx - w * 0.07, h * 0.20), 2.2, eyePaint);
    canvas.drawCircle(Offset(cx + w * 0.07, h * 0.20), 2.2, eyePaint);
    final smile = Path()
      ..moveTo(cx - w * 0.05, h * 0.255)
      ..quadraticBezierTo(cx, h * 0.275, cx + w * 0.05, h * 0.255);
    canvas.drawPath(
      smile,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFB54A55),
    );

    // ─── hair fringe — small arc over forehead ──────────────────────────
    final fringe = Path()
      ..moveTo(cx - w * 0.21, h * 0.18)
      ..quadraticBezierTo(cx, h * 0.08, cx + w * 0.21, h * 0.18)
      ..lineTo(cx + w * 0.18, h * 0.15)
      ..quadraticBezierTo(cx, h * 0.10, cx - w * 0.18, h * 0.15)
      ..close();
    canvas.drawPath(fringe, hairPaint);

    // ─── torso / top (rounded trapezoid via path) ───────────────────────
    final torso = Path()
      ..moveTo(cx - w * 0.22, h * 0.34)
      ..quadraticBezierTo(cx - w * 0.30, h * 0.42, cx - w * 0.26, h * 0.55)
      ..lineTo(cx + w * 0.26, h * 0.55)
      ..quadraticBezierTo(cx + w * 0.30, h * 0.42, cx + w * 0.22, h * 0.34)
      ..close();
    canvas.drawPath(torso, topPaint);

    // ─── arms (skin) — small ellipses on either side ────────────────────
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - w * 0.30, h * 0.45),
        width: w * 0.10,
        height: h * 0.20,
      ),
      skinPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + w * 0.30, h * 0.45),
        width: w * 0.10,
        height: h * 0.20,
      ),
      skinPaint,
    );

    // ─── bottom (skirt / pants block) ───────────────────────────────────
    final skirt = Path()
      ..moveTo(cx - w * 0.26, h * 0.55)
      ..lineTo(cx + w * 0.26, h * 0.55)
      ..lineTo(cx + w * 0.32, h * 0.78)
      ..lineTo(cx - w * 0.32, h * 0.78)
      ..close();
    canvas.drawPath(skirt, bottomPaint);

    // ─── legs (skin) ────────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx - w * 0.10, h * 0.86),
          width: w * 0.10,
          height: h * 0.16,
        ),
        const Radius.circular(8),
      ),
      skinPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx + w * 0.10, h * 0.86),
          width: w * 0.10,
          height: h * 0.16,
        ),
        const Radius.circular(8),
      ),
      skinPaint,
    );

    // ─── shoes ──────────────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx - w * 0.10, h * 0.96),
          width: w * 0.14,
          height: h * 0.05,
        ),
        const Radius.circular(6),
      ),
      shoesPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx + w * 0.10, h * 0.96),
          width: w * 0.14,
          height: h * 0.05,
        ),
        const Radius.circular(6),
      ),
      shoesPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DollPainter old) {
    return old.skin != skin ||
        old.hair != hair ||
        old.top != top ||
        old.bottom != bottom ||
        old.shoes != shoes;
  }
}
