/// Pure-dart logic for 2048. No Flutter imports — keeps the rules
/// testable and lets the screen worry only about animation + paint.
///
/// The grid is a 4×4 of nullable `Tile` objects. Each tile carries an
/// `id` so the UI layer can track which tile slid where (and animate
/// from its previous cell to the new one) across a move.
library;

import 'dart:math';

/// One numbered square on the board.
class Tile {
  /// Stable identity used by the UI to tween position across moves.
  final int id;

  /// Power-of-two value (2, 4, 8, …).
  int value;

  /// Set on the frame a merge happened, so the UI can pop the new tile.
  bool mergedThisMove;

  /// Set when this tile spawned this move, for an entrance animation.
  bool spawnedThisMove;

  Tile({
    required this.id,
    required this.value,
    this.mergedThisMove = false,
    this.spawnedThisMove = false,
  });
}

/// Direction of a swipe.
enum Move { left, right, up, down }

/// Snapshot of a tile's start/end cell during a single move — emitted
/// so the UI can animate `from` → `to`.
class TileMotion {
  final int id;
  final int value;
  final int fromRow;
  final int fromCol;
  final int toRow;
  final int toCol;
  /// True when this tile was consumed into another (the merge target);
  /// the UI fades it out at the destination.
  final bool mergedInto;

  const TileMotion({
    required this.id,
    required this.value,
    required this.fromRow,
    required this.fromCol,
    required this.toRow,
    required this.toCol,
    required this.mergedInto,
  });
}

/// Result of attempting a move — tells the UI whether anything moved,
/// how to animate the transition, and what the new grid looks like.
class MoveResult {
  /// True if at least one tile changed cells or merged.
  final bool moved;

  /// True if any merge happened (UI uses for haptic + pop animation).
  final bool merged;

  /// Points scored this move (sum of merge totals).
  final int gained;

  /// Per-tile motion data so the UI can tween positions.
  final List<TileMotion> motions;

  const MoveResult({
    required this.moved,
    required this.merged,
    required this.gained,
    required this.motions,
  });
}

/// Owns the 4×4 grid and all gameplay rules. The UI calls `move()`,
/// inspects the returned `MoveResult` for animation data, then calls
/// `spawnRandom()` once the slide animation has played out.
class Board {
  static const int size = 4;

  /// Row-major grid: `grid[r][c]`.
  final List<List<Tile?>> grid;

  int _nextId;
  final Random _rng;

  Board._(this.grid, this._nextId, this._rng);

  /// Fresh game — empty board with two starter tiles.
  factory Board.fresh({Random? rng}) {
    final r = rng ?? Random();
    final g = List.generate(
      size,
      (_) => List<Tile?>.filled(size, null, growable: false),
      growable: false,
    );
    final b = Board._(g, 1, r);
    b.spawnRandom();
    b.spawnRandom();
    return b;
  }

  /// Clone for undo snapshots.
  Board copy() {
    final g = List.generate(
      size,
      (r) => List<Tile?>.generate(
        size,
        (c) {
          final t = grid[r][c];
          return t == null ? null : Tile(id: t.id, value: t.value);
        },
        growable: false,
      ),
      growable: false,
    );
    return Board._(g, _nextId, _rng);
  }

