import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

/// Pong — single-phone vs AI or 2-player (vertical layout). Drag a paddle
/// up/down with your thumb. First to 7 wins. CustomPainter render with
/// gradient bg, glowing paddles, a haloed ball + dashed centre line. Tiny
/// haptics on hit, score and win — feels alive without being noisy.
class PongScreen extends StatefulWidget {
  const PongScreen({super.key});

  @override
  State<PongScreen> createState() => _PongScreenState();
}

enum _Mode { ai, twoPlayer }

class _PongScreenState extends State<PongScreen>
    with SingleTickerProviderStateMixin {
  static const int _winScore = 7;

  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;

  Size _size = Size.zero;

  // Paddle Y positions in fraction (0..1) of play-area height (centre of paddle).
  double _leftY = 0.5;
  double _rightY = 0.5;

  // Ball state in fractional coords.
  double _bx = 0.5, _by = 0.5;
  double _vx = 0, _vy = 0;

  int _leftScore = 0;
  int _rightScore = 0;
  bool _gameOver = false;
  String? _winner;

  _Mode _mode = _Mode.ai;
  final math.Random _rng = math.Random();

  // Tunables (fractions of play-area shorter side, mostly height).
  static const double _paddleW = 0.04;     // width of paddle (along Y)
  static const double _paddleH = 0.18;     // length of paddle (along X / wide axis)
  static const double _ballR = 0.018;
  static const double _baseSpeed = 0.55;   // fractions per second

  @override
  void initState() {
    super.initState();
    _resetBall(toRight: _rng.nextBool());
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _resetBall({required bool toRight}) {
    _bx = 0.5;
    _by = 0.5;
    // Random launch angle, biased toward horizontal motion.
    final double angle = (_rng.nextDouble() * 0.5 - 0.25) * math.pi; // -45..45 deg
    final double dir = toRight ? 1 : -1;
    _vx = dir * _baseSpeed * math.cos(angle);
    _vy = _baseSpeed * math.sin(angle);
  }

  void _onTick(Duration elapsed) {
    if (_gameOver) {
      _last = elapsed;
      return;
    }
    final double dt =
        _last == Duration.zero ? 0 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt == 0 || _size == Size.zero) return;

    // AI follows ball (only on left paddle when in AI mode — left = "Amrita",
    // right = "you"). Smooth, slightly imperfect — fun, not unbeatable.
    if (_mode == _Mode.ai) {
      final double targetY = _by;
      final double diff = targetY - _leftY;
      // ~75% of ball speed; clamp by max step.
      final double maxStep = 0.55 * dt;
      final double step = diff.abs() < maxStep ? diff : maxStep * diff.sign;
      _leftY = (_leftY + step).clamp(_paddleH / 2, 1 - _paddleH / 2);
    }

    // Move ball.
    _bx += _vx * dt;
    _by += _vy * dt;

    // Top / bottom walls (in 2P vertical layout the long axis is horizontal —
    // ball travels left-right; top/bottom of play area bounces).
    if (_by - _ballR < 0) {
      _by = _ballR;
      _vy = _vy.abs();
    } else if (_by + _ballR > 1) {
      _by = 1 - _ballR;
      _vy = -_vy.abs();
    }

    // Left paddle (player 2 / AI). Paddle is at x = _paddleW (centre).
    final double leftPaddleX = _paddleW;
    if (_bx - _ballR <= leftPaddleX + _paddleW / 2 &&
        _bx > leftPaddleX - _paddleW / 2 &&
        _vx < 0) {
      if ((_by - _leftY).abs() <= _paddleH / 2 + _ballR) {
        _reflect(paddleY: _leftY, toRight: true);
        HapticFeedback.lightImpact();
      }
    }

    // Right paddle. Centre at x = 1 - _paddleW.
    final double rightPaddleX = 1 - _paddleW;
    if (_bx + _ballR >= rightPaddleX - _paddleW / 2 &&
        _bx < rightPaddleX + _paddleW / 2 &&
        _vx > 0) {
      if ((_by - _rightY).abs() <= _paddleH / 2 + _ballR) {
        _reflect(paddleY: _rightY, toRight: false);
        HapticFeedback.lightImpact();
      }
    }

    // Goals.
    if (_bx < -0.02) {
      _rightScore += 1;
      HapticFeedback.mediumImpact();
      _afterPoint(toRight: false);
    } else if (_bx > 1.02) {
      _leftScore += 1;
      HapticFeedback.mediumImpact();
      _afterPoint(toRight: true);
    }

    setState(() {});
  }

  void _reflect({required double paddleY, required bool toRight}) {
    // Angle based on where it hit the paddle (centre = straight, edge = sharp).
    final double offset = ((_by - paddleY) / (_paddleH / 2)).clamp(-1.0, 1.0);
    final double angle = offset * (math.pi / 3); // up to 60deg
    // Speed scales slightly with rallies — re-derive from current magnitude.
    final double speed = math.min(
      1.1,
      math.sqrt(_vx * _vx + _vy * _vy) * 1.04,
    );
    final double dir = toRight ? 1 : -1;
    _vx = dir * speed * math.cos(angle);
    _vy = speed * math.sin(angle);
    // Nudge ball out of paddle so it doesn't re-trigger.
    if (toRight) {
      _bx = _paddleW + _paddleW / 2 + _ballR + 0.001;
    } else {
      _bx = 1 - _paddleW - _paddleW / 2 - _ballR - 0.001;
    }
  }

  void _afterPoint({required bool toRight}) {
    if (_leftScore >= _winScore || _rightScore >= _winScore) {
      _gameOver = true;
      _winner = _leftScore > _rightScore
          ? (_mode == _Mode.ai ? 'amrita wins' : 'p2 wins')
          : (_mode == _Mode.ai ? 'you win' : 'p1 wins');
      HapticFeedback.heavyImpact();
      return;
    }
    _resetBall(toRight: toRight);
  }

  void _restart() {
    setState(() {
      _leftScore = 0;
      _rightScore = 0;
      _gameOver = false;
      _winner = null;
      _leftY = 0.5;
      _rightY = 0.5;
      _resetBall(toRight: _rng.nextBool());
    });
  }

  void _setMode(_Mode m) {
    setState(() {
      _mode = m;
    });
    _restart();
  }

  void _onDragLeft(double dy, double height) {
    if (_mode == _Mode.ai) return; // AI controls the left paddle.
    setState(() {
      _leftY =
          (_leftY + dy / height).clamp(_paddleH / 2, 1 - _paddleH / 2);
    });
  }

  void _onDragRight(double dy, double height) {
    setState(() {
      _rightY =
          (_rightY + dy / height).clamp(_paddleH / 2, 1 - _paddleH / 2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final double safeBottom =
        MediaQuery.viewPaddingOf(context).bottom + 18;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('pong',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'restart',
            onPressed: _restart,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ModeBar(mode: _mode, onChanged: _setMode),
            _ScoreBar(
              leftLabel: _mode == _Mode.ai ? 'amrita' : 'p2',
              rightLabel: _mode == _Mode.ai ? 'you' : 'p1',
              left: _leftScore,
              right: _rightScore,
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom),
                child: LayoutBuilder(builder: (context, constraints) {
                  _size = constraints.biggest;
                  return Stack(
                    children: [
                      // The play area is the whole box; left half is player2/AI
                      // drag area, right half is player1 drag area.
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _PongPainter(
                            leftY: _leftY,
                            rightY: _rightY,
                            bx: _bx,
                            by: _by,
                            paddleW: _paddleW,
                            paddleH: _paddleH,
                            ballR: _ballR,
                          ),
                        ),
                      ),
                      // Left half drag.
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: _size.width / 2,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragUpdate: (d) =>
                              _onDragLeft(d.delta.dy, _size.height),
                        ),
                      ),
                      // Right half drag.
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: _size.width / 2,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragUpdate: (d) =>
                              _onDragRight(d.delta.dy, _size.height),
                        ),
                      ),
                      if (_gameOver)
                        Positioned.fill(
                          child: _GameOverCard(
                            title: _winner ?? '',
                            score:
                                '$_leftScore  —  $_rightScore',
                            onRestart: _restart,
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;
  const _ModeBar({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          _chip('vs amrita', _Mode.ai),
          const SizedBox(width: 8),
          _chip('2-player', _Mode.twoPlayer),
        ],
      ),
    );
  }

  Widget _chip(String label, _Mode m) {
    final bool active = mode == m;
    return GestureDetector(
      onTap: () => onChanged(m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.rose.withValues(alpha: 0.16) : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppTheme.rose : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppTheme.rose : AppTheme.textDim,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final String leftLabel, rightLabel;
  final int left, right;
  const _ScoreBar({
    required this.leftLabel,
    required this.rightLabel,
    required this.left,
    required this.right,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          _side(leftLabel, left, AppTheme.lavender),
          const SizedBox(width: 12),
          const Text('vs',
              style: TextStyle(
                color: AppTheme.textDim,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(width: 12),
          _side(rightLabel, right, AppTheme.rose),
        ],
      ),
    );
  }

  Widget _side(String label, int score, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                  color: c,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                )),
            Text('$score',
                style: const TextStyle(
                  color: AppTheme.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                )),
          ],
        ),
      ),
    );
  }
}

