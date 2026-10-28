import { DartEvent, emit } from './bridge';
import { EpubBook, EpubTocEntry, openEpub } from './epub/epub_book';
import { loadBinary, base64ToBuffer } from './io';
import { Pager } from './pager';
import { applyTheme } from './renderer';
import { clampColor, highlightRange, offsetOf } from './text';
import {
  BookEngine,
  HighlightRecord,
  OpenBookPayload,
  PageChangePayload,
  ThemePayload,
  TocEntry,
} from './types';

/** 图片解码完成后内容高度会变，统一防抖重排 */
const RELAYOUT_DELAY_MS = 80;

/**
 * EPUB 引擎：按章分页 + 全局字符偏移定位。
 *
 * 与 TXT 引擎共用 Pager 和同一套定位模型（全局字符偏移），因此：
 * - 进度落在 Dart 的 `startOffset` 上，划线落在 `start/end` 上，语义与 TXT 完全一致；
 * - 不再需要 CFI，Flutter 侧与数据库无需任何改动。
 *
 * 定位串（TOC 的 cfi 字段）格式为 `<spineIndex>#<anchor>`，
 * 目录与正文内链共用 `goToCfi` 一条通路。
 */
export class EpubEngine implements BookEngine {
  private readonly viewport: HTMLElement;
  private readonly content: HTMLElement;
  private readonly pager: Pager;
  private book: EpubBook | null = null;

  /** 当前章在 spine 中的索引 */
  private spine = 0;
  /** 各章起始全局偏移 */
  private chapterStart: number[] = [];
  /** 全书纯文本长度（进度换算的分母） */
  private totalLength = 0;

  private annotations = new Map<string, HighlightRecord>();
  private relayoutTimer: number | undefined;

  constructor(surface: HTMLElement) {
    this.viewport = document.createElement('div');
    this.viewport.className = 'ink-viewport';
    this.content = document.createElement('div');
    this.content.className = 'ink-book ink-epub';
    this.viewport.appendChild(this.content);
    surface.appendChild(this.viewport);

    this.pager = new Pager({
      viewport: this.viewport,
      content: this.content,
      onPageChanged: () => this.notifyChanged(),
    });

    this.content.addEventListener('click', this.onContentClick);
  }

  get contentRoot(): HTMLElement {
    return this.content;
  }

  async open(payload: OpenBookPayload): Promise<void> {
    // 字节来源两条：web 端宿主以内嵌 base64 下发（读不到本地文件）；
    // Android 走路径，用 XHR 读 file://（fetch 不支持 file:，见 io.ts）
    const inline = payload.dataBase64
      ? base64ToBuffer(payload.dataBase64)
      : await loadBinary(payload.filePath);
    this.book = await openEpub(inline);

    // 预计算各章起始偏移：进度换算与划线归属都依赖它，只算一次
    this.chapterStart = [];
    let acc = 0;
    for (const len of this.book.chapterLengths) {
      this.chapterStart.push(acc);
      acc += len;
    }
    this.totalLength = acc;

    emit(DartEvent.onMeta, {
      title: this.book.title || payload.bookId,
      author: this.book.author,
    });
    emit(DartEvent.onToc, { items: this.toTocItems(this.book.toc) });

    // 恢复进度：优先全局字符偏移。
    // Dart 侧下发的字段名是 startOffset（见 reader_controller.openBookInEngine），
    // 旧类型里的 start 一并兼容；老 foliate CFI（epubcfi(...)）无法解析，按开头进入。
    const start = payload.start ?? payload.startOffset ?? 0;
    const { spine, ratio } = this.locate(start);
    await this.showChapter(spine, ratio);
  }

  applyTheme(t: ThemePayload): void {
    // 主题样式挂在 document.head（见 renderer.inject），换章不会丢，注入一次即可
    applyTheme(this.viewport, t);
    // 字号/行距变化只需重新分栏，章节 HTML 无需重新解析
    this.pager.relayout('keep-ratio');
    this.notifyChanged();
  }

