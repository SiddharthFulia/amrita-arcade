import 'dart:math';
import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/material.dart'
    show Colors, ValueNotifier, TextPainter, TextSpan, TextStyle, TextDirection, FontWeight, Shadow;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';

/// The seven tetromino shapes (0=empty, 1=cell).
/// Each piece has 4 rotation states pre-baked so rotation = bumping an index.
class _Piece {
  _Piece(this.id, this.color, this.rotations);

  final int id;
  final Color color;
  // rotations[r] is a list of (row, col) offsets from the piece's top-left.
  final List<List<List<int>>> rotations;

  static List<List<int>> _cellsFromMatrix(List<List<int>> m) {
    final out = <List<int>>[];
    for (var r = 0; r < m.length; r++) {
      for (var c = 0; c < m[r].length; c++) {
        if (m[r][c] == 1) out.add([r, c]);
      }
    }
    return out;
  }

  static List<List<int>> _rotateCW(List<List<int>> m) {
    final h = m.length;
    final w = m[0].length;
    return List.generate(w, (r) => List.generate(h, (c) => m[h - 1 - c][r]));
  }

  static _Piece fromBase(int id, Color color, List<List<int>> base) {
    final rotations = <List<List<int>>>[];
    var cur = base;
    for (var i = 0; i < 4; i++) {
      rotations.add(_cellsFromMatrix(cur));
      cur = _rotateCW(cur);
    }
    return _Piece(id, color, rotations);
  }
}

/// Active piece state in the world.
class _ActivePiece {
  _ActivePiece(this.piece, this.row, this.col, this.rotation);
  final _Piece piece;
  int row;
  int col;
  int rotation;

  List<List<int>> get cells => piece.rotations[rotation];
}

class TetrisGame extends FlameGame {
  TetrisGame();

  // ---- Board ----
  static const int cols = 10;
  static const int rows = 20;

  // grid[r][c] == 0 empty, else piece id (1..7).
  late List<List<int>> grid;

  // ---- Pieces ----
  late final List<_Piece> _pieces;
  final Random _rng = Random();

  _ActivePiece? _active;
  _Piece? _next;

  // ---- Score ----
  int score = 0;
  int best = 0;
  int linesCleared = 0;
  bool gameOver = false;
  bool _suspended = false;

  // Notifiers so the Flutter UI rebuilds on changes.
  final ValueNotifier<int> scoreN = ValueNotifier<int>(0);
  final ValueNotifier<int> bestN = ValueNotifier<int>(0);
  final ValueNotifier<int> linesN = ValueNotifier<int>(0);
  final ValueNotifier<bool> gameOverN = ValueNotifier<bool>(false);
  final ValueNotifier<Object?> nextN = ValueNotifier<Object?>(null);

  // ---- Timing ----
  double _fallAccum = 0;
  double _fallInterval = 0.5; // seconds

  SharedPreferences? _prefs;

  @override
  Color backgroundColor() => AppTheme.bg;

  @override
  Future<void> onLoad() async {
    _pieces = _buildPieces();
    grid = List.generate(rows, (_) => List<int>.filled(cols, 0));
    _prefs = await SharedPreferences.getInstance();
    best = _prefs?.getInt('tetris_best') ?? 0;
    bestN.value = best;
    _next = _randomPiece();
    nextN.value = _next;
    _spawn();
  }

  List<_Piece> _buildPieces() {
    // I = sky, O = gold, T = lavender, S = success, Z = danger, J = pink, L = rose
    return [
      _Piece.fromBase(1, AppTheme.sky, [
        [0, 0, 0, 0],
        [1, 1, 1, 1],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]),
      _Piece.fromBase(2, AppTheme.gold, [
        [1, 1],
        [1, 1],
      ]),
      _Piece.fromBase(3, AppTheme.lavender, [
        [0, 1, 0],
        [1, 1, 1],
        [0, 0, 0],
      ]),
      _Piece.fromBase(4, AppTheme.success, [
        [0, 1, 1],
        [1, 1, 0],
        [0, 0, 0],
      ]),
      _Piece.fromBase(5, AppTheme.danger, [
        [1, 1, 0],
        [0, 1, 1],
        [0, 0, 0],
      ]),
      _Piece.fromBase(6, AppTheme.pink, [
        [1, 0, 0],
        [1, 1, 1],
        [0, 0, 0],
      ]),
      _Piece.fromBase(7, AppTheme.rose, [
        [0, 0, 1],
        [1, 1, 1],
        [0, 0, 0],
      ]),
    ];
  }

