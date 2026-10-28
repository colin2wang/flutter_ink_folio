import 'package:file_picker/file_picker.dart';

import 'picked_file.dart';

/// 移动端/桌面端文件选择：走 file_picker（Android 上就是 SAF）。
///
/// 统一要 bytes：SAF 给的是临时 content:// 路径，拷来拷去不如直接读字节。
Future<PickedFile?> pickSingleFile({List<String>? extensions}) async {
  final result = await FilePicker.platform.pickFiles(
    type: extensions == null ? FileType.any : FileType.custom,
    allowedExtensions: extensions,
    withData: true,
  );
  final files = result?.files;
  if (files == null || files.isEmpty) return null;
  final f = files.first;
  return PickedFile(name: f.name, bytes: f.bytes, path: f.path);
}