  goToPercent(p: number): void {
    const { spine, ratio } = this.locate(this.totalLength * Math.max(0, Math.min(1, p)));
    this.jumpTo(spine, ratio);
  }

  goToOffset(start: number): void {
    const { spine, ratio } = this.locate(start);
    this.jumpTo(spine, ratio);
  }

  goToCfi(cfi: string): void {
    const raw = (cfi ?? '').trim();
    const i = raw.indexOf('#');
    const head = i < 0 ? raw : raw.slice(0, i);
    const anchor = i < 0 ? '' : raw.slice(i + 1);
    const index = Number(head);
    // 老 foliate CFI 以 epubcfi( 开头，Number() 得 NaN → 忽略
    if (!Number.isFinite(index)) return;
    void this.showChapter(index).then(() => {
      if (anchor) this.scrollToAnchor(anchor);
    });
  }

  next(): void {
    if (this.pager.next()) return;
    if (this.book && this.spine < this.book.chapterCount - 1) {
      void this.showChapter(this.spine + 1);
    }
  }

  prev(): void {
    if (this.pager.prev()) return;
    // 回到上一章的最后一页
    if (this.spine > 0) void this.showChapter(this.spine - 1, 1);
  }

  addAnnotation(a: HighlightRecord): void {
    this.annotations.set(a.id, a);
    const range = this.toChapterRange(a);
    if (!range) return;
    highlightRange(
      this.content,
      range.start,
      range.end,
      `ink-hl ink-hl-${clampColor(a.color)}`,
      a.id,
    );
    emit(DartEvent.onNeedRefresh, { type: 'partial' });
  }

  removeAnnotation(id: string): void {
    this.annotations.delete(id);
    // 高亮绘制时做了 splitText，无法可靠反查原始节点，重渲染本章最稳
    void this.showChapter(this.spine, this.pager.ratio);
  }

  exportAnnotations(): HighlightRecord[] {
    return [...this.annotations.values()];
  }

  resolveSelection(sel: Selection): { start: number; end: number } | null {
    try {
      const range = sel.getRangeAt(0);
      const s = offsetOf(this.content, range.startContainer, range.startOffset);
      const e = offsetOf(this.content, range.endContainer, range.endOffset);
      if (s == null || e == null) return null;
      const base = this.chapterStart[this.spine] ?? 0;
      return { start: base + Math.min(s, e), end: base + Math.max(s, e) };
    } catch {
      return null;
    }
  }

  destroy(): void {
    if (this.relayoutTimer) window.clearTimeout(this.relayoutTimer);
    this.content.removeEventListener('click', this.onContentClick);
    this.pager.destroy();
    this.book?.destroy();
    this.book = null;
    this.content.remove();
    this.viewport.remove();
  }

  // -------------------------------------------------------------------------
  // 内部实现
  // -------------------------------------------------------------------------

  private async showChapter(index: number, ratio = 0): Promise<void> {
    const book = this.book;
    if (!book) return;

    const clamped = Math.max(0, Math.min(book.chapterCount - 1, Math.trunc(index)));
    this.spine = clamped;
    this.content.innerHTML = await book.renderChapter(clamped);
    this.watchAssets();

    this.pager.relayout('reset');
    if (ratio > 0) this.pager.goToRatio(ratio, false);
    this.paintAnnotations();
    this.notifyChanged();
  }

  private jumpTo(spine: number, ratio: number): void {
    if (spine === this.spine) this.pager.goToRatio(ratio);
    else void this.showChapter(spine, ratio);
  }

  /** 全局偏移 →（章索引, 章内比例） */
  private locate(offset: number): { spine: number; ratio: number } {
    const book = this.book;
    if (!book || offset <= 0) return { spine: 0, ratio: 0 };
    for (let i = book.chapterCount - 1; i >= 0; i--) {
      const from = this.chapterStart[i] ?? 0;
      if (offset >= from) {
        const len = book.chapterLengths[i] ?? 0;
        return { spine: i, ratio: len ? (offset - from) / len : 0 };
      }
    }
    return { spine: 0, ratio: 0 };
  }

