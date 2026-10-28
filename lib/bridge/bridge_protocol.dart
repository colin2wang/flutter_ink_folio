/// 引擎桥接协议版本：与 `web_engine/src/bridge.ts` 的 `ENGINE_PROTOCOL` 必须同值。
///
/// **改动 Dart↔TS 的 payload 字段就要两边一起 +1**。web 宿主在 onReady 时比对，
/// 不一致就提示「产物过旧」——否则漏跑 `build_web.ps1` 时一切静默失败。
/// 3 = openBook 支持 `dataBase64`（web 端 EPUB 内嵌字节）
const int engineProtocolVersion = 3;

/// 统一 JSON 信封协议（Dart ↔ TS）。
/// Dart→TS 走 evaluateJavascript 调 window.__reader.dispatch(msg)
/// TS→Dart 走 window.flutter_inappwebview.callHandler('event', msg)
class BridgeMessage {
  BridgeMessage({required this.action, required this.payload, this.requestId});

  final String action;
  final Map<String, dynamic> payload;
  final String? requestId;

  Map<String, dynamic> toJson() => {
        'action': action,
        'payload': payload,
        if (requestId != null) 'requestId': requestId,
      };
}

/// Dart → TS 的 action
abstract final class TsAction {
  static const openBook = 'openBook'; // {bookId,kind,filePath,text?,cfi?,highlights?}
  static const applyTheme = 'applyTheme'; // {mode,fontSize,lineHeight,fontFamily,fontPath}
  static const scrollToPercent = 'scrollToPercent'; // {percent 0..1}
  static const scrollToOffset = 'scrollToOffset'; // {start} txt 字符偏移（回退引擎目录用）
  static const scrollToCfi = 'scrollToCfi'; // {cfi} epub 定位串（<spineIndex>#<anchor>）
  static const nextPage = 'nextPage';
  static const prevPage = 'prevPage';
  static const addAnnotation = 'addAnnotation'; // {id,kind,start?,end?,cfiRange?,color}
  static const removeAnnotation = 'removeAnnotation'; // {id}
  static const exportAnnotations = 'exportAnnotations'; // {}
}

/// TS → Dart 的 event（JavaScriptHandler 名固定为 'event'）
abstract final class DartEvent {
  static const handlerName = 'event';

  static const onReady = 'onReady'; // {}
  static const onMeta = 'onMeta'; // {title,author}
  static const onToc = 'onToc'; // {items:[{title,offset?,cfi?}]}
  static const onPageChanged = 'onPageChanged'; // {percent,cfi?,chapter?,start?,index,total}
  static const onLongPress = 'onLongPress'; // {text,cfiRange?,start?,end?}
  static const onToggleChrome = 'onToggleChrome'; // {}
  static const onNeedRefresh = 'onNeedRefresh'; // {type:'full'|'partial'}
  static const onAnnotationsExport = 'onAnnotationsExport'; // {list:[...]}
  static const onError = 'onError'; // {message}
}

/// 阅读主题模式（与 TS 侧 renderer 对齐）
enum ReaderThemeMode { paper, gray, night }

extension ReaderThemeModeX on ReaderThemeMode {
  String get id => switch (this) {
        ReaderThemeMode.paper => 'paper',
        ReaderThemeMode.gray => 'gray',
        ReaderThemeMode.night => 'night',
      };

  static ReaderThemeMode from(String? s) => switch (s) {
        'night' => ReaderThemeMode.night,
        'gray' => ReaderThemeMode.gray,
        _ => ReaderThemeMode.paper,
      };
}
