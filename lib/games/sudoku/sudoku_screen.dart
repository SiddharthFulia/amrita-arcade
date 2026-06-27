import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import 'sudoku_models.dart';

/// Sudoku — Sid + Amrita's arcade collection.
///
/// 9×9 grid with three difficulties, pencil notes, conflict detection,
/// timer, and per-difficulty best-time persistence.
class SudokuScreen extends StatefulWidget {
  const SudokuScreen({super.key});

  @override
  State<SudokuScreen> createState() => _SudokuScreenState();
}

class _SudokuScreenState extends State<SudokuScreen> {
  final SudokuGenerator _gen = SudokuGenerator();

  late List<List<Cell>> _board;
  Set<int> _conflicts = <int>{};

  int? _selRow;
  int? _selCol;

  SudokuDifficulty _difficulty = SudokuDifficulty.easy;
  bool _notesMode = false;

  // Timer.
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _running = false;
  bool _won = false;

  // Best times.
  final Map<SudokuDifficulty, Duration?> _bests = {
    SudokuDifficulty.easy: null,
    SudokuDifficulty.medium: null,
    SudokuDifficulty.hard: null,
  };

  @override
  void initState() {
    super.initState();
    _newGame(_difficulty);
    _loadBests();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadBests() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      for (final d in SudokuDifficulty.values) {
        final v = p.getInt(d.prefsKey);
        _bests[d] = v == null ? null : Duration(seconds: v);
      }
    });
  }

  Future<void> _saveBestIfBetter() async {
    final cur = _bests[_difficulty];
    if (cur != null && _elapsed >= cur) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_difficulty.prefsKey, _elapsed.inSeconds);
    setState(() => _bests[_difficulty] = _elapsed);
  }

  void _newGame(SudokuDifficulty d) {
    _ticker?.cancel();
    final puzzle = _gen.generate(d);
    setState(() {
      _difficulty = d;
      _board = puzzle.board;
      _conflicts = <int>{};
      _selRow = null;
      _selCol = null;
      _notesMode = false;
      _elapsed = Duration.zero;
      _running = false;
      _won = false;
    });
  }

  void _startTimerIfNeeded() {
    if (_running || _won) return;
    _running = true;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  void _selectCell(int r, int c) {
    setState(() {
      _selRow = r;
      _selCol = c;
    });
  }

  void _input(int value) {
    final r = _selRow, c = _selCol;
    if (r == null || c == null || _won) return;
    final cell = _board[r][c];
    if (cell.given) return;

    _startTimerIfNeeded();

    setState(() {
      if (_notesMode) {
        // Notes only make sense on empty cells.
        if (cell.value != 0) cell.value = 0;
        if (cell.notes.contains(value)) {
          cell.notes.remove(value);
        } else {
          cell.notes.add(value);
        }
      } else {
        cell.value = (cell.value == value) ? 0 : value;
        cell.notes.clear();
        // Any same-value notes in row/col/box get cleaned up so the player
        // sees an accurate pencil-mark state.
        if (cell.value != 0) _cleanNotes(r, c, cell.value);
      }
      _conflicts = SudokuRules.conflicts(_board);
    });

    if (SudokuRules.isSolved(_board)) _onWin();
  }

  void _cleanNotes(int row, int col, int v) {
    for (var i = 0; i < 9; i++) {
      _board[row][i].notes.remove(v);
      _board[i][col].notes.remove(v);
    }
    final br = (row ~/ 3) * 3, bc = (col ~/ 3) * 3;
    for (var dr = 0; dr < 3; dr++) {
      for (var dc = 0; dc < 3; dc++) {
        _board[br + dr][bc + dc].notes.remove(v);
      }
    }
  }

  void _erase() {
    final r = _selRow, c = _selCol;
    if (r == null || c == null || _won) return;
    final cell = _board[r][c];
    if (cell.given) return;
    setState(() {
      cell.value = 0;
      cell.notes.clear();
      _conflicts = SudokuRules.conflicts(_board);
    });
  }

  void _onWin() {
    _ticker?.cancel();
    _running = false;
    _won = true;
    HapticFeedback.heavyImpact();
    _saveBestIfBetter();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showWinSheet());
  }

  void _showWinSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => _WinCard(
        elapsed: _elapsed,
        difficulty: _difficulty,
        best: _bests[_difficulty],
        onNewGame: () {
          Navigator.of(context).pop();
          _newGame(_difficulty);
        },
      ),
    );
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  // ─────────────────── UI ───────────────────

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom + 18;
    final selVal = (_selRow != null && _selCol != null)
        ? _board[_selRow!][_selCol!].value
        : 0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Row(children: [
          _DifficultyChip(label: _difficulty.label),
          const SizedBox(width: 10),
          Icon(Icons.timer_outlined,
              size: 16, color: AppTheme.textDim),
          const SizedBox(width: 4),
          Text(
            _fmt(_elapsed),
            style: const TextStyle(
              color: AppTheme.text,
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          if (_conflicts.isNotEmpty) ...[
            const SizedBox(width: 10),
            Icon(Icons.error_outline,
                size: 14, color: AppTheme.danger),
            const SizedBox(width: 2),
            Text(
              '${_conflicts.length ~/ 2}',
              style: const TextStyle(
                color: AppTheme.danger,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ]),
        actions: [
          IconButton(
            tooltip: 'new game',
            onPressed: () => _showDifficultyPicker(),
            icon: const Icon(Icons.refresh, color: AppTheme.text),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: _DifficultyRow(
              current: _difficulty,
              onPick: (d) => _newGame(d),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AspectRatio(
              aspectRatio: 1,
              child: _Board(
                board: _board,
                selRow: _selRow,
                selCol: _selCol,
                selValue: selVal,
                conflicts: _conflicts,
                onTap: _selectCell,
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPad),
            child: _NumberPad(
              notesMode: _notesMode,
              onNumber: _input,
              onToggleNotes: () =>
                  setState(() => _notesMode = !_notesMode),
              onErase: _erase,
              counts: _digitCounts(),
            ),
          ),
        ],
      ),
    );
  }

  /// How many of each digit are already placed — used to dim a digit on
  /// the pad once all 9 instances are on the board.
  Map<int, int> _digitCounts() {
    final m = <int, int>{for (var i = 1; i <= 9; i++) i: 0};
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        final v = _board[r][c].value;
        if (v != 0) m[v] = (m[v] ?? 0) + 1;
      }
    }
    return m;
  }

  void _showDifficultyPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surfaceElev,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'pick a difficulty',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              for (final d in SudokuDifficulty.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _newGame(d);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 14),
                        child: Row(
                          children: [
                            Text(
                              d.label,
                              style: const TextStyle(
                                color: AppTheme.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '· ${d.givens} givens',
                              style: const TextStyle(
                                color: AppTheme.textDim,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            if (_bests[d] != null)
                              Text(
                                'best ${_fmt(_bests[d]!)}',
                                style: const TextStyle(
                                  color: AppTheme.gold,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
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
      ),
    );
  }
}

// ─────────────────── widgets ───────────────────

class _DifficultyChip extends StatelessWidget {
  final String label;
  const _DifficultyChip({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: AppTheme.amrita,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _DifficultyRow extends StatelessWidget {
  final SudokuDifficulty current;
  final ValueChanged<SudokuDifficulty> onPick;
  const _DifficultyRow({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final d in SudokuDifficulty.values) ...[
          Expanded(
            child: _Pill(
              label: d.label,
              selected: d == current,
              onTap: () => onPick(d),
            ),
          ),
          if (d != SudokuDifficulty.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.transparent : AppTheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: selected ? AppTheme.amrita : null,
            border: Border.all(
              color: selected ? Colors.transparent : AppTheme.border,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.textDim,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  final List<List<Cell>> board;
  final int? selRow;
  final int? selCol;
  final int selValue;
  final Set<int> conflicts;
  final void Function(int row, int col) onTap;

  const _Board({
    required this.board,
    required this.selRow,
    required this.selCol,
    required this.selValue,
    required this.conflicts,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final size = c.maxWidth;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.lavender.withValues(alpha: 0.45), width: 1.5),
          ),
          padding: const EdgeInsets.all(4),
          child: CustomPaint(
            painter: _GridLinesPainter(),
            child: Column(
              children: [
                for (var r = 0; r < 9; r++)
                  Expanded(
                    child: Row(
                      children: [
                        for (var col = 0; col < 9; col++)
                          Expanded(
                            child: _CellTile(
                              cell: board[r][col],
                              row: r,
                              col: col,
                              isSelected: r == selRow && col == selCol,
                              isPeer: _isPeer(r, col),
                              isSameValue: selValue != 0 &&
                                  board[r][col].value == selValue,
                              isConflict: conflicts.contains(r * 9 + col),
                              onTap: () => onTap(r, col),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isPeer(int r, int c) {
    if (selRow == null || selCol == null) return false;
    if (r == selRow || c == selCol) return true;
    return (r ~/ 3 == selRow! ~/ 3) && (c ~/ 3 == selCol! ~/ 3);
  }
}

class _GridLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = AppTheme.border
      ..strokeWidth = 0.6;
    final thick = Paint()
      ..color = AppTheme.lavender.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;

    final w = size.width / 9;
    for (var i = 1; i < 9; i++) {
      final p = (i % 3 == 0) ? thick : thin;
      canvas.drawLine(Offset(w * i, 0), Offset(w * i, size.height), p);
      canvas.drawLine(Offset(0, w * i), Offset(size.width, w * i), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CellTile extends StatelessWidget {
  final Cell cell;
  final int row;
  final int col;
  final bool isSelected;
  final bool isPeer;
  final bool isSameValue;
  final bool isConflict;
  final VoidCallback onTap;

  const _CellTile({
    required this.cell,
    required this.row,
    required this.col,
    required this.isSelected,
    required this.isPeer,
    required this.isSameValue,
    required this.isConflict,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    if (isSelected) {
      bg = AppTheme.rose.withValues(alpha: 0.30);
    } else if (isSameValue && cell.value != 0) {
      bg = AppTheme.gold.withValues(alpha: 0.22);
    } else if (isPeer) {
      bg = AppTheme.lavender.withValues(alpha: 0.10);
    } else {
      bg = Colors.transparent;
    }

    Color fg;
    if (cell.given) {
      fg = AppTheme.text;
    } else if (isConflict) {
      fg = AppTheme.danger;
    } else {
      fg = AppTheme.sky;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: isConflict
              ? Border.all(color: AppTheme.danger, width: 1.4)
              : null,
        ),
        alignment: Alignment.center,
        child: cell.value != 0
            ? Text(
                '${cell.value}',
                style: TextStyle(
                  color: fg,
                  fontWeight:
                      cell.given ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 20,
                ),
              )
            : (cell.notes.isEmpty
                ? const SizedBox.shrink()
                : _NotesGrid(notes: cell.notes)),
      ),
    );
  }
}

class _NotesGrid extends StatelessWidget {
  final Set<int> notes;
  const _NotesGrid({required this.notes});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Column(
        children: [
          for (var r = 0; r < 3; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < 3; c++)
                    Expanded(
                      child: Center(
                        child: Text(
                          notes.contains(r * 3 + c + 1)
                              ? '${r * 3 + c + 1}'
                              : '',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberPad extends StatelessWidget {
  final bool notesMode;
  final ValueChanged<int> onNumber;
  final VoidCallback onToggleNotes;
  final VoidCallback onErase;
  final Map<int, int> counts;

  const _NumberPad({
    required this.notesMode,
    required this.onNumber,
    required this.onToggleNotes,
    required this.onErase,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 1; i <= 9; i++) ...[
              Expanded(
                child: _PadKey(
                  label: '$i',
                  exhausted: (counts[i] ?? 0) >= 9,
                  onTap: () => onNumber(i),
                ),
              ),
              if (i != 9) const SizedBox(width: 5),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: _PadAction(
                label: notesMode ? 'notes · on' : 'notes',
                icon: Icons.edit_outlined,
                active: notesMode,
                onTap: onToggleNotes,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _PadAction(
                label: 'erase',
                icon: Icons.backspace_outlined,
                active: false,
                onTap: onErase,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PadKey extends StatelessWidget {
  final String label;
  final bool exhausted;
  final VoidCallback onTap;
  const _PadKey({
    required this.label,
    required this.exhausted,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: exhausted ? null : onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: exhausted ? AppTheme.textMuted : AppTheme.lavender,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _PadAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _PadAction({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.transparent : AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            gradient: active ? AppTheme.amrita : null,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? Colors.transparent : AppTheme.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? Colors.white : AppTheme.textDim),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppTheme.textDim,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WinCard extends StatelessWidget {
  final Duration elapsed;
  final SudokuDifficulty difficulty;
  final Duration? best;
  final VoidCallback onNewGame;

  const _WinCard({
    required this.elapsed,
    required this.difficulty,
    required this.best,
    required this.onNewGame,
  });

  String _fmt(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final isNewBest = best != null && elapsed <= best!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceElev,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: AppTheme.lavender.withValues(alpha: 0.5), width: 1.4),
          ),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (r) => AppTheme.amrita.createShader(r),
                child: const Text(
                  'solved!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isNewBest ? 'new best time on ${difficulty.label} · nice'
                          : 'cleared on ${difficulty.label}',
                style: const TextStyle(
                  color: AppTheme.textDim,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Stat(label: 'time', value: _fmt(elapsed)),
                  const SizedBox(width: 12),
                  _Stat(
                    label: 'best',
                    value: best != null ? _fmt(best!) : '—',
                    accent: isNewBest,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onNewGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.rose,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'new game',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5),
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

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  const _Stat({
    required this.label,
    required this.value,
    this.accent = false,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent
                ? AppTheme.gold.withValues(alpha: 0.6)
                : AppTheme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppTheme.textDim,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: accent ? AppTheme.gold : AppTheme.text,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
