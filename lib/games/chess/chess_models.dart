// Pure-dart chess engine — board state, legal-move generation, minimax AI.
//
// No external chess libraries. The board is a flat 64-cell list, indexed
// 0..63 where 0 = a8 (top-left from white's perspective) and 63 = h1
// (bottom-right). Rank 8 sits at indices 0..7, rank 1 at 56..63.
//
// We track everything mutable on [GameState]: piece grid, side-to-move,
// castling rights, en-passant target square, halfmove clock, fullmove
// number, plus a tiny move-history stack so the AI can undo cleanly.
//
// The AI is alpha-beta minimax with material + piece-square tables.
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Basic enums + value types.
// ---------------------------------------------------------------------------

enum PieceColor { white, black }

extension PieceColorOps on PieceColor {
  PieceColor get other =>
      this == PieceColor.white ? PieceColor.black : PieceColor.white;
}

enum PieceKind { pawn, knight, bishop, rook, queen, king }

class Piece {
  final PieceColor color;
  final PieceKind kind;
  const Piece(this.color, this.kind);

  /// Unicode glyph (we render in colour, so glyph choice is purely visual —
  /// we use the solid black glyphs and recolour them).
  String get glyph {
    switch (kind) {
      case PieceKind.king:   return '♚'; // ♚
      case PieceKind.queen:  return '♛'; // ♛
      case PieceKind.rook:   return '♜'; // ♜
      case PieceKind.bishop: return '♝'; // ♝
      case PieceKind.knight: return '♞'; // ♞
      case PieceKind.pawn:   return '♟'; // ♟
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Piece && other.color == color && other.kind == kind;
  @override
  int get hashCode => color.hashCode * 31 + kind.hashCode;
}

/// A move from [from] to [to]. May be a special move:
///   - [promotion]: pawn reaches last rank — what to become.
///   - [isCastle]: true for both sides of castling.
///   - [isEnPassant]: true if a pawn captured via en-passant.
class Move {
  final int from;
  final int to;
  final PieceKind? promotion;
  final bool isCastle;
  final bool isEnPassant;

  const Move(
    this.from,
    this.to, {
    this.promotion,
    this.isCastle = false,
    this.isEnPassant = false,
  });

  @override
  bool operator ==(Object other) =>
      other is Move &&
      other.from == from &&
      other.to == to &&
      other.promotion == promotion &&
      other.isCastle == isCastle &&
      other.isEnPassant == isEnPassant;

  @override
  int get hashCode =>
      Object.hash(from, to, promotion, isCastle, isEnPassant);

  @override
  String toString() {
    final p = promotion != null ? '=${_kindLetter(promotion!)}' : '';
    return '${squareName(from)}${squareName(to)}$p';
  }
}

String _kindLetter(PieceKind k) {
  switch (k) {
    case PieceKind.knight: return 'N';
    case PieceKind.bishop: return 'B';
    case PieceKind.rook:   return 'R';
    case PieceKind.queen:  return 'Q';
    case PieceKind.king:   return 'K';
    case PieceKind.pawn:   return '';
  }
}

/// Convert square index 0..63 → algebraic, e.g. 0 → "a8", 63 → "h1".
String squareName(int idx) {
  final file = idx & 7;          // 0..7 → a..h
  final rank = 8 - (idx >> 3);   // 0..7 → 8..1
  return '${String.fromCharCode(0x61 + file)}$rank';
}

int fileOf(int idx) => idx & 7;
int rankOf(int idx) => idx >> 3; // 0 = top (rank 8), 7 = bottom (rank 1)

// ---------------------------------------------------------------------------
// Castling rights bitmask.
// ---------------------------------------------------------------------------

class CastleRights {
  bool wK, wQ, bK, bQ;
  CastleRights({this.wK = true, this.wQ = true, this.bK = true, this.bQ = true});

  CastleRights copy() =>
      CastleRights(wK: wK, wQ: wQ, bK: bK, bQ: bQ);
}

// ---------------------------------------------------------------------------
// Game state.
// ---------------------------------------------------------------------------

class GameState {
  /// 64 squares; null = empty.
  List<Piece?> board;
  PieceColor turn;
  CastleRights castle;
  /// En-passant target square index (the square the capturing pawn would
  /// move to), or -1 if none.
  int epSquare;
  int halfmoveClock;
  int fullmoveNumber;

  GameState({
    required this.board,
    required this.turn,
    required this.castle,
    required this.epSquare,
    required this.halfmoveClock,
    required this.fullmoveNumber,
  });

  factory GameState.initial() {
    final b = List<Piece?>.filled(64, null);
    // Black back rank (rank 8 → indices 0..7).
    const backRank = [
      PieceKind.rook, PieceKind.knight, PieceKind.bishop, PieceKind.queen,
      PieceKind.king, PieceKind.bishop, PieceKind.knight, PieceKind.rook,
    ];
    for (var f = 0; f < 8; f++) {
      b[f] = Piece(PieceColor.black, backRank[f]);
      b[8 + f] = const Piece(PieceColor.black, PieceKind.pawn);
      b[48 + f] = const Piece(PieceColor.white, PieceKind.pawn);
      b[56 + f] = Piece(PieceColor.white, backRank[f]);
    }
    return GameState(
      board: b,
      turn: PieceColor.white,
      castle: CastleRights(),
      epSquare: -1,
      halfmoveClock: 0,
      fullmoveNumber: 1,
    );
  }

  GameState clone() => GameState(
        board: List<Piece?>.from(board),
        turn: turn,
        castle: castle.copy(),
        epSquare: epSquare,
        halfmoveClock: halfmoveClock,
        fullmoveNumber: fullmoveNumber,
      );

  /// Locate the king of [c]; returns -1 if not found (shouldn't happen).
  int kingSquare(PieceColor c) {
    for (var i = 0; i < 64; i++) {
      final p = board[i];
      if (p != null && p.color == c && p.kind == PieceKind.king) return i;
    }
    return -1;
  }
}

// ---------------------------------------------------------------------------
// Move execution with undo support.
//
// We snapshot enough info on the way in (captured piece, ep square,
// castle rights, etc.) so [undo] can perfectly reverse the move. That's
// the cornerstone of a fast minimax search — we mutate-and-undo instead
// of cloning the whole state on every node.
// ---------------------------------------------------------------------------

class _Undo {
  final Move move;
  final Piece? captured;          // captured piece (or ep-captured pawn)
  final int capturedIdx;          // where the captured piece sat
  final int prevEp;
  final CastleRights prevCastle;
  final int prevHalfmove;
  final Piece movedBefore;        // the piece that moved (pre-promotion)
  _Undo({
    required this.move,
    required this.captured,
    required this.capturedIdx,
    required this.prevEp,
    required this.prevCastle,
    required this.prevHalfmove,
    required this.movedBefore,
  });
}

class ChessEngine {
  ChessEngine();

  // ===== move execution ====================================================

  /// Mutates [s] applying [m]. Returns the undo token. Assumes legality —
  /// callers should pre-filter with [legalMoves].
  _Undo _make(GameState s, Move m) {
    final piece = s.board[m.from]!;
    Piece? captured = s.board[m.to];
    var capturedIdx = m.to;

    final undo = _Undo(
      move: m,
      captured: captured,
      capturedIdx: capturedIdx,
      prevEp: s.epSquare,
      prevCastle: s.castle.copy(),
      prevHalfmove: s.halfmoveClock,
      movedBefore: piece,
    );

    // En-passant capture removes a pawn from a different square.
    if (m.isEnPassant) {
      final dir = piece.color == PieceColor.white ? 1 : -1; // rows: white pawn moves "up" (idx -8)
      capturedIdx = m.to + 8 * dir; // the captured pawn sits one rank "behind" the target
      captured = s.board[capturedIdx];
      s.board[capturedIdx] = null;
    }

    s.board[m.from] = null;
    s.board[m.to] = m.promotion != null
        ? Piece(piece.color, m.promotion!)
        : piece;

    // Castling: also move the rook.
    if (m.isCastle) {
      if (m.to == m.from + 2) {
        // King-side
        final rookFrom = m.from + 3;
        final rookTo = m.from + 1;
        s.board[rookTo] = s.board[rookFrom];
        s.board[rookFrom] = null;
      } else {
        // Queen-side
        final rookFrom = m.from - 4;
        final rookTo = m.from - 1;
        s.board[rookTo] = s.board[rookFrom];
        s.board[rookFrom] = null;
      }
    }

    // Update castling rights — king or rook move/loss.
    if (piece.kind == PieceKind.king) {
      if (piece.color == PieceColor.white) {
        s.castle.wK = false; s.castle.wQ = false;
      } else {
        s.castle.bK = false; s.castle.bQ = false;
      }
    }
    if (piece.kind == PieceKind.rook) {
      if (m.from == 63) s.castle.wK = false;
      if (m.from == 56) s.castle.wQ = false;
      if (m.from == 7)  s.castle.bK = false;
      if (m.from == 0)  s.castle.bQ = false;
    }
    // Capturing a rook on its starting square removes that side's right.
    if (captured != null && captured.kind == PieceKind.rook) {
      if (capturedIdx == 63) s.castle.wK = false;
      if (capturedIdx == 56) s.castle.wQ = false;
      if (capturedIdx == 7)  s.castle.bK = false;
      if (capturedIdx == 0)  s.castle.bQ = false;
    }

    // Set new ep square (only on a two-square pawn push).
    if (piece.kind == PieceKind.pawn && (m.to - m.from).abs() == 16) {
      s.epSquare = (m.from + m.to) ~/ 2;
    } else {
      s.epSquare = -1;
    }

    // Halfmove clock — reset on pawn move or capture.
    if (piece.kind == PieceKind.pawn || captured != null) {
      s.halfmoveClock = 0;
    } else {
      s.halfmoveClock++;
    }
    if (s.turn == PieceColor.black) s.fullmoveNumber++;
    s.turn = s.turn.other;

    // Replace the recorded capture info if it was en-passant (we needed
    // the right capturedIdx, which we computed above).
    if (m.isEnPassant) {
      return _Undo(
        move: m,
        captured: captured,
        capturedIdx: capturedIdx,
        prevEp: undo.prevEp,
        prevCastle: undo.prevCastle,
        prevHalfmove: undo.prevHalfmove,
        movedBefore: undo.movedBefore,
      );
    }
    return undo;
  }

  void _undo(GameState s, _Undo u) {
    final m = u.move;
    s.turn = s.turn.other;
    if (s.turn == PieceColor.black) s.fullmoveNumber--;
    s.halfmoveClock = u.prevHalfmove;
    s.castle = u.prevCastle;
    s.epSquare = u.prevEp;

    // Undo castling rook move first (king will be undone below).
    if (m.isCastle) {
      if (m.to == m.from + 2) {
        final rookFrom = m.from + 3;
        final rookTo = m.from + 1;
        s.board[rookFrom] = s.board[rookTo];
        s.board[rookTo] = null;
      } else {
        final rookFrom = m.from - 4;
        final rookTo = m.from - 1;
        s.board[rookFrom] = s.board[rookTo];
        s.board[rookTo] = null;
      }
    }

    // Move the (pre-promotion) piece back.
    s.board[m.from] = u.movedBefore;
    s.board[m.to] = null;

    // Restore captured piece.
    if (u.captured != null) {
      s.board[u.capturedIdx] = u.captured;
    }
  }

  /// Public API — apply a move and return the resulting state. Does NOT
  /// mutate the input. Use for the UI's main game progression.
  GameState applyMove(GameState s, Move m) {
    final next = s.clone();
    _make(next, m);
    return next;
  }

  // ===== move generation ===================================================

  /// All pseudo-legal moves for [s.turn] (may leave king in check).
  List<Move> _pseudoMoves(GameState s) {
    final out = <Move>[];
    final me = s.turn;
    for (var i = 0; i < 64; i++) {
      final p = s.board[i];
      if (p == null || p.color != me) continue;
      switch (p.kind) {
        case PieceKind.pawn:   _pawnMoves(s, i, out); break;
        case PieceKind.knight: _stepMoves(s, i, _knightSteps, out); break;
        case PieceKind.king:   _stepMoves(s, i, _kingSteps, out);
                               _castleMoves(s, i, out); break;
        case PieceKind.bishop: _slideMoves(s, i, _bishopDirs, out); break;
        case PieceKind.rook:   _slideMoves(s, i, _rookDirs, out); break;
        case PieceKind.queen:  _slideMoves(s, i, _bishopDirs, out);
                               _slideMoves(s, i, _rookDirs, out); break;
      }
    }
    return out;
  }

  /// Fully legal moves for the side to move. Filters pseudo-legal moves
  /// to exclude those that leave the king in check.
  List<Move> legalMoves(GameState s) {
    final out = <Move>[];
    final pseudo = _pseudoMoves(s);
    for (final m in pseudo) {
      final u = _make(s, m);
      final inCheck = _isSquareAttacked(
        s,
        s.kingSquare(s.turn.other), // we just flipped turn
        s.turn,                     // attacker is now opposite of moving side
      );
      _undo(s, u);
      if (!inCheck) out.add(m);
    }
    return out;
  }

  /// Legal moves for the piece on [from] — used by the UI when the player
  /// taps a square. Returns empty list if no piece or wrong colour.
  List<Move> legalMovesFrom(GameState s, int from) {
    final p = s.board[from];
    if (p == null || p.color != s.turn) return const [];
    return legalMoves(s).where((m) => m.from == from).toList();
  }

  // --- piece-specific generation -----

  static const _knightSteps = [-17, -15, -10, -6, 6, 10, 15, 17];
  static const _kingSteps   = [-9, -8, -7, -1, 1, 7, 8, 9];
  static const _bishopDirs  = [-9, -7, 7, 9];
  static const _rookDirs    = [-8, -1, 1, 8];

  void _stepMoves(GameState s, int from, List<int> steps, List<Move> out) {
    final p = s.board[from]!;
    final fFile = fileOf(from);
    for (final d in steps) {
      final to = from + d;
      if (to < 0 || to >= 64) continue;
      // File-wrap guard: a king/knight can't jump from h-file to a-file.
      final tFile = fileOf(to);
      if ((fFile - tFile).abs() > 2) continue;
      final tgt = s.board[to];
      if (tgt == null || tgt.color != p.color) {
        out.add(Move(from, to));
      }
    }
  }

  void _slideMoves(GameState s, int from, List<int> dirs, List<Move> out) {
    final p = s.board[from]!;
    for (final d in dirs) {
      var prev = from;
      var to = from + d;
      while (to >= 0 && to < 64) {
        // File-wrap guard: stop if we wrapped from h → a (or a → h).
        if ((fileOf(prev) - fileOf(to)).abs() > 1) break;
        final tgt = s.board[to];
        if (tgt == null) {
          out.add(Move(from, to));
        } else {
          if (tgt.color != p.color) out.add(Move(from, to));
          break;
        }
        prev = to;
        to += d;
      }
    }
  }

  void _pawnMoves(GameState s, int from, List<Move> out) {
    final p = s.board[from]!;
    final dir = p.color == PieceColor.white ? -8 : 8;     // white moves up = idx -8
    final startRank = p.color == PieceColor.white ? 6 : 1; // pre-double-push rank
    final promoRank = p.color == PieceColor.white ? 0 : 7; // rank of promotion target

    final one = from + dir;
    if (one >= 0 && one < 64 && s.board[one] == null) {
      if (rankOf(one) == promoRank) {
        _emitPromotions(from, one, out);
      } else {
        out.add(Move(from, one));
        // Double push from start rank.
        if (rankOf(from) == startRank) {
          final two = from + dir * 2;
          if (s.board[two] == null) out.add(Move(from, two));
        }
      }
    }

    // Captures (incl. en passant).
    for (final dc in [-1, 1]) {
      final to = from + dir + dc;
      if (to < 0 || to >= 64) continue;
      if ((fileOf(from) - fileOf(to)).abs() != 1) continue;
      final tgt = s.board[to];
      if (tgt != null && tgt.color != p.color) {
        if (rankOf(to) == promoRank) {
          _emitPromotions(from, to, out);
        } else {
          out.add(Move(from, to));
        }
      } else if (tgt == null && to == s.epSquare) {
        out.add(Move(from, to, isEnPassant: true));
      }
    }
  }

  void _emitPromotions(int from, int to, List<Move> out) {
    for (final k in [
      PieceKind.queen, PieceKind.rook, PieceKind.bishop, PieceKind.knight,
    ]) {
      out.add(Move(from, to, promotion: k));
    }
  }

  void _castleMoves(GameState s, int from, List<Move> out) {
    final p = s.board[from]!;
    final isWhite = p.color == PieceColor.white;
    final homeKing = isWhite ? 60 : 4;
    if (from != homeKing) return;
    // King in check? Can't castle.
    if (_isSquareAttacked(s, from, p.color.other)) return;

    final rights = s.castle;
    final canK = isWhite ? rights.wK : rights.bK;
    final canQ = isWhite ? rights.wQ : rights.bQ;

    if (canK) {
      // squares between king and h-rook: from+1, from+2.
      if (s.board[from + 1] == null &&
          s.board[from + 2] == null &&
          s.board[from + 3] != null &&
          s.board[from + 3]!.kind == PieceKind.rook &&
          s.board[from + 3]!.color == p.color &&
          !_isSquareAttacked(s, from + 1, p.color.other) &&
          !_isSquareAttacked(s, from + 2, p.color.other)) {
        out.add(Move(from, from + 2, isCastle: true));
      }
    }
    if (canQ) {
      if (s.board[from - 1] == null &&
          s.board[from - 2] == null &&
          s.board[from - 3] == null &&
          s.board[from - 4] != null &&
          s.board[from - 4]!.kind == PieceKind.rook &&
          s.board[from - 4]!.color == p.color &&
          !_isSquareAttacked(s, from - 1, p.color.other) &&
          !_isSquareAttacked(s, from - 2, p.color.other)) {
        out.add(Move(from, from - 2, isCastle: true));
      }
    }
  }

  // ===== check / attack detection ==========================================

  /// Is [sq] attacked by any piece of [by] in [s]?
  bool _isSquareAttacked(GameState s, int sq, PieceColor by) {
    if (sq < 0) return false;
    // Pawn attacks.
    final pawnDir = by == PieceColor.white ? 8 : -8; // attacker pawn sits at sq + pawnDir
    for (final dc in [-1, 1]) {
      final from = sq + pawnDir + dc;
      if (from < 0 || from >= 64) continue;
      if ((fileOf(sq) - fileOf(from)).abs() != 1) continue;
      final p = s.board[from];
      if (p != null && p.color == by && p.kind == PieceKind.pawn) return true;
    }
    // Knight attacks.
    for (final d in _knightSteps) {
      final from = sq + d;
      if (from < 0 || from >= 64) continue;
      if ((fileOf(sq) - fileOf(from)).abs() > 2) continue;
      final p = s.board[from];
      if (p != null && p.color == by && p.kind == PieceKind.knight) return true;
    }
    // King attacks (adjacent squares).
    for (final d in _kingSteps) {
      final from = sq + d;
      if (from < 0 || from >= 64) continue;
      if ((fileOf(sq) - fileOf(from)).abs() > 1) continue;
      final p = s.board[from];
      if (p != null && p.color == by && p.kind == PieceKind.king) return true;
    }
    // Sliders: bishops/queens on diagonals, rooks/queens on files+ranks.
    if (_slideAttack(s, sq, by, _bishopDirs,
        const {PieceKind.bishop, PieceKind.queen})) {
      return true;
    }
    if (_slideAttack(s, sq, by, _rookDirs,
        const {PieceKind.rook, PieceKind.queen})) {
      return true;
    }
    return false;
  }

  bool _slideAttack(GameState s, int sq, PieceColor by,
      List<int> dirs, Set<PieceKind> kinds) {
    for (final d in dirs) {
      var prev = sq;
      var to = sq + d;
      while (to >= 0 && to < 64) {
        if ((fileOf(prev) - fileOf(to)).abs() > 1) break;
        final p = s.board[to];
        if (p != null) {
          if (p.color == by && kinds.contains(p.kind)) return true;
          break;
        }
        prev = to;
        to += d;
      }
    }
    return false;
  }

  /// Is [c]'s king currently in check?
  bool inCheck(GameState s, PieceColor c) =>
      _isSquareAttacked(s, s.kingSquare(c), c.other);

  // ===== terminal-state classification =====================================

  GameResult result(GameState s) {
    final moves = legalMoves(s);
    if (moves.isEmpty) {
      if (inCheck(s, s.turn)) {
        return s.turn == PieceColor.white
            ? GameResult.blackMate
            : GameResult.whiteMate;
      }
      return GameResult.stalemate;
    }
    if (s.halfmoveClock >= 100) return GameResult.fiftyMove;
    if (_insufficientMaterial(s)) return GameResult.insufficient;
    return GameResult.ongoing;
  }

  bool _insufficientMaterial(GameState s) {
    // Quick check: K vs K, K+minor vs K, K+minor vs K+minor (any colours).
    var minors = 0;
    for (var i = 0; i < 64; i++) {
      final p = s.board[i];
      if (p == null) continue;
      switch (p.kind) {
        case PieceKind.pawn:
        case PieceKind.rook:
        case PieceKind.queen:
          return false;
        case PieceKind.bishop:
        case PieceKind.knight:
          minors++;
          break;
        case PieceKind.king:
          break;
      }
    }
    return minors <= 2;
  }

  // ===== AI: minimax + alpha-beta ==========================================

  /// Choose best move for [s.turn] with the requested [difficulty]. Returns
  /// null if the side to move has no legal moves.
  Move? chooseMove(GameState s, AiDifficulty difficulty) {
    final depth = switch (difficulty) {
      AiDifficulty.easy   => 1,
      AiDifficulty.medium => 2,
      AiDifficulty.hard   => 3,
    };
    final usePsq = difficulty == AiDifficulty.hard;

    final moves = legalMoves(s);
    if (moves.isEmpty) return null;

    // Easy: a small random sprinkle so the AI feels human and varies its
    // openings. Sort by quick eval, then jitter among the top picks.
    final rng = math.Random();
    final maximising = s.turn == PieceColor.white;

    Move? best;
    var bestScore = maximising ? -1 << 30 : 1 << 30;
    final scored = <_ScoredMove>[];

    for (final m in moves) {
      final u = _make(s, m);
      final score = -_negamax(
        s,
        depth - 1,
        -1 << 30,
        1 << 30,
        s.turn == PieceColor.white ? 1 : -1,
        usePsq,
      ) * (maximising ? 1 : -1);
      // Re-derive from white-perspective for selection.
      final whiteEval = _evaluate(s, usePsq);
      _undo(s, u);
      scored.add(_ScoredMove(m, score, whiteEval));
    }

    if (difficulty == AiDifficulty.easy) {
      scored.sort((a, b) => maximising
          ? b.score.compareTo(a.score)
          : a.score.compareTo(b.score));
      final top = scored.take(math.min(4, scored.length)).toList();
      return top[rng.nextInt(top.length)].move;
    }

    for (final sm in scored) {
      if (maximising ? sm.score > bestScore : sm.score < bestScore) {
        bestScore = sm.score;
        best = sm.move;
      }
    }
    return best ?? moves.first;
  }

  /// Negamax with alpha-beta. [colour] = +1 if white-to-move, -1 if black.
  /// Returns the evaluation from the side-to-move's perspective.
  int _negamax(GameState s, int depth, int alpha, int beta, int colour,
      bool usePsq) {
    if (depth == 0) {
      return colour * _evaluate(s, usePsq);
    }
    final moves = legalMoves(s);
    if (moves.isEmpty) {
      if (inCheck(s, s.turn)) {
        // Mate — negative huge from the mated side's POV (we add depth so
        // shorter mates score higher when negated by the caller).
        return -1000000 + (10 - depth);
      }
      return 0; // stalemate
    }
    // Move ordering: try captures first for better alpha-beta pruning.
    moves.sort((a, b) {
      final ca = s.board[a.to] != null ? 1 : 0;
      final cb = s.board[b.to] != null ? 1 : 0;
      return cb - ca;
    });
    var best = -1 << 30;
    for (final m in moves) {
      final u = _make(s, m);
      final score = -_negamax(s, depth - 1, -beta, -alpha, -colour, usePsq);
      _undo(s, u);
      if (score > best) best = score;
      if (best > alpha) alpha = best;
      if (alpha >= beta) break;
    }
    return best;
  }

  // ===== evaluation ========================================================

  static const _matVal = {
    PieceKind.pawn:   100,
    PieceKind.knight: 320,
    PieceKind.bishop: 330,
    PieceKind.rook:   500,
    PieceKind.queen:  900,
    PieceKind.king:   0,
  };

  // Piece-square tables, white perspective, index 0 = a8. Black squares
  // are mirrored at lookup time.
  static const List<int> _pawnPsq = [
      0,  0,  0,  0,  0,  0,  0,  0,
     50, 50, 50, 50, 50, 50, 50, 50,
     10, 10, 20, 30, 30, 20, 10, 10,
      5,  5, 10, 25, 25, 10,  5,  5,
      0,  0,  0, 20, 20,  0,  0,  0,
      5, -5,-10,  0,  0,-10, -5,  5,
      5, 10, 10,-20,-20, 10, 10,  5,
      0,  0,  0,  0,  0,  0,  0,  0,
  ];
  static const List<int> _knightPsq = [
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50,
  ];
  static const List<int> _bishopPsq = [
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5, 10, 10,  5,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20,
  ];
  static const List<int> _rookPsq = [
      0,  0,  0,  0,  0,  0,  0,  0,
      5, 10, 10, 10, 10, 10, 10,  5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
     -5,  0,  0,  0,  0,  0,  0, -5,
      0,  0,  0,  5,  5,  0,  0,  0,
  ];
  static const List<int> _queenPsq = [
    -20,-10,-10, -5, -5,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20,
  ];
  static const List<int> _kingPsq = [
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
     20, 20,  0,  0,  0,  0, 20, 20,
     20, 30, 10,  0,  0, 10, 30, 20,
  ];

  /// White-positive evaluation in centipawns. Material + (optionally)
  /// piece-square tables for positional nudging.
  int _evaluate(GameState s, bool usePsq) {
    var score = 0;
    for (var i = 0; i < 64; i++) {
      final p = s.board[i];
      if (p == null) continue;
      final v = _matVal[p.kind]!;
      score += p.color == PieceColor.white ? v : -v;
      if (!usePsq) continue;
      final idxFromWhite = p.color == PieceColor.white ? i : (56 - (i & ~7) + (i & 7));
      int psq;
      switch (p.kind) {
        case PieceKind.pawn:   psq = _pawnPsq[idxFromWhite]; break;
        case PieceKind.knight: psq = _knightPsq[idxFromWhite]; break;
        case PieceKind.bishop: psq = _bishopPsq[idxFromWhite]; break;
        case PieceKind.rook:   psq = _rookPsq[idxFromWhite]; break;
        case PieceKind.queen:  psq = _queenPsq[idxFromWhite]; break;
        case PieceKind.king:   psq = _kingPsq[idxFromWhite]; break;
      }
      score += p.color == PieceColor.white ? psq : -psq;
    }
    return score;
  }
}

class _ScoredMove {
  final Move move;
  final int score;
  final int whiteEval;
  _ScoredMove(this.move, this.score, this.whiteEval);
}

enum AiDifficulty { easy, medium, hard }

enum GameResult {
  ongoing,
  whiteMate,   // white delivers mate (black is mated)
  blackMate,   // black delivers mate (white is mated)
  stalemate,
  fiftyMove,
  insufficient,
}

extension GameResultOps on GameResult {
  bool get isOver => this != GameResult.ongoing;
  bool get isDraw =>
      this == GameResult.stalemate ||
      this == GameResult.fiftyMove ||
      this == GameResult.insufficient;
}

/// Algebraic-ish notation for the move list panel. Not fully SAN — we use
/// long algebraic ("e2e4", "g1f3", "e7e8=Q", "O-O", "O-O-O") because it's
/// unambiguous without re-running the move generator.
String moveToLongAlg(GameState before, Move m) {
  if (m.isCastle) return m.to > m.from ? 'O-O' : 'O-O-O';
  final piece = before.board[m.from];
  final letter = piece == null ? '' : _kindLetter(piece.kind);
  final captureSep =
      (before.board[m.to] != null || m.isEnPassant) ? 'x' : '-';
  final promo = m.promotion != null ? '=${_kindLetter(m.promotion!)}' : '';
  return '$letter${squareName(m.from)}$captureSep${squareName(m.to)}$promo';
}
