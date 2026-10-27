import 'package:flutter/foundation.dart';

/// 轻量日志（debug 输出，release 被树摇）
void appLog(String message) {
  if (kDebugMode) debugPrint('[inkreader] $message');
}
