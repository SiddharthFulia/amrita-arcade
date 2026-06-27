import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';

/// Breakout — paddle at bottom, drag to move. Ball bounces off paddle and
/// walls. Top of screen filled with rose / pink / lavender / sky / gold /
/// success-coloured brick rows. Hit → destroy + score. 3 lives. Ball
/// speed bumps every 8 bricks broken. Clearing the wall → next level (more
/// rows, slightly faster). Best score persisted in `breakout_best`.
class BreakoutScreen extends StatefulWidget {
  const BreakoutScreen({super.key});

  @override
  State<BreakoutScreen> createState() => _BreakoutScreenState();
}

class _Brick {
  final int row, col;
  bool alive = true;
  _Brick(this.row, this.col);
}

class _BreakoutScreenState extends State<BreakoutScreen>
    with SingleTickerProviderStateMixin {
  static const String _bestKey = 'breakout_best';

  static const int _cols = 10;
  static const int _baseRows = 6;
  static const double _paddleW = 0.20;     // fraction of width
  static const double _paddleH = 0.018;    // fraction of height
  static const double _ballR = 0.012;      // fraction of min(w,h) (we use width)
  static const double _topMargin = 0.10;   // 10% top reserved (above bricks)
  static const double _brickArea = 0.35;   // bricks fill from 0.10 .. 0.45 of height

  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  Size _size = Size.zero;
  final math.Random _rng = math.Random();

  // Paddle x (centre) in fraction.
  double _paddleX = 0.5;

  // Ball state (fractional).
  double _bx = 0.5, _by = 0.7;
  double _vx = 0, _vy = 0;

  int _rows = _baseRows;
  int _level = 1;
  int _score = 0;
  int _best = 0;
  int _lives = 3;
  int _brickStreak = 0; // counted within current life — for speed bumps
  bool _waitingForLaunch = true;
  bool _gameOver = false;
  bool _won = false;

  late List<_Brick> _bricks;

  @override
  void initState() {
    super.initState();
    _bricks = _buildBricks(_rows);
    _resetBall();
    _bootstrap();
    _ticker.start();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _best = prefs.getInt(_bestKey) ?? 0;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  List<_Brick> _buildBricks(int rows) {
    return [
      for (int r = 0; r < rows; r++)
        for (int c = 0; c < _cols; c++) _Brick(r, c),
    ];
  }

  void _resetBall() {
    _waitingForLaunch = true;
    _bx = _paddleX;
    _by = 1 - 0.06 - _paddleH - _ballR - 0.005;
    _vx = 0;
    _vy = 0;
  }

  void _launch() {
    if (!_waitingForLaunch) return;
    _waitingForLaunch = false;
    final double angle = (_rng.nextBool() ? -1 : 1) *
        (math.pi / 4 + _rng.nextDouble() * math.pi / 8);
    final double speed = _currentSpeed();
    _vx = speed * math.sin(angle);
    _vy = -speed * math.cos(angle);
  }

  double _currentSpeed() {
    // Base speed grows with level + with every 8 bricks broken.
    final double base = 0.55 + (_level - 1) * 0.05;
    final int bumps = _brickStreak ~/ 8;
    return math.min(1.3, base + bumps * 0.06);
  }

  void _onTick(Duration elapsed) {
    if (_gameOver || _won) {
      _last = elapsed;
      return;
    }
    final double dt =
        _last == Duration.zero ? 0 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt == 0 || _size == Size.zero) return;

    if (_waitingForLaunch) {
      _bx = _paddleX;
      setState(() {});
      return;
    }

    _bx += _vx * dt;
    _by += _vy * dt;

    // Walls.
    if (_bx - _ballR < 0) {
      _bx = _ballR;
      _vx = _vx.abs();
      HapticFeedback.selectionClick();
    } else if (_bx + _ballR > 1) {
      _bx = 1 - _ballR;
      _vx = -_vx.abs();
      HapticFeedback.selectionClick();
    }
    if (_by - _ballR < 0) {
      _by = _ballR;
      _vy = _vy.abs();
      HapticFeedback.selectionClick();
    }

    // Paddle. Centre at (_paddleX, 1 - 0.06).
    final double paddleCy = 1 - 0.06;
    final double paddleHalfW = _paddleW / 2;
    final double paddleHalfH = _paddleH / 2;
    if (_vy > 0 &&
        _by + _ballR >= paddleCy - paddleHalfH &&
        _by - _ballR <= paddleCy + paddleHalfH &&
        _bx >= _paddleX - paddleHalfW - _ballR &&
        _bx <= _paddleX + paddleHalfW + _ballR) {
      // Reflect — angle depends on contact point along paddle.
      final double offset =
          ((_bx - _paddleX) / paddleHalfW).clamp(-1.0, 1.0);
      final double angle = offset * (math.pi / 3); // up to 60deg from vertical
      final double speed = _currentSpeed();
      _vx = speed * math.sin(angle);
      _vy = -speed * math.cos(angle).abs();
      _by = paddleCy - paddleHalfH - _ballR - 0.001;
      HapticFeedback.lightImpact();
    }

    // Bricks.
    _checkBrickCollision();

    // Below paddle → lose life.
    if (_by - _ballR > 1.02) {
      _lives -= 1;
      HapticFeedback.mediumImpact();
      if (_lives <= 0) {
        _gameOver = true;
        _persistBest();
      } else {
        _resetBall();
      }
    }

    // Level cleared.
    if (_bricks.every((b) => !b.alive)) {
      _won = true;
      HapticFeedback.heavyImpact();
      _persistBest();
    }

    setState(() {});
  }

  Future<void> _persistBest() async {
    if (_score > _best) {
      _best = _score;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_bestKey, _best);
    }
  }

  void _checkBrickCollision() {
    if (_size == Size.zero) return;
    // Brick layout (in fractional coords).
    const double left = 0.02;
    const double right = 0.98;
    const double brickGap = 0.004;
    final double rowH = _brickArea / _rows;
    final double colW = (right - left) / _cols;
    // Bounding box of ball.
    for (final b in _bricks) {
      if (!b.alive) continue;
      final double x0 = left + b.col * colW + brickGap / 2;
      final double x1 = left + (b.col + 1) * colW - brickGap / 2;
      final double y0 = _topMargin + b.row * rowH + brickGap / 2;
      final double y1 = _topMargin + (b.row + 1) * rowH - brickGap / 2;
      // Circle-rect collision (closest point on rect).
      final double cx = _bx.clamp(x0, x1);
      final double cy = _by.clamp(y0, y1);
      final double dx = _bx - cx;
      final double dy = _by - cy;
      if (dx * dx + dy * dy <= _ballR * _ballR) {
        b.alive = false;
        _score += 10;
        _brickStreak += 1;
        // Reflect on the dominant axis.
        if (dx.abs() > dy.abs()) {
          _vx = -_vx;
          if (_bx < x0) {
            _bx = x0 - _ballR - 0.001;
          } else {
            _bx = x1 + _ballR + 0.001;
          }
        } else {
          _vy = -_vy;
          if (_by < y0) {
            _by = y0 - _ballR - 0.001;
          } else {
            _by = y1 + _ballR + 0.001;
          }
        }
        // Boost speed every 8 bricks.
        if (_brickStreak % 8 == 0) {
          final double newSpeed = _currentSpeed();
          final double cur =
              math.sqrt(_vx * _vx + _vy * _vy).clamp(0.0001, 99);
          _vx = _vx / cur * newSpeed;
          _vy = _vy / cur * newSpeed;
        }
        HapticFeedback.selectionClick();
        return; // one brick per frame is plenty
      }
    }
  }

  void _nextLevel() {
    setState(() {
      _level += 1;
      _rows = math.min(_baseRows + (_level - 1), 9);
      _bricks = _buildBricks(_rows);
      _won = false;
      _brickStreak = 0;
      _resetBall();
    });
  }

  void _restart() {
    setState(() {
      _level = 1;
      _rows = _baseRows;
      _bricks = _buildBricks(_rows);
      _score = 0;
      _lives = 3;
      _brickStreak = 0;
      _gameOver = false;
      _won = false;
      _resetBall();
    });
  }

  void _onDrag(double dx, double width) {
    if (width <= 0) return;
    setState(() {
      _paddleX =
          (_paddleX + dx / width).clamp(_paddleW / 2, 1 - _paddleW / 2);
      if (_waitingForLaunch) _bx = _paddleX;
    });
  }

  @override
  Widget build(BuildContext context) {
    final double safeBottom =
        MediaQuery.viewPaddingOf(context).bottom + 18;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('breakout',
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
            _StatsBar(
              score: _score,
              best: _best,
              lives: _lives,
              level: _level,
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom),
                child: LayoutBuilder(builder: (context, constraints) {
                  _size = constraints.biggest;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) =>
                        _onDrag(d.delta.dx, _size.width),
                    onTap: _waitingForLaunch ? _launch : null,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _BreakoutPainter(
                              bricks: _bricks,
                              rows: _rows,
                              cols: _cols,
                              paddleX: _paddleX,
                              paddleW: _paddleW,
                              paddleH: _paddleH,
                              bx: _bx,
                              by: _by,
                              ballR: _ballR,
                              topMargin: _topMargin,
                              brickArea: _brickArea,
                              waitingForLaunch: _waitingForLaunch,
                            ),
                          ),
                        ),
                        if (_gameOver)
                          Positioned.fill(
                            child: _OverlayCard(
                              title: 'game over',
                              subtitle:
                                  'score $_score   best $_best',
                              actionLabel: 'play again',
                              onAction: _restart,
                            ),
                          ),
                        if (_won)
                          Positioned.fill(
                            child: _OverlayCard(
                              title: 'level $_level cleared',
                              subtitle: 'score $_score',
                              actionLabel: 'next level',
                              onAction: _nextLevel,
                            ),
                          ),
                      ],
                    ),
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