  _Piece _randomPiece() => _pieces[_rng.nextInt(_pieces.length)];

  void _spawn() {
    final p = _next ?? _randomPiece();
    _next = _randomPiece();
    nextN.value = _next;
    // Start near top centre. I piece needs col 3 for 4-wide row.
    final startCol = (cols ~/ 2) - 2;
    final fresh = _ActivePiece(p, 0, startCol, 0);
    if (_collides(fresh, fresh.row, fresh.col, fresh.rotation)) {
      // Game over — flush board state so the last piece is visible.
      _active = null;
      gameOver = true;
      gameOverN.value = true;
      HapticFeedback.heavyImpact();
      _persistBest();
      return;
    }
    _active = fresh;
  }

  bool _collides(_ActivePiece p, int row, int col, int rot) {
    final cells = p.piece.rotations[rot];
    for (final rc in cells) {
      final r = row + rc[0];
      final c = col + rc[1];
      if (c < 0 || c >= cols || r >= rows) return true;
      if (r < 0) continue; // above board OK during spawn
      if (grid[r][c] != 0) return true;
    }
    return false;
  }

  void _lock() {
    final a = _active;
    if (a == null) return;
    for (final rc in a.cells) {
      final r = a.row + rc[0];
      final c = a.col + rc[1];
      if (r < 0 || r >= rows || c < 0 || c >= cols) continue;
      grid[r][c] = a.piece.id;
    }
    HapticFeedback.mediumImpact();
    final cleared = _clearLines();
    if (cleared > 0) {
      const bonus = [0, 100, 300, 600, 1000];
      score += bonus[cleared.clamp(0, 4)];
      linesCleared += cleared;
      scoreN.value = score;
      linesN.value = linesCleared;
      // Speed up every 10 lines, floor 100ms.
      final level = linesCleared ~/ 10;
      _fallInterval = max(0.1, 0.5 - level * 0.04);
    }
    if (score > best) {
      best = score;
      bestN.value = best;
      _persistBest();
    }
    _spawn();
  }

  int _clearLines() {
    var cleared = 0;
    for (var r = rows - 1; r >= 0; r--) {
      var full = true;
      for (var c = 0; c < cols; c++) {
        if (grid[r][c] == 0) {
          full = false;
          break;
        }
      }
      if (full) {
        grid.removeAt(r);
        grid.insert(0, List<int>.filled(cols, 0));
        cleared++;
        r++; // re-check this row index since rows shifted down
      }
    }
    return cleared;
  }

  Future<void> _persistBest() async {
    await _prefs?.setInt('tetris_best', best);
  }

  // ---- Controls (called from Flutter buttons) ----

  void moveLeft() {
    if (_lockedOut) return;
    final a = _active!;
    if (!_collides(a, a.row, a.col - 1, a.rotation)) {
      a.col -= 1;
    }
  }

  void moveRight() {
    if (_lockedOut) return;
    final a = _active!;
    if (!_collides(a, a.row, a.col + 1, a.rotation)) {
      a.col += 1;
    }
  }

  void softDrop() {
    if (_lockedOut) return;
    final a = _active!;
    if (!_collides(a, a.row + 1, a.col, a.rotation)) {
      a.row += 1;
    } else {
      _lock();
    }
  }

  void rotate() {
    if (_lockedOut) return;
    final a = _active!;
    final nextRot = (a.rotation + 1) % 4;
    // Simple wall-kick: try col, col-1, col+1, col-2, col+2.
    const kicks = [0, -1, 1, -2, 2];
    for (final k in kicks) {
      if (!_collides(a, a.row, a.col + k, nextRot)) {
        a.col += k;
        a.rotation = nextRot;
        HapticFeedback.lightImpact();
        return;
      }
    }
  }

  void hardDrop() {
    if (_lockedOut) return;
    final a = _active!;
    var drop = 0;
    while (!_collides(a, a.row + drop + 1, a.col, a.rotation)) {
      drop++;
    }
    a.row += drop;
    _lock();
  }

