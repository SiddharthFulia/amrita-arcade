import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// Direction the snake is currently heading. Up/Down are on the y-axis.
enum SnakeDir { up, down, left, right }

extension on SnakeDir {
  SnakeDir get opposite => switch (this) {
        SnakeDir.up => SnakeDir.down,
        SnakeDir.down => SnakeDir.up,
        SnakeDir.left => SnakeDir.right,
        SnakeDir.right => SnakeDir.left,
      };

  /// (dx, dy) on the integer grid. y grows downward.
  (int, int) get delta => switch (this) {
        SnakeDir.up => (0, -1),
        SnakeDir.down => (0, 1),
        SnakeDir.left => (-1, 0),
        SnakeDir.right => (1, 0),
      };
}

/// Snake game — 22x22 board, wraps on all four edges (infinite).
/// Cat-headed snake with rose→pink gradient body, glowing gold food.
class SnakeGame extends FlameGame {
  SnakeGame({
    required this.onScore,
    required this.onGameOver,
    int? initialBest,
  }) : best = initialBest ?? 0;

  // ── board ──────────────────────────────────────────────────────────
  static const int cols = 22;
  static const int rows = 22;

  // ── speed ──────────────────────────────────────────────────────────
  static const double baseStepSeconds = 0.130; // 130ms per tile
  static const double minStepSeconds = 0.060;  // floor

  // ── callbacks ──────────────────────────────────────────────────────
  final void Function(int score) onScore;
  final void Function(int score, int best) onGameOver;

  // ── state ──────────────────────────────────────────────────────────
  /// Snake body. Index 0 is the head. Each entry is a grid cell.
  final List<Point<int>> _body = <Point<int>>[];
  SnakeDir _dir = SnakeDir.right;
  /// Up to 3 queued direction changes — so rapid swipes register.
  final List<SnakeDir> _turnQueue = <SnakeDir>[];
  Point<int> _food = const Point<int>(10, 10);

  int score = 0;
  int best;
  bool _alive = true;
  @override
  bool paused = false;
  double _stepAccum = 0;
  final math.Random _rng = math.Random();

  // ── lifecycle ──────────────────────────────────────────────────────
  @override
  Color backgroundColor() => AppTheme.bg;

  @override
  Future<void> onLoad() async {
    _reset();
  }

  void _reset() {
    _body
      ..clear()
      ..addAll(<Point<int>>[
        const Point<int>(6, 11),
        const Point<int>(5, 11),
        const Point<int>(4, 11),
      ]);
    _dir = SnakeDir.right;
    _turnQueue.clear();
    score = 0;
    _alive = true;
    paused = false;
    _stepAccum = 0;
    _placeFood();
    onScore(score);
  }

  void restart() => _reset();

  void togglePause() {
    if (!_alive) return;
    paused = !paused;
  }

  /// External input from the screen's swipe detector.
  void queueTurn(SnakeDir dir) {
    if (!_alive || paused) return;
    // Don't allow reversing into self.
    final SnakeDir effectiveLast =
        _turnQueue.isNotEmpty ? _turnQueue.last : _dir;
    if (dir == effectiveLast || dir == effectiveLast.opposite) return;
    if (_turnQueue.length >= 3) return;
    _turnQueue.add(dir);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_alive || paused) return;

