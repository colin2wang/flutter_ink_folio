/** 统一 JSON 信封（与 Dart 侧 BridgeMessage 对齐） */
export interface BridgeMessage<T = unknown> {
  action: string;
  payload: T;
  requestId?: string;
}

/** Dart → TS action 名 */
export const TsAction = {
  openBook: 'openBook',
  applyTheme: 'applyTheme',
  scrollToPercent: 'scrollToPercent',
  scrollToOffset: 'scrollToOffset',
  scrollToCfi: 'scrollToCfi',
  nextPage: 'nextPage',
  prevPage: 'prevPage',
  addAnnotation: 'addAnnotation',
  removeAnnotation: 'removeAnnotation',
  exportAnnotations: 'exportAnnotations',
} as const;

/** TS → Dart event 名 */
export const DartEvent = {
  handlerName: 'event',
  onReady: 'onReady',
  onMeta: 'onMeta',
  onToc: 'onToc',
  onPageChanged: 'onPageChanged',
  onLongPress: 'onLongPress',
  onToggleChrome: 'onToggleChrome',
  onNeedRefresh: 'onNeedRefresh',
  onAnnotationsExport: 'onAnnotationsExport',
  onError: 'onError',
} as const;

export interface ThemePayload {
  mode: 'paper' | 'gray' | 'night';
  fontSize: number;
  lineHeight: number;
  fontFamily: string;
  fontPath?: string;
  /** 页边距（px）：左右取原值，上下取 0.6 倍。缺省 0（正文贴边） */
  margin?: number;
  /** 首行缩进（em）：0 = 不缩进 */
  indent?: number;
  /** 段间距（em）：缺省表示不覆盖原文（EPUB 自带样式说了算） */
  paraSpacing?: number;
}

export interface OpenBookPayload {
  bookId: string;
  kind: 'txt' | 'epub';
  filePath: string;
  text?: string; // txt 直传内容（web 平台文件不可达）
  /** epub 直传字节（base64）：web 端引擎读不到本地文件，由 Dart 读好嵌进来 */
  dataBase64?: string;
  cfi?: string;
  start?: number;
  /** Dart 侧实际下发的进度字段名（reader_controller.openBookInEngine 用 startOffset） */
  startOffset?: number;
  highlights?: HighlightRecord[];
}

export interface HighlightRecord {
  id: string;
  start?: number;
  end?: number;
  cfiRange?: string;
  color: number;
}

export interface TocEntry {
  title: string;
  offset?: number;
  /** 目录定位串：txt 为字符偏移，epub 为 `<spineIndex>` 或 `<spineIndex>#<anchorId>` */
  cfi?: string;
}

export interface PageChangePayload {
  percent: number; // 0..1
  cfi?: string;
  start?: number;
  chapter?: string;
  index?: number;
  total?: number;
}

/** 引擎抽象：epub 引擎与 txt 引擎共同实现 */
export interface BookEngine {
  /** 正文根元素：手势层判定选区归属、主题注入的作用点 */
  readonly contentRoot: HTMLElement;
  /** Selection → 全局字符偏移（两种引擎语义一致，高亮与进度共用） */
  resolveSelection(sel: Selection): { start: number; end: number } | null;

  open(payload: OpenBookPayload): Promise<void>;
  applyTheme(t: ThemePayload): void;
  goToPercent(p: number): void;
  goToOffset(start: number): void;
  goToCfi(cfi: string): void;
  next(): void;
  prev(): void;
  addAnnotation(a: HighlightRecord): void;
  removeAnnotation(id: string): void;
  exportAnnotations(): HighlightRecord[];
  destroy(): void;
}
