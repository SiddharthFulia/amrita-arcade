import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';

/// Captures the supplied RepaintBoundary key to PNG bytes. Since we don't
/// have `image_gallery_saver` wired in, this just shows a confirmation
/// toast — Sid can add the dep later.
///
// TODO: wire image_gallery_saver here (or share_plus with XFile) so the
// captured bytes actually land in the user's gallery.
class SavePhotoButton extends StatelessWidget {
  final GlobalKey boundaryKey;
  const SavePhotoButton({super.key, required this.boundaryKey});

  Future<Uint8List?> _capture() async {
    final obj = boundaryKey.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) return null;
    final image = await obj.toImage(pixelRatio: 3.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'save photo',
      icon: const Icon(Icons.photo_camera_rounded, color: AppTheme.rose),
      onPressed: () async {
        HapticFeedback.mediumImpact();
        final bytes = await _capture();
        if (!context.mounted) return;
        final msg = bytes == null
            ? 'capture failed'
            : 'image captured (${(bytes.length / 1024).toStringAsFixed(1)} kb)'
                ' — saving requires image_gallery_saver dep (see TODO)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.surfaceElev,
            content: Text(
              msg,
              style: const TextStyle(color: AppTheme.text),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      },
    );
  }
}
