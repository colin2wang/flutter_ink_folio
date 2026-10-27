import 'dart:io';

import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_log.dart';

/// 字体管理：把 assets/fonts/ 下的 .otf/.ttf 拷贝到沙盒 fonts 目录，
/// 返回 {文件名(不含扩展名): 绝对路径}，供 applyTheme.fontPath 注入 @font-face。
class FontManager {
  FontManager._();
  static final instance = FontManager._();

  static const _assetDir = 'assets/fonts';
  static const _exts = ['.otf', '.ttf'];

  final Map<String, String> _customFonts = {}; // name -> sandbox path

  /// 启动时调用一次；无自定义字体时静默返回空表
  Future<Map<String, String>> prepare() async {
    if (_customFonts.isNotEmpty) return _customFonts;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final fontAssets = manifest
          .listAssets()
          .where((a) => a.startsWith(_assetDir) &&
              _exts.any((e) => a.toLowerCase().endsWith(e)))
          .toList();
      if (fontAssets.isEmpty) return _customFonts;

      final base = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(base.path, 'fonts'));
      if (!dir.existsSync()) dir.createSync(recursive: true);

      for (final asset in fontAssets) {
        try {
          final name = p.basenameWithoutExtension(asset);
          final dest = p.join(dir.path, p.basename(asset));
          final f = File(dest);
          if (!f.existsSync()) {
            final data = await rootBundle.load(asset);
            await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
          }
          _customFonts[name] = dest;
          appLog('font ready: $name -> $dest');
        } catch (e) {
          appLog('font copy failed: $asset, $e');
        }
      }
    } catch (e) {
      appLog('FontManager.prepare failed: $e');
    }
    return _customFonts;
  }

  Map<String, String> get available => Map.unmodifiable(_customFonts);
}
