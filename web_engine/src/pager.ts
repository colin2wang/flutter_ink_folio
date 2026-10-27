/**
 * 通用多栏分页器：TXT 与 EPUB 引擎共用。
 *
 * 原理：把内容流放进一个「定高 + 定栏宽」的 CSS multi-column 容器，
 * 由浏览器完成断行与分栏；总页数 = scrollWidth / (栏宽 + 栏间距)，
 * 翻页用 translateX 平移整条内容带。
 *
 * 墨水屏约束：不做任何过渡/动画（transition: none），翻页是瞬时的；
 * 也正因为如此，两次翻页之间必须显式 relayout，不能依赖 transitionend。
 */
export type RelayoutMode =
  /** 内容整体替换后回到第 0 页（换章） */
  | 'reset'
  /** 保持当前页码（仅做越界收敛） */
  | 'keep-page'
  /** 按比例回位（字号/行距变化、转屏）——页数变了但阅读位置不变 */
  | 'keep-ratio';

export interface PagerHost {
  /** 视口：负责裁剪（overflow: hidden）与提供尺寸 */
  readonly viewport: HTMLElement;
  /** 内容带：被切成多栏的容器，innerHTML 由引擎负责填充 */
  readonly content: HTMLElement;
  /** 页码或总页数变化后回调（引擎在此上报进度 / 请求刷新） */
  onPageChanged(page: number, total: number): void;
}

const RESIZE_DEBOUNCE_MS = 80;

export class Pager {
  private page = 0;
  private total = 1;
  private timer: number | undefined;

  constructor(private readonly host: PagerHost) {
    window.addEventListener('resize', this.onResize);
  }

  private readonly onResize = (): void => {
    if (this.timer) window.clearTimeout(this.timer);
    // 转屏/软键盘会连续触发 resize，必须防抖，否则墨水屏上会连续全刷
    this.timer = window.setTimeout(() => this.relayout('keep-ratio'), RESIZE_DEBOUNCE_MS);
  };

  get index(): number {
    return this.page;
  }

  get pages(): number {
    return this.total;
  }

  /** 当前进度 0..1（单页时为 0） */
  get ratio(): number {
    return this.total <= 1 ? 0 : this.page / (this.total - 1);
  }

  /** 栏间距：与栏宽成比例，翻页位移必须用它参与计算，否则会累积偏移 */
  private gapOf(vw: number): number {
    return Math.round(vw * 0.06);
  }

  /**
   * 重新分栏。内容替换或样式变化后必须调用。
   * 读取 scrollWidth 会强制同步布局（reflow），因此调用后页数即为最终值。
   */
  relayout(mode: RelayoutMode = 'keep-page'): void {
    const vw = this.host.viewport.clientWidth;
    const vh = this.host.viewport.clientHeight;
    if (!vw || !vh) return;

    const prevRatio = this.ratio;
    const gap = this.gapOf(vw);
    const s = this.host.content.style;
    s.height = `${vh}px`;
    s.columnWidth = `${vw}px`;
    s.columnGap = `${gap}px`;
    s.columnFill = 'auto';
    s.position = 'relative';
    s.transition = 'none';
    s.willChange = 'transform';

    this.total = Math.max(1, Math.round(this.host.content.scrollWidth / (vw + gap)));

    const target =
      mode === 'reset' ? 0
        : mode === 'keep-ratio' ? Math.round(prevRatio * (this.total - 1))
          : Math.min(this.page, this.total - 1);
    this.goToPage(target, false);
  }

  goToPage(page: number, notify = true): void {
    this.page = Math.max(0, Math.min(this.total - 1, page));
    const vw = this.host.viewport.clientWidth;
    this.host.content.style.transform = `translateX(${-this.page * (vw + this.gapOf(vw))}px)`;
    if (notify) this.host.onPageChanged(this.page, this.total);
  }

  goToRatio(ratio: number, notify = true): void {
    if (this.total <= 1) return;
    const r = Math.max(0, Math.min(1, ratio));
    this.goToPage(Math.round(r * (this.total - 1)), notify);
  }

  /** @returns 是否真的翻了页；false 表示已到本章边界（引擎据此切换章节） */
  next(): boolean {
    if (this.page >= this.total - 1) return false;
    this.goToPage(this.page + 1);
    return true;
  }

  /** @returns 是否真的翻了页；false 表示已到本章开头 */
  prev(): boolean {
    if (this.page <= 0) return false;
    this.goToPage(this.page - 1);
    return true;
  }

  destroy(): void {
    window.removeEventListener('resize', this.onResize);
    if (this.timer) window.clearTimeout(this.timer);
  }
}
