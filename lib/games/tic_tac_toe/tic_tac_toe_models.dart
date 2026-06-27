// Pure-dart game logic for tic-tac-toe: board state, win detection, and an
// AI opponent built around full-tree minimax with alpha-beta pruning.
//
// The board is 9 cells indexed 0..8 reading top-left → bottom-right. Each
// cell is either `Mark.empty`, `Mark.x`, or `Mark.o`. Tic-tac-toe's full
// game tree is tiny (≤ 9! / pruning), so we don't need depth limits.
import 'dart:math';

enum Mark { empty, x, o }

enum AiDifficulty { easy, medium, hard }

/// All eight winning triples (rows, cols, diagonals).
const List<List<int>> kWinLines = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8], // rows
  [0, 3, 6], [1, 4, 7], [2, 5, 8], // cols
  [0, 4, 8], [2, 4, 6],            // diagonals
];

/// Result of a board scan — either no winner yet or a winning [Mark]
/// with the triple of cell indices that won.
class WinResult {
  final Mark winner;       // Mark.empty == no winner
  final List<int>? line;   // null if no winner
  const WinResult(this.winner, this.line);

  static const none = WinResult(Mark.empty, null);
  bool get hasWinner => winner != Mark.empty;
}

/// Inspect the board and return the winning line, if any.
WinResult detectWin(List<Mark> board) {
  for (final line in kWinLines) {
    final a = board[line[0]];
    if (a == Mark.empty) continue;
    if (a == board[line[1]] && a == board[line[2]]) {
      return WinResult(a, line);
    }
  }
  return WinResult.none;
}

/// True when no empty cells remain.
bool isBoardFull(List<Mark> board) {
  for (final c in board) {
    if (c == Mark.empty) return false;
  }
  return true;
}

/// List of empty cell indices.
List<int> emptyCells(List<Mark> board) {
  final out = <int>[];
  for (var i = 0; i < 9; i++) {
    if (board[i] == Mark.empty) out.add(i);
  }
  return out;
}

/// Picks the AI's next move for the given board. The AI plays as [aiMark]
/// (which is always [Mark.o] in the screen, but kept generic for tests).
class TttAi {
  final Random _rng;
  TttAi({Random? rng}) : _rng = rng ?? Random();

  int chooseMove(List<Mark> board, Mark aiMark, AiDifficulty diff) {
    final moves = emptyCells(board);
    if (moves.isEmpty) return -1;

    switch (diff) {
      case AiDifficulty.easy:
        return moves[_rng.nextInt(moves.length)];
      case AiDifficulty.medium:
        // 60% optimal, 40% random — gives Sid a fighting chance with
        // occasional blunders that still feel human.
        if (_rng.nextDouble() < 0.6) return _bestMove(board, aiMark);
        return moves[_rng.nextInt(moves.length)];
      case AiDifficulty.hard:
        return _bestMove(board, aiMark);
    }
  }

  /// Full-tree minimax with alpha-beta pruning. The state space is small
  /// enough that we explore everything; pruning still cuts work meaningfully.
  int _bestMove(List<Mark> board, Mark aiMark) {
    final opp = aiMark == Mark.x ? Mark.o : Mark.x;
    var bestScore = -1000;
    var bestMove = -1;
    final moves = emptyCells(board);
    // Center-first ordering helps alpha-beta prune more aggressively.
    moves.sort((a, b) => _centerBias(a).compareTo(_centerBias(b)));
    for (final m in moves) {
      board[m] = aiMark;
      final score = _minimax(board, false, aiMark, opp, -1000, 1000, 1);
      board[m] = Mark.empty;
      if (score > bestScore) {
        bestScore = score;
        bestMove = m;
      }
    }
    return bestMove;
  }

  int _centerBias(int i) {
    if (i == 4) return 0;
    if (i == 0 || i == 2 || i == 6 || i == 8) return 1;
    return 2;
  }

  /// Returns a score from the AI's perspective. Prefers faster wins and
  /// slower losses by subtracting/adding the ply depth.
  int _minimax(List<Mark> board, bool aiTurn, Mark ai, Mark opp,
      int alpha, int beta, int depth) {
    final w = detectWin(board);
    if (w.hasWinner) {
      return w.winner == ai ? 10 - depth : depth - 10;
    }
    if (isBoardFull(board)) return 0;

    if (aiTurn) {
      var best = -1000;
      for (final m in emptyCells(board)) {
        board[m] = ai;
        final s = _minimax(board, false, ai, opp, alpha, beta, depth + 1);
        board[m] = Mark.empty;
        if (s > best) best = s;
        if (best > alpha) alpha = best;
        if (beta <= alpha) break;
      }
      return best;
    } else {
      var best = 1000;
      for (final m in emptyCells(board)) {
        board[m] = opp;
        final s = _minimax(board, true, ai, opp, alpha, beta, depth + 1);
        board[m] = Mark.empty;
        if (s < best) best = s;
        if (best < beta) beta = best;
        if (beta <= alpha) break;
      }
      return best;
    }
  }
}
