import { DartEvent, emit } from './bridge';
import {
  BookEngine,
  HighlightRecord,
  OpenBookPayload,
  PageChangePayload,
  ThemePayload,
  TocEntry,
} from './types';
import { applyTheme } from './renderer';

/**
 * TXT 引擎：CSS 多栏分页 + 字符偏移定位 + 偏移高亮。
 * 也是 assets/web 回退引擎（vanilla JS）的 TS 原型，两者行为一致。
 */
export class TxtEngine implements BookEngine {
  private viewport: HTMLElement;
  private content: HTMLElement;
  private text = '';
  private page = 0;
  private total = 1;
  private toc: TocEntry[] = [];
  private annotations = new Map<string, HighlightRecord>();
  private theme: ThemePayload = {
    mode: 'paper', fontSize: 19, lineHeight: 1.7, fontFamily: 'serif',
  };
  private chapterTitle = '';
  private resizeTimer: number | undefined;

  constructor(surface: HTMLElement) {
    this.viewport = document.createElement('div');
    this.viewport.className = 'ink-viewport';
    this.content = document.createElement('div');
    this.content.className = 'ink-book ink-txt';
    this.viewport.appendChild(this.content);
    surface.appendChild(this.viewport);

    window.addEventListener('resize', () => {
      if (this.resizeTimer) window.clearTimeout(this.resizeTimer);
      this.resizeTimer = window.setTimeout(() => this.relayout(true), 80);
    });
  }

  async open(payload: OpenBookPayload): Promise<void> {
    this.text = payload.text ?? (await this.loadFile(payload.filePath));
    this.page = 0;
    this.toc = buildToc(this.text);
    this.render();
    applyTheme(this.viewport, this.theme);
    emit(DartEvent.onMeta, { title: payload.bookId, author: '' });
    emit(DartEvent.onToc, { items: this.toc });
    // 恢复进度：优先字符偏移，其次百分比（cfi 字段在 txt 引擎中复用为百分比）
    if (payload.start && payload.start > 0) this.goToOffset(payload.start);
    else {
      const cfiNum = Number(payload.cfi);
      if (!Number.isNaN(cfiNum) && cfiNum > 0) this.goToPercent(cfiNum);
    }
    this.notifyChanged();
  }

  private async loadFile(path: string): Promise<string> {
    // Android WebView：allowUniversalAccessFromFileURLs 开启后可 fetch file://
    const res = await fetch(path.startsWith('file:') ? path : `file://${path}`);
    return await res.text();
  }

  private render(): void {
    // 按 DOM 构建正文 + 高亮包裹（选区偏移用纯文本行走计算，不受 span 影响）
    this.content.innerHTML = buildHtml(this.text, [...this.annotations.values()]);
    this.relayout(false);
  }

  private relayout(keepRatio: boolean): void {
    const vw = this.viewport.clientWidth;
    const vh = this.viewport.clientHeight;
    if (!vw || !vh) return;
    const gap = Math.round(vw * 0.06);
    const s = this.content.style;
    s.height = `${vh}px`;
    s.columnWidth = `${vw}px`;
    s.columnGap = `${gap}px`;
    s.columnFill = 'auto';
    s.position = 'relative';
    s.transition = 'none';
    s.willChange = 'transform';

    const raw = this.content.scrollWidth;
    this.total = Math.max(1, Math.round(raw / (vw + gap)));
    if (keepRatio) {
      this.page = Math.min(this.total - 1, this.page);
    }
    this.goToPage(this.page, false);
  }

  private goToPage(p: number, notify = true): void {
    this.page = Math.max(0, Math.min(this.total - 1, p));
    const vw = this.viewport.clientWidth;
    const gap = Math.round(vw * 0.06);
    this.content.style.transform = `translateX(${-this.page * (vw + gap)}px)`;
    if (notify) this.notifyChanged();
  }

  private notifyChanged(): void {
    const percent = this.total <= 1 ? 0 : this.page / (this.total - 1);
    const start = Math.floor(this.text.length * percent);
    this.chapterTitle = chapterAt(this.toc, start);
    const payload: PageChangePayload = {
      percent,
      start,
      chapter: this.chapterTitle,
      index: this.page,
      total: this.total,
    };
    emit(DartEvent.onPageChanged, payload);
    emit(DartEvent.onNeedRefresh, { type: 'full' }); // TS 渲染完成 → 请求全刷
  }

  applyTheme(t: ThemePayload): void {
    this.theme = t;
    applyTheme(this.viewport, t);
    // 字号/行距变化 → 重排并按比例回位
    const ratio = this.total <= 1 ? 0 : this.page / (this.total - 1);
    this.render();
    this.goToPage(Math.round(ratio * (this.total - 1)), false);
    this.notifyChanged();
  }