  /// All currently-living tiles (post-move state, excludes consumed
  /// merge sources). The UI iterates this to know what to paint at
  /// rest.
  List<Tile> get tiles {
    final out = <Tile>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final t = grid[r][c];
        if (t != null) out.add(t);
      }
    }
    return out;
  }

  /// (row, col) of `tile`, or `null` if it's not on the board.
  ({int row, int col})? locate(Tile tile) {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (identical(grid[r][c], tile)) return (row: r, col: c);
      }
    }
    return null;
  }

  /// Drop a 2 (90%) or 4 (10%) on a random empty cell. Returns the
  /// tile so the UI can flag it for an entrance animation.
  Tile? spawnRandom() {
    final empties = <({int r, int c})>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (grid[r][c] == null) empties.add((r: r, c: c));
      }
    }
    if (empties.isEmpty) return null;
    final pick = empties[_rng.nextInt(empties.length)];
    final value = _rng.nextDouble() < 0.9 ? 2 : 4;
    final t = Tile(id: _nextId++, value: value, spawnedThisMove: true);
    grid[pick.r][pick.c] = t;
    return t;
  }

  /// Returns true if there exists any legal move.
  bool get hasMoves {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (grid[r][c] == null) return true;
        final v = grid[r][c]!.value;
        if (r + 1 < size && grid[r + 1][c]?.value == v) return true;
        if (c + 1 < size && grid[r][c + 1]?.value == v) return true;
      }
    }
    return false;
  }

  /// Whether the player has reached the 2048 tile this game.
  bool get hasReached2048 {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if ((grid[r][c]?.value ?? 0) >= 2048) return true;
      }
    }
    return false;
  }

  /// Apply a swipe. Mutates the board in place and returns motion
  /// data so the UI can animate. Does NOT spawn a new tile — that's
  /// the caller's job (after the slide animation).
  MoveResult move(Move dir) {
    // Clear per-move flags from the previous turn so the UI doesn't
    // re-pop stale merges.
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final t = grid[r][c];
        if (t != null) {
          t.mergedThisMove = false;
          t.spawnedThisMove = false;
        }
      }
    }

    // Walk each row/column in the slide direction, collapsing tiles
    // toward the leading edge. Strategy: extract the line, compact it
    // (slide + merge), then write it back — recording each tile's
    // origin and final cell as we go.
    final motions = <TileMotion>[];
    var moved = false;
    var merged = false;
    var gained = 0;

    final lines = _linesFor(dir); // ordered cells per line
    for (final line in lines) {
      // Read the original line as (tile, originIdx) pairs, skipping
      // empties.
      final originals = <({Tile tile, int from})>[];
      for (var i = 0; i < line.length; i++) {
        final cell = line[i];
        final t = grid[cell.r][cell.c];
        if (t != null) originals.add((tile: t, from: i));
      }

      // Compact + merge into a new line.
      final compacted = <Tile>[];
      // Track origin index of each entry in `compacted` so we can
      // emit motions later.
      final compactedOrigins = <int>[];
      // Track tiles that were merged INTO `compacted[k]` (so we can
      // emit a TileMotion with mergedInto=true for the consumed one).
      final consumedSources = <int, ({Tile tile, int from})>{};

      for (final o in originals) {
        if (compacted.isNotEmpty &&
            compacted.last.value == o.tile.value &&
            !consumedSources.containsKey(compacted.length - 1)) {
          // Merge: the existing `compacted.last` is the "target" —
          // it stays at its destination cell, its value doubles.
          // The incoming tile is consumed and animates into the same
          // destination, fading out.
          final target = compacted.last;
          target.value *= 2;
          target.mergedThisMove = true;
          gained += target.value;
          merged = true;
          consumedSources[compacted.length - 1] = o;
        } else {
          compacted.add(o.tile);
          compactedOrigins.add(o.from);
        }
      }

      // Write the new line back into the grid, clearing any cells we
      // no longer occupy.
      for (var i = 0; i < line.length; i++) {
        final cell = line[i];
        grid[cell.r][cell.c] = null;
      }
      for (var i = 0; i < compacted.length; i++) {
        final cell = line[i];
        grid[cell.r][cell.c] = compacted[i];
      }

      // Emit motions: the "winners" (in `compacted`) and the
      // "consumed" merge sources.
      for (var i = 0; i < compacted.length; i++) {
        final t = compacted[i];
        final from = compactedOrigins[i];
        final destCell = line[i];
        final srcCell = line[from];
        if (from != i) moved = true;
        motions.add(TileMotion(
          id: t.id,
          value: t.mergedThisMove ? t.value ~/ 2 : t.value,
          fromRow: srcCell.r,
          fromCol: srcCell.c,
          toRow: destCell.r,
          toCol: destCell.c,
          mergedInto: false,
        ));
        final consumed = consumedSources[i];
        if (consumed != null) {
          moved = true;
          final srcCellC = line[consumed.from];
          motions.add(TileMotion(
            id: consumed.tile.id,
            value: consumed.tile.value,
            fromRow: srcCellC.r,
            fromCol: srcCellC.c,
            toRow: destCell.r,
            toCol: destCell.c,
            mergedInto: true,
          ));
        }
      }
    }

    return MoveResult(
      moved: moved,
      merged: merged,
      gained: gained,
      motions: motions,
    );
  }

  /// Build the 4 lines (rows or cols) for a given direction, with
  /// each line ordered so cell[0] is the leading edge tiles slide
  /// toward.
  List<List<({int r, int c})>> _linesFor(Move dir) {
    final lines = <List<({int r, int c})>>[];
    switch (dir) {
      case Move.left:
        for (var r = 0; r < size; r++) {
          lines.add([for (var c = 0; c < size; c++) (r: r, c: c)]);
        }
      case Move.right:
        for (var r = 0; r < size; r++) {
          lines.add([for (var c = size - 1; c >= 0; c--) (r: r, c: c)]);
        }
      case Move.up:
        for (var c = 0; c < size; c++) {
          lines.add([for (var r = 0; r < size; r++) (r: r, c: c)]);
        }
      case Move.down:
        for (var c = 0; c < size; c++) {
          lines.add([for (var r = size - 1; r >= 0; r--) (r: r, c: c)]);
        }
    }
    return lines;
  }
}
