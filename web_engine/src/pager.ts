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
  private observer: ResizeObserver | null = null;
  /** 上一次真正参与排版的视口尺寸，用来丢掉重复/过期的 resize */
  private lastSize = '';
  /** 是否已经就「视口与窗口不一致」告过警（避免每次 resize 刷屏） */
  private healed = false;

  constructor(private readonly host: PagerHost) {
    // 用 ResizeObserver 观测视口本身，而不是只靠 window.resize：
    // 1) observe 时会立即回调一次真实尺寸，能纠正初始化时量到的过期值；
    // 2) iframe 被宿主改尺寸时，iframe 内 window 的 resize 不一定触发，
    //    一旦漏掉就永远按旧高度分栏（表现：正文只占左上角一小块，
    //    其余内容被排到屏幕右侧看不见的下一栏）。
    // 但 measure() 补过尺寸后会写死内联宽高，这时元素不再跟着窗口变，
    // 所以 window.resize 仍要常驻。
    if (typeof ResizeObserver !== 'undefined') {
      this.observer = new ResizeObserver(() => this.onResize());
      this.observer.observe(host.viewport);
    }
    window.addEventListener('resize', this.onResize);
  }

  private readonly onResize = (): void => {
    if (this.timer) window.clearTimeout(this.timer);
    // 转屏/软键盘会连续触发 resize，必须防抖，否则墨水屏上会连续全刷
    this.timer = window.setTimeout(() => {
      const size = this.measure();
      const key = size ? `${size.w}x${size.h}` : null;
      if (!key || key === this.lastSize) return;
      this.relayout('keep-ratio');
    }, RESIZE_DEBOUNCE_MS);
  };

  /**
   * 量视口尺寸。
   *
   * 唯一可信的基准是「整个浏览器上下文有多大」——`.ink-viewport` 本身是
   * `position:absolute; inset:0`，它**本该**等于窗口尺寸。量出来差一截，
   * 说明这层定位没生效（样式没跟上，或者宿主 iframe 根本没铺满，
   * 比如停在浏览器默认的 300×150）。这时必须按窗口尺寸纠正：
   * 用错尺寸分栏，`column-width/height` 就全错，正文会缩在左上角一小条，
   * 其余内容排到看不见的下一栏——日志里一切正常，屏幕上却像没渲染。
   */
  private measure(): { w: number; h: number } | null {
    const doc = document.documentElement;
    const winW = window.innerWidth || doc.clientWidth || 0;
    const winH = window.innerHeight || doc.clientHeight || 0;
    // 还没进入布局（宿主视图刚插入 / 尺寸 0）：交给调用方下一帧重试
    if (!winW || !winH) return null;

    const ew = this.host.viewport.clientWidth;
    const eh = this.host.viewport.clientHeight;
    if (ew && eh && Math.abs(ew - winW) <= 8 && Math.abs(eh - winH) <= 8) {
      return { w: ew, h: eh };
    }

    const style = this.host.viewport.style;
    const w = `${winW}px`;
    const h = `${winH}px`;
    if (style.width !== w || style.height !== h) {
      style.width = w;
      style.height = h;
      if (!this.healed) {
        // 走 console.warn：Android 会经 onConsoleMessage 进宿主的运行日志
        console.warn(
            `[ink] 视口 ${ew}x${eh} 与窗口 ${winW}x${winH} 不一致，已按窗口纠正`);
      }
    }
    this.healed = true;
    return { w: winW, h: winH };
  }

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
  relayout(mode: RelayoutMode = 'keep-page', retry = 0): void {
    const size = this.measure();
    if (!size) {
      // 容器还没进入布局（首次打开/刚插入 DOM）：下一帧再量，
      // 否则会按 0 尺寸分栏，正文全部挤在一栏里
      if (retry < 20) {
        requestAnimationFrame(() => this.relayout(mode, retry + 1));
      } else {
        console.warn('[ink] relayout 放弃：视口尺寸始终为 0（宿主视图没尺寸？）');
      }
      return;
    }
    const vw = size.w;
    const vh = size.h;
    this.lastSize = `${vw}x${vh}`;

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
    const vw = this.measure()?.w ?? 0;
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
    this.observer?.disconnect();
    this.observer = null;
    window.removeEventListener('resize', this.onResize);
    if (this.timer) window.clearTimeout(this.timer);
  }
}
