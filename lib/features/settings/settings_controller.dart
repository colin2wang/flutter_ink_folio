import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/reader_settings.dart';
import '../../services/font_manager.dart';

/// 全局阅读设置控制器：shared_preferences 持久化 + 变更通知
class SettingsController extends ChangeNotifier {
  static const _kKey = 'reader_settings_v1';

  static final SettingsController shared = SettingsController._();
  SettingsController._();

  ReaderSettings _settings = ReaderSettings();
  Map<String, String> customFonts = {}; // 字体名 -> 沙盒路径

  ReaderSettings get settings => _settings;

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kKey);
    if (raw != null) {
      try {
        _settings = ReaderSettings.fromPrefsJson(
            (jsonDecode(raw) as Map).cast<String, dynamic>());
      } catch (_) {
        _settings = ReaderSettings();
      }
    }
    customFonts = await FontManager.instance.prepare();
    notifyListeners();
  }

  Future<void> update(void Function(ReaderSettings s) mutate) async {
    mutate(_settings);
    await _persist();
    notifyListeners();
  }

  /// 整体替换：设置对话框里改的是一份草稿副本，交互结束（滑块松手/选芯片）
  /// 才整体写回——拖动过程中不重排，否则墨水屏会被刷花
  Future<void> apply(ReaderSettings s) async {
    _settings = s;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async => (await SharedPreferences.getInstance())
      .setString(_kKey, jsonEncode(_settings.toPrefsJson()));
}
