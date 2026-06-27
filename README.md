# amrita arcade

A mini-games collection built with [Flame](https://flame-engine.org/) for Sid + Amrita. Sibling project to [`amrita-app`](https://github.com/SiddharthFulia/amrita-arcade-app) — runs standalone or gets bundled in via webview/intent.

## Structure (one folder per game)

```
lib/
  main.dart                # MaterialApp → GamesHubPage
  theme/app_theme.dart     # rose/lavender/gold tokens
  hub/games_hub_page.dart  # tile grid → push each game
  games/
    snake/
      snake_screen.dart    # Scaffold + GameWidget host
      snake_game.dart      # FlameGame subclass (logic + render)
    tetris/...
    flappy/...
    g2048/...
    minesweeper/...
    tic_tac_toe/...
```

## How to add a new game
1. `mkdir lib/games/<name>` — match the existing convention (`<name>_screen.dart` + `<name>_game.dart`).
2. Use `flame: ^1.18.0` (already in pubspec) for tile/sprite games; plain Flutter for board games.
3. Wire a tile into `lib/hub/games_hub_page.dart` under the right `_Section`.
4. Pull theme constants from `lib/theme/app_theme.dart` — never hardcode colours.
5. Reserve `MediaQuery.viewPaddingOf(context).bottom + 24` for any bottom-row buttons.

## Run

```bash
flutter pub get
flutter run
```
