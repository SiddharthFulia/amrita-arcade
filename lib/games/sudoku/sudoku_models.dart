import 'dart:math';

/// Difficulty levels — controls how many cells are revealed as givens.
enum SudokuDifficulty { easy, medium, hard }

extension SudokuDifficultyX on SudokuDifficulty {
  String get label => switch (this) {
        SudokuDifficulty.easy => 'easy',
        SudokuDifficulty.medium => 'medium',
        SudokuDifficulty.hard => 'hard',
      };

  /// Number of cells pre-filled at the start.
  int get givens => switch (this) {
        SudokuDifficulty.easy => 40,
        SudokuDifficulty.medium => 30,
        SudokuDifficulty.hard => 22,
      };

  String get prefsKey => switch (this) {
        SudokuDifficulty.easy => 'sudoku_best_easy',
        SudokuDifficulty.medium => 'sudoku_best_medium',
        SudokuDifficulty.hard => 'sudoku_best_hard',
      };
}

/// A single cell on the Sudoku board.
///
/// - [value] is 0 if empty, 1–9 otherwise.
/// - [given] marks cells the puzzle started with (immutable to the player).
/// - [notes] is the player's pencil-marks for that cell.
class Cell {
  int value;
  bool given;
  Set<int> notes;

  Cell({this.value = 0, this.given = false, Set<int>? notes})
      : notes = notes ?? <int>{};

  Cell clone() => Cell(
        value: value,
        given: given,
        notes: {...notes},
      );

  bool get isEmpty => value == 0;
}

/// Holds the result of generating a puzzle — both the playable board
/// (with holes) and the completed solution for hint/validate purposes.
class SudokuPuzzle {
  final List<List<Cell>> board;
  final List<List<int>> solution;
  final SudokuDifficulty difficulty;

  SudokuPuzzle({
    required this.board,
    required this.solution,
    required this.difficulty,
  });
}

/// Pure-dart sudoku generator + solver.
///
/// Strategy: full-solve-then-poke.
///   1. Build a completed valid grid by running a randomised backtracking
///      filler (shuffle the candidate digits at every cell).
///   2. Copy the grid, then remove cells one-by-one in a random order down
///      to `givens` cells. We don't enforce uniqueness — keeps it snappy
///      on a phone and still gives a playable puzzle.
class SudokuGenerator {
  SudokuGenerator({Random? rng}) : _rng = rng ?? Random();

  final Random _rng;

  SudokuPuzzle generate(SudokuDifficulty difficulty) {
    final grid = List.generate(9, (_) => List<int>.filled(9, 0));
    _fill(grid);

    // Copy as the solution before poking holes.
    final solution = List.generate(9, (r) => List<int>.from(grid[r]));

    // Remove cells down to the target givens.
    final positions = <int>[for (var i = 0; i < 81; i++) i]..shuffle(_rng);
    final toRemove = 81 - difficulty.givens;
    for (var i = 0; i < toRemove; i++) {
      final p = positions[i];
      grid[p ~/ 9][p % 9] = 0;
    }

    final board = List.generate(
      9,
      (r) => List.generate(
        9,
        (c) {
          final v = grid[r][c];
          return Cell(value: v, given: v != 0);
        },
      ),
    );

    return SudokuPuzzle(
      board: board,
      solution: solution,
      difficulty: difficulty,
    );
  }

  /// Randomised backtracking fill — produces a uniformly-shuffled full grid.
  bool _fill(List<List<int>> g) {
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        if (g[r][c] != 0) continue;
        final digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(_rng);
        for (final d in digits) {
          if (_isSafe(g, r, c, d)) {
            g[r][c] = d;
            if (_fill(g)) return true;
            g[r][c] = 0;
          }
        }
        return false;
      }
    }
    return true;
  }

  bool _isSafe(List<List<int>> g, int r, int c, int v) {
    for (var i = 0; i < 9; i++) {
      if (g[r][i] == v || g[i][c] == v) return false;
    }
    final br = (r ~/ 3) * 3;
    final bc = (c ~/ 3) * 3;
    for (var dr = 0; dr < 3; dr++) {
      for (var dc = 0; dc < 3; dc++) {
        if (g[br + dr][bc + dc] == v) return false;
      }
    }
    return true;
  }
}

/// Classic backtracking solver. Exposed as a utility for hint features
/// or test suites — returns true if it found a solution, mutating [g].
class SudokuSolver {
  bool solve(List<List<int>> g) {
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        if (g[r][c] != 0) continue;
        for (var d = 1; d <= 9; d++) {
          if (_isSafe(g, r, c, d)) {
            g[r][c] = d;
            if (solve(g)) return true;
            g[r][c] = 0;
          }
        }
        return false;
      }
    }
    return true;
  }

  bool _isSafe(List<List<int>> g, int r, int c, int v) {
    for (var i = 0; i < 9; i++) {
      if (g[r][i] == v || g[i][c] == v) return false;
    }
    final br = (r ~/ 3) * 3;
    final bc = (c ~/ 3) * 3;
    for (var dr = 0; dr < 3; dr++) {
      for (var dc = 0; dc < 3; dc++) {
        if (g[br + dr][bc + dc] == v) return false;
      }
    }
    return true;
  }
}

/// Validation helpers that work on a board of [Cell].
class SudokuRules {
  /// Returns the set of (row, col) coordinates of cells that conflict with
  /// another cell in the same row / column / 3×3 box. Empty cells are skipped.
  static Set<int> conflicts(List<List<Cell>> b) {
    final bad = <int>{};

    // Rows + columns.
    for (var i = 0; i < 9; i++) {
      final rowSeen = <int, int>{};
      final colSeen = <int, int>{};
      for (var j = 0; j < 9; j++) {
        final rv = b[i][j].value;
        if (rv != 0) {
          if (rowSeen.containsKey(rv)) {
            bad.add(i * 9 + j);
            bad.add(i * 9 + rowSeen[rv]!);
          } else {
            rowSeen[rv] = j;
          }
        }
        final cv = b[j][i].value;
        if (cv != 0) {
          if (colSeen.containsKey(cv)) {
            bad.add(j * 9 + i);
            bad.add(colSeen[cv]! * 9 + i);
          } else {
            colSeen[cv] = j;
          }
        }
      }
    }

    // 3×3 boxes.
    for (var br = 0; br < 3; br++) {
      for (var bc = 0; bc < 3; bc++) {
        final seen = <int, int>{};
        for (var dr = 0; dr < 3; dr++) {
          for (var dc = 0; dc < 3; dc++) {
            final r = br * 3 + dr;
            final c = bc * 3 + dc;
            final v = b[r][c].value;
            if (v == 0) continue;
            final idx = r * 9 + c;
            if (seen.containsKey(v)) {
              bad.add(idx);
              bad.add(seen[v]!);
            } else {
              seen[v] = idx;
            }
          }
        }
      }
    }

    return bad;
  }

  /// True when every cell is filled and there are no conflicts.
  static bool isSolved(List<List<Cell>> b) {
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        if (b[r][c].value == 0) return false;
      }
    }
    return conflicts(b).isEmpty;
  }
}
