import 'package:flutter/material.dart';

import '../../data/models/annotation.dart';
import '../../data/models/book.dart';
import '../../data/repo/repositories.dart';

/// 全局笔记/划线列表（从书架 AppBar 之外的入口进入，这里挂在路由 '/annotations'）
class AnnotationListPage extends StatefulWidget {
  const AnnotationListPage({super.key});

  @override
  State<AnnotationListPage> createState() => _AnnotationListPageState();
}

class _AnnotationListPageState extends State<AnnotationListPage> {
  List<Book> _books = [];
  Map<String, List<Annotation>> _byBook = {};
  String? _selectedBookId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final books = await Repositories.library.getAllBooks();
    final map = <String, List<Annotation>>{};
    for (final b in books) {
      final list = await Repositories.annotations.forBook(b.id);
      if (list.isNotEmpty) map[b.id] = list;
    }
    if (!mounted) return;
    setState(() {
      _books = books.where((b) => map.containsKey(b.id)).toList();
      _byBook = map;
      _selectedBookId ??= _books.isEmpty ? null : _books.first.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _selectedBookId == null ? const <Annotation>[] : _byBook[_selectedBookId] ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('笔记与划线')),
      body: _books.isEmpty
          ? const Center(child: Text('还没有任何划线或笔记'))
          : Column(
              children: [
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    children: [
                      for (final b in _books)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(b.title, overflow: TextOverflow.ellipsis),
                            selected: _selectedBookId == b.id,
                            onSelected: (_) => setState(() => _selectedBookId = b.id),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final a = list[i];
                      return ListTile(
                        title: Text(a.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: a.note == null
                            ? null
                            : Text('✎ ${a.note}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Text(
                          a.kind == 'note' ? '笔记' : '划线',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
