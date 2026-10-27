import 'package:flutter/material.dart';

import 'features/annotation/annotation_list_page.dart';
import 'features/shelf/shelf_page.dart';
import 'theme/app_theme.dart';
import 'theme/instant_route.dart';

/// 应用根：灰阶 ThemeData + 瞬时路由（无转场动画，规避墨水屏残影）
class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});

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
