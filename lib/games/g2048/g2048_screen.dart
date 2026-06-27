import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import 'g2048_models.dart';

/// 2048 — Sid + Amrita arcade edition. Pure Flutter board, per-tile
/// position tweens for smooth slides, gold/rose tile palette.
class G2048Screen extends StatefulWidget {
  const G2048Screen({super.key});

  @override
  State<G2048Screen> createState() => _G2048ScreenState();
}

class _G2048ScreenState extends State<G2048Screen>
    with SingleTickerProviderStateMixin {
  static const _bestKey = 'g2048_best';
  static const _animDuration = Duration(milliseconds: 200);

  late Board _board;
  int _score = 0;
  int _best = 0;
  bool _gameOver = false;

  /// Last move's motions — what the animation paints. When idle this
  /// is `null` and we draw tiles at their resting cells.
  List<TileMotion>? _motions;
  Tile? _spawned;

  /// One-step undo snapshot.
  ({Board board, int score})? _undo;

  late final AnimationController _anim;
  late final Animation<double> _curve;

  // Lock input while a slide is mid-flight to prevent partial-move
  // double-swipes glitching the animation.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _board = Board.fresh();
    _anim = AnimationController(vsync: this, duration: _animDuration);
    _curve = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _loadBest();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _best = prefs.getInt(_bestKey) ?? 0);
  }

  Future<void> _saveBest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bestKey, _best);
  }

  void _resetGame() {
    setState(() {
      _board = Board.fresh();
      _score = 0;
      _gameOver = false;
      _motions = null;
      _spawned = null;
      _undo = null;
    });
  }

  void _doUndo() {
    final u = _undo;
    if (u == null || _busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _board = u.board;
      _score = u.score;
      _gameOver = false;
      _motions = null;
      _spawned = null;
      _undo = null;
    });
  }

  Future<void> _doMove(Move dir) async {
    if (_busy || _gameOver) return;
    // Snapshot first so undo can roll back to the pre-move state.
    final snapshot = (board: _board.copy(), score: _score);
    final result = _board.move(dir);
    if (!result.moved) return;
    _busy = true;
    HapticFeedback.selectionClick();
    if (result.merged) HapticFeedback.lightImpact();

    setState(() {
      _undo = snapshot;
      _score += result.gained;
      if (_score > _best) {
        _best = _score;
        _saveBest();
      }
      _motions = result.motions;
      _spawned = null;
    });

    _anim.forward(from: 0);
    await _anim.forward(from: 0);
    if (!mounted) return;

    // Slide done — spawn the new tile, clear motion data so we render
    // resting tiles, then check game-over.
    final spawned = _board.spawnRandom();
    setState(() {
      _motions = null;
      _spawned = spawned;
    });
    _busy = false;

    if (!_board.hasMoves) {
      HapticFeedback.heavyImpact();
      setState(() => _gameOver = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom + 18;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(
          '2048 · $_score · best $_best',
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'undo',
            onPressed: _undo == null ? null : _doUndo,
            icon: const Icon(Icons.undo_rounded),
            color: AppTheme.lavender,
            disabledColor: AppTheme.textMuted,
          ),
          IconButton(
            tooltip: 'new game',
            onPressed: _resetGame,
            icon: const Icon(Icons.refresh_rounded),
            color: AppTheme.rose,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() < 80) return;
                        _doMove(v > 0 ? Move.right : Move.left);
                      },
                      onVerticalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() < 80) return;
                        _doMove(v > 0 ? Move.down : Move.up);
                      },
                      child: _buildBoard(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'swipe to slide  ·  merge equals  ·  reach 2048',
                style: TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        const padding = 8.0;
        const gap = 8.0;
        final cellSize = (side - padding * 2 - gap * (Board.size - 1)) /
            Board.size;

        return Stack(
          children: [
            // Board background + grid cells.
            Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              padding: const EdgeInsets.all(padding),
              child: Column(
                children: List.generate(Board.size, (r) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          bottom: r == Board.size - 1 ? 0 : gap),
                      child: Row(
                        children: List.generate(Board.size, (c) {
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                  right: c == Board.size - 1 ? 0 : gap),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceElev,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Tile layer — absolutely-positioned with tweens.
            ..._buildTileWidgets(cellSize, padding, gap),
            if (_gameOver) _buildGameOver(),
          ],
        );
      },
    );
  }

  Offset _cellOffset(int row, int col, double cellSize, double pad, double gap) {
    return Offset(
      pad + col * (cellSize + gap),
      pad + row * (cellSize + gap),
    );
  }

  /// Builds the tile widgets. While `_motions` is set we render
  /// tweened tiles from their `from` → `to` cells. Otherwise we draw
  /// the current resting board.
  List<Widget> _buildTileWidgets(double cellSize, double pad, double gap) {
    final widgets = <Widget>[];

    if (_motions != null) {
      // Mid-animation: paint motions. Sort merged-source tiles AFTER
      // their targets so they appear on top while sliding in.
      final motions = [..._motions!];
      motions.sort(
          (a, b) => (a.mergedInto ? 1 : 0).compareTo(b.mergedInto ? 1 : 0));
      for (final m in motions) {
        final from = _cellOffset(m.fromRow, m.fromCol, cellSize, pad, gap);
        final to = _cellOffset(m.toRow, m.toCol, cellSize, pad, gap);
        widgets.add(AnimatedBuilder(
          animation: _curve,
          builder: (_, __) {
            final t = _curve.value;
            final dx = from.dx + (to.dx - from.dx) * t;
            final dy = from.dy + (to.dy - from.dy) * t;
            // Consumed merge-sources fade out as they approach the
            // destination so the target's pop reads as the result.
            final opacity = m.mergedInto ? (1 - t).clamp(0.0, 1.0) : 1.0;
            return Positioned(
              left: dx,
              top: dy,
              width: cellSize,
              height: cellSize,
              child: Opacity(
                opacity: opacity,
                child: _TileBox(value: m.value, size: cellSize),
              ),
            );
          },
        ));
      }
    } else {
      // Resting state: paint live tiles at their grid cells. Spawned
      // tile gets a scale-in pop on first frame.
      for (var r = 0; r < Board.size; r++) {
        for (var c = 0; c < Board.size; c++) {
          final t = _board.grid[r][c];
          if (t == null) continue;
          final pos = _cellOffset(r, c, cellSize, pad, gap);
          Widget tile = _TileBox(
            value: t.value,
            size: cellSize,
            pop: t.mergedThisMove,
          );
          if (identical(t, _spawned)) {
            tile = TweenAnimationBuilder<double>(
              key: ValueKey('spawn-${t.id}'),
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutBack,
              builder: (_, v, child) =>
                  Transform.scale(scale: v, child: child),
              child: tile,
            );
          }
          widgets.add(Positioned(
            left: pos.dx,
            top: pos.dy,
            width: cellSize,
            height: cellSize,
            child: tile,
          ));
        }
      }
    }

    return widgets;
  }

  Widget _buildGameOver() {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: AppTheme.bg.withValues(alpha: 0.82),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShaderMask(
                shaderCallback: (r) => AppTheme.amrita.createShader(r),
                child: const Text(
                  'game over',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'score  $_score',
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'best   $_best',
                style: const TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _resetGame,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.rose,
                  foregroundColor: AppTheme.bg,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'play again',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
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

/// The painted square for a single tile value. Optional `pop` plays
/// a quick scale bump when a merge produced this value.
class _TileBox extends StatelessWidget {
  final int value;
  final double size;
  final bool pop;
  const _TileBox({required this.value, required this.size, this.pop = false});

  @override
  Widget build(BuildContext context) {
    final bg = _tileColor(value);
    final isLight = value <= 4;
    final fg = isLight ? const Color(0xFF1B1320) : AppTheme.text;
    // Smaller font for bigger numbers so 1024/2048 still fit.
    final fontSize = value < 100
        ? size * 0.42
        : value < 1000
            ? size * 0.34
            : size * 0.26;

    final box = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.35),
            blurRadius: 12,
            spreadRadius: -2,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$value',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
          letterSpacing: 0.5,
        ),
      ),
    );

    if (!pop) return box;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: box,
    );
  }

  static Color _tileColor(int v) {
    switch (v) {
      case 2:
        return const Color(0xFFEEE4DA);
      case 4:
        return const Color(0xFFEDE0C8);
      case 8:
        return AppTheme.gold;
      case 16:
        return AppTheme.rose;
      case 32:
        return AppTheme.pink;
      case 64:
        return AppTheme.lavender;
      case 128:
        return AppTheme.success;
      default:
        return AppTheme.rose;
    }
  }
}
