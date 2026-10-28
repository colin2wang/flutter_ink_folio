import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../bridge/bridge_protocol.dart';
import '../../core/app_log.dart';
import '../../core/id_gen.dart';
import '../../data/models/annotation.dart';
import '../../data/models/book.dart';
import '../../data/models/reader_settings.dart';
import '../../data/repo/repositories.dart';
import '../../services/book_blob_store.dart';
import '../../services/book_import_service.dart';
import '../settings/settings_controller.dart';

/// 阅读页状态机：持书、进度落库（防抖）、事件分发、刷新节拍。
class ReaderController extends ChangeNotifier {
  ReaderController({required this.bookId, required SettingsController settingsController})
      : _settingsCtrl = settingsController {
    // 设置变更 → 引擎即时换肤（applyTheme）
    _settingsCtrl.addListener(_onSettingsChanged);
  }

  final String bookId;
  final SettingsController _settingsCtrl;

  void _onSettingsChanged() {
    applyThemeToEngine();
  }

  Book? book;
  List<Annotation> annotations = [];
  List<TocItem> toc = [];
  String metaTitle = '';
  String metaAuthor = '';

  bool chromeVisible = false; // 顶栏/底栏默认隐藏（墨水屏清单项）
  bool busy = true;

  /// TS onLongPress 上报的选区，非空时阅读区浮出操作条
  Map<String, dynamic>? pendingSelection;

  String? currentChapter;

  /// 引擎上报的页码（0 起）与总页数，供底部进度尺的气泡文案用。
  /// TXT 是全书页、EPUB 是本章页——只做相对位置参考，不入库
  int pageIndex = 0;
  int pageTotal = 0;

  void clearSelection() {
    pendingSelection = null;
    notifyListeners();
  }

  /// 由 ReaderPage 注入（Dart→TS 通道就绪后）
  void Function(String action, Map<String, dynamic> payload)? _post;

  Timer? _saveDebounce;
  int _pageCounterForFullRefresh = 0;
  ReaderSettings get settings => _settingsCtrl.settings;
  SettingsController get settingsController => _settingsCtrl;

  Future<void> init() async {
    book = await Repositories.library.getBook(bookId);
    annotations = await Repositories.annotations.forBook(bookId);
    busy = false;
    notifyListeners();
  }

  void bindPost(
      void Function(String action, Map<String, dynamic> payload) post) {
    _post = post;
  }

  // -------------------------------------------------------------------------
  // Dart → TS
  // -------------------------------------------------------------------------

  Future<void> openBookInEngine() async {
    final b = book;
    if (b == null) return;
    String? text;
    if (b.kind == 'txt') {
      text = await BookImportService.instance.loadTextContent(b);
    }
    // web 上引擎读不到本地文件（没有 file:// 沙盒，fetch 也拒 file:），
    // EPUB 的 zip 只能由 Dart 读好、以 base64 内嵌下发；Android 始终走 filePath
    String? epubBase64;
    if (kIsWeb && b.kind == 'epub') {
      final bytes = BookBlobStore.instance.get(b.id);
      if (bytes != null) epubBase64 = base64Encode(bytes);
    }
    final highlights = annotations
        .where((a) => a.kind == 'highlight')
        .map((a) => {
              'id': a.id,
              if (a.cfiRange != null) 'cfiRange': a.cfiRange,
              if (a.startOffset != null) 'start': a.startOffset,
              if (a.endOffset != null) 'end': a.endOffset,
              'color': a.colorIndex,
            })
        .toList();
    _post?.call(TsAction.openBook, {
      'bookId': b.id,
      'kind': b.kind,
      'filePath': b.filePath,
      if (text != null) 'text': text,
      if (epubBase64 != null) 'dataBase64': epubBase64,
      'cfi': b.cfi,
      'startOffset': b.startOffset,
      'highlights': highlights,
    });
  }

  void applyThemeToEngine() {
    _post?.call(TsAction.applyTheme, settings.toBridgeJson());
  }

  void jumpToPercent(double percent) {
    _post?.call(TsAction.scrollToPercent, {'percent': percent.clamp(0, 1)});
  }

  void jumpToOffset(int start) {
    _post?.call(TsAction.scrollToOffset, {'start': start});
  }

  void jumpToCfi(String cfi) {
    _post?.call(TsAction.scrollToCfi, {'cfi': cfi});
  }

  void nextPage() => _post?.call(TsAction.nextPage, {});
  void prevPage() => _post?.call(TsAction.prevPage, {});

