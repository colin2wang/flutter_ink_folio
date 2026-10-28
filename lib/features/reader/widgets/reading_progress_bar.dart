import 'package:flutter/material.dart';

import '../reader_controller.dart';

/// 底部阅读进度尺：常驻一条 2px 细线，点按或横拖才展开。
///
/// 三条墨水屏取舍：
/// - **不占阅读区**：常驻态只有 2px，落在 `SafeArea` 让出的手势条空白里；
///   只有拖动时那枚「页码 / 百分比」气泡才向上溢出，松手即消失。
/// - **不跟手重排**：拖动过程只重绘本 Widget，松手才下发 `scrollToPercent`。
///   引擎每接收一次跳转就要整屏重排重绘（墨水屏上是全刷），跟着手指走
///   会把屏幕刷花、也拖不动。
/// - **零动画**：没有 `AnimatedContainer` / 渐变 / 阴影 / 圆角阴影，
///   展开与收起是瞬时切换（墨水屏残影规避清单）。
class ReadingProgressBar extends StatefulWidget {
  const ReadingProgressBar({
    super.key,
    required this.controller,
    this.height = 18,
    this.showLabel = true,
  });

  final ReaderController controller;

  /// 触摸热区高度；线本身仍只有 2px，贴底绘制
  final double height;

  /// 拖动时是否显示上浮的气泡。
  /// web 端 iframe 是 DOM，盖在 Flutter 画布之上，气泡会被挡住，故关闭。
  final bool showLabel;

  @override
  State<ReadingProgressBar> createState() => _ReadingProgressBarState();
}

class _ReadingProgressBarState extends State<ReadingProgressBar> {
  /// 拖动中的临时比例；非空表示正在拖（线加粗、气泡上浮、显示游标）
  double? _drag;

  bool get _dragging => _drag != null;

  double get _percent => (_drag ?? (widget.controller.book?.percent ?? 0))
      .clamp(0.0, 1.0)
      .toDouble();

  void _seek(Offset at, double width) {
    if (width <= 0) return;
    final v = (at.dx / width).clamp(0.0, 1.0).toDouble();
    if (v == _drag) return;
    setState(() => _drag = v);
  }

  void _commit() {
    final v = _drag;
    if (v == null) return;
    // 只有松手才让引擎动手：一次 scrollToPercent = 一次整屏重排
    widget.controller.jumpToPercent(v);
    // 线交还给引擎上报的真实进度（跳转后引擎会立刻回一次 onPageChanged）
    setState(() => _drag = null);
  }

  void _cancel() {
    if (_drag != null) setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (ctx, _) {
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        return LayoutBuilder(
          builder: (ctx, cons) {
            final width = cons.maxWidth;
            final filled = width * _percent;
            final cursorX =
                (filled - 1).clamp(0.0, width > 2 ? width - 2 : 0.0);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _seek(d.localPosition, width),
              onTapUp: (_) => _commit(),
              onTapCancel: _cancel,
              onHorizontalDragStart: (d) => _seek(d.localPosition, width),
              onHorizontalDragUpdate: (d) => _seek(d.localPosition, width),
              onHorizontalDragEnd: (_) => _commit(),
              onHorizontalDragCancel: _cancel,
              child: SizedBox(
                height: widget.height,
                child: Stack(
                  // 气泡要浮到线上方，允许溢出
                  clipBehavior: Clip.none,
                  children: [
                    // 轨道
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ColoredBox(
                        color: onSurface.withOpacity(.12),
                        child: const SizedBox(height: 2),
                      ),
                    ),
                    // 已读
                    Positioned(
                      left: 0,
                      bottom: 0,
                      width: filled,
                      child: ColoredBox(
                        color: onSurface.withOpacity(_dragging ? .8 : .5),
                        child: const SizedBox(height: 2),
                      ),
                    ),
                    if (_dragging) ...[
                      // 拖动游标：一条竖线从线上伸出来，比圆点更适合墨水屏
                      Positioned(
                        left: cursorX,
                        bottom: 0,
                        width: 2,
                        height: widget.height - 6,
                        child: ColoredBox(color: onSurface),
                      ),
                      if (widget.showLabel) _bubble(context, onSurface),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 页码 + 百分比：拖动时浮在线之上，不常驻（不占阅读区）
  Widget _bubble(BuildContext context, Color onSurface) {
    final c = widget.controller;
    final pct = (_percent * 100).round();
    final text = c.pageTotal > 1
        ? '${c.pageIndex + 1} / ${c.pageTotal} · $pct%'
        : '$pct%';
    return Positioned(
      left: 0,
      right: 0,
      bottom: widget.height + 2,
      child: Center(
        child: DecoratedBox(
          // 不透明底色 + 1px 细边：压在正文上也不会糊成一片
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border.all(color: onSurface.withOpacity(.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: onSurface.withOpacity(.85),
                // 等宽数字：翻页时数字不左右跳
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
