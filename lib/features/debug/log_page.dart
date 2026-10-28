import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_log.dart';

/// 运行日志页：把 [AppLog] 的环形缓冲摊在屏幕上，一键复制全部。
///
/// 入口：书架顶栏的 debug 按钮（见 shelf_page.dart）。
/// 手机（release APK）出问题时：复现 → 返回书架 → 打开本页 → 复制全部 → 粘贴出去。
///
/// 墨水屏约束：列表滚动用 jumpTo（不用 animateTo），不引入任何动画。
class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final ScrollController _scroll = ScrollController();
  final AppLog _log = AppLog.instance;

  @override
  void initState() {
    super.initState();
    _log.addListener(_onLogChanged);
    // 首帧后直接贴到底部：最新的日志在最下面
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void dispose() {
    _log.removeListener(_onLogChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onLogChanged() {
    if (!mounted) return;
    // 只有本来就在底部才跟着跟：用户往上翻着看历史时别硬拽回去
    final atEnd = !_scroll.hasClients ||
        _scroll.position.pixels >=
            _scroll.position.maxScrollExtent - 8;
    setState(() {});
    if (atEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
    }
  }

  void _jumpToEnd() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  Future<void> _copyAll() async {
    final text = _log.dump();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${_log.count} 条日志')),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志？'),
        content: const Text('缓冲里的日志会被全部删除，已复制出去的不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) _log.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _log.entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            onPressed: entries.isEmpty ? null : _copyAll,
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: '复制全部',
          ),
          IconButton(
            onPressed: entries.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空',
          ),
        ],
      ),
      body: Column(
        children: [
          _Header(count: _log.count, dropped: _log.dropped),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text('暂无日志',
                        style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(.5))),
                  )
                : ListView.builder(
                    controller: _scroll,
                    itemCount: entries.length,
                    itemBuilder: (ctx, i) => _LogLine(entry: entries[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.dropped});

  final int count;
  final int dropped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '共 $count 条${dropped > 0 ? '（已丢弃最早 $dropped 条）' : ''}',
              style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(.7)),
            ),
          ),
          Text('复现后点右上角复制',
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withOpacity(.45))),
        ],
      ),
    );
  }
}

/// 单条日志：等宽字体、按级别区分浓淡（灰阶，不用彩色）
class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final (color, weight) = switch (entry.level) {
      'E' => (onSurface, FontWeight.w600),
      'W' => (onSurface.withOpacity(.8), FontWeight.w500),
      _ => (onSurface.withOpacity(.75), FontWeight.w400),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Text(
        entry.line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: color,
          fontWeight: weight,
        ),
      ),
    );
  }
}
