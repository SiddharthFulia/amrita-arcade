import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import 'flappy_game.dart';

/// Flappy screen — Scaffold + Flame GameWidget + game-over overlay.
class FlappyScreen extends StatefulWidget {
  const FlappyScreen({super.key});

  @override
  State<FlappyScreen> createState() => _FlappyScreenState();
}

class _FlappyScreenState extends State<FlappyScreen> {
  static const _bestKey = 'flappy_best';

  FlappyGame? _game;
  int _score = 0;
  int _best = 0;
  bool _showGameOver = false;
  int _gameOverScore = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final best = prefs.getInt(_bestKey) ?? 0;
    if (!mounted) return;
    setState(() {
      _best = best;
      _game = FlappyGame(
        initialBest: best,
        onScore: (s) {
          if (!mounted) return;
          setState(() => _score = s);
        },
        onDeath: _handleDeath,
      );
    });
  }

  Future<void> _handleDeath(int score, int best) async {
    if (best > _best) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_bestKey, best);
    }
    if (!mounted) return;
    setState(() {
      _best = best;
      _gameOverScore = score;
      _showGameOver = true;
    });
  }

  void _flyAgain() {
    setState(() {
      _showGameOver = false;
      _score = 0;
    });
    _game?.restart();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (r) => AppTheme.amrita.createShader(r),
          child: Text(
            'flappy  ·  $_score  ·  best $_best',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: game == null
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.rose),
              )
            : Stack(
                children: [
                  Positioned.fill(child: GameWidget(game: game)),
                  if (_showGameOver)
                    Positioned.fill(
                      child: _GameOverCard(
                        score: _gameOverScore,
                        best: _best,
                        bottomPad: bottomPad,
                        onFlyAgain: _flyAgain,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _GameOverCard extends StatelessWidget {
  const _GameOverCard({
    required this.score,
    required this.best,
    required this.bottomPad,
    required this.onFlyAgain,
  });

  final int score;
  final int best;
  final double bottomPad;
  final VoidCallback onFlyAgain;

  @override
  Widget build(BuildContext context) {
    final isNewBest = score > 0 && score >= best;
    return Container(
      // Block taps from reaching the game underneath — no tap-trap restart.
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPad + 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: AppTheme.rose.withValues(alpha: 0.18),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShaderMask(
                shaderCallback: (r) => AppTheme.amrita.createShader(r),
                child: const Text(
                  'game over',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatBlock(label: 'score', value: '$score'),
                  _StatBlock(
                    label: 'best',
                    value: '$best',
                    accent: isNewBest ? AppTheme.gold : AppTheme.textDim,
                  ),
                ],
              ),
              if (isNewBest) ...[
                const SizedBox(height: 12),
                const Text(
                  '✨ new best ✨',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppTheme.amrita,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.rose.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: onFlyAgain,
                      child: const Center(
                        child: Text(
                          'fly again',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
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

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    this.accent = AppTheme.text,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textDim,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: accent,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
