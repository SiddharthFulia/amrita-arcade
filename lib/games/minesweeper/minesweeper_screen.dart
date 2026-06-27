import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import 'minesweeper_models.dart';

/// Minesweeper — Sid's amrita arcade. Tap to reveal, long-press to flag,
/// race the clock, beat your best.
class MinesweeperScreen extends StatefulWidget {
  const MinesweeperScreen({super.key});

  @override
  State<MinesweeperScreen> createState() => _MinesweeperScreenState();
}

class _MinesweeperScreenState extends State<MinesweeperScreen> {
  MinesweeperDifficulty _difficulty = MinesweeperDifficulty.easy;
  late MinesweeperBoard _board;
  Timer? _ticker;
  int _elapsed = 0;
  bool _running = false;
  int? _bestSeconds;

  @override
  void initState() {
    super.initState();
    _board = MinesweeperBoard(_difficulty);
    _loadBest();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _bestSeconds = prefs.getInt(_difficulty.prefsKey));
  }

  Future<void> _saveIfBest() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_difficulty.prefsKey);
    if (current == null || _elapsed < current) {
      await prefs.setInt(_difficulty.prefsKey, _elapsed);
      if (!mounted) return;
      setState(() => _bestSeconds = _elapsed);
    }
  }

  void _startTimer() {
    _ticker?.cancel();
    _running = true;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
    });
  }

  void _stopTimer() {
    _ticker?.cancel();
    _ticker = null;
    _running = false;
  }

  void _newGame({MinesweeperDifficulty? difficulty}) {
    setState(() {
      if (difficulty != null) _difficulty = difficulty;
      _board = MinesweeperBoard(_difficulty);
      _elapsed = 0;
    });
    _stopTimer();
    _loadBest();
  }

  void _onReveal(int r, int c) {
    if (_board.isGameOver) return;
    final cell = _board.cells[r][c];
    if (cell.isRevealed || cell.isFlagged) return;

    HapticFeedback.selectionClick();

    final wasFirst = !_board.minesPlaced;
    final hitMine = _board.reveal(r, c);

    // First-tap safety: if somehow the first tap is a mine, regenerate
    // until the first reveal opens a safe area (defense in depth — the
    // model already excludes the tap from mine placement).
    if (wasFirst && hitMine) {
      var attempts = 0;
      while (hitMine && attempts < 8) {
        _board = MinesweeperBoard(_difficulty);
        if (!_board.reveal(r, c)) break;
        attempts++;
      }
    }

    if (!_running && !_board.isGameOver) _startTimer();

    if (_board.isLost) {
      HapticFeedback.heavyImpact();
      _stopTimer();
    } else if (_board.isWon) {
      HapticFeedback.mediumImpact();
      _stopTimer();
      _saveIfBest();
    }

    setState(() {});
  }

  void _onFlag(int r, int c) {
    if (_board.isGameOver) return;
    final cell = _board.cells[r][c];
    if (cell.isRevealed) return;
    HapticFeedback.mediumImpact();
    setState(() => _board.toggleFlag(r, c));
  }

  String _fmtTime(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom + 18;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('💣 minesweeper',
                style: TextStyle(
                  color: AppTheme.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                )),
            const SizedBox(width: 10),
            _HudChip(
              icon: Icons.timer_outlined,
              label: _fmtTime(_elapsed),
              color: AppTheme.sky,
            ),
            const SizedBox(width: 6),
            _HudChip(
              icon: Icons.flag_outlined,
              label: '${_board.minesLeft}',
              color: AppTheme.rose,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'new game',
            icon: const Icon(Icons.refresh, color: AppTheme.lavender),
            onPressed: () => _newGame(),
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DifficultyPicker(
                current: _difficulty,
                onPick: (d) {
                  if (d == _difficulty) return;
                  _newGame(difficulty: d);
                },
              ),
              const SizedBox(height: 10),
              if (_bestSeconds != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'best ${_difficulty.label}: ${_fmtTime(_bestSeconds!)}',
                    style: const TextStyle(
                      color: AppTheme.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Expanded(
                child: Center(
                  child: LayoutBuilder(builder: (context, constraints) {
                    final maxW = constraints.maxWidth;
                    final maxH = constraints.maxHeight;
                    final boardSide = maxW < maxH ? maxW : maxH;
                    return SizedBox(
                      width: boardSide,
                      height: boardSide,
                      child: _BoardGrid(
                        board: _board,
                        onReveal: _onReveal,
                        onFlag: _onFlag,
                      ),
                    );
                  }),
                ),
              ),
              if (_board.isGameOver) ...[
                const SizedBox(height: 10),
                _GameOverBanner(won: _board.isWon, elapsed: _elapsed),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _newGame(),
                      icon: const Icon(Icons.replay, size: 18),
                      label: Text(_board.isGameOver ? 'play again' : 'new game'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.text,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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

class _DifficultyPicker extends StatelessWidget {
  final MinesweeperDifficulty current;
  final ValueChanged<MinesweeperDifficulty> onPick;
  const _DifficultyPicker({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final d in MinesweeperDifficulty.values) ...[
          Expanded(child: _Chip(d: d, selected: d == current, onTap: () => onPick(d))),
          if (d != MinesweeperDifficulty.values.last) const SizedBox(width: 8),
        ]
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final MinesweeperDifficulty d;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.d, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.rose.withValues(alpha: 0.18) : AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.rose : AppTheme.border,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                d.label,
                style: TextStyle(
                  color: selected ? AppTheme.rose : AppTheme.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${d.rows}×${d.cols} · ${d.mines}💣',
                style: const TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HudChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _HudChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardGrid extends StatelessWidget {
  final MinesweeperBoard board;
  final void Function(int r, int c) onReveal;
  final void Function(int r, int c) onFlag;
  const _BoardGrid({
    required this.board,
    required this.onReveal,
    required this.onFlag,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: board.cols,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 1,
        ),
        itemCount: board.rows * board.cols,
        itemBuilder: (_, i) {
          final r = i ~/ board.cols;
          final c = i % board.cols;
          final cell = board.cells[r][c];
          final isExploded =
              board.exploded && board.explodedRow == r && board.explodedCol == c;
          return _CellTile(
            cell: cell,
            isExploded: isExploded,
            onTap: () => onReveal(r, c),
            onLongPress: () => onFlag(r, c),
          );
        },
      ),
    );
  }
}

class _CellTile extends StatelessWidget {
  final MinesweeperCell cell;
  final bool isExploded;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _CellTile({
    required this.cell,
    required this.isExploded,
    required this.onTap,
    required this.onLongPress,
  });

  static const _numberColors = <Color>[
    AppTheme.sky, // 1
    AppTheme.success, // 2
    AppTheme.rose, // 3
    AppTheme.lavender, // 4
    AppTheme.pink, // 5
    AppTheme.gold, // 6
    AppTheme.text, // 7
    AppTheme.danger, // 8
  ];

  @override
  Widget build(BuildContext context) {
    final bg = _bg();
    final border = _border();
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border, width: 0.5),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: _content(),
          ),
        ),
      ),
    );
  }

  Color _bg() {
    if (isExploded) return AppTheme.danger.withValues(alpha: 0.55);
    if (cell.isRevealed) {
      return cell.isMine
          ? AppTheme.danger.withValues(alpha: 0.25)
          : AppTheme.surfaceElev;
    }
    return AppTheme.bg;
  }

  Color _border() {
    if (cell.isRevealed) return AppTheme.border;
    return AppTheme.border.withValues(alpha: 0.7);
  }

  Widget _content() {
    if (!cell.isRevealed) {
      if (cell.isFlagged) {
        return const Text('🚩', style: TextStyle(fontSize: 18));
      }
      return const SizedBox.shrink();
    }
    if (cell.isMine) {
      return const Text('💣', style: TextStyle(fontSize: 18));
    }
    if (cell.adjacentMines == 0) {
      return const SizedBox.shrink();
    }
    final color = _numberColors[cell.adjacentMines - 1];
    return Text(
      '${cell.adjacentMines}',
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
    );
  }
}

class _GameOverBanner extends StatelessWidget {
  final bool won;
  final int elapsed;
  const _GameOverBanner({required this.won, required this.elapsed});

  @override
  Widget build(BuildContext context) {
    final color = won ? AppTheme.success : AppTheme.danger;
    final emoji = won ? '✨' : '💥';
    final msg = won ? 'cleared in ${_fmt(elapsed)} — gorgeous' : 'boom. try again?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}