  void reset() {
    grid = List.generate(rows, (_) => List<int>.filled(cols, 0));
    score = 0;
    linesCleared = 0;
    _fallInterval = 0.5;
    _fallAccum = 0;
    gameOver = false;
    _suspended = false;
    scoreN.value = 0;
    linesN.value = 0;
    gameOverN.value = false;
    _next = _randomPiece();
    nextN.value = _next;
    _spawn();
  }

  bool get _lockedOut => gameOver || _suspended || _active == null;

  // ---- Game loop ----
  @override
  void update(double dt) {
    super.update(dt);
    if (_lockedOut) return;
    _fallAccum += dt;
    if (_fallAccum >= _fallInterval) {
      _fallAccum = 0;
      final a = _active!;
      if (!_collides(a, a.row + 1, a.col, a.rotation)) {
        a.row += 1;
      } else {
        _lock();
      }
    }
  }

  // ---- Render ----
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final sz = size;
    if (sz.x <= 0 || sz.y <= 0) return;

    // Compute cell size that fits within the FlameGame area while keeping 1:2 board ratio.
    final cellW = sz.x / cols;
    final cellH = sz.y / rows;
    final cell = min(cellW, cellH);
    final boardW = cell * cols;
    final boardH = cell * rows;
    final ox = (sz.x - boardW) / 2;
    final oy = (sz.y - boardH) / 2;

    // Backdrop panel.
    final panel = Paint()..color = AppTheme.surface;
    final border = Paint()
      ..color = AppTheme.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Rect.fromLTWH(ox - 2, oy - 2, boardW + 4, boardH + 4);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(rrect, panel);
    canvas.drawRRect(rrect, border);

    // Grid lines (faint).
    final gridLine = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var c = 1; c < cols; c++) {
      final x = ox + c * cell;
      canvas.drawLine(Offset(x, oy), Offset(x, oy + boardH), gridLine);
    }
    for (var r = 1; r < rows; r++) {
      final y = oy + r * cell;
      canvas.drawLine(Offset(ox, y), Offset(ox + boardW, y), gridLine);
    }

    // Locked cells.
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final id = grid[r][c];
        if (id == 0) continue;
        _drawCell(canvas, ox + c * cell, oy + r * cell, cell, _colorFor(id));
      }
    }

    // Ghost piece.
    final a = _active;
    if (a != null && !gameOver) {
      var drop = 0;
      while (!_collides(a, a.row + drop + 1, a.col, a.rotation)) {
        drop++;
      }
      final ghostPaint = Paint()
        ..color = a.piece.color.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final rc in a.cells) {
        final r = a.row + rc[0] + drop;
        final c = a.col + rc[1];
        if (r < 0 || r >= rows || c < 0 || c >= cols) continue;
        final x = ox + c * cell;
        final y = oy + r * cell;
        final cellRect = Rect.fromLTWH(
          x + 2,
          y + 2,
          cell - 4,
          cell - 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(cellRect, const Radius.circular(3)),
          ghostPaint,
        );
      }

      // Active piece.
      for (final rc in a.cells) {
        final r = a.row + rc[0];
        final c = a.col + rc[1];
        if (r < 0) continue;
        _drawCell(canvas, ox + c * cell, oy + r * cell, cell, a.piece.color);
      }
    }

    if (gameOver) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'GAME OVER',
          style: TextStyle(
            color: AppTheme.rose,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 8),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(ox + (boardW - tp.width) / 2, oy + boardH / 2 - tp.height / 2),
      );
    }
  }

  void _drawCell(Canvas canvas, double x, double y, double cell, Color color) {
    final fill = Paint()..color = color;
    final inner = Rect.fromLTWH(x + 1, y + 1, cell - 2, cell - 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, const Radius.circular(3)),
      fill,
    );
    // subtle top highlight
    final hi = Paint()..color = Colors.white.withValues(alpha: 0.18);
    final hiRect = Rect.fromLTWH(x + 2, y + 2, cell - 4, (cell - 4) * 0.35);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hiRect, const Radius.circular(2)),
      hi,
    );
  }

  Color _colorFor(int id) {
    for (final p in _pieces) {
      if (p.id == id) return p.color;
    }
    return AppTheme.textDim;
  }

  /// Public helper for the AppBar next-piece chip.
  static List<List<int>> previewCells(Object piece) {
    final p = piece as _Piece;
    return p.rotations[0];
  }

  static Color previewColor(Object piece) {
    final p = piece as _Piece;
    return p.color;
  }
}
