import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'tetris_game.dart';

class TetrisScreen extends StatefulWidget {
  const TetrisScreen({super.key});

  @override
  State<TetrisScreen> createState() => _TetrisScreenState();
}

class _TetrisScreenState extends State<TetrisScreen> {
  late final TetrisGame _game;

  @override
  void initState() {
    super.initState();
    _game = TetrisGame();
    _game.gameOverN.addListener(_onGameOver);
  }

  @override
  void dispose() {
    _game.gameOverN.removeListener(_onGameOver);
    super.dispose();
  }

  void _onGameOver() {
    if (!_game.gameOverN.value || !mounted) return;
    // Defer so it doesn't fight the render frame.
    Future.microtask(() async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.border),
          ),
          title: const Text(
            'Game over',
            style: TextStyle(color: AppTheme.rose, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Score ${_game.score} — Best ${_game.best}',
            style: const TextStyle(color: AppTheme.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close',
                  style: TextStyle(color: AppTheme.textDim)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.rose),
              onPressed: () {
                Navigator.of(ctx).pop();
                _game.reset();
              },
              child: const Text('Play again'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom + 18;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Tetris',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            ValueListenableBuilder<int>(
              valueListenable: _game.scoreN,
              builder: (_, s, _) => _Chip(label: 'Score', value: '$s'),
            ),
            const SizedBox(width: 6),
            ValueListenableBuilder<int>(
              valueListenable: _game.bestN,
              builder: (_, b, _) => _Chip(label: 'Best', value: '$b'),
            ),
            const Spacer(),
            ValueListenableBuilder<Object?>(
              valueListenable: _game.nextN,
              builder: (_, p, _) => _NextChip(piece: p),
            ),
          ],
        ),
        titleSpacing: 12,
        actions: [
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.refresh, color: AppTheme.textDim),
            onPressed: () => _game.reset(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: GameWidget(game: _game),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
              child: Row(
                children: [
                  Expanded(
                    child: _HoldButton(
                      icon: Icons.chevron_left_rounded,
                      label: 'Left',
                      onTrigger: _game.moveLeft,
                      color: AppTheme.lavender,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TapButton(
                      icon: Icons.rotate_right_rounded,
                      label: 'Rotate',
                      onPressed: _game.rotate,
                      color: AppTheme.gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TapButton(
                      icon: Icons.vertical_align_bottom_rounded,
                      label: 'Drop',
                      onPressed: _game.hardDrop,
                      color: AppTheme.rose,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _HoldButton(
                      icon: Icons.chevron_right_rounded,
                      label: 'Right',
                      onTrigger: _game.moveRight,
                      color: AppTheme.lavender,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 11)),
          const SizedBox(width: 6),
          Text(value,
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              )),
        ],
      ),
    );
  }
}

class _NextChip extends StatelessWidget {
  const _NextChip({required this.piece});
  final Object? piece;

  @override
  Widget build(BuildContext context) {
    if (piece == null) {
      return const SizedBox(width: 56, height: 36);
    }
    final cells = TetrisGame.previewCells(piece!);
    final color = TetrisGame.previewColor(piece!);

    // Find bounds so the chip stays tight regardless of piece.
    var minR = 4, maxR = -1, minC = 4, maxC = -1;
    for (final rc in cells) {
      if (rc[0] < minR) minR = rc[0];
      if (rc[0] > maxR) maxR = rc[0];
      if (rc[1] < minC) minC = rc[1];
      if (rc[1] > maxC) maxC = rc[1];
    }
    final h = (maxR - minR + 1).clamp(1, 4);
    final w = (maxC - minC + 1).clamp(1, 4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Next',
              style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
          const SizedBox(width: 6),
          CustomPaint(
            size: Size(w * 7.0, h * 7.0),
            painter: _PiecePainter(
              cells: cells,
              minR: minR,
              minC: minC,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PiecePainter extends CustomPainter {
  _PiecePainter({
    required this.cells,
    required this.minR,
    required this.minC,
    required this.color,
  });
  final List<List<int>> cells;
  final int minR;
  final int minC;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / ((cells.isEmpty ? 1 : _spanC()));
    final cellH = size.height / ((cells.isEmpty ? 1 : _spanR()));
    final cell = cellW < cellH ? cellW : cellH;
    final paint = Paint()..color = color;
    for (final rc in cells) {
      final r = rc[0] - minR;
      final c = rc[1] - minC;
      final rect = Rect.fromLTWH(c * cell, r * cell, cell - 1, cell - 1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        paint,
      );
    }
  }

  int _spanR() {
    var lo = 1 << 30, hi = -1;
    for (final rc in cells) {
      if (rc[0] < lo) lo = rc[0];
      if (rc[0] > hi) hi = rc[0];
    }
    return (hi - lo + 1).clamp(1, 4);
  }

  int _spanC() {
    var lo = 1 << 30, hi = -1;
    for (final rc in cells) {
      if (rc[1] < lo) lo = rc[1];
      if (rc[1] > hi) hi = rc[1];
    }
    return (hi - lo + 1).clamp(1, 4);
  }

  @override
  bool shouldRepaint(covariant _PiecePainter old) =>
      old.color != color || old.cells != cells;
}

class _TapButton extends StatelessWidget {
  const _TapButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.surface,
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.icon,
    required this.label,
    required this.onTrigger,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTrigger;
  final Color color;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  Timer? _repeat;

  void _start() {
    widget.onTrigger();
    _repeat?.cancel();
    _repeat = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => widget.onTrigger(),
    );
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _start(),
        onTapUp: (_) => _stop(),
        onTapCancel: _stop,
        onPanEnd: (_) => _stop(),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: widget.color.withValues(alpha: 0.55)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 26, color: widget.color),
              const SizedBox(height: 2),
              Text(widget.label,
                  style: TextStyle(fontSize: 11, color: widget.color)),
            ],
          ),
        ),
      ),
    );
  }
}