    _stepAccum += dt;
    final double step = _currentStepSeconds;
    while (_stepAccum >= step) {
      _stepAccum -= step;
      _tick();
      if (!_alive) return;
    }
  }

  double get _currentStepSeconds {
    // 10ms faster per 10 food eaten, clamped.
    final double s = baseStepSeconds - (score ~/ 10) * 0.010;
    return s < minStepSeconds ? minStepSeconds : s;
  }

  void _tick() {
    if (_turnQueue.isNotEmpty) {
      _dir = _turnQueue.removeAt(0);
    }

    final (int dx, int dy) = _dir.delta;
    final Point<int> head = _body.first;
    final Point<int> next = Point<int>(
      (head.x + dx) % cols < 0 ? (head.x + dx) % cols + cols : (head.x + dx) % cols,
      (head.y + dy) % rows < 0 ? (head.y + dy) % rows + rows : (head.y + dy) % rows,
    );

    final bool ate = next == _food;

    // Self-collision check. If eating, we don't shrink, so tail still
    // occupies its cell — include it. If not eating, the tail will move,
    // so the tail cell is fair game.
    final int checkLen = ate ? _body.length : _body.length - 1;
    for (int i = 0; i < checkLen; i++) {
      if (_body[i] == next) {
        _die();
        return;
      }
    }

    _body.insert(0, next);
    if (ate) {
      score++;
      onScore(score);
      HapticFeedback.lightImpact();
      _placeFood();
    } else {
      _body.removeLast();
    }
  }

  void _die() {
    _alive = false;
    if (score > best) best = score;
    HapticFeedback.heavyImpact();
    onGameOver(score, best);
  }

  void _placeFood() {
    // Pick a random empty cell. Board is small (484 cells) so retry is fine.
    while (true) {
      final Point<int> p = Point<int>(_rng.nextInt(cols), _rng.nextInt(rows));
      if (!_body.contains(p)) {
        _food = p;
        return;
      }
    }
  }

  // ── render ─────────────────────────────────────────────────────────
  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final Size sz = size.toSize();
    // Inset board with a little breathing room.
    const double pad = 6;
    final double availW = sz.width - pad * 2;
    final double availH = sz.height - pad * 2;
    final double cell = math.min(availW / cols, availH / rows);
    final double boardW = cell * cols;
    final double boardH = cell * rows;
    final double ox = (sz.width - boardW) / 2;
    final double oy = (sz.height - boardH) / 2;

    // Board background.
    final Rect boardRect = Rect.fromLTWH(ox, oy, boardW, boardH);
    final Paint surfacePaint = Paint()..color = AppTheme.surface;
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect.inflate(2), const Radius.circular(12)),
      surfacePaint,
    );
    final Paint borderPaint = Paint()
      ..color = AppTheme.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect.inflate(2), const Radius.circular(12)),
      borderPaint,
    );

    // Subtle grid dots.
    final Paint dotPaint = Paint()..color = AppTheme.border.withValues(alpha: 0.35);
    for (int x = 0; x < cols; x++) {
      for (int y = 0; y < rows; y++) {
        final double cx = ox + x * cell + cell / 2;
        final double cy = oy + y * cell + cell / 2;
        canvas.drawCircle(Offset(cx, cy), 0.6, dotPaint);
      }
    }

    // Food — glowing gold dot.
    _drawFood(canvas, ox, oy, cell);

    // Snake body (tail → head so head paints on top).
    for (int i = _body.length - 1; i >= 0; i--) {
      final Point<int> seg = _body[i];
      final double t = _body.length == 1 ? 0 : i / (_body.length - 1);
      // Head=rose, tail=pink (so it's brightest at the head).
      final Color c = Color.lerp(AppTheme.rose, AppTheme.pink, t)!;
      final Rect r = Rect.fromLTWH(
        ox + seg.x * cell + 1.2,
        oy + seg.y * cell + 1.2,
        cell - 2.4,
        cell - 2.4,
      );
      final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(cell * 0.28));

      if (i == 0) {
        _drawHead(canvas, rr, r, cell);
      } else {
        final Paint p = Paint()..color = c;
        canvas.drawRRect(rr, p);
      }
    }
  }

  void _drawFood(Canvas canvas, double ox, double oy, double cell) {
    final double cx = ox + _food.x * cell + cell / 2;
    final double cy = oy + _food.y * cell + cell / 2;
    // Glow.
    final Paint glow = Paint()
      ..color = AppTheme.gold.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(cx, cy), cell * 0.55, glow);
    // Core.
    final Paint core = Paint()..color = AppTheme.gold;
    canvas.drawCircle(Offset(cx, cy), cell * 0.32, core);
    // Highlight.
    final Paint hi = Paint()..color = const Color(0xFFFFF4C2);
    canvas.drawCircle(
      Offset(cx - cell * 0.08, cy - cell * 0.08),
      cell * 0.10,
      hi,
    );
  }

  void _drawHead(Canvas canvas, RRect rr, Rect r, double cell) {
    // Body of the head — brighter rose with a slight glow.
    final Paint headGlow = Paint()
      ..color = AppTheme.rose.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(rr, headGlow);
    final Paint headPaint = Paint()..color = AppTheme.rose;
    canvas.drawRRect(rr, headPaint);

    // Cat ears — two little triangles on top of the head, rotated to face dir.
    canvas.save();
    canvas.translate(r.center.dx, r.center.dy);
    canvas.rotate(_headRotation);
    final double half = cell / 2 - 1.2;

    final Path earL = Path()
      ..moveTo(-half * 0.7, -half * 0.85)
      ..lineTo(-half * 0.25, -half * 1.25)
      ..lineTo(-half * 0.10, -half * 0.55)
      ..close();
    final Path earR = Path()
      ..moveTo(half * 0.10, -half * 0.55)
      ..lineTo(half * 0.25, -half * 1.25)
      ..lineTo(half * 0.70, -half * 0.85)
      ..close();
    final Paint earPaint = Paint()..color = AppTheme.rose;
    canvas.drawPath(earL, earPaint);
    canvas.drawPath(earR, earPaint);
    // Inner ear (pink).
    final Path innerL = Path()
      ..moveTo(-half * 0.50, -half * 0.85)
      ..lineTo(-half * 0.28, -half * 1.10)
      ..lineTo(-half * 0.20, -half * 0.70)
      ..close();
    final Path innerR = Path()
      ..moveTo(half * 0.20, -half * 0.70)
      ..lineTo(half * 0.28, -half * 1.10)
      ..lineTo(half * 0.50, -half * 0.85)
      ..close();
    final Paint innerPaint = Paint()..color = AppTheme.pink;
    canvas.drawPath(innerL, innerPaint);
    canvas.drawPath(innerR, innerPaint);

    // Eyes.
    final Paint eyeWhite = Paint()..color = const Color(0xFFFFF6FB);
    final Paint pupil = Paint()..color = const Color(0xFF0B0710);
    final double eyeR = cell * 0.13;
    final double pupilR = cell * 0.06;
    final double eyeY = -cell * 0.06;
    final double eyeX = cell * 0.18;
    canvas.drawCircle(Offset(-eyeX, eyeY), eyeR, eyeWhite);
    canvas.drawCircle(Offset(eyeX, eyeY), eyeR, eyeWhite);
    canvas.drawCircle(Offset(-eyeX, eyeY), pupilR, pupil);
    canvas.drawCircle(Offset(eyeX, eyeY), pupilR, pupil);

    canvas.restore();
  }

  double get _headRotation => switch (_dir) {
        SnakeDir.up => 0,
        SnakeDir.right => math.pi / 2,
        SnakeDir.down => math.pi,
        SnakeDir.left => -math.pi / 2,
      };
}

/// Tiny int Point — Flame's `Vector2` is double-based, and we want exact
/// equality on grid cells.
class Point<T extends num> {
  final T x;
  final T y;
  const Point(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is Point<T> && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}
