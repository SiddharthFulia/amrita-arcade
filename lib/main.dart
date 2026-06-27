import 'package:flutter/material.dart';
import 'hub/games_hub_page.dart';
import 'theme/app_theme.dart';

void main() => runApp(const ArcadeApp());

class ArcadeApp extends StatelessWidget {
  const ArcadeApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'amrita arcade',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const GamesHubPage(),
    );
  }
}
