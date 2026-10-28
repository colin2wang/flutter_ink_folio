import 'package:flutter/material.dart';

import '../../core/app_log.dart';
import '../../data/models/book.dart';
import '../../data/repo/repositories.dart';
import '../../services/book_blob_store.dart';
import '../../services/book_import_service.dart';
import '../../theme/instant_route.dart';
import '../debug/log_page.dart';
import '../settings/settings_controller.dart';
import '../reader/reader_page.dart';

/// 书架：列表 + 导入 + 长按删除。灰阶占位封面，无图片解码负担。
class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

class _ShelfPageState extends State<ShelfPage> {
  List<Book> _books = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh(seeding: true);
  }

  Future<void> _refresh({bool seeding = false}) async {
    if (seeding) {
      await BookImportService.instance.seedSampleBook();
    }
    final books = await Repositories.library.getAllBooks();
    if (mounted) setState(() => _books = books);
  }

  Future<void> _import() async {
    // 日志放在 busy 判断之前：按钮被禁用/卡住时也要留下痕迹，
    // 否则现象就是「点了什么都没发生，日志也空」
    appLog('[shelf] 点击导入 busy=$_busy');
    if (_busy) return;
    setState(() => _busy = true);
    ImportResult? result;
    try {
      result = await BookImportService.instance.pickAndImport();
    } finally {
      // 无论抛错/超时都要解锁，否则按钮永久禁用且之后点一下没任何反应
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || result == null) return;
    // 取消不再静默：否则「选了却未被收到」与「主动取消」在用户眼里一样，
    // 都会变成「点了没反应」
    if (result.isCancelled) {
      appLog('[shelf] 选择器无返回（取消或未取到文件）');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未收到文件（取消选择或未被选中）')),
      );
      return;
    }
    if (!result.isOk) {
      appLog('[shelf] 导入失败：${result.reason}', level: 'E');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.reason ?? '导入失败')),
      );
      return;
    }
    appLog('[shelf] 导入成功 id=${result.bookId}');
    await _refresh();
  }

  Future<void> _confirmDelete(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除本书？'),
        content: Text('《${book.title}》及其笔记将被移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await Repositories.library.deleteBook(book.id);
    await Repositories.annotations.removeForBook(book.id);
    await Repositories.content.delete(book.id);
    BookBlobStore.instance.remove(book.id);
    await _refresh();
  }

  Future<void> _open(Book book) async {
    book.lastReadAt = DateTime.now().millisecondsSinceEpoch;
    await Repositories.library.upsertBook(book);
    if (!mounted) return;
    await Navigator.of(context).push(instantRoute(ReaderPage(
      bookId: book.id,
      settingsController: SettingsController.shared,
    )));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          // debug 入口：运行日志（release 也常驻，手机上出问题靠它把日志取出来）
          IconButton(
            onPressed: () => Navigator.of(context).push(instantRoute(
              const LogPage(),
              settings: const RouteSettings(name: '/debug/logs'),
            )),
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: '运行日志',
          ),
          IconButton(
            // 不用 `_busy ? null : _import`：onPressed 为 null 时点击完全不触发，
            // 「按钮禁用了」和「代码没跑」在日志里无法区分
            onPressed: _import,
            icon: const Icon(Icons.add),
            tooltip: '导入 .txt / .epub',
          ),
        ],
      ),
      body: _books.isEmpty
          ? Center(
              child: Text('书架空空，点右上角 + 导入\n或使用内置示例书',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(.6))),
            )
          : ListView.separated(
              itemCount: _books.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final b = _books[i];
                return ListTile(
                  onLongPress: () => _confirmDelete(b),
                  onTap: () => _open(b),
                  leading: _PlaceholderCover(index: b.colorIndex, title: b.title),
                  title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${b.kind.toUpperCase()}'
                    '${b.author.isEmpty ? '' : ' · ${b.author}'}'
                    '${b.percent > 0 ? ' · 已读 ${(b.percent * 100).toStringAsFixed(0)}%' : ' · 未读'}',
                    maxLines: 1,
                  ),
                );
              },
            ),
    );
  }
}

/// 灰阶占位封面（无网络、无图片缓存依赖）
class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.index, required this.title});

  final int index;
  final String title;

  static const shades = [
    Color(0xFFE0E0E0),
    Color(0xFFBDBDBD),
    Color(0xFF9E9E9E),
    Color(0xFF757575),
    Color(0xFF616161),
  ];

  @override
  Widget build(BuildContext context) {
    final shade = shades[index.clamp(1, 5) - 1];
    return Container(
      width: 44,
      height: 60,
      alignment: Alignment.center,
      color: shade,
      padding: const EdgeInsets.all(3),
      child: Text(
        title.isEmpty ? '书' : title.characters.first,
        maxLines: 1,
        style: TextStyle(
          fontSize: 20,
          color: index >= 3 ? Colors.white : Colors.black87,
        ),
      ),
    );
  }
}
