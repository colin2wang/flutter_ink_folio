import 'package:flutter/material.dart';

/// 瞬时页面切换：transitionDuration 必须为 0，
/// 禁止 Material 默认的左右滑动/淡入淡出（墨水屏残影主要来源之一）。
Route<T> instantRoute<T>(Widget page, {RouteSettings? settings}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) => page,
  );
}
