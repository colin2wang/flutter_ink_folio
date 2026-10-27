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
}

export interface OpenBookPayload {
  bookId: string;
  kind: 'txt' | 'epub';
  filePath: string;
  text?: string; // txt 直传内容（web 平台文件不可达）
  cfi?: string;
  start?: number;
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

/** 引擎抽象：foliate 引擎与 txt 引擎共同实现 */
export interface BookEngine {
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
