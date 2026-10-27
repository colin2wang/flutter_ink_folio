import { ThemePayload } from './types';

const STYLE_ID = 'ink-theme-style';

/**
 * 主题渲染：灰阶三档 + 字体注入 + 中文避头尾。
 * 规则：无动画/无渐变/无阴影/无模糊（墨水屏残影规避清单）。
 */
export function applyTheme(root: HTMLElement, t: ThemePayload, docs: Document[] = [document]): void {
  for (const doc of docs) inject(doc, buildCss(t));
  root.style.background = bgOf(t.mode);
}

/**
 * 写入主题样式：同一文档内复用固定 id 的 <style>。
 * - 复用而非追加：换章/重排会反复调用，逐次 append 会让样式表无限膨胀
 * - 内容相同则跳过：减少无谓重排（墨水屏下每次重排都要全刷）
 * - 不走 instanceof HTMLStyleElement：docs 可能来自 iframe（跨 realm 判定失效）
 */
function inject(doc: Document, css: string): void {
  const host: Element | null = doc.head ?? doc.documentElement;
  if (!host) return;

  // XHTML 文档（EPUB 章节常见）的 tagName 保留原始大小写，统一转小写比较
  const existing = doc.getElementById(STYLE_ID);
  const isStyle = existing?.tagName?.toLowerCase() === 'style';
  let style = existing && isStyle ? (existing as HTMLStyleElement) : null;
  if (!style) {
    style = doc.createElement('style');
    style.id = STYLE_ID;
    host.appendChild(style);
  }
  if (style.textContent !== css) style.textContent = css;
}

function bgOf(mode: ThemePayload['mode']): string {
  return mode === 'night' ? '#111111' : mode === 'gray' ? '#ECECEC' : '#FFFFFF';
}

function buildCss(t: ThemePayload): string {
  const [bg, fg] = fgBg(t.mode);
  const family = fontCss(t);
  const face = t.fontPath ? fontFaceCss(t.fontPath) : '';
  return `${face}
    html, body {
      background: ${bg} !important;
      transition: none !important;
      animation: none !important;
    }
    .ink-viewport {
      position: absolute;
      inset: 0;
      overflow: hidden;
    }
    .ink-book, .ink-book * {
      background: transparent !important;
      box-shadow: none !important;
      text-shadow: none !important;
      filter: none !important;
      transition: none !important;
      animation: none !important;
      color: ${fg};
    }
    .ink-book {
      font-family: ${family} !important;
      font-size: ${t.fontSize}px !important;
      line-height: ${t.lineHeight} !important;
      text-align: justify;
      /* 中文避头尾 + 禁止孤字悬挂 */
      line-break: strict;
      word-break: normal;
      overflow-wrap: anywhere;
      letter-spacing: 0.02em;
      -webkit-hyphens: none;
      hyphens: none;
    }
    .ink-book img { max-width: 100% !important; height: auto !important; }
    /* EPUB 排版兜底：多栏分页下浮动/绝对定位会破坏分栏，图文块需避免跨栏断裂 */
    .ink-epub * { float: none !important; position: static !important; }
    .ink-epub img, .ink-epub svg, .ink-epub figure, .ink-epub table {
      max-width: 100% !important;
      height: auto !important;
      break-inside: avoid;
    }
    .ink-epub h1, .ink-epub h2, .ink-epub h3, .ink-epub h4 { break-after: avoid; }
    .ink-epub p { text-align: justify; }
    .ink-hl { background: currentColor; opacity: 0.28; border-radius: 1px; }
    .ink-hl-1 { opacity: 0.18; }
    .ink-hl-5 { opacity: 0.4; }`;
}

function fgBg(mode: ThemePayload['mode']): [string, string] {
  switch (mode) {
    case 'night': return ['#111111', '#C9C9C9'];
    case 'gray': return ['#ECECEC', '#1F1F1F'];
    default: return ['#FFFFFF', '#111111'];
  }
}

function fontCss(t: ThemePayload): string {
  switch (t.fontFamily) {
    case 'sans':
      return '"Noto Sans CJK SC", "Source Han Sans SC", sans-serif';
    default:
      if (t.fontFamily.startsWith('custom:')) {
        const name = t.fontFamily.slice(7).replace(/"/g, '');
        return `"${name}", "Noto Serif CJK SC", serif`;
      }
      return '"Noto Serif CJK SC", "Source Han Serif SC", serif';
  }
}

/** 自定义字体（FontManager 拷入沙盒后以 file:// 路径下发） */
function fontFaceCss(path: string): string {
  const url = path.startsWith('file:') ? path : `file://${path}`;
  return `@font-face {
      font-family: "custom";
      src: url("${url}");
      font-display: swap;
    }`;
}
