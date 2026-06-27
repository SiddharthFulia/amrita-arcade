import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';

/// Memory Match — flip pairs of sweet emoji cards. Three difficulties,
/// best-moves persisted per difficulty. The card flip uses a single
/// Matrix4..rotateY(t * pi) so the same widget shows back when t<0.5
/// and the face once it's crossed the half-turn, faked via a counter-
/// rotated child so the emoji isn't mirrored.
class MemoryMatchScreen extends StatefulWidget {
  const MemoryMatchScreen({super.key});

  @override
  State<MemoryMatchScreen> createState() => _MemoryMatchScreenState();
}

enum _Diff { easy, medium, hard }

extension on _Diff {
  String get label => switch (this) {
        _Diff.easy => 'easy',
        _Diff.medium => 'medium',
        _Diff.hard => 'hard',
      };
  int get cols => switch (this) {
        _Diff.easy => 4,
        _Diff.medium => 4,
        _Diff.hard => 6,
      };
  int get rows => switch (this) {
        _Diff.easy => 3,
        _Diff.medium => 4,
        _Diff.hard => 5,
      };
  int get pairs => (cols * rows) ~/ 2;
  String get prefsKey => 'memory_best_$label';
}

class _Card {
  final int id;
  final String emoji;
  bool open;
  bool matched;
  _Card(this.id, this.emoji, {this.open = false, this.matched = false});
}

class _MemoryMatchScreenState extends State<MemoryMatchScreen> {
  static const _pool = <String>[
    '🌸', '🍰', '🌙', '⭐', '🪷', '🦋',
    '☕', '🐈', '💖', '🍵', '🌺', '🍩',
    '🌹', '🍑', '🦄', '✨', '🍯', '🌷',
  ];

  _Diff _diff = _Diff.easy;
  late List<_Card> _cards;
  int? _firstIdx;
  bool _locking = false;
  int _moves = 0;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  DateTime? _startedAt;
  bool _won = false;
  bool _newBest = false;

  final Map<_Diff, int?> _best = {
    _Diff.easy: null,
    _Diff.medium: null,
    _Diff.hard: null,
  };

