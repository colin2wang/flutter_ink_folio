import 'package:flutter/foundation.dart'
    show kIsWeb, kProfileMode, kReleaseMode, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'bridge/bridge_protocol.dart';
import 'core/app_log.dart';
import 'features/settings/settings_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先装日志收集：之后任何日志/未捕获异常都进环形缓冲（书架顶栏可复制导出）
  AppLog.instance.install();
  // 带上引擎协议号：改完代码没重启/没重编时，一眼就能从日志第一行看出来
  appLog('启动 ${kIsWeb ? 'web' : defaultTargetPlatform.name}'
      '（${kReleaseMode ? 'release' : kProfileMode ? 'profile' : 'debug'}）'
      ' · 引擎协议 $engineProtocolVersion');
  // 日志落盘：黑屏/卡死时进程会被杀，内存缓冲一起消失，
  // 只有文件里的「上一次会话」还能取证（书架顶栏 → 运行日志 → 复制磁盘日志）
  await AppLog.instance.attachFile();
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
