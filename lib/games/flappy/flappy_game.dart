import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart'
    show
        Alignment,
        Colors,
        FontWeight,
        LinearGradient,
        TextAlign,
        TextDirection,
        TextPainter,
        TextSpan,
        TextStyle;
import 'package:flutter/services.dart' show HapticFeedback;

import '../../theme/app_theme.dart';

/// Flappy bird with a rose-gold butterfly and parallax stars.
///
/// Pick: render everything in `FlameGame.render()` rather than splitting the
/// bird/pipes/stars into `PositionComponent`s. The game only has ~30 stars,
/// 2-3 pipe pairs, and one bird on screen at once — components would be
/// overkill and `render(canvas)` keeps all state visible in one file.
class FlappyGame extends FlameGame with TapCallbacks {
  FlappyGame({
    required this.onScore,
    required this.onDeath,
    required this.initialBest,
  });

  final void Function(int score) onScore;
  final void Function(int score, int best) onDeath;
  final int initialBest;

  // tunables
  static const double _gravity = 1400;          // px/s^2
  static const double _flapImpulse = -430;      // px/s (negative = up)
  static const double _pipeSpeed = 160;         // px/s
  static const double _pipeWidth = 70;
  static const double _gapSize = 170;           // vertical opening
  static const double _birdRadius = 18;
  static const double _groundHeight = 60;

  // state
  final _rand = math.Random();
  late double _birdX;
  double _birdY = 0;
  double _vy = 0;
  double _rotation = 0;
  final List<_Pipe> _pipes = [];
  final List<_Star> _stars = [];
  double _spawnTimer = 0;
  final double _spawnInterval = 1.6; // seconds — tuned to ~70% screen-height gap
  int _score = 0;
  int _best = 0;
  _Phase _phase = _Phase.idle;
  double _groundOffset = 0;

  int get score => _score;
  int get best => _best;
  bool get isIdle => _phase == _Phase.idle;
  bool get isDead => _phase == _Phase.dead;