class _GameOverCard extends StatelessWidget {
  final String title;
  final String score;
  final VoidCallback onRestart;
  const _GameOverCard({
    required this.title,
    required this.score,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElev,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.rose.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (r) => AppTheme.amrita.createShader(r),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(score,
                style: const TextStyle(
                  color: AppTheme.textDim,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onRestart,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.rose,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
              ),
              child: const Text('play again',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PongPainter extends CustomPainter {
  final double leftY, rightY, bx, by, paddleW, paddleH, ballR;
  _PongPainter({
    required this.leftY,
    required this.rightY,
    required this.bx,
    required this.by,
    required this.paddleW,
    required this.paddleH,
    required this.ballR,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;

    // Gradient background.
    final Paint bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF150C1F), Color(0xFF0B0710), Color(0xFF1A0F22)],
      ).createShader(bounds);
    final RRect rrect = RRect.fromRectAndRadius(bounds, const Radius.circular(16));
    canvas.drawRRect(rrect, bg);

    // Border.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppTheme.border,
    );

    // Dashed centre line (vertical).
    final double cx = size.width / 2;
    const double dashH = 10, gapH = 8;
    final Paint dashPaint = Paint()
      ..color = AppTheme.lavender.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (double y = 8; y < size.height - 8; y += dashH + gapH) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + dashH), dashPaint);
    }

