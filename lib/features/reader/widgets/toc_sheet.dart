import 'package:flutter/material.dart';

import '../reader_controller.dart';

/// 目录弹层：txt 用字符偏移跳转；epub 用 CFI。
/// 打开/关闭都属"大块内容变化"→ 全刷（关闭时）。
Future<void> showTocSheet(BuildContext context, ReaderController controller) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final toc = controller.toc;
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('目录（${toc.length}）',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const Divider(height: 1),
              Expanded(
                child: toc.isEmpty
                    ? const Center(child: Text('本书暂无目录结构'))
                    : ListView.builder(
                        itemCount: toc.length,
                        itemBuilder: (ctx, i) {
                          final item = toc[i];
                          return ListTile(
                            dense: true,
                            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              if (item.cfi != null) {
                                controller.jumpToCfi(item.cfi!);
                              } else if (item.offset != null) {
                                controller.jumpToOffset(item.offset!);
                              }
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
  controller.onEpdRefresh?.call('full');
}

/// 笔记/划线列表弹层（阅读页内）
Future<void> showAnnotationsSheet(
    BuildContext context, ReaderController controller) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return AnimatedBuilder(
        animation: controller,
        builder: (ctx, _) {
          final list = controller.annotations;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('划线与笔记（${list.length}）',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: list.isEmpty
                        ? const Center(child: Text('长按正文即可划线'))
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (ctx, i) {
                              final a = list[i];
                              return ListTile(
                                dense: true,
                                title: Text(a.text,
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: a.note == null
                                    ? null
                                    : Text(a.note!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () => controller.removeAnnotation(a),
                                ),
                                onTap: () {
                                  if (a.cfiRange != null) {
                                    controller.jumpToCfi(a.cfiRange!);
                                  } else if (a.startOffset != null) {
                                    controller.jumpToOffset(a.startOffset!);
                                  }
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  controller.onEpdRefresh?.call('full');
}
