import 'dart:math';

/// Difficulty preset — board dimensions + mine count.
enum MinesweeperDifficulty { easy, medium, hard }

extension MinesweeperDifficultyX on MinesweeperDifficulty {
  int get rows => switch (this) {
        MinesweeperDifficulty.easy => 9,
        MinesweeperDifficulty.medium => 13,
        MinesweeperDifficulty.hard => 16,
      };

  int get cols => rows;

  int get mines => switch (this) {
        MinesweeperDifficulty.easy => 10,
        MinesweeperDifficulty.medium => 30,
        MinesweeperDifficulty.hard => 60,
      };

  String get label => switch (this) {
        MinesweeperDifficulty.easy => 'easy',
        MinesweeperDifficulty.medium => 'medium',
        MinesweeperDifficulty.hard => 'hard',
      };

  String get prefsKey => switch (this) {
        MinesweeperDifficulty.easy => 'minesweeper_best_easy',
        MinesweeperDifficulty.medium => 'minesweeper_best_medium',
        MinesweeperDifficulty.hard => 'minesweeper_best_hard',
      };
}

/// A single cell on the board. Mutated in place by the controller for
/// reveal / flag operations — cheap, no immutable tree.
class MinesweeperCell {
  final int row;
  final int col;
  bool isMine;
  bool isRevealed;
  bool isFlagged;
  int adjacentMines;

  MinesweeperCell({
    required this.row,
    required this.col,
    this.isMine = false,
    this.isRevealed = false,
    this.isFlagged = false,
    this.adjacentMines = 0,
  });
}

/// Pure-dart minesweeper board — owns generation, reveal/flag logic, and
/// flood-fill. UI just reads `cells` and calls reveal/flag.
class MinesweeperBoard {
  final MinesweeperDifficulty difficulty;
  final int rows;
  final int cols;
  final int totalMines;
  final Random _rng;

  late List<List<MinesweeperCell>> cells;
  bool minesPlaced = false;
  bool exploded = false;
  int? explodedRow;
  int? explodedCol;
  int revealedCount = 0;
  int flagCount = 0;

  MinesweeperBoard(this.difficulty, {Random? rng})
      : rows = difficulty.rows,
        cols = difficulty.cols,
        totalMines = difficulty.mines,
        _rng = rng ?? Random() {
    _initEmpty();
  }

  void _initEmpty() {
    cells = List.generate(
      rows,
      (r) => List.generate(cols, (c) => MinesweeperCell(row: r, col: c)),
    );
    minesPlaced = false;
    exploded = false;
    explodedRow = null;
    explodedCol = null;
    revealedCount = 0;
    flagCount = 0;
  }

  int get totalCells => rows * cols;
  int get nonMineCells => totalCells - totalMines;
  int get minesLeft => totalMines - flagCount;
  bool get isWon => !exploded && revealedCount >= nonMineCells;
  bool get isLost => exploded;
  bool get isGameOver => isWon || isLost;

  /// Place mines anywhere except (safeRow, safeCol) and its neighbors —
  /// guarantees the first reveal opens a comfortable hole.
  void _placeMines(int safeRow, int safeCol) {
    final forbidden = <int>{};
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        final r = safeRow + dr;
        final c = safeCol + dc;
        if (_inBounds(r, c)) forbidden.add(r * cols + c);
      }
    }

    final candidates = <int>[];
    for (var i = 0; i < totalCells; i++) {
      if (!forbidden.contains(i)) candidates.add(i);
    }
    candidates.shuffle(_rng);

    final mineCount = min(totalMines, candidates.length);
    for (var i = 0; i < mineCount; i++) {
      final idx = candidates[i];
      cells[idx ~/ cols][idx % cols].isMine = true;
    }

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (cells[r][c].isMine) continue;
        cells[r][c].adjacentMines = _countAdjacentMines(r, c);
      }
    }
    minesPlaced = true;
  }

  int _countAdjacentMines(int r, int c) {
    var n = 0;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr;
        final nc = c + dc;
        if (_inBounds(nr, nc) && cells[nr][nc].isMine) n++;
      }
    }
    return n;
  }

  bool _inBounds(int r, int c) => r >= 0 && r < rows && c >= 0 && c < cols;

  /// Toggle a flag on a covered cell. No-op if already revealed or game over.
  void toggleFlag(int r, int c) {
    if (isGameOver) return;
    final cell = cells[r][c];
    if (cell.isRevealed) return;
    cell.isFlagged = !cell.isFlagged;
    flagCount += cell.isFlagged ? 1 : -1;
  }

  /// Reveal a cell. Returns true if the cell was a mine (game over).
  /// On the very first reveal, lays out mines guaranteeing the tapped cell
  /// (and its neighbors) are safe.
  bool reveal(int r, int c) {
    if (isGameOver) return false;
    final cell = cells[r][c];
    if (cell.isRevealed || cell.isFlagged) return false;

    if (!minesPlaced) {
      _placeMines(r, c);
    }

    if (cell.isMine) {
      cell.isRevealed = true;
      exploded = true;
      explodedRow = r;
      explodedCol = c;
      // Surface all remaining mines for the post-mortem.
      for (final row in cells) {
        for (final cc in row) {
          if (cc.isMine) cc.isRevealed = true;
        }
      }
      return true;
    }

    _floodReveal(r, c);
    return false;
  }

  /// Iterative BFS flood — pop a cell, reveal it, and if it has zero adjacent
  /// mines push its 8 neighbors. Iterative avoids stack overflow on the 16x16
  /// hard board where a single tap can cascade across the whole field.
  void _floodReveal(int startR, int startC) {
    final queue = <List<int>>[
      [startR, startC]
    ];
    while (queue.isNotEmpty) {
      final pos = queue.removeLast();
      final r = pos[0];
      final c = pos[1];
      if (!_inBounds(r, c)) continue;
      final cell = cells[r][c];
      if (cell.isRevealed || cell.isFlagged || cell.isMine) continue;
      cell.isRevealed = true;
      revealedCount++;
      if (cell.adjacentMines != 0) continue;
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          if (dr == 0 && dc == 0) continue;
          queue.add([r + dr, c + dc]);
        }
      }
    }
  }

  void reset() => _initEmpty();
}
