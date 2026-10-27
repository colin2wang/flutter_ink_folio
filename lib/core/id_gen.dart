import 'dart:math';

/// 免依赖 id 生成（时间戳 + 随机段，本机唯一性足够）
String genId() {
  final r = Random();
  return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
      '${r.nextInt(0x7fffffff).toRadixString(36)}';
}