  @override
  void initState() {
    super.initState();
    _newGame();
    _loadBests();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadBests() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      for (final d in _Diff.values) {
        final v = prefs.getInt(d.prefsKey);
        _best[d] = v;
      }
    });
  }

  Future<void> _saveBest(_Diff d, int moves) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(d.prefsKey, moves);
  }

  void _newGame() {
    _ticker?.cancel();
    final n = _diff.pairs;
    final emojis = _pool.take(n).toList();
    final deck = <_Card>[];
    for (var i = 0; i < n; i++) {
      deck.add(_Card(i * 2, emojis[i]));
      deck.add(_Card(i * 2 + 1, emojis[i]));
    }
    deck.shuffle(math.Random());
    setState(() {
      _cards = deck;
      _firstIdx = null;
      _locking = false;
      _moves = 0;
      _elapsed = Duration.zero;
      _startedAt = null;
      _won = false;
      _newBest = false;
    });
  }

  void _startTimerIfNeeded() {
    if (_startedAt != null) return;
    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_startedAt!));
    });
  }

  void _onTap(int idx) {
    if (_locking || _won) return;
    final c = _cards[idx];
    if (c.open || c.matched) return;
    _startTimerIfNeeded();

    setState(() => c.open = true);

    if (_firstIdx == null) {
      _firstIdx = idx;
      return;
    }

    final first = _cards[_firstIdx!];
    setState(() => _moves++);

    if (first.emoji == c.emoji && _firstIdx != idx) {
      HapticFeedback.lightImpact();
      setState(() {
        first.matched = true;
        c.matched = true;
        _firstIdx = null;
      });
      if (_cards.every((x) => x.matched)) {
        _onWin();
      }
    } else {
      _locking = true;
      final a = _firstIdx!;
      final b = idx;
      _firstIdx = null;
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          _cards[a].open = false;
          _cards[b].open = false;
          _locking = false;
        });
      });
    }
  }

  Future<void> _onWin() async {
    _ticker?.cancel();
    HapticFeedback.mediumImpact();
    final prev = _best[_diff];
    final isBest = prev == null || _moves < prev;
    if (isBest) {
      _best[_diff] = _moves;
      await _saveBest(_diff, _moves);
    }
    if (!mounted) return;
    setState(() {
      _won = true;
      _newBest = isBest;
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom + 16;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (r) => AppTheme.amrita.createShader(r),
          child: const Text('memory',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 6),
                  child: Row(
                    children: [
                      for (final d in _Diff.values) ...[
                        _DiffChip(
                          label: d.label,
                          selected: d == _diff,
                          onTap: () {
                            setState(() => _diff = d);
                            _newGame();
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                      const Spacer(),
                      _NewGameButton(onTap: _newGame),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                  child: Row(
                    children: [
                      _Stat(label: 'moves', value: '$_moves'),
                      const SizedBox(width: 18),
                      _Stat(label: 'time', value: _fmt(_elapsed)),
                      const Spacer(),
                      _Stat(
                        label: 'best',
                        value: _best[_diff] == null ? '—' : '${_best[_diff]}',
                        accent: AppTheme.gold,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(10, 4, 10, bottomPad),
                    child: LayoutBuilder(
                      builder: (_, constraints) {
                        final cols = _diff.cols;
                        final rows = _diff.rows;
                        const gap = 8.0;
                        final w = (constraints.maxWidth - (cols - 1) * gap) / cols;
                        final h = (constraints.maxHeight - (rows - 1) * gap) / rows;
                        final side = math.min(w, h);
                        return Center(
                          child: SizedBox(
                            width: side * cols + gap * (cols - 1),
                            height: side * rows + gap * (rows - 1),
                            child: GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                crossAxisSpacing: gap,
                                mainAxisSpacing: gap,
                                childAspectRatio: 1,
                              ),
                              itemCount: _cards.length,
                              itemBuilder: (_, i) {
                                final c = _cards[i];
                                return _MemoryCard(
                                  card: c,
                                  onTap: () => _onTap(i),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            if (_won)
              _WinOverlay(
                moves: _moves,
                time: _fmt(_elapsed),
                newBest: _newBest,
                onPlay: _newGame,
              ),
          ],
        ),
      ),
    );
  }
}

class _DiffChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DiffChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: selected ? AppTheme.amrita : null,
            color: selected ? null : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.transparent : AppTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _NewGameButton extends StatelessWidget {
  final VoidCallback onTap;
  const _NewGameButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElev,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.rose.withValues(alpha: 0.4)),
          ),
          child: const Text(
            'new game',
            style: TextStyle(
              color: AppTheme.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;
  const _Stat({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(label,
            style: const TextStyle(
              color: AppTheme.textDim,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            )),
        const SizedBox(width: 5),
        Text(value,
            style: TextStyle(
              color: accent ?? AppTheme.text,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ],
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final _Card card;
  final VoidCallback onTap;
  const _MemoryCard({required this.card, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final faceUp = card.open || card.matched;
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: faceUp ? 1 : 0, end: faceUp ? 1 : 0),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        builder: (_, t, __) {
          final angle = t * math.pi;
          final showFront = t > 0.5;
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateY(angle);
          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: showFront
                ? Transform(
                    transform: Matrix4.identity()..rotateY(math.pi),
                    alignment: Alignment.center,
                    child: _Face(card: card),
                  )
                : const _Back(),
          );
        },
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.amrita,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppTheme.rose.withValues(alpha: 0.20),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 38,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  final _Card card;
  const _Face({required this.card});

  @override
  Widget build(BuildContext context) {
    final matched = card.matched;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: matched
              ? AppTheme.success.withValues(alpha: 0.85)
              : AppTheme.border,
          width: matched ? 2 : 1,
        ),
        boxShadow: matched
            ? [
                BoxShadow(
                  color: AppTheme.success.withValues(alpha: 0.45),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Text(
            card.emoji,
            style: const TextStyle(fontSize: 40),
          ),
        ),
      ),
    );
  }
}

class _WinOverlay extends StatelessWidget {
  final int moves;
  final String time;
  final bool newBest;
  final VoidCallback onPlay;
  const _WinOverlay({
    required this.moves,
    required this.time,
    required this.newBest,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElev,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: AppTheme.lavender.withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (r) => AppTheme.amrita.createShader(r),
                child: const Text(
                  'you won',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'won in $moves moves · $time',
                style: const TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              if (newBest)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: AppTheme.amrita,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'new best ♥',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textDim,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    child: const Text('back',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: onPlay,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 11),
                        decoration: BoxDecoration(
                          gradient: AppTheme.amrita,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Text(
                          'play again',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
