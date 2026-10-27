import 'package:flutter/material.dart';

import '../../../bridge/bridge_protocol.dart';
import '../reader_controller.dart';
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
                  onPressed: () => showReaderSettingsSheet(context, controller),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 阅读设置底部弹层：字号/行距/主题/字体/全刷节拍。
/// 大块内容变化 → 关闭时全刷一次。
Future<void> showReaderSettingsSheet(
    BuildContext context, ReaderController controller) async {
  final settingsController = controller.settingsController;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => AnimatedBuilder(
      animation: settingsController,
      builder: (ctx, _) {
        final s = settingsController.settings;
        final fonts = settingsController.customFonts;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('阅读设置',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _sliderRow(ctx, '字号 ${s.fontSize.round()}',
                    s.fontSize, 12, 32, 1,
                    (v) => settingsController.update((st) => st.fontSize = v)),
                _sliderRow(ctx, '行距 ${s.lineHeight.toStringAsFixed(2)}',
                    s.lineHeight, 1.2, 2.4, 0.05,
                    (v) => settingsController.update((st) => st.lineHeight = v)),
                const SizedBox(height: 8),
                const Text('主题'),
                Row(
                  children: [
                    for (final m in ReaderThemeMode.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_themeName(m)),
                          selected: s.themeMode == m,
                          onSelected: (_) => settingsController
                              .update((st) => st.themeMode = m),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('全刷节拍'),
                Row(
                  children: [
                    for (final n in const [0, 1, 3, 6])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(n == 0 ? '仅局刷' : '每 $n 页'),
                          selected: s.fullRefreshEvery == n,
                          onSelected: (_) => settingsController
                              .update((st) => st.fullRefreshEvery = n),
                        ),
                      ),
                  ],
                ),
                if (fonts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('自定义字体（assets/fonts 内置）'),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('默认'),
                        selected: !s.fontFamily.startsWith('custom:'),
                        onSelected: (_) => settingsController
                            .update((st) => st.fontFamily = 'serif'),
                      ),
                      for (final name in fonts.keys)
                        ChoiceChip(
                          label: Text(name),
                          selected: s.fontFamily == 'custom:$name',
                          onSelected: (_) => settingsController.update((st) {
                            st.fontFamily = 'custom:$name';
                            st.fontPath = fonts[name];
                          }),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
  // 大块内容变化 → 全刷
  controller.onEpdRefresh?.call('full');
}

String _themeName(ReaderThemeMode m) => switch (m) {
      ReaderThemeMode.paper => '纸白',
      ReaderThemeMode.gray => '浅灰',
      ReaderThemeMode.night => '夜间',
    };

Widget _sliderRow(BuildContext ctx, String label, double value, double min,
    double max, double step, ValueChanged<double> onChanged) {
  return Row(
    children: [
      SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 14))),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(ctx).copyWith(
            overlayShape: SliderComponentShape.noOverlay,
            trackHeight: 2,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / step).round(),
            onChanged: onChanged,
          ),
        ),
      ),
    ],
  );
}