class _StatsBar extends StatelessWidget {
  final int score, best, lives, level;
  const _StatsBar({
    required this.score,
    required this.best,
    required this.lives,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          _stat('score', '$score', AppTheme.rose),
          const SizedBox(width: 8),
          _stat('best', '$best', AppTheme.gold),
          const SizedBox(width: 8),
          _stat('lvl', '$level', AppTheme.lavender),
          const SizedBox(width: 8),
          _stat('lives', '$lives', AppTheme.success),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  color: c,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                )),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                )),
          ],
        ),
      ),
    );
  }
}

class _OverlayCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  const _OverlayCard({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
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
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(subtitle,
                style: const TextStyle(
                  color: AppTheme.textDim,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.rose,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
              ),
              child: Text(actionLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakoutPainter extends CustomPainter {
  final List<_Brick> bricks;
  final int rows, cols;
  final double paddleX, paddleW, paddleH;
  final double bx, by, ballR;
  final double topMargin, brickArea;
  final bool waitingForLaunch;

  static const List<Color> _rowColors = [
    AppTheme.rose,
    AppTheme.pink,
    AppTheme.lavender,
    AppTheme.sky,
    AppTheme.gold,
    AppTheme.success,
  ];

  _BreakoutPainter({
    required this.bricks,
    required this.rows,
    required this.cols,
    required this.paddleX,
    required this.paddleW,
    required this.paddleH,
    required this.bx,
    required this.by,
    required this.ballR,
    required this.topMargin,
    required this.brickArea,
    required this.waitingForLaunch,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    // Gradient bg.
    final Paint bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1A0F22), Color(0xFF0B0710)],
      ).createShader(bounds);
    final RRect rrect =
        RRect.fromRectAndRadius(bounds, const Radius.circular(16));
    canvas.drawRRect(rrect, bg);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = AppTheme.border,
    );

    // Bricks.
    const double left = 0.02;
    const double right = 0.98;
    const double brickGap = 0.004;
    final double rowH = brickArea / rows;
    final double colW = (right - left) / cols;

    for (final b in bricks) {
      if (!b.alive) continue;
      final double x0 = (left + b.col * colW + brickGap / 2) * size.width;
      final double x1 = (left + (b.col + 1) * colW - brickGap / 2) * size.width;
      final double y0 = (topMargin + b.row * rowH + brickGap / 2) * size.height;
      final double y1 =
          (topMargin + (b.row + 1) * rowH - brickGap / 2) * size.height;
      final Rect r = Rect.fromLTRB(x0, y0, x1, y1);
      final Color c = _rowColors[b.row % _rowColors.length];
      final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(4));
      // Subtle glow.
      canvas.drawRRect(
        rr.inflate(1.2),
        Paint()
          ..color = c.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Body with vertical shading.
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              c.withValues(alpha: 0.95),
              c.withValues(alpha: 0.70),
            ],
          ).createShader(r),
      );
    }

    // Paddle.
    final double pwPx = paddleW * size.width;
    final double phPx = paddleH * size.height;
    final Rect paddleRect = Rect.fromCenter(
      center: Offset(paddleX * size.width, (1 - 0.06) * size.height),
      width: pwPx,
      height: phPx,
    );
    final RRect prr =
        RRect.fromRectAndRadius(paddleRect, const Radius.circular(6));
    canvas.drawRRect(
      prr.inflate(3),
      Paint()
        ..color = AppTheme.rose.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      prr,
      Paint()
        ..shader = const LinearGradient(
          colors: [AppTheme.rose, AppTheme.pink],
        ).createShader(paddleRect),
    );

    // Ball.
    final Offset bc = Offset(bx * size.width, by * size.height);
    final double rPx = ballR * size.width;
    canvas.drawCircle(
      bc,
      rPx * 2.4,
      Paint()
        ..color = AppTheme.rose.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(bc, rPx, Paint()..color = Colors.white);

    // Hint when waiting to launch.
    if (waitingForLaunch) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'tap to launch',
          style: TextStyle(
            color: AppTheme.textDim,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          (size.width - tp.width) / 2,
          (1 - 0.06) * size.height - phPx - 28,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BreakoutPainter old) => true;
}
