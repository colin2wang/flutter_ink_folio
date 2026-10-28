import { DartEvent, emit } from './bridge';
import { loadText } from './io';
import { Pager } from './pager';
import {
  BookEngine,
  HighlightRecord,
  OpenBookPayload,
  PageChangePayload,
  ThemePayload,
  TocEntry,
} from './types';
import { applyTheme } from './renderer';
import { clampColor, escapeAttr, escapeHtml, offsetOf } from './text';

/**
 * TXT 引擎：CSS 多栏分页 + 字符偏移定位 + 偏移高亮。
 * 也是 assets/web 回退引擎（vanilla JS）的 TS 原型，两者行为一致。
 *
 * 排版与翻页交给 Pager（与 EPUB 引擎共用），这里只负责纯文本 → HTML。
 */
export class TxtEngine implements BookEngine {
  private readonly viewport: HTMLElement;
  private readonly content: HTMLElement;
  private readonly pager: Pager;
  private text = '';
  private toc: TocEntry[] = [];
  private annotations = new Map<string, HighlightRecord>();
  private theme: ThemePayload = {
    mode: 'paper', fontSize: 19, lineHeight: 1.7, fontFamily: 'serif',
  };

  constructor(surface: HTMLElement) {
    this.viewport = document.createElement('div');
    this.viewport.className = 'ink-viewport';
    this.content = document.createElement('div');
    this.content.className = 'ink-book ink-txt';
    this.viewport.appendChild(this.content);
    surface.appendChild(this.viewport);

    this.pager = new Pager({
      viewport: this.viewport,
      content: this.content,
      onPageChanged: () => this.notifyChanged(),
    });
  }

  get contentRoot(): HTMLElement {
    return this.content;
  }

  async open(payload: OpenBookPayload): Promise<void> {
    this.text = payload.text ?? (await this.loadFile(payload.filePath));
    this.toc = buildToc(this.text);
    this.render();
    applyTheme(this.viewport, this.theme);
    emit(DartEvent.onMeta, { title: payload.bookId, author: '' });
    emit(DartEvent.onToc, { items: this.toc });
    // 恢复进度：优先字符偏移，其次百分比（cfi 字段在 txt 引擎中复用为百分比）
    // Dart 下发字段名为 startOffset，老版本是 start，两者都认
    const start = payload.start ?? payload.startOffset ?? 0;
    if (start > 0) this.goToOffset(start);
    else {
      const cfiNum = Number(payload.cfi);
      if (!Number.isNaN(cfiNum) && cfiNum > 0) this.goToPercent(cfiNum);
    }
    this.notifyChanged();
  }

  private async loadFile(path: string): Promise<string> {
    // 正常路径是 Dart 直接下发 text（见 open）；这里只是 filePath 兜底。
    // 不能用 fetch：Android WebView 的 fetch 不支持 file://（见 io.ts）
    return await loadText(path);
  }

  private render(): void {
    // 按 DOM 构建正文 + 高亮包裹（选区偏移用纯文本行走计算，不受 span 影响）
    this.content.innerHTML = buildHtml(this.text, [...this.annotations.values()]);
    this.pager.relayout('keep-page');
  }

  private notifyChanged(): void {
    const percent = this.pager.ratio;
    const start = Math.floor(this.text.length * percent);
    const payload: PageChangePayload = {
      percent,
      start,
      chapter: chapterAt(this.toc, start),
      index: this.pager.index,
      total: this.pager.pages,
    };
    emit(DartEvent.onPageChanged, payload);
    emit(DartEvent.onNeedRefresh, { type: 'full' }); // TS 渲染完成 → 请求全刷
  }

  applyTheme(t: ThemePayload): void {
    this.theme = t;
    applyTheme(this.viewport, t);
    // 字号/行距变化 → 重排并按比例回位
    const ratio = this.pager.ratio;
    this.render();
    this.pager.goToRatio(ratio, false);
    this.notifyChanged();
  }

  goToPercent(p: number): void {
    this.pager.goToRatio(p);
  }

  goToOffset(start: number): void {
    // 定位：按字符偏移估算页码（章节级精确，页内为比例近似，够用）
    const ratio = this.text.length ? start / this.text.length : 0;
    this.goToPercent(ratio);
  }

  goToCfi(cfi: string): void {
    // txt 引擎把 cfi 字段当百分比复用（见 open）
    const n = Number(cfi);
    if (!Number.isNaN(n)) this.goToPercent(n);
  }

  next(): void {
    this.pager.next();
  }

  prev(): void {
    this.pager.prev();
  }

  addAnnotation(a: HighlightRecord): void {
    this.annotations.set(a.id, a);
    this.render();
    emit(DartEvent.onNeedRefresh, { type: 'partial' });
  }

  removeAnnotation(id: string): void {
    this.annotations.delete(id);
    this.render();
    emit(DartEvent.onNeedRefresh, { type: 'partial' });
  }

  exportAnnotations(): HighlightRecord[] {
    return [...this.annotations.values()];
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
    this.pager.destroy();
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


