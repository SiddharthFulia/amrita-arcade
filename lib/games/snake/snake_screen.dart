import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import 'snake_game.dart';

/// Snake — Tinkerbell-themed Flame game. 22x22 wrapping board, cat-headed
/// snake, glowing gold food, swipe-to-turn.
class SnakeScreen extends StatefulWidget {
  const SnakeScreen({super.key});

  @override
  State<SnakeScreen> createState() => _SnakeScreenState();
}

class _SnakeScreenState extends State<SnakeScreen> {
  static const String _bestKey = 'snake_best';

  SnakeGame? _game;
  int _score = 0;
  int _best = 0;
  bool _gameOver = false;
  bool _paused = false;

  // For swipe detection.
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int best = prefs.getInt(_bestKey) ?? 0;
    if (!mounted) return;
    setState(() {
      _best = best;
      _game = SnakeGame(
        initialBest: best,
        onScore: _handleScore,
        onGameOver: _handleGameOver,
      );
    });
  }

  void _handleScore(int score) {
    if (!mounted) return;
    setState(() => _score = score);
  }

  Future<void> _handleGameOver(int score, int best) async {
    if (!mounted) return;
    setState(() {
      _gameOver = true;
      _score = score;
      _best = best;
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bestKey, best);
  }

  void _restart() {
    setState(() {
      _gameOver = false;
      _paused = false;
      _score = 0;
    });
    _game?.restart();
  }

  void _togglePause() {
    final SnakeGame? g = _game;
    if (g == null || _gameOver) return;
    g.togglePause();
    setState(() => _paused = g.paused);
  }

  // ── swipe handling ─────────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) => _dragStart = d.localPosition;

  void _onPanUpdate(DragUpdateDetails d) {
    final Offset? start = _dragStart;
    if (start == null) return;
    final Offset delta = d.localPosition - start;
    const double threshold = 24;
    if (delta.distance < threshold) return;

    final SnakeDir dir = delta.dx.abs() > delta.dy.abs()
        ? (delta.dx > 0 ? SnakeDir.right : SnakeDir.left)
        : (delta.dy > 0 ? SnakeDir.down : SnakeDir.up);
    _game?.queueTurn(dir);
    _dragStart = d.localPosition; // reset anchor so a 2nd swipe in same drag works
  }

  void _onPanEnd(DragEndDetails _) => _dragStart = null;

  @override
  Widget build(BuildContext context) {
    final SnakeGame? game = _game;
    final double bottomPad =
        MediaQuery.viewPaddingOf(context).bottom + 18;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(
          'snake  ·  $_score  ·  best $_best',
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _paused ? 'resume' : 'pause',
            icon: Icon(
              _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppTheme.gold,
            ),
            onPressed: _togglePause,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // Score + best chips.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  _Chip(label: 'score', value: '$_score', color: AppTheme.rose),
                  const SizedBox(width: 8),
                  _Chip(label: 'best', value: '$_best', color: AppTheme.gold),
                ],
              ),
            ),
            // Board.
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 6, 12, bottomPad),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      children: [
                        if (game != null)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: _onPanStart,
                            onPanUpdate: _onPanUpdate,
                            onPanEnd: _onPanEnd,
                            child: GameWidget(game: game),
                          )
                        else
                          const Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.rose,
                            ),
                          ),
                        if (_paused && !_gameOver) _PauseOverlay(onResume: _togglePause),
                        if (_gameOver)
                          _GameOverOverlay(
                            score: _score,
                            best: _best,
                            onPlayAgain: _restart,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
//  UI bits
// ─────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Chip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  final VoidCallback onResume;
  const _PauseOverlay({required this.onResume});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onResume,
        child: Container(
          color: AppTheme.bg.withValues(alpha: 0.75),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pause_circle_filled_rounded,
                  size: 64, color: AppTheme.gold),
              const SizedBox(height: 10),
              const Text(
                'paused',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'tap to resume',
                style: TextStyle(color: AppTheme.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  final int score, best;
  final VoidCallback onPlayAgain;
  const _GameOverOverlay({
    required this.score,
    required this.best,
    required this.onPlayAgain,
  });

  @override
  Widget build(BuildContext context) {
    final bool isNewBest = score >= best && score > 0;
    return Positioned.fill(
      child: Container(
        color: AppTheme.bg.withValues(alpha: 0.85),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (r) => AppTheme.amrita.createShader(r),
                child: const Text(
                  'game over',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Chip(label: 'score', value: '$score', color: AppTheme.rose),
                  const SizedBox(width: 10),
                  _Chip(label: 'best', value: '$best', color: AppTheme.gold),
                ],
              ),
              if (isNewBest) ...[
                const SizedBox(height: 12),
                Text(
                  '✨ new best ✨',
                  style: TextStyle(
                    color: AppTheme.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: onPlayAgain,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.rose,
                  foregroundColor: AppTheme.bg,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text(
                  'play again',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
