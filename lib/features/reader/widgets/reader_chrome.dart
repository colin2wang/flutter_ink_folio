import 'package:flutter/material.dart';

import '../reader_controller.dart';
import 'reader_settings_dialog.dart';
import 'toc_sheet.dart';

/// 顶栏 + 底栏：默认隐藏，点阅读区中央切换。
/// 出现/消失各触发一次局刷（由 controller.toggleChrome 内部处理）。
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({super.key, required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) {
        if (!controller.chromeVisible) return const SizedBox.shrink();
        final b = controller.book;
        return Column(
          children: [
            _TopBar(controller: controller, title: b?.title ?? ''),
            const Spacer(),
            _BottomBar(controller: controller),
          ],
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.title});

  final ReaderController controller;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            BackButton(onPressed: () => Navigator.of(context).maybePop()),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
            ),
            IconButton(
              icon: const Icon(Icons.menu_book),
              tooltip: '目录',
              onPressed: () => showTocSheet(context, controller),
            ),
            IconButton(
              icon: const Icon(Icons.notes),
              tooltip: '笔记/划线',
              onPressed: () => showAnnotationsSheet(context, controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller});

  final ReaderController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条：拖动跳转（直接订阅 controller，避免额外监听器泄漏）
            AnimatedBuilder(
              animation: controller,
              builder: (ctx, _) {
                final percent = controller.book?.percent ?? 0;
                return SliderTheme(
                  data: SliderTheme.of(ctx).copyWith(
                    overlayShape: SliderComponentShape.noOverlay,
                    trackHeight: 2,
                  ),
                  child: Slider(
                    value: percent.clamp(0, 1),
                    onChanged: controller.jumpToPercent,
                  ),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    controller.prevPage();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    controller.nextPage();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.text_fields),
                  tooltip: '阅读设置',
                  onPressed: () async {
                    await showReaderSettingsDialog(context, controller);
                    // 对话框盖住的正文要重画：墨水屏上不刷会残留一层浮层
                    controller.onEpdRefresh?.call('full');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
