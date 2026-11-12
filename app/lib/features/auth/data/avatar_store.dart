import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Copies picked profile photos into the app's documents dir — the
/// gallery/cache path from image_picker can be reclaimed by the OS,
/// which would silently lose the avatar after logout or a cache sweep.
class AvatarStore {
  /// Copies [src] to `avatars/<username>.<ext>` and returns the
  /// durable path, or null when the copy fails.
  Future<String?> persist(String src, String username) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ext = src.contains('.') ? src.split('.').last : 'jpg';
      final dest = File('${dir.path}/avatars/$username.$ext');
      await dest.parent.create(recursive: true);
      await File(src).copy(dest.path);
      // FileImage caches by path — evict so overwriting the same
      // avatar file actually repaints the new image.
      await FileImage(dest).evict();
      return dest.path;
    } catch (_) {
      return null;
    }
  }
}
