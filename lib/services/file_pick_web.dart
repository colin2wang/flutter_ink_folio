import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import '../../core/app_log.dart';
import 'picked_file.dart';

/// `<input type=file>` 被取消时抛的 `cancel` 事件（Chrome 113+ 才有）。
/// dart:html 的 `FileUploadInputElement` 没有 `onCancel` getter，只能自己包。
const _fileCancelEvent = html.EventStreamProvider<html.Event>('cancel');

/// web 端文件选择：直接操作原生 `<input type="file">`。
///
/// **为什么不用 file_picker**：它的 web 实现在部分环境下会静默返回 null
/// （用户明明选中了文件），日志里只能看到「选择器无返回」，无从排查。
/// 自己做只有三件事——click、等 change、读字节，行为完全可控。
///
/// 不设 `accept`：`.epub` 在部分系统的选择器里会被当成未知类型置灰，
/// 文件看得见却选不中；扩展名校验统一放在导入服务里做。
Future<PickedFile?> pickSingleFile({List<String>? extensions}) {
  final completer = Completer<PickedFile?>();
  final input = html.FileUploadInputElement()
    ..multiple = false
    ..style.display = 'none';
  final body = html.document.body;
  if (body == null) return Future<PickedFile?>.value(null);
  body.append(input);

  var settled = false;
  StreamSubscription<html.Event>? focusSub;
  StreamSubscription<html.Event>? cancelSub;

  void finish(PickedFile? file) {
    if (settled) return;
    settled = true;
    focusSub?.cancel();
    focusSub = null;
    cancelSub?.cancel();
    cancelSub = null;
    input.remove();
    completer.complete(file);
  }

  input.onChange.listen((_) async {
    final files = input.files;
    final file = (files == null || files.isEmpty) ? null : files.first;
    if (file == null) {
      appLog('[import/web] change 事件里没有文件');
      finish(null);
      return;
    }
    try {
      final bytes = await _readBytes(file);
      appLog('[import/web] 选中 ${file.name} ${bytes.length} bytes');
      finish(PickedFile(name: file.name, bytes: bytes));
    } catch (e) {
      appLog('[import/web] 读取文件失败：$e', level: 'E');
      finish(null);
    }
  });

  // 明确取消：Chrome 113+ 支持 `<input type=file>` 的 cancel 事件，最可靠。
  // dart:html 没给 onCancel getter，只能自己造一个事件流
  cancelSub = _fileCancelEvent.forTarget(input).listen((_) {
    appLog('[import/web] 用户主动取消（cancel 事件）');
    finish(null);
  });

  // focus 兜底（仅当浏览器没有 cancel 事件）。
  //
  // **时序实测**：Chrome 上是 focus 先到、change 后到，两者相差可达 800ms
  // （日志：「关闭选择器且未选文件」17.216 → 「选中 xxx.epub」18.018）。
  // 所以这里必须等足够久再判，否则会把「已选中」误判成「取消」——
  // file_picker 的 web 实现就是栽在这一步（focus 后立即判），表现为
  // 用户明明选了文件，pickFiles 却返回 null。
  focusSub = html.window.onFocus.listen((_) {
    Timer(const Duration(milliseconds: 2500), () {
      if (settled) return;
      final files = input.files;
      if (files == null || files.isEmpty) {
        appLog('[import/web] 关闭选择器且未选文件（focus 兜底）');
        finish(null);
      }
    });
  });

  input.click();
  return completer.future;
}

Future<Uint8List> _readBytes(html.File file) async {
  final reader = html.FileReader();
  final loaded = reader.onLoad.first;
  reader.readAsArrayBuffer(file);
  await loaded;
  final result = reader.result;
  if (result is ByteBuffer) return result.asUint8List();
  if (result is Uint8List) return result;
  throw StateError('文件读取结果为空（${reader.error?.name ?? 'unknown'}）');
}