  @override
  Future<void> onLoad() async {
    _best = initialBest;
    _birdX = size.x * 0.28;
    _birdY = size.y * 0.45;
    _seedStars();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x > 0 && size.y > 0) {
      _birdX = size.x * 0.28;
      if (_phase == _Phase.idle) {
        _birdY = size.y * 0.45;
      }
      if (_stars.isEmpty) _seedStars();
    }
  }

  void _seedStars() {
    _stars.clear();
    for (var i = 0; i < 30; i++) {
      _stars.add(_Star(
        x: _rand.nextDouble() * size.x,
        y: _rand.nextDouble() * size.y,
        r: 0.6 + _rand.nextDouble() * 1.8,
        speed: 8 + _rand.nextDouble() * 32,
        twinkle: _rand.nextDouble() * math.pi * 2,
      ));
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (_phase == _Phase.dead) return;       // ignore taps after death (no tap-trap)
    if (_phase == _Phase.idle) {
      _phase = _Phase.flying;
      _pipes.clear();
      _spawnTimer = 0;
      _score = 0;
      onScore(_score);
    }
    _vy = _flapImpulse;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_phase == _Phase.dead) return;

    // stars always drift
    for (final s in _stars) {
      s.x -= s.speed * dt;
      s.twinkle += dt * 2;
      if (s.x < -2) {
        s.x = size.x + 2;
        s.y = _rand.nextDouble() * size.y;
      }
    }
    _groundOffset = (_groundOffset + _pipeSpeed * dt) % 24;

    if (_phase == _Phase.idle) {
      // gentle bob while waiting for first tap
      _birdY = size.y * 0.45 + math.sin(_groundOffset / 24 * math.pi * 2) * 6;
      _rotation = 0;
      return;
    }

    // physics
    _vy += _gravity * dt;
    _birdY += _vy * dt;
    _rotation = (_vy / 600).clamp(-0.5, 1.1);

    // spawn pipes
    _spawnTimer += dt;
    if (_spawnTimer >= _spawnInterval) {
      _spawnTimer = 0;
      final minGapY = 80.0;
      final maxGapY = size.y - _groundHeight - 80 - _gapSize;
      final gapY = minGapY + _rand.nextDouble() * math.max(20.0, maxGapY - minGapY);
      _pipes.add(_Pipe(x: size.x + _pipeWidth, gapY: gapY));
    }

    // move pipes + score
    for (final p in _pipes) {
      p.x -= _pipeSpeed * dt;
      if (!p.passed && p.x + _pipeWidth < _birdX - _birdRadius) {
        p.passed = true;
        _score += 1;
        HapticFeedback.selectionClick();
        onScore(_score);
      }
    }
    _pipes.removeWhere((p) => p.x + _pipeWidth < -10);

    // collisions
    if (_birdY - _birdRadius < 0 ||
        _birdY + _birdRadius > size.y - _groundHeight) {
      _die();
      return;
    }
    final birdRect = Rect.fromCircle(
      center: Offset(_birdX, _birdY),
      radius: _birdRadius - 2,
    );
    for (final p in _pipes) {
      final top = Rect.fromLTWH(p.x, 0, _pipeWidth, p.gapY);
      final bot = Rect.fromLTWH(
        p.x,
        p.gapY + _gapSize,
        _pipeWidth,
        size.y - _groundHeight - (p.gapY + _gapSize),
      );
      if (birdRect.overlaps(top) || birdRect.overlaps(bot)) {
        _die();
        return;
      }
    }
  }

  void _die() {
    if (_phase == _Phase.dead) return;
    _phase = _Phase.dead;
    HapticFeedback.heavyImpact();
    if (_score > _best) _best = _score;
    onDeath(_score, _best);
  }

  /// Called from the screen when the user taps "fly again".
  void restart() {
    _phase = _Phase.idle;
    _pipes.clear();
    _spawnTimer = 0;
    _score = 0;
    _vy = 0;
    _birdY = size.y * 0.45;
    onScore(_score);
  }

  // ───────────────────────── render ─────────────────────────

  @override
  void render(Canvas canvas) {
    _drawSky(canvas);
    _drawStars(canvas);
    _drawPipes(canvas);
    _drawGround(canvas);
    _drawBird(canvas);
    if (_phase == _Phase.idle) _drawHint(canvas);
    super.render(canvas);
  }

  void _drawSky(Canvas canvas) {
    final rect = Offset.zero & Size(size.x, size.y);
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF1A0F2E),  // deep indigo
          Color(0xFF2A1444),  // amrita purple
          Color(0xFF3D1A4B),  // dusky plum
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _drawStars(Canvas canvas) {
    for (final s in _stars) {
      final alpha = 0.45 + 0.45 * math.sin(s.twinkle).abs();
      final paint = Paint()
        ..color = AppTheme.gold.withValues(alpha: alpha * (s.r / 2.4))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
      canvas.drawCircle(Offset(s.x, s.y), s.r, paint);
    }
  }

  void _drawPipes(Canvas canvas) {
    for (final p in _pipes) {
      final topRect = Rect.fromLTWH(p.x, 0, _pipeWidth, p.gapY);
      final botRect = Rect.fromLTWH(
        p.x,
        p.gapY + _gapSize,
        _pipeWidth,
        size.y - _groundHeight - (p.gapY + _gapSize),
      );

      final body = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF166534),  // dark green
            Color(0xFF22C55E),  // bright green
            Color(0xFF15803D),  // mid green
          ],
          stops: [0.0, 0.45, 1.0],
        ).createShader(topRect);
      canvas.drawRect(topRect, body);
      canvas.drawRect(botRect, body);

      // edge highlights
      final hi = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(p.x + 8, 0),
        Offset(p.x + 8, p.gapY),
        hi,
      );
      canvas.drawLine(
        Offset(p.x + 8, p.gapY + _gapSize),
        Offset(p.x + 8, size.y - _groundHeight),
        hi,
      );

      // caps (the classic flappy cap, slightly wider)
      const capH = 22.0;
      const capW = _pipeWidth + 8;
      final topCap = Rect.fromLTWH(p.x - 4, p.gapY - capH, capW, capH);
      final botCap = Rect.fromLTWH(p.x - 4, p.gapY + _gapSize, capW, capH);
      final capPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF14532D), Color(0xFF22C55E), Color(0xFF14532D)],
        ).createShader(topCap);
      canvas.drawRRect(_capRRect(topCap), capPaint);
      canvas.drawRRect(_capRRect(botCap), capPaint);
      // cap outline
      final capStroke = Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawRRect(_capRRect(topCap), capStroke);
      canvas.drawRRect(_capRRect(botCap), capStroke);
    }
  }

  RRect _capRRect(Rect r) =>
      RRect.fromRectAndRadius(r, const Radius.circular(4));

  void _drawGround(Canvas canvas) {
    final groundTop = size.y - _groundHeight;
    final rect = Rect.fromLTWH(0, groundTop, size.x, _groundHeight);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppTheme.rose.withValues(alpha: 0.35),
          AppTheme.lavender.withValues(alpha: 0.25),
          AppTheme.bg,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);

    // scrolling tick marks for motion cue
    final tickPaint = Paint()
      ..color = AppTheme.gold.withValues(alpha: 0.35)
      ..strokeWidth = 2;
    for (double x = -_groundOffset; x < size.x; x += 24) {
      canvas.drawLine(
        Offset(x, groundTop + 6),
        Offset(x + 10, groundTop + 6),
        tickPaint,
      );
    }
  }

  void _drawBird(Canvas canvas) {
    canvas.save();
    canvas.translate(_birdX, _birdY);
    canvas.rotate(_rotation);

    // rose-gold gradient body
    final bodyRect = Rect.fromCircle(center: Offset.zero, radius: _birdRadius);
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppTheme.gold, AppTheme.rose, AppTheme.lavender],
      ).createShader(bodyRect);
    canvas.drawCircle(Offset.zero, _birdRadius, bodyPaint);

    // soft glow
    final glow = Paint()
      ..color = AppTheme.rose.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset.zero, _birdRadius + 2, glow);

    // butterfly emoji on top — readable + cute
    final tp = TextPainter(
      text: const TextSpan(
        text: '🦋',
        style: TextStyle(fontSize: 22),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));

    canvas.restore();
  }

  void _drawHint(Canvas canvas) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'tap to flap',
        style: TextStyle(
          color: Color(0xFFF6EEFB),
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.x - tp.width) / 2, size.y * 0.28),
    );
  }
}

enum _Phase { idle, flying, dead }

class _Pipe {
  _Pipe({required this.x, required this.gapY});
  double x;
  double gapY;
  bool passed = false;
}

class _Star {
  _Star({
    required this.x,
    required this.y,
    required this.r,
    required this.speed,
    required this.twinkle,
  });
  double x, y, r, speed, twinkle;
}
