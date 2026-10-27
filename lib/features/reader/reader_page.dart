import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../bridge/epd_channel.dart';
import '../../bridge/js_bridge.dart';
import '../../services/web_asset_copier.dart';
import '../settings/settings_controller.dart';
import 'reader_controller.dart';
import 'widgets/note_menu.dart';
import 'widgets/reader_chrome.dart';

/// 阅读页容器：持有 InAppWebView，加载 TS 引擎，双向桥接。
///
/// 加载策略：
/// - Android：把 assets/web 拷贝到 <documents>/webview_root，loadFile 加载
///   （与书籍同盘，JS fetch file:// 书籍/字体均可达）。
/// - Web(chrome)：flutter_inappwebview 的 web 实现（iframe），initialData 注入
///   内联 JS（iframe 无 base URL，相对资源不可达，故把 main.js 内联进 HTML）。
class ReaderPage extends StatefulWidget {
  const ReaderPage(
      {super.key, required this.bookId, required this.settingsController});

  final String bookId;
  final SettingsController settingsController;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final ReaderController controller;
  late final JsBridge bridge;
  late final Future<WebViewEntry> _entryFuture;
  InAppWebViewController? _webController;

  static _ReaderPageState? _active;

  /// JsBridge 的 handler callback 是顶层/闭包签名，这里借活跃实例转发
  static void _dispatchGlobal(String event, Map<String, dynamic> payload) {
    _active?.controller.handleEvent(event, payload);
  }

  @override
  void initState() {
    super.initState();
    _active = this;
    bridge = JsBridge(_dispatchGlobal);
    controller = ReaderController(
      bookId: widget.bookId,
      settingsController: widget.settingsController,
    );
    controller.onEpdRefresh = (type) {
      // 时序契约：onPageChanged（渲染完成）之后才触发，顺序不能反
      if (type == 'full') {
        EpdChannel.full();
      } else {
        EpdChannel.partial();
      }
    };
    controller.init();
    _entryFuture = _resolveEntry();
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    bridge.detach();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: FutureBuilder<WebViewEntry>(
        future: _entryFuture,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          }
          final entry = snap.data!;
          return Stack(
            children: [
              Positioned.fill(
                child: InAppWebView(
                  initialUrlRequest:
                      URLRequest(url: WebUri(entry.url)),
                  initialData: entry.data,
                  initialSettings: webViewSettings(),
                  onWebViewCreated: (c) {
                    _webController = c;
                    bridge.bind(c);
                    controller.bindPost((action, payload) {
                      bridge.post(action, payload);
                    });
                  },
                  onLoadStop: (c, url) async {
                    // 引擎脚本就绪后引导启动；正式通信等引擎 onReady 回调
                    controller.applyThemeToEngine();
                    await controller.openBookInEngine();
                  },
                  onConsoleMessage: (_, msg) => debugWebConsole(msg),
                ),
              ),
              // 顶栏/底栏：默认隐藏，点中央切换（TS onToggleChrome 驱动）
              ReaderChrome(controller: controller),
              SelectionBar(controller: controller),
            ],
          );
        },
      ),
    );
  }

  Future<WebViewEntry> _resolveEntry() async {
    if (kIsWeb) {
      final html = await rootBundle.loadString('assets/web/index.html');
      final js = await rootBundle.loadString('assets/web/main.js');
      // 内联脚本：iframe 无 base URL，相对引用会 404
      final inlined = html.replaceFirst(
        'INLINE_MAIN_JS',
        js.replaceAll('</script', '<\\/script'),
      );
      return WebViewEntry(
        url: 'about:blank',
        data: InAppWebViewInitialData(data: inlined, mimeType: 'text/html'),
      );
    }
    final root = await WebAssetCopier.instance.prepare();
    return WebViewEntry(url: 'file://$root/index.html');
  }
}

class WebViewEntry {
  WebViewEntry({required this.url, this.data});
  final String url;
  final InAppWebViewInitialData? data;
}
