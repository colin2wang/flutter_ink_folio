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
  static const scrollToCfi = 'scrollToCfi'; // {cfi} epub CFI（foliate 引擎用）
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
