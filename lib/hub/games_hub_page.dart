import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// Game screen imports — each game lives in its own folder.
import '../games/snake/snake_screen.dart';
import '../games/tetris/tetris_screen.dart';
import '../games/flappy/flappy_screen.dart';
import '../games/pong/pong_screen.dart';
import '../games/breakout/breakout_screen.dart';
import '../games/g2048/g2048_screen.dart';
import '../games/minesweeper/minesweeper_screen.dart';
import '../games/tic_tac_toe/tic_tac_toe_screen.dart';
import '../games/memory_match/memory_match_screen.dart';
import '../games/sudoku/sudoku_screen.dart';
import '../games/chess/chess_screen.dart';
import '../games/dress_up/dress_up_screen.dart';

/// Arcade hub. One tile per game, grouped by genre. Each game lives
/// in `lib/games/<name>/` — see README.md for the convention.
class GamesHubPage extends StatelessWidget {
  const GamesHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sections = <_Section>[
      _Section('🕹️  classic arcade', [
        _G('🐍', 'snake',        (_) => const SnakeScreen()),
        _G('🧱', 'tetris',       (_) => const TetrisScreen()),
        _G('🐦', 'flappy',       (_) => const FlappyScreen()),
        _G('🏓', 'pong',         (_) => const PongScreen()),
        _G('🧊', 'breakout',     (_) => const BreakoutScreen()),
      ]),
      _Section('🧠  mind & puzzle', [
        _G('🔢', '2048',         (_) => const G2048Screen()),
        _G('💣', 'minesweeper',  (_) => const MinesweeperScreen()),
        _G('🃏', 'memory',       (_) => const MemoryMatchScreen()),
        _G('🧮', 'sudoku',       (_) => const SudokuScreen()),
        _G('♟', 'chess',         (_) => const ChessScreen()),
      ]),
      _Section('👫  2-player', [
        _G('⭕', 'tic-tac-toe',  (_) => const TicTacToeScreen()),
      ]),
      _Section('👗  for her', [
        _G('💃', 'style my date', (_) => const DressUpScreen()),
      ]),
    ];

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (r) => AppTheme.amrita.createShader(r),
          child: const Text('amrita arcade',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(
            12, 12, 12,
            MediaQuery.viewPaddingOf(context).bottom + 24,
          ),
          itemCount: sections.length,
          itemBuilder: (_, sectionIdx) {
            final s = sections[sectionIdx];
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                    child: Row(children: [
                      Text(s.title,
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          )),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              AppTheme.rose.withValues(alpha: 0.35),
                              AppTheme.rose.withValues(alpha: 0.0),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.95,
                    ),
                    itemCount: s.games.length,
                    itemBuilder: (_, i) {
                      final g = s.games[i];
                      return _Tile(g: g);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final _G g;
  const _Tile({required this.g});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: g.builder),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(g.emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 4),
              Text(g.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section {
  final String title;
  final List<_G> games;
  const _Section(this.title, this.games);
}

class _G {
  final String emoji, label;
  final WidgetBuilder builder;
  const _G(this.emoji, this.label, this.builder);
}