    // Paddles. paddleW is fraction of width for x-extent, paddleH fraction
    // of height for y-extent.
    final double pwPx = paddleW * size.width;
    final double phPx = paddleH * size.height;

    _drawPaddle(
      canvas,
      Rect.fromCenter(
        center: Offset(paddleW * size.width, leftY * size.height),
        width: pwPx,
        height: phPx,
      ),
      AppTheme.lavender,
    );
    _drawPaddle(
      canvas,
      Rect.fromCenter(
        center: Offset((1 - paddleW) * size.width, rightY * size.height),
        width: pwPx,
        height: phPx,
      ),
      AppTheme.rose,
    );

    // Ball with halo.
    final Offset ballCenter = Offset(bx * size.width, by * size.height);
    final double rPx = ballR * size.height;
    canvas.drawCircle(
      ballCenter,
      rPx * 2.2,
      Paint()
        ..color = AppTheme.rose.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(ballCenter, rPx, Paint()..color = Colors.white);
  }

  void _drawPaddle(Canvas canvas, Rect r, Color color) {
    final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
    // Glow.
    canvas.drawRRect(
      rr.inflate(3),
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(rr, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _PongPainter old) =>
      old.leftY != leftY ||
      old.rightY != rightY ||
      old.bx != bx ||
      old.by != by;
}
