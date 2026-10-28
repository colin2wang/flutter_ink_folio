import 'package:flutter/material.dart';

import '../../../bridge/bridge_protocol.dart';
import '../../../data/models/reader_settings.dart';
import '../reader_controller.dart';

/// 阅读设置对话框（字体 / 字号 / 行距 / 页边距 / 首行缩进 / 段间距 /
/// 主题 / 全刷节拍 / 底部进度）。
///
/// **零动画**：`transitionDuration: Duration.zero`。Material 对话框默认有
/// 150ms 的淡入+缩放，在墨水屏上是好几帧残影，与 instantRoute 同一原则。
///
/// **交互模型**：对话框里改的是一份草稿副本 [_draft]，滑块松手或点选项卡时
/// 才整体写回并下发引擎（= 一次重排 + 一次全刷）。拖动过程中就重排的话，
/// 屏幕会一路闪到底。
Future<void> showReaderSettingsDialog(
    BuildContext context, ReaderController controller) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '阅读设置',
    barrierColor: const Color(0x55000000),
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, _, __) => _SettingsDialog(controller: controller),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.controller});

  final ReaderController controller;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late ReaderSettings _draft = widget.controller.settings.copy();

  /// 写回设置（→ 引擎）并刷新数值文案。滑块只在松手时走这里。
  ///
  /// 传的是副本：[_draft] 必须与 SettingsController 里那份保持独立，
  /// 否则拖动中的临时值会随对象引用直接变成“已生效”的设置
  /// （不重排也不落盘，下次任意通知才突然生效）。
  void _commit() {
    widget.controller.applySettings(_draft.copy());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mute = theme.colorScheme.onSurface.withValues(alpha: .6);
    final fonts = widget.controller.settingsController.customFonts;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: ConstrainedBox(
        // 墨水屏设备横屏也够用；再宽会让滑块行程过长
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('阅读设置',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    onPressed: () {
                      _draft = ReaderSettings();
                      _commit();
                    },
                    child: const Text('恢复默认', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              _label('字体'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _fontChip('宋体（衬线）', 'serif'),
                  _fontChip('黑体（无衬线）', 'sans'),
                  for (final entry in fonts.entries)
                    _fontChip(entry.key, 'custom:${entry.key}',
                        fontPath: entry.value),
                ],
              ),
              if (fonts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '想用别的字体：把 .ttf/.otf 放进 assets/fonts/ 后重新构建，'
                    '这里会自动出现',
                    style: TextStyle(fontSize: 11, height: 1.4, color: mute),
                  ),
                ),
              const SizedBox(height: 8),

              _sliderRow(
                label: '字号',
                valueText: _draft.fontSize.round().toString(),
                value: _draft.fontSize,
                min: 12,
                max: 32,
                step: 1,
                onChanged: (v) => setState(() => _draft.fontSize = v),
              ),
              _sliderRow(
                label: '行距',
                valueText: _draft.lineHeight.toStringAsFixed(2),
                value: _draft.lineHeight,
                min: 1.2,
                max: 2.4,
                step: 0.05,
                onChanged: (v) => setState(() => _draft.lineHeight = v),
              ),
              _sliderRow(
                label: '页边距',
                valueText: '${_draft.margin.round()}',
                value: _draft.margin,
                min: 0,
                max: 64,
                step: 4,
                onChanged: (v) => setState(() => _draft.margin = v),
              ),

              const SizedBox(height: 8),
              _label('段落'),
              _chips(
                options: const ['默认段距', '段间无空白'],
                selected: _draft.paraSpacing == null ? 0 : 1,
                onSelected: (i) {
                  _draft.paraSpacing = i == 0 ? null : 0;
                  _commit();
                },
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('首行缩进两字', style: TextStyle(fontSize: 14)),
                value: _draft.indent > 0,
                onChanged: (on) {
                  _draft.indent = on ? 2 : 0;
                  _commit();
                },
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('底部显示阅读进度', style: TextStyle(fontSize: 14)),
                value: _draft.showProgress,
                onChanged: (on) {
                  _draft.showProgress = on;
                  _commit();
                },
              ),

              const SizedBox(height: 8),
              _label('主题'),
              _chips(
                options: [for (final m in ReaderThemeMode.values) _themeName(m)],
                selected: ReaderThemeMode.values.indexOf(_draft.themeMode),
                onSelected: (i) {
                  _draft.themeMode = ReaderThemeMode.values[i];
                  _commit();
                },
              ),

              const SizedBox(height: 8),
              _label('全刷节拍（墨水屏除残影用）'),
              _chips(
                options: const ['仅局刷', '每 1 页', '每 3 页', '每 6 页'],
                selected: const [0, 1, 3, 6].indexOf(_draft.fullRefreshEvery),
                onSelected: (i) {
                  _draft.fullRefreshEvery = const [0, 1, 3, 6][i];
                  _commit();
                },
              ),

              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: .6))),
      );

  Widget _fontChip(String label, String family, {String? fontPath}) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 13)),
      selected: _draft.fontFamily == family,
      onSelected: (_) {
        _draft.fontFamily = family;
        _draft.fontPath = fontPath;
        _commit();
      },
    );
  }

  /// 滑块：onChanged 只改草稿（不重排），松手才 commit
  Widget _sliderRow({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    final divisions = ((max - min) / step).round();
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text('$label $valueText',
              style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              overlayShape: SliderComponentShape.noOverlay,
              trackHeight: 2,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: (_) => _commit(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _chips({
    required List<String> options,
    required int selected,
    required ValueChanged<int> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (var i = 0; i < options.length; i++)
          ChoiceChip(
            label: Text(options[i], style: const TextStyle(fontSize: 13)),
            selected: selected == i,
            onSelected: (_) => onSelected(i),
          ),
      ],
    );
  }
}

String _themeName(ReaderThemeMode m) => switch (m) {
      ReaderThemeMode.paper => '纸白',
      ReaderThemeMode.gray => '浅灰',
      ReaderThemeMode.night => '夜间',
    };
