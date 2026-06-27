// Tic-tac-toe screen — mode picker, 3×3 grid, scoreboard, win line.
//
// X is always rose, O is always lavender. Two modes: vs friend (alternate
// taps on one phone) and vs computer (player is X, AI is O, three diffs).
// Scores persist per-mode in shared_preferences.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import 'tic_tac_toe_models.dart';

enum _Mode { vsFriend, vsAi }

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});

  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen>
    with SingleTickerProviderStateMixin {
  // --- game state -------------------------------------------------------
  List<Mark> _board = List.filled(9, Mark.empty);
  Mark _turn = Mark.x;
  WinResult _result = WinResult.none;
  bool _draw = false;
  bool _aiThinking = false;

  // --- mode + difficulty ------------------------------------------------
  _Mode _mode = _Mode.vsFriend;
  AiDifficulty _difficulty = AiDifficulty.medium;
  final TttAi _ai = TttAi();

  // --- score state (loaded from prefs) ---------------------------------
  int _xWins = 0;
  int _oWins = 0;
  int _draws = 0;

  // --- win-line glow animation -----------------------------------------
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _loadScores();
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Persistence — one prefs bucket per mode.
  // ---------------------------------------------------------------------
  String _kx() => _mode == _Mode.vsFriend
      ? 'ttt_vs_friend_xwins' : 'ttt_vs_ai_xwins';
  String _ko() => _mode == _Mode.vsFriend
      ? 'ttt_vs_friend_owins' : 'ttt_vs_ai_owins';
  String _kd() => _mode == _Mode.vsFriend
      ? 'ttt_vs_friend_draws' : 'ttt_vs_ai_draws';

  Future<void> _loadScores() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _xWins = p.getInt(_kx()) ?? 0;
      _oWins = p.getInt(_ko()) ?? 0;
      _draws = p.getInt(_kd()) ?? 0;
    });
  }

  Future<void> _saveScores() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kx(), _xWins);
    await p.setInt(_ko(), _oWins);
    await p.setInt(_kd(), _draws);
  }

  Future<void> _resetScores() async {
    setState(() { _xWins = 0; _oWins = 0; _draws = 0; });
    await _saveScores();
  }

  // ---------------------------------------------------------------------
  // Game flow.
  // ---------------------------------------------------------------------
  void _newGame() {
    setState(() {
      _board = List.filled(9, Mark.empty);
      _turn = Mark.x;
      _result = WinResult.none;
      _draw = false;
      _aiThinking = false;
    });
  }

  void _switchMode(_Mode m) {
    if (m == _mode) return;
    setState(() { _mode = m; });
    _newGame();
    _loadScores();
  }

  void _tapCell(int i) {
    if (_result.hasWinner || _draw) return;
    if (_aiThinking) return;
    if (_board[i] != Mark.empty) return;
    // In vs-ai mode, only X (player) may tap.
    if (_mode == _Mode.vsAi && _turn != Mark.x) return;

    HapticFeedback.selectionClick();
    _place(i, _turn);
    if (_afterMoveChecks()) return;

    // Pass turn.
    setState(() {
      _turn = _turn == Mark.x ? Mark.o : Mark.x;
    });

    if (_mode == _Mode.vsAi && _turn == Mark.o) {
      _runAiMove();
    }
  }

  void _place(int i, Mark m) {
    setState(() { _board[i] = m; });
  }

  /// Returns true if the game ended on this move.
  bool _afterMoveChecks() {
    final w = detectWin(_board);
    if (w.hasWinner) {
      setState(() { _result = w; });
      if (w.winner == Mark.x) {
        _xWins++;
      } else {
        _oWins++;
      }
      HapticFeedback.lightImpact();
      _saveScores();
      return true;
    }
    if (isBoardFull(_board)) {
      setState(() { _draw = true; });
      _draws++;
      HapticFeedback.mediumImpact();
      _saveScores();
      return true;
    }
    return false;
  }

  Future<void> _runAiMove() async {
    setState(() { _aiThinking = true; });
    // Tiny delay so it feels like the AI "thinks" rather than snapping.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    if (_result.hasWinner || _draw) {
      setState(() { _aiThinking = false; });
      return;
    }
    final move = _ai.chooseMove(List<Mark>.from(_board), Mark.o, _difficulty);
    if (move < 0) {
      setState(() { _aiThinking = false; });
      return;
    }
    HapticFeedback.selectionClick();
    _place(move, Mark.o);
    setState(() { _aiThinking = false; });
    if (_afterMoveChecks()) return;
    setState(() { _turn = Mark.x; });
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
        title: const Text('tic-tac-toe',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
          child: Column(
            children: [
              _modePicker(),
              const SizedBox(height: 12),
              if (_mode == _Mode.vsAi) _difficultyPicker(),
              if (_mode == _Mode.vsAi) const SizedBox(height: 12),
              _scoreboard(),
              const SizedBox(height: 14),
              _statusLine(),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _grid(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _buttons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modePicker() {
    return Row(
      children: [
        Expanded(child: _chip(
          label: 'vs friend',
          selected: _mode == _Mode.vsFriend,
          onTap: () => _switchMode(_Mode.vsFriend),
        )),
        const SizedBox(width: 8),
        Expanded(child: _chip(
          label: 'vs computer',
          selected: _mode == _Mode.vsAi,
          onTap: () => _switchMode(_Mode.vsAi),
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
          onTap: () { setState(() => _difficulty = AiDifficulty.easy); _newGame(); },
        )),
        const SizedBox(width: 8),
        Expanded(child: _chip(
          label: 'medium',
          selected: _difficulty == AiDifficulty.medium,
          accent: AppTheme.gold,
          onTap: () { setState(() => _difficulty = AiDifficulty.medium); _newGame(); },
        )),
        const SizedBox(width: 8),
        Expanded(child: _chip(
          label: 'hard',
          selected: _difficulty == AiDifficulty.hard,
          accent: AppTheme.danger,
          onTap: () { setState(() => _difficulty = AiDifficulty.hard); _newGame(); },
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
          padding: const EdgeInsets.symmetric(vertical: 10),
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

  Widget _scoreboard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(child: _scoreCell('X', _xWins, AppTheme.rose)),
          _vDivider(),
          Expanded(child: _scoreCell('O', _oWins, AppTheme.lavender)),
          _vDivider(),
          Expanded(child: _scoreCell('draws', _draws, AppTheme.gold)),
        ],
      ),
    );
  }

  Widget _scoreCell(String label, int v, Color c) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            )),
        const SizedBox(height: 2),
        Text('$v',
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            )),
      ],
    );
  }

  Widget _vDivider() => Container(
    width: 1, height: 32, color: AppTheme.border,
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );

  Widget _statusLine() {
    String text;
    Color color;
    if (_result.hasWinner) {
      final who = _result.winner == Mark.x ? 'X' : 'O';
      color = _result.winner == Mark.x ? AppTheme.rose : AppTheme.lavender;
      if (_mode == _Mode.vsAi) {
        text = _result.winner == Mark.x ? 'you win!' : 'AI wins';
      } else {
        text = '$who wins!';
      }
    } else if (_draw) {
      text = 'draw';
      color = AppTheme.gold;
    } else if (_aiThinking) {
      text = 'AI thinking…';
      color = AppTheme.lavender;
    } else {
      final who = _turn == Mark.x ? 'X' : 'O';
      color = _turn == Mark.x ? AppTheme.rose : AppTheme.lavender;
      if (_mode == _Mode.vsAi) {
        text = _turn == Mark.x ? 'your move' : "AI's move";
      } else {
        text = "$who's turn";
      }
    }
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _grid() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, c) {
          final size = c.maxWidth;
          return Stack(
            children: [
              SizedBox(
                width: size,
                height: size,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: 9,
                  itemBuilder: (_, i) => _cell(i),
                ),
              ),
              if (_result.hasWinner && _result.line != null)
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _glow,
                    builder: (_, _) => CustomPaint(
                      size: Size(size, size),
                      painter: _WinLinePainter(
                        line: _result.line!,
                        color: _result.winner == Mark.x
                            ? AppTheme.rose
                            : AppTheme.lavender,
                        // 0..1 → pulse the glow softly.
                        pulse: _glow.value,
                        gridPadding: 8,
                        cellSpacing: 6,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _cell(int i) {
    final m = _board[i];
    final highlight = _result.hasWinner && _result.line!.contains(i);
    final isEmpty = m == Mark.empty;
    final color = m == Mark.x ? AppTheme.rose : AppTheme.lavender;
    return Material(
      color: highlight
          ? color.withValues(alpha: 0.10)
          : AppTheme.surfaceElev,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isEmpty ? () => _tapCell(i) : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlight ? color : AppTheme.border,
              width: highlight ? 1.4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: isEmpty
              ? const SizedBox.shrink()
              : Text(
                  m == Mark.x ? 'X' : 'O',
                  style: TextStyle(
                    color: color,
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    shadows: [
                      Shadow(
                        color: color.withValues(alpha: 0.55),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

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
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            label: 'reset scores',
            color: AppTheme.textDim,
            filled: false,
            onTap: _confirmResetScores,
          ),
        ),
      ],
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
          padding: const EdgeInsets.symmetric(vertical: 14),
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

  Future<void> _confirmResetScores() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('reset scores?',
            style: TextStyle(color: AppTheme.text)),
        content: Text(
          _mode == _Mode.vsFriend
              ? 'clears vs-friend wins and draws.'
              : 'clears vs-computer wins and draws.',
          style: const TextStyle(color: AppTheme.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('cancel',
                style: TextStyle(color: AppTheme.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('reset',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await _resetScores();
  }
}

/// Paints a glowing line through the three winning cells.
///
/// The grid widget has [gridPadding] outer padding and uses [cellSpacing]
/// between cells. We compute each cell's center accordingly so the line
/// lines up perfectly with the actual GridView layout.
class _WinLinePainter extends CustomPainter {
  final List<int> line;
  final Color color;
  final double pulse;
  final double gridPadding;
  final double cellSpacing;

  _WinLinePainter({
    required this.line,
    required this.color,
    required this.pulse,
    required this.gridPadding,
    required this.cellSpacing,
  });

  Offset _center(int idx, Size size) {
    final inner = size.width - gridPadding * 2;
    final cell = (inner - cellSpacing * 2) / 3;
    final col = idx % 3;
    final row = idx ~/ 3;
    final x = gridPadding + col * (cell + cellSpacing) + cell / 2;
    final y = gridPadding + row * (cell + cellSpacing) + cell / 2;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = _center(line.first, size);
    final c = _center(line.last, size);
    final glowAlpha = 0.45 + 0.35 * pulse;
    final glow = Paint()
      ..color = color.withValues(alpha: glowAlpha)
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a, c, glow);
    canvas.drawLine(a, c, stroke);
  }

  @override
  bool shouldRepaint(covariant _WinLinePainter old) =>
      old.line != line || old.color != color || old.pulse != pulse;
}
