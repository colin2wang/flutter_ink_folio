import 'file_pick_io.dart' if (dart.library.html) 'file_pick_web.dart' as impl;
import 'picked_file.dart';

export 'picked_file.dart';

/// 选一个文件；返回 null 表示取消（或没拿到任何文件）。
///
/// web 走自建的原生 `<input type="file">`（`file_pick_web.dart`），其余平台走
/// file_picker（`file_pick_io.dart`）。两者差异见各自文件顶部说明。
Future<PickedFile?> pickSingleFile({List<String>? extensions}) =>
    impl.pickSingleFile(extensions: extensions);
