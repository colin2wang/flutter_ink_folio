import 'dart:async';

import 'package:flutter/material.dart';

import 'bridge/epd_channel.dart';
import 'core/app_log.dart';
import 'features/annotation/annotation_list_page.dart';
import 'features/shelf/shelf_page.dart';
import 'theme/app_theme.dart';
import 'theme/instant_route.dart';

/// 应用根：灰阶 ThemeData + 瞬时路由（无转场动画，规避墨水屏残影）
///
/// 另挂一个生命周期观察者：从系统界面（文件选择器、设置、其它 App）
/// 回来时补一次重绘 + 全刷，见 [_ReaderAppState._recoverAfterResume]。
class ReaderApp extends StatefulWidget {
  const ReaderApp({super.key});

  @override
  State<ReaderApp> createState() => _ReaderAppState();
}

class _ReaderAppState extends State<ReaderApp> with WidgetsBindingObserver {
  /// 是否真的离开过前台。只认 paused/hidden：下拉通知栏那类 inactive
  /// 不该触发全刷（墨水屏每刷一次都要黑闪一下）
  bool _leftForeground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appLog('[life] $state');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftForeground = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _leftForeground) {
      _leftForeground = false;
      _recoverAfterResume();
    }
  }

  /// 回前台兜底：先强制整棵树重建（逼一帧出来），400ms 后再补一次全刷。
  ///
  /// 现场（BOOX Note X3 Pro / Android 12）：从系统文件选择器选完 EPUB 回来，
  /// 整屏黑、熄屏唤醒也不恢复，只能杀进程；而同一次进程里书架逻辑是好的
  /// （书已经入库了）——说明不是卡死，而是画面没上屏。
  /// 根因修复是关掉 Impeller（AndroidManifest 里 EnableImpeller=false，
  /// Skia 在 surface 重建上稳得多），这里只是兜底：万一画面上了屏但
  /// 墨水屏面板停在黑帧上，一次全刷能把它拉回来。
  void _recoverAfterResume() {
    if (!mounted) return;
    appLog('[life] 回前台：重建视图并补一次全刷');
    setState(() {});
    Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      EpdChannel.full();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '墨屏阅读',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        // 全局禁用 OverscrollGlow（墨水屏上发光效果是彩色噪点源）
        return ScrollConfiguration(
          behavior: const NoGlowScrollBehavior(),
          child: child!,
        );
      },
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/annotations':
            return instantRoute(const AnnotationListPage(), settings: settings);
          default:
            return instantRoute(const ShelfPage(), settings: settings);
        }
      },
      home: const ShelfPage(),
    );
  }
}

class NoGlowScrollBehavior extends ScrollBehavior {
  const NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child; // 不绘制 glow
  }
}
