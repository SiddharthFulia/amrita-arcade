// Chess — vs-AI / vs-friend on one phone, with tap-to-move highlights,
// castling, en-passant, promotion, check/mate/stalemate detection.
//
// The engine lives in chess_models.dart. This file is the Flutter face:
// mode/difficulty chips on top, 8×8 board, status line, and an optional
// move list. White is at the bottom (Sid's perspective); the AI plays
// black in vs-ai mode.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'chess_models.dart';

enum _Mode { vsAi, vsFriend }

class ChessScreen extends StatefulWidget {
  const ChessScreen({super.key});

  @override
  State<ChessScreen> createState() => _ChessScreenState();
}

class _ChessScreenState extends State<ChessScreen>
    with SingleTickerProviderStateMixin {
  // --- engine + state ---------------------------------------------------
  final ChessEngine _engine = ChessEngine();
  GameState _state = GameState.initial();
  GameResult _result = GameResult.ongoing;

  int? _selected;                // tapped piece (square index 0..63)
  List<Move> _selectedMoves = const [];
  Move? _lastMove;               // for "from→to" highlight
  bool _aiThinking = false;

  // Move history for the side panel — pre-move state + the move played.
  final List<String> _history = [];

  // --- mode / difficulty ------------------------------------------------
  _Mode _mode = _Mode.vsAi;
  AiDifficulty _difficulty = AiDifficulty.medium;

  // --- check-glow animation --------------------------------------------
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Game flow.
  // ---------------------------------------------------------------------
  void _newGame() {
    setState(() {
      _state = GameState.initial();
      _result = GameResult.ongoing;
      _selected = null;
      _selectedMoves = const [];
      _lastMove = null;
      _aiThinking = false;
      _history.clear();
    });
  }

  void _switchMode(_Mode m) {
    if (m == _mode) return;
    setState(() { _mode = m; });
    _newGame();
  }

  void _setDifficulty(AiDifficulty d) {
    if (d == _difficulty) return;
    setState(() { _difficulty = d; });
    _newGame();
  }

  /// Player taps square [idx]. Either selects a piece, deselects, or plays
  /// a move if the tap lands on a legal destination.
  Future<void> _tapSquare(int idx) async {
    if (_result.isOver || _aiThinking) return;

    // In vs-ai mode the player only controls white.
    if (_mode == _Mode.vsAi && _state.turn != PieceColor.white) return;

    // Tap on a legal destination → play it.
    if (_selected != null) {
      final candidates =
          _selectedMoves.where((m) => m.to == idx).toList();
      if (candidates.isNotEmpty) {
        Move move = candidates.first;
        // Promotion? Ask the user if there are multiple promotion options.
        if (candidates.length > 1 &&
            candidates.every((c) => c.promotion != null)) {
          final chosen = await _askPromotion(_state.turn);
          if (chosen == null) return;
          move = candidates.firstWhere((c) => c.promotion == chosen);
        }
        _playMove(move);
        return;
      }
    }

    // Otherwise, (re)select if it's our piece.
    final p = _state.board[idx];
    if (p != null && p.color == _state.turn) {
      HapticFeedback.selectionClick();
      setState(() {
        _selected = idx;
        _selectedMoves = _engine.legalMovesFrom(_state, idx);
      });
    } else {
      setState(() {
        _selected = null;
        _selectedMoves = const [];
      });
    }
  }

  void _playMove(Move m) {
    final captured = _state.board[m.to] != null || m.isEnPassant;
    final notation = moveToLongAlg(_state, m);
    final next = _engine.applyMove(_state, m);
    final result = _engine.result(next);
    final wasCheck = _engine.inCheck(next, next.turn);

    if (wasCheck || result == GameResult.whiteMate ||
        result == GameResult.blackMate) {
      HapticFeedback.heavyImpact();
    } else if (captured) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }

    setState(() {
      _state = next;
      _result = result;
      _lastMove = m;
      _selected = null;
      _selectedMoves = const [];
      _history.add(notation);
    });

    if (result.isOver) return;
    if (_mode == _Mode.vsAi && _state.turn == PieceColor.black) {
      _runAiMove();
    }
  }

  Future<void> _runAiMove() async {
    setState(() { _aiThinking = true; });
    // Move the search off the build phase. For depth 3 it can take a few
    // hundred ms, so yield the UI thread first.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final move = await Future.microtask(
      () => _engine.chooseMove(_state, _difficulty),
    );
    if (!mounted) return;
    if (move == null) {
      setState(() {
        _aiThinking = false;
        _result = _engine.result(_state);
      });
      return;
    }
    setState(() { _aiThinking = false; });
    _playMove(move);
  }

  Future<PieceKind?> _askPromotion(PieceColor c) async {
    return showDialog<PieceKind>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('promote to', style: TextStyle(color: AppTheme.text)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in [
              PieceKind.queen, PieceKind.rook,
              PieceKind.bishop, PieceKind.knight,
            ])
              IconButton(
                iconSize: 36,
                onPressed: () => Navigator.of(ctx).pop(k),
                icon: Text(
                  Piece(c, k).glyph,
                  style: TextStyle(
                    fontSize: 34,
                    color: c == PieceColor.white
                        ? AppTheme.gold
                        : AppTheme.lavender,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // UI.
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom + 18;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('chess',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPad),
          child: Column(
            children: [
              _modePicker(),
              const SizedBox(height: 10),
              if (_mode == _Mode.vsAi) _difficultyPicker(),
              if (_mode == _Mode.vsAi) const SizedBox(height: 10),
              _statusLine(),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _boardWidget(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_history.isNotEmpty) _moveListPanel(),
              const SizedBox(height: 10),
              _buttons(),
              // Result overlay sits as an extra row below — keeps board sizing stable.
              if (_result.isOver) ...[
                const SizedBox(height: 10),
                _resultBanner(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // --- chips -----------------------------------------------------------

  Widget _modePicker() {
    return Row(
      children: [
        Expanded(child: _chip(
          label: 'vs ai',
          selected: _mode == _Mode.vsAi,
          onTap: () => _switchMode(_Mode.vsAi),
        )),
        const SizedBox(width: 8),
        Expanded(child: _chip(
          label: 'vs friend',
          selected: _mode == _Mode.vsFriend,
          onTap: () => _switchMode(_Mode.vsFriend),
        )),
      ],
    );
  }

  Widget _difficultyPicker() {
    return Row(
      children: [
        Expanded(child: _chip(
          label: 'easy',
          selected: _difficulty == AiDifficulty.easy,
          accent: AppTheme.success,
          onTap: () => _setDifficulty(AiDifficulty.easy),
        )),
        const SizedBox(width: 8),
        Expanded(child: _chip(
          label: 'medium',
          selected: _difficulty == AiDifficulty.medium,
          accent: AppTheme.gold,
          onTap: () => _setDifficulty(AiDifficulty.medium),
        )),
        const SizedBox(width: 8),
        Expanded(child: _chip(
          label: 'hard',
          selected: _difficulty == AiDifficulty.hard,
          accent: AppTheme.danger,
          onTap: () => _setDifficulty(AiDifficulty.hard),
        )),
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? accent,
  }) {
    final c = accent ?? AppTheme.rose;
    return Material(
      color: selected ? c.withValues(alpha: 0.18) : AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? c : AppTheme.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? c : AppTheme.textDim,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  // --- status ----------------------------------------------------------

  Widget _statusLine() {
    String text;
    Color colour;
    if (_result == GameResult.whiteMate) {
      text = _mode == _Mode.vsAi ? 'checkmate — you win!' : 'white wins by mate';
      colour = AppTheme.gold;
    } else if (_result == GameResult.blackMate) {
      text = _mode == _Mode.vsAi ? 'checkmate — AI wins' : 'black wins by mate';
      colour = AppTheme.lavender;
    } else if (_result == GameResult.stalemate) {
      text = 'stalemate';
      colour = AppTheme.gold;
    } else if (_result == GameResult.fiftyMove) {
      text = 'draw — fifty-move rule';
      colour = AppTheme.gold;
    } else if (_result == GameResult.insufficient) {
      text = 'draw — insufficient material';
      colour = AppTheme.gold;
    } else if (_aiThinking) {
      text = 'AI thinking…';
      colour = AppTheme.lavender;
    } else {
      final whiteToMove = _state.turn == PieceColor.white;
      final check = _engine.inCheck(_state, _state.turn);
      if (_mode == _Mode.vsAi) {
        text = whiteToMove ? 'your move' : "AI's move";
      } else {
        text = whiteToMove ? "white's turn" : "black's turn";
      }
      if (check) text = '$text — check!';
      colour = whiteToMove ? AppTheme.gold : AppTheme.lavender;
    }
    return Text(
      text,
      style: TextStyle(
        color: colour,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }

  // --- board -----------------------------------------------------------

  Widget _boardWidget() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, c) {
          // Compute legal-destination set for the currently selected piece.
          final dests = _selectedMoves.map((m) => m.to).toSet();

          // King-in-check highlight square (if any).
          int checkSq = -1;
          if (!_result.isOver && _engine.inCheck(_state, _state.turn)) {
            checkSq = _state.kingSquare(_state.turn);
          }

          return AnimatedBuilder(
            animation: _glow,
            builder: (_, _) => GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
              ),
              itemCount: 64,
              itemBuilder: (_, i) => _square(
                i,
                dests: dests,
                checkSq: checkSq,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _square(int idx, {required Set<int> dests, required int checkSq}) {
    final file = fileOf(idx);
    final rank = rankOf(idx);
    final isLight = (file + rank) % 2 == 0;

    // Rose-tinted light squares, dim-surface dark squares.
    Color bg = isLight
        ? AppTheme.rose.withValues(alpha: 0.18)
        : AppTheme.surfaceElev;

    // Last-move highlight (subtle gold tint).
    if (_lastMove != null &&
        (idx == _lastMove!.from || idx == _lastMove!.to)) {
      bg = Color.alphaBlend(AppTheme.gold.withValues(alpha: 0.22), bg);
    }
    // Selected piece — stronger gold.
    if (_selected == idx) {
      bg = Color.alphaBlend(AppTheme.gold.withValues(alpha: 0.35), bg);
    }

    final piece = _state.board[idx];
    final isCheckSq = idx == checkSq;
    final isDest = dests.contains(idx);
    final isCaptureDest = isDest && piece != null;

    return GestureDetector(
      onTap: () => _tapSquare(idx),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: isCheckSq
              ? Border.all(
                  color: AppTheme.danger.withValues(
                      alpha: 0.55 + 0.35 * _glow.value),
                  width: 2,
                )
              : null,
          boxShadow: isCheckSq
              ? [
                  BoxShadow(
                    color: AppTheme.danger.withValues(
                        alpha: 0.35 + 0.35 * _glow.value),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Coordinate labels — a..h on rank 1, 1..8 on file a.
            if (rank == 7)
              Positioned(
                right: 2, bottom: 0,
                child: Text(
                  String.fromCharCode(0x61 + file),
                  style: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.7),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (file == 0)
              Positioned(
                left: 2, top: 0,
                child: Text(
                  '${8 - rank}',
                  style: TextStyle(
                    color: AppTheme.textMuted.withValues(alpha: 0.7),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (piece != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                    piece.glyph,
                    style: TextStyle(
                      fontSize: 40,
                      height: 1.0,
                      color: piece.color == PieceColor.white
                          ? AppTheme.gold
                          : AppTheme.lavender,
                      shadows: [
                        Shadow(
                          color: (piece.color == PieceColor.white
                                  ? AppTheme.gold
                                  : AppTheme.lavender)
                              .withValues(alpha: 0.35),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Legal-move marker — dot for empty target, ring for capture.
            if (isDest && !isCaptureDest)
              IgnorePointer(
                child: Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: AppTheme.sky.withValues(alpha: 0.75),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (isCaptureDest)
              IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.85),
                      width: 2.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- move list panel -------------------------------------------------

  Widget _moveListPanel() {
    // Show up to last 6 plies, in pairs (white, black).
    final start = _history.length > 6 ? _history.length - 6 : 0;
    final visible = _history.sublist(start);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (var i = 0; i < visible.length; i++)
            Text(
              (start + i).isEven
                  ? '${((start + i) >> 1) + 1}. ${visible[i]}'
                  : visible[i],
              style: TextStyle(
                color: (start + i).isEven ? AppTheme.gold : AppTheme.lavender,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
        ],
      ),
    );
  }

  // --- buttons + banner ------------------------------------------------

  Widget _buttons() {
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: 'new game',
            color: AppTheme.rose,
            filled: true,
            onTap: _newGame,
          ),
        ),
      ],
    );
  }

  Widget _resultBanner() {
    String text;
    Color colour;
    switch (_result) {
      case GameResult.whiteMate:
        text = _mode == _Mode.vsAi ? 'you delivered checkmate!' : 'white wins!';
        colour = AppTheme.gold;
        break;
      case GameResult.blackMate:
        text = _mode == _Mode.vsAi ? 'AI delivered checkmate' : 'black wins!';
        colour = AppTheme.lavender;
        break;
      case GameResult.stalemate:
        text = 'stalemate — draw';
        colour = AppTheme.gold;
        break;
      case GameResult.fiftyMove:
        text = 'fifty-move rule — draw';
        colour = AppTheme.gold;
        break;
      case GameResult.insufficient:
        text = 'insufficient material — draw';
        colour = AppTheme.gold;
        break;
      case GameResult.ongoing:
        return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colour.withValues(alpha: 0.6), width: 1.4),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: colour,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: filled ? color.withValues(alpha: 0.18) : AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: filled ? color : AppTheme.border,
              width: filled ? 1.4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: filled ? color : AppTheme.textDim,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
