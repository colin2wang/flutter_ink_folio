import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../reader_controller.dart';

/// 划线选择菜单：TS 发 onLongPress({text, start, end, cfiRange}) 后，
/// controller.pendingSelection 非空，阅读区上方浮出操作条。
/// 覆盖层出现/消失属小面积变化 → 局刷。
class SelectionBar extends StatelessWidget {
  const SelectionBar({super.key, required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) {
        final sel = controller.pendingSelection;
        if (sel == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _dismiss(controller),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await controller.addAnnotation(
                          text: sel['text'] ?? '',
                          start: (sel['start'] as num?)?.toInt(),
                          end: (sel['end'] as num?)?.toInt(),
                          cfiRange: sel['cfiRange'] as String?,
                          chapterTitle: controller.currentChapter,
                        );
                        _dismiss(controller);
                      },
                      child: const Text('划线'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final note = await _editNote(context);
                        if (note == null) return;
                        await controller.addAnnotation(
                          text: sel['text'] ?? '',
                          start: (sel['start'] as num?)?.toInt(),
                          end: (sel['end'] as num?)?.toInt(),
                          cfiRange: sel['cfiRange'] as String?,
                          chapterTitle: controller.currentChapter,
                          note: note.isEmpty ? null : note,
                        );
                        _dismiss(controller);
                      },
                      child: const Text('笔记'),
                    ),
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: sel['text'] ?? ''));
                        _dismiss(controller);
                      },
                      child: const Text('复制'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _dismiss(ReaderController c) {
    c.clearSelection();
    c.onEpdRefresh?.call('partial');
  }

  Future<String?> _editNote(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('写笔记'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '记录此刻的想法…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('保存')),
        ],
      ),
    );
  }
}
