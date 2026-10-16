import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// A font file the user imported for danmaku rendering.
class CustomFont {
  final File file;

  CustomFont(this.file);

  String get fileName => file.uri.pathSegments.last;

  /// Display name, the file name without its extension.
  String get name {
    final int dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  /// Family the font is registered under; prefixed so it never shadows a
  /// bundled or system family.
  String get family => 'oneanime_custom_$fileName';
}

/// Imports, registers and removes user fonts. Fonts live in the app support
/// directory and are registered with the engine lazily, once per launch.
class FontManager {
  static const List<String> supportedExtensions = ['ttf', 'otf', 'ttc'];

  static final Set<String> _loadedFamilies = {};

  static Future<Directory> _fontDir() async {
    final Directory support = await getApplicationSupportDirectory();
    final Directory dir = Directory('${support.path}/fonts');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static bool _isFontFile(String path) {
    final String lower = path.toLowerCase();
    return supportedExtensions.any((ext) => lower.endsWith('.$ext'));
  }

  static Future<List<CustomFont>> list() async {
    try {
      final Directory dir = await _fontDir();
      final List<CustomFont> fonts = dir
          .listSync()
          .whereType<File>()
          .where((f) => _isFontFile(f.path))
          .map(CustomFont.new)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return fonts;
    } catch (e) {
      debugPrint('读取自定义字体失败 ${e.toString()}');
      return [];
    }
  }

  /// Registers [font] with the engine; returns false when the file is not a
  /// font the engine can read.
  static Future<bool> load(CustomFont font) async {
    if (_loadedFamilies.contains(font.family)) {
      return true;
    }
    try {
      final Uint8List bytes = await font.file.readAsBytes();
      final FontLoader loader = FontLoader(font.family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loadedFamilies.add(font.family);
      return true;
    } catch (e) {
      debugPrint('加载字体 ${font.fileName} 失败 ${e.toString()}');
      return false;
    }
  }

  /// Makes sure the custom family referenced by [family] (if any) is
  /// registered before text is laid out with it.
  static Future<void> ensureLoaded(String? family) async {
    if (family == null ||
        !family.startsWith('oneanime_custom_') ||
        _loadedFamilies.contains(family)) {
      return;
    }
    for (final CustomFont font in await list()) {
      if (font.family == family) {
        await load(font);
        return;
      }
    }
  }

  /// Lets the user pick a font file and copies it into the font directory.
  /// Returns the imported font, or null if the user cancelled.
  /// Throws a [FormatException] with a user facing message on bad input.
  static Future<CustomFont?> pickAndImport() async {
    // Android file managers rarely know a MIME type for fonts and grey them
    // out under a custom filter, so pick anything and check afterwards.
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    final String? path = result?.files.single.path;
    if (path == null) {
      return null;
    }
    if (!_isFontFile(path)) {
      throw const FormatException('请选择 ttf / otf / ttc 字体文件');
    }
    final Directory dir = await _fontDir();
    final String fileName = File(path).uri.pathSegments.last;
    final File target = File('${dir.path}/$fileName');
    await File(path).copy(target.path);
    final CustomFont font = CustomFont(target);
    // A replaced file keeps its family name, so drop the stale registration.
    _loadedFamilies.remove(font.family);
    if (!await load(font)) {
      await target.delete();
      throw const FormatException('字体文件无法读取');
    }
    return font;
  }

  static Future<void> delete(CustomFont font) async {
    try {
      await font.file.delete();
    } catch (e) {
      debugPrint('删除字体失败 ${e.toString()}');
    }
  }
}
