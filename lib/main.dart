import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'features/settings/settings_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 墨水屏：保持竖屏、禁用系统 UI 自动 hide 动画（瞬时切换由 App 内处理）
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  // 预加载阅读设置（含字体扫描），避免阅读页首帧闪默认样式
  await SettingsController.shared.load();
  runApp(const ReaderApp());
}
