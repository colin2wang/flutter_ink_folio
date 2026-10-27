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