  /** 把全局偏移的划线换算成本章内的 [start, end)；不在本章返回 null */
  private toChapterRange(a: HighlightRecord): { start: number; end: number } | null {
    const len = this.book?.chapterLengths[this.spine] ?? 0;
    if (a.start == null || a.end == null) return null;
    const base = this.chapterStart[this.spine] ?? 0;
    const s = a.start - base;
    const e = a.end - base;
    if (e <= 0 || s >= len) return null;
    return { start: Math.max(0, s), end: Math.min(e, len) };
  }

  private paintAnnotations(): void {
    for (const a of this.annotations.values()) {
      const range = this.toChapterRange(a);
      if (!range) continue;
      highlightRange(
        this.content,
        range.start,
        range.end,
        `ink-hl ink-hl-${clampColor(a.color)}`,
        a.id,
      );
    }
  }

  /** 图片是按 blob: URL 异步解码的，加载完页数会变，必须重排 */
  private watchAssets(): void {
    for (const img of Array.from(this.content.querySelectorAll('img'))) {
      img.addEventListener('load', this.onAssetSettled, { once: true });
      img.addEventListener('error', this.onAssetSettled, { once: true });
    }
  }

  private readonly onAssetSettled = (): void => {
    if (this.relayoutTimer) window.clearTimeout(this.relayoutTimer);
    this.relayoutTimer = window.setTimeout(
      () => this.pager.relayout('keep-ratio'),
      RELAYOUT_DELAY_MS,
    );
  };

  private readonly onContentClick = (ev: MouseEvent): void => {
    const link = (ev.target as Element | null)?.closest('[data-epub-href]');
    if (!link) return;
    ev.preventDefault();
    this.goToCfi(link.getAttribute('data-epub-href') ?? '');
  };

  /** 跳到章内锚点：多栏布局下按元素在内容坐标系中的横向位置反算页码 */
  private scrollToAnchor(anchor: string): void {
    const id = `ink-c${this.spine}-${anchor}`;
    const el = Array.from(this.content.querySelectorAll<HTMLElement>('[id]'))
      .find(n => n.id === id);
    if (!el) return;
    // 步进必须用 Pager 内部那套（栏宽已扣页边距），现量 clientWidth 会偏
    const stride = this.pager.stride;
    if (stride <= 0) return;
    this.pager.goToPage(Math.floor(el.offsetLeft / stride));
  }

  private notifyChanged(): void {
    const len = this.book?.chapterLengths[this.spine] ?? 0;
    const start = (this.chapterStart[this.spine] ?? 0) + Math.round(len * this.pager.ratio);
    const payload: PageChangePayload = {
      percent: this.totalLength ? start / this.totalLength : 0,
      start,
      chapter: this.currentChapterTitle(),
      index: this.pager.index,
      total: this.pager.pages,
    };
    emit(DartEvent.onPageChanged, payload);
    emit(DartEvent.onNeedRefresh, { type: 'full' }); // TS 渲染完成 → 请求全刷
  }

  /** 当前章标题：目录里最后一个不晚于当前 spine 的条目 */
  private currentChapterTitle(): string {
    let title = '';
    const walk = (list: readonly EpubTocEntry[]): void => {
      for (const e of list) {
        if (e.spineIndex >= 0 && e.spineIndex <= this.spine) title = e.title;
        walk(e.children);
      }
    };
    if (this.book) walk(this.book.toc);
    return title;
  }

  /** 目录：定位串塞进 cfi（Dart 侧目录点击优先取 cfi），offset 顺带给出章索引 */
  private toTocItems(list: readonly EpubTocEntry[]): TocEntry[] {
    return list.map(e => ({
      title: e.title.slice(0, 60),
      cfi: `${e.spineIndex}#${e.anchor}`,
      offset: e.spineIndex,
    }));
  }
}