  goToPercent(p: number): void {
    if (this.total <= 1) return;
    this.goToPage(Math.round(p * (this.total - 1)));
  }

  goToOffset(start: number): void {
    // 定位：按偏移估算页码后二分校正（简化：直接按比例 + 章节对齐由 Dart 侧处理）
    const ratio = this.text.length ? start / this.text.length : 0;
    this.goToPercent(ratio);
  }

  goToCfi(cfi: string): void {
    // txt 引擎把 cfi 字段当百分比复用（见 open）
    const n = Number(cfi);
    if (!Number.isNaN(n)) this.goToPercent(n);
  }

  next(): void {
    if (this.page < this.total - 1) this.goToPage(this.page + 1);
  }

  prev(): void {
    if (this.page > 0) this.goToPage(this.page - 1);
  }

  addAnnotation(a: HighlightRecord): void {
    this.annotations.set(a.id, a);
    this.render();
    this.goToPage(this.page, false);
    emit(DartEvent.onNeedRefresh, { type: 'partial' });
  }

  removeAnnotation(id: string): void {
    this.annotations.delete(id);
    this.render();
    this.goToPage(this.page, false);
    emit(DartEvent.onNeedRefresh, { type: 'partial' });
  }

  exportAnnotations(): HighlightRecord[] {
    return [...this.annotations.values()];
  }

  /** 手势层取当前正文根 */
  get contentRoot(): HTMLElement {
    return this.content;
  }

  /** Selection → 字符偏移（按文本节点行走累计） */
  resolveSelection(sel: Selection): { start: number; end: number } | null {
    try {
      const range = sel.getRangeAt(0);
      const start = offsetOf(this.content, range.startContainer, range.startOffset);
      const end = offsetOf(this.content, range.endContainer, range.endOffset);
      if (start == null || end == null) return null;
      return { start: Math.min(start, end), end: Math.max(start, end) };
    } catch {
      return null;
    }
  }

  destroy(): void {
    this.content.remove();
    this.viewport.remove();
  }
}

// ---------------------------------------------------------------------------
// 目录 / 高亮 HTML / 偏移计算
// ---------------------------------------------------------------------------

const CHAPTER_RE = /^\s*(第[一二三四五六七八九十百千万零〇\d]+[章回卷节部篇]|楔子|序章|序言|尾声|后记|番外.{0,12}).{0,60}$/;

export function buildToc(text: string): TocEntry[] {
  const toc: TocEntry[] = [];
  let offset = 0;
  for (const line of text.split('\n')) {
    if (CHAPTER_RE.test(line.trim())) {
      toc.push({ title: line.trim().slice(0, 40), offset });
    }
    offset += line.length + 1;
  }
  return toc;
}

function chapterAt(toc: TocEntry[], offset: number): string {
  let title = '';
  for (const t of toc) {
    if ((t.offset ?? 0) <= offset) title = t.title;
    else break;
  }
  return title;
}

export function buildHtml(text: string, annos: HighlightRecord[]): string {
  const sorted = annos
    .filter(a => a.start != null && a.end != null && (a.end as number) > (a.start as number))
    .sort((a, b) => (a.start as number) - (b.start as number));

  // 区间合并：重叠部分保留先到者（避免嵌套 span 破坏偏移计算）
  const marks: Array<{ at: number; open: boolean; a: HighlightRecord }> = [];
  let cursor = -1;
  for (const a of sorted) {
    const s = a.start as number;
    const e = a.end as number;
    if (s < cursor) continue;
    marks.push({ at: s, open: true, a });
    marks.push({ at: e, open: false, a });
    cursor = e;
  }

  let html = '';
  let pos = 0;
  for (const m of marks.sort((x, y) => x.at - y.at || (x.open ? -1 : 1))) {
    html += escapeHtml(text.slice(pos, m.at));
    if (m.open) {
      html += `<span class="ink-hl ink-hl-${clampColor(m.a.color)}" data-anno="${escapeAttr(m.a.id)}">`;
    } else {
      html += '</span>';
    }
    pos = m.at;
  }
  html += escapeHtml(text.slice(pos));
  // 段落化：空行分段，保留简单换行
  return html
    .split(/\n{2,}/)
    .map(seg => `<p>${seg.replace(/\n/g, '<br>')}</p>`)
    .join('');
}

function offsetOf(root: Node, node: Node, offset: number): number | null {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let total = 0;
  let n: Node | null;
  while ((n = walker.nextNode())) {
    if (n === node) return total + offset;
    total += (n.textContent ?? '').length;
  }
  return null;
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function escapeAttr(s: string): string {
  return s.replace(/"/g, '&quot;');
}

function clampColor(c: number): number {
  return Math.max(1, Math.min(5, Math.round(c) || 2));
}
