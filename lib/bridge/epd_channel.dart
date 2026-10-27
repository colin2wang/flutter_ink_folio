import 'package:flutter/services.dart';

import '../core/app_log.dart';

/// 墨水屏刷新通道：Flutter → Android EpdRefreshPlugin。
///
/// 时序契约：TS 渲染完成 → onPageChanged → 这里 full()。
/// 顺序不能反，否则刷的是旧帧。
class EpdChannel {
  EpdChannel._();
  static const MethodChannel _ch = MethodChannel('ebook_reader/epd');

  /// 全刷（翻页、目录/设置等大块内容变化）
  static Future<void> full() => _invoke('full');

  /// 局刷（弹菜单、划线等小面积变化）
  static Future<void> partial() => _invoke('partial');

  /// 设置默认刷新模式：'quality' | 'speed' | 'balanced'
  static Future<void> setMode(String mode) => _invoke('setMode', {'mode': mode});

  /// 设备是否被识别为墨水屏（识别失败时 App 不再频繁调用，省电）
  static Future<bool> isEink() async {
    try {
      return await _ch.invokeMethod<bool>('isEink') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      await _ch.invokeMethod(method, args);
    } on PlatformException catch (e) {
      // 非 e-ink 设备（模拟器/web）插件不存在或调用失败：静默
      appLog('EpdChannel.$method failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      // web / 热重载环境：静默
    }
  }
}