  /// 划线确认后：入库 + 通知 TS 绘制
  Future<void> addAnnotation({
    required String text,
    String? cfiRange,
    int? start,
    int? end,
    String? chapterTitle,
    String? note,
  }) async {
    final a = Annotation(
      id: genId(),
      bookId: bookId,
      kind: note == null ? 'highlight' : 'note',
      text: text,
      note: note,
      cfiRange: cfiRange,
      startOffset: start,
      endOffset: end,
      chapterTitle: chapterTitle,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    annotations.add(a);
    await Repositories.annotations.upsert(a);
    _post?.call(TsAction.addAnnotation, {
      'id': a.id,
      'kind': a.kind,
      if (cfiRange != null) 'cfiRange': cfiRange,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
      'color': a.colorIndex,
      if (note != null) 'note': note,
    });
    notifyListeners();
  }

  Future<void> removeAnnotation(Annotation a) async {
    annotations.removeWhere((x) => x.id == a.id);
    await Repositories.annotations.remove(a.id);
    _post?.call(TsAction.removeAnnotation, {'id': a.id});
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // TS → Dart（JsBridge 分发）
  // -------------------------------------------------------------------------

  void handleEvent(String event, Map<String, dynamic> payload) {
    switch (event) {
      case DartEvent.onMeta:
        metaTitle = payload['title'] as String? ?? '';
        metaAuthor = payload['author'] as String? ?? '';
        break;
      case DartEvent.onToc:
        final items = (payload['items'] as List?) ?? const [];
        toc = items
            .map((e) =>
                TocItem.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        break;
      case DartEvent.onPageChanged:
        _onPageChanged(payload);
        break;
      case DartEvent.onNeedRefresh:
        final type = payload['type'] as String? ?? 'full';
        _epd(type == 'partial');
        break;
      case DartEvent.onLongPress:
        pendingSelection = payload;
        break;
      case DartEvent.onToggleChrome:
        toggleChrome();
        break;
      case DartEvent.onError:
        appLog('engine error: ${payload['message']}', level: 'E');
        break;
      default:
        break;
    }
    notifyListeners();
  }

  void _onPageChanged(Map<String, dynamic> payload) {
    final b = book;
    if (b == null) return;
    currentChapter = payload['chapter'] as String? ?? currentChapter;
    pageIndex = (payload['index'] as num?)?.toInt() ?? pageIndex;
    pageTotal = (payload['total'] as num?)?.toInt() ?? pageTotal;
    b.percent = ((payload['percent'] as num?) ?? 0).toDouble();
    b.cfi = payload['cfi'] as String?;
    b.startOffset = (payload['start'] as num?)?.toInt() ?? b.startOffset;
    b.chapterIndex = (payload['index'] as num?)?.toInt() ?? b.chapterIndex;
    b.lastReadAt = DateTime.now().millisecondsSinceEpoch;

    // 防抖落库
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      Repositories.library.upsertBook(b);
    });

    // 刷新节拍：每 fullRefreshEvery 页一次全刷（0=不自动全刷）
    final every = settings.fullRefreshEvery;
    if (every > 0) {
      _pageCounterForFullRefresh++;
      if (_pageCounterForFullRefresh >= every) {
        _pageCounterForFullRefresh = 0;
        _epd(false); // full
      }
    }
  }

  void _epd(bool partial) {
    // 这里只记录语义，实际 MethodChannel 由 ReaderPage 持有的 EpdChannel 调用，
    // 通过回调解耦，便于测试替换。
    onEpdRefresh?.call(partial ? 'partial' : 'full');
  }

  /// ReaderPage 注入：void Function(String type)
  void Function(String type)? onEpdRefresh;

  // -------------------------------------------------------------------------
  // Chrome（顶栏/底栏）
  // -------------------------------------------------------------------------

  void toggleChrome() {
    chromeVisible = !chromeVisible;
    // 弹出/消失各触发一次局刷（墨水屏清单：菜单类小面积变化）
    _epd(true);
    notifyListeners();
  }

  @override
  void dispose() {
    _settingsCtrl.removeListener(_onSettingsChanged);
    _saveDebounce?.cancel();
    super.dispose();
  }
}

class TocItem {
  TocItem({required this.title, this.offset, this.cfi, this.children});

  final String title;
  final int? offset; // txt 字符偏移
  final String? cfi; // epub CFI
  final List<TocItem>? children;

  factory TocItem.fromJson(Map<String, dynamic> j) => TocItem(
        title: (j['title'] ?? '') as String,
        offset: (j['offset'] as num?)?.toInt(),
        cfi: j['cfi'] as String?,
        children: null,
      );
}
