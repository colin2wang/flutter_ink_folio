import 'dart:typed_data';

/// 一次文件选择的结果。
///
/// 只带“选择器真正交出来的东西”：web 上永远只有 [name] + [bytes]（没有路径），
/// 移动端 SAF 可能同时给 [path] 与 [bytes]。
class PickedFile {
  const PickedFile({required this.name, this.bytes, this.path});

  final String name;
  final Uint8List? bytes;
  final String? path;
}
