import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'components/avatar_doll.dart';
import 'components/backdrop_picker.dart';
import 'components/category_tabs.dart';
import 'components/outfit_picker.dart';
import 'components/save_button.dart';
import 'data/backdrops.dart';
import 'data/outfits.dart';
import 'models/style.dart';
import '../../theme/app_theme.dart';

/// "style my date 💖" — a dress-up game for two dolls (you, gold accent)
/// (her, rose accent). All state lives here; the components are dumb.
class DressUpScreen extends StatefulWidget {
  const DressUpScreen({super.key});

  @override
  State<DressUpScreen> createState() => _DressUpScreenState();
}

class _DressUpScreenState extends State<DressUpScreen> {
  static const _prefsKey = 'dress_up_state';

  // ─── default looks ─────────────────────────────────────────────────────
  static const _defaultYou = AvatarStyle(
    hairId: 'h_long_black',
    topId: 't_white_tee',
    bottomId: 'b_jeans',
    shoesId: 's_sneakers',
    accessoryId: 'a_shades',
    skin: Color(0xFFD8A878),
  );
  static const _defaultHer = AvatarStyle(
    hairId: 'h_long_brown',
    topId: 't_rose_dress',
    bottomId: 'b_skirt',
    shoesId: 's_heels',
    accessoryId: 'a_lipstick',
    skin: Color(0xFFE7BFA0),
  );

  late AvatarStyle _you;
  late AvatarStyle _her;
  late String _backdropId;
  late Set<String> _unlocked;
  bool _allUnlocked = false;
  bool _editingYou = false; // tap her by default — she gets the attention 💖

  CategoryKind _kind = CategoryKind.top;
  final _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _you = _defaultYou;
    _her = _defaultHer;
    _backdropId = BackdropCatalog.all.first.id;
    _unlocked = _starterUnlocks();
    _loadFromPrefs();
  }

  // 12 unlocked to start — first 2 from each main slot + 2 hairstyles.
  Set<String> _starterUnlocks() {
    final s = <String>{};
    void take(List<StyleOption> list, int n) {
      for (var i = 0; i < n && i < list.length; i++) {
        s.add(list[i].id);
      }
    }
    take(OutfitCatalog.hair, 3);
    take(OutfitCatalog.top, 2);
    take(OutfitCatalog.bottom, 2);
    take(OutfitCatalog.shoes, 2);
    take(OutfitCatalog.accessory, 3);
    return s;
  }

  Set<String> _everythingUnlocked() {
    return {
      for (final o in OutfitCatalog.hair) o.id,
      for (final o in OutfitCatalog.top) o.id,
      for (final o in OutfitCatalog.bottom) o.id,
      for (final o in OutfitCatalog.shoes) o.id,
      for (final o in OutfitCatalog.accessory) o.id,
    };
  }

  // ─── persistence ───────────────────────────────────────────────────────
  Future<void> _loadFromPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _you = AvatarStyle.fromJson(
            (j['you'] as Map<String, dynamic>?) ?? const {}, _defaultYou);
        _her = AvatarStyle.fromJson(
            (j['her'] as Map<String, dynamic>?) ?? const {}, _defaultHer);
        _backdropId = (j['backdrop'] as String?) ?? _backdropId;
        _allUnlocked = (j['all'] as bool?) ?? false;
        if (_allUnlocked) {
          _unlocked = _everythingUnlocked();
        }
      });
    } catch (_) {/* ignore — defaults stand */}
  }

  Future<void> _saveToPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _prefsKey,
        jsonEncode({
          'you': _you.toJson(),
          'her': _her.toJson(),
          'backdrop': _backdropId,
          'all': _allUnlocked,
        }),
      );
    } catch (_) {/* swallow — non-fatal */}
  }

  // ─── interactions ──────────────────────────────────────────────────────
  void _setActive(bool you) {
    if (_editingYou == you) return;
    HapticFeedback.lightImpact();
    setState(() => _editingYou = you);
  }

  void _applyOption(StyleOption o) {
    setState(() {
      if (_editingYou) {
        _you = _you.withSlot(o.kind, o.id);
      } else {
        _her = _her.withSlot(o.kind, o.id);
      }
    });
    _saveToPrefs();
  }

  void _applyBackdrop(Backdrop b) {
    setState(() => _backdropId = b.id);
    _saveToPrefs();
  }

  void _resetLooks() {
    HapticFeedback.selectionClick();
    setState(() {
      _you = _defaultYou;
      _her = _defaultHer;
      _backdropId = BackdropCatalog.all.first.id;
    });
    _saveToPrefs();
  }

  void _toggleUnlockAll() {
    HapticFeedback.selectionClick();
    setState(() {
      _allUnlocked = !_allUnlocked;
      _unlocked = _allUnlocked ? _everythingUnlocked() : _starterUnlocks();
    });
    _saveToPrefs();
  }

  // ─── build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final backdrop = BackdropCatalog.byId(_backdropId);
    final activeStyle = _editingYou ? _you : _her;
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom + 18;
    final unlockedCount = _unlocked.length;
    final total = OutfitCatalog.totalCount;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (r) => AppTheme.amrita.createShader(r),
          child: const Text(
            'style my date 💖',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        actions: [
          // unlock count chip
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.lavender.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.lavender.withValues(alpha: 0.5)),
              ),
              child: Text(
                '💎 $unlockedCount/$total',
                style: const TextStyle(
                  color: AppTheme.lavender,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _allUnlocked ? 'lock extras' : 'unlock all',
            icon: Icon(
              _allUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
              color: AppTheme.lavender,
            ),
            onPressed: _toggleUnlockAll,
          ),
          IconButton(
            tooltip: 'reset',
            icon: const Icon(Icons.restart_alt_rounded, color: AppTheme.gold),
            onPressed: _resetLooks,
          ),
          SavePhotoButton(boundaryKey: _captureKey),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── stage (backdrop + the two dolls) ─────────────────────────
          Expanded(
            child: RepaintBoundary(
              key: _captureKey,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 380),
                decoration: BoxDecoration(gradient: backdrop.gradient),
                child: Stack(
                  children: [
                    // soft vignette so text/dolls pop
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.35),
                            ],
                            radius: 1.1,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: AvatarDoll(
                              style: _you,
                              isActive: _editingYou,
                              accent: AppTheme.gold,
                              name: 'you',
                              onTap: () => _setActive(true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AvatarDoll(
                              style: _her,
                              isActive: !_editingYou,
                              accent: AppTheme.rose,
                              name: 'her',
                              onTap: () => _setActive(false),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // floating "active" caption
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _editingYou
                                ? 'styling: you 💛  · tap her to switch'
                                : 'styling: her 💖  · tap you to switch',
                            style: const TextStyle(
                              color: AppTheme.text,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── bottom sheet: tabs + swatch row ──────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            padding: EdgeInsets.only(top: 12, bottom: bottomPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CategoryTabs(
                  selected: _kind,
                  onChanged: (k) => setState(() => _kind = k),
                ),
                const SizedBox(height: 10),
                if (_kind == CategoryKind.backdrop)
                  BackdropPicker(
                    selectedId: _backdropId,
                    onPick: _applyBackdrop,
                  )
                else
                  OutfitPicker(
                    kind: _kind,
                    selectedId: activeStyle.slot(_kind),
                    unlocked: _unlocked,
                    onPick: _applyOption,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
