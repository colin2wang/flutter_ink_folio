import 'dart:io';

import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_log.dart';

/// 把 assets/web/（TS 引擎产物或回退引擎）拷贝到沙盒，
/// WebView 从 file:// 加载 —— 拷贝到 documents 下与书籍同盘，
/// 配合 allowFileAccessFromFileURLs 即可用 **XHR** 读书籍/字体。
/// 注意不能用 `fetch`：Blink 的 Fetch 不支持 file:// scheme（见 web_engine/src/io.ts）。
class WebAssetCopier {
  WebAssetCopier._();
  static final instance = WebAssetCopier._();

  static const _assetDir = 'assets/web';

  String? _root;

  Future<String> prepare() async {
    if (_root != null) return _root!;
    final base = await getApplicationDocumentsDirectory();
    final root = p.join(base.path, 'webview_root');
    final rootDir = Directory(root);
    if (rootDir.existsSync()) rootDir.deleteSync(recursive: true);
    rootDir.createSync(recursive: true);

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final files = manifest
        .listAssets()
        .where((a) => a.startsWith('$_assetDir/'))
        .toList();

    for (final asset in files) {
      final rel = asset.substring(_assetDir.length + 1);
      final dest = File(p.join(root, rel));
      await dest.parent.create(recursive: true);
      final data = await rootBundle.load(asset);
      await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    appLog('web assets copied to $root (${files.length} files)');
    _root = root;
    return root;
  }
}
