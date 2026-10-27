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
 * foliate 引擎：epub/mobi/fb2 解析与分页交给 foliate-js（View 自定义元素）。
 * 依赖：web_engine/package.json 中的 foliate-js（github:johnfactotum/foliate-js）。
 *
 * foliate-js 无 TypeScript 类型声明，这里用 any 面向运行时编程，
 * 关键调用点均包 try/catch 并通过 onError 上报，避免引擎升级炸掉壳层。
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
type Any = any;

export async function createFoliateEngine(surface: HTMLElement): Promise<BookEngine> {
  // 导入即注册 <foliate-view> 自定义元素
  await import('foliate-js/view.js');

  const view: Any = document.createElement('foliate-view');
  view.style.position = 'absolute';
  view.style.inset = '0';
  surface.appendChild(view);

  const localAnnos = new Map<string, HighlightRecord>();
  let theme: ThemePayload = { mode: 'paper', fontSize: 19, lineHeight: 1.7, fontFamily: 'serif' };

  const injectStyles = () => {
    try {
      const contents = view.renderer?.getContents?.() ?? [];
      for (const c of contents) {
        if (c?.doc) applyTheme(surface, theme, [c.doc as Document]);
      }
    } catch { /* 部分版本接口名不同，忽略 */ }
  };

  view.addEventListener('relocate', (e: Any) => {
    const d = e.detail ?? {};
    const payload: PageChangePayload = {
      percent: typeof d.fraction === 'number' ? d.fraction : 0,
      cfi: d.cfi,
      chapter: d.tocItem?.label?.trim?.() ?? undefined,
      index: typeof d.location === 'object' ? d.location?.current : undefined,
      total: typeof d.location === 'object' ? d.location?.total : undefined,
    };
    emit(DartEvent.onPageChanged, payload);
    emit(DartEvent.onNeedRefresh, { type: 'full' }); // 渲染完成 → 全刷（时序不能反）
  });

  view.addEventListener('load', (e: Any) => {
    // 章节/资源加载完成：补注入主题（iframe 文档替换后样式会丢）
    injectStyles();
    try {
      const tocRaw: Any[] = view.book?.toc ?? [];
      const items: TocEntry[] = [];
      const walk = async (list: Any[]) => {
        for (const t of list) {
          let cfi: string | undefined;
          try {
            // href → cfi（foliate 支持 resolveNavigation）
            const resolved = await view.resolveNavigation?.(t.href);
            cfi = resolved?.cfi ?? (typeof resolved === 'string' ? resolved : undefined);
          } catch { /* 忽略单个目录项解析失败 */ }
          items.push({ title: (t.label ?? '').trim().slice(0, 60), cfi });
          if (t.subitems?.length) await walk(t.subitems as Any[]);
        }
      };
      void walk(tocRaw).then(() => {
        emit(DartEvent.onToc, { items });
        emit(DartEvent.onNeedRefresh, { type: 'full' });
      });
    } catch { /* toc 可选 */ }
  });

  return {
    async open(payload: OpenBookPayload) {
      // filePath → Blob：Android 端 fetch file:// 由 WebView 设置放行
      const res = await fetch(payload.filePath.startsWith('file:')
        ? payload.filePath
        : `file://${payload.filePath}`);
      const blob = await res.blob();
      await view.open(blob); // View.open 自动识别 epub/mobi/fb2
      injectStyles();
      if (payload.cfi) view.goTo(payload.cfi);
      else if (typeof payload.start === 'number') view.goToFraction?.(0);
      emit(DartEvent.onMeta, { title: '', author: '' });
    },

    applyTheme(t: ThemePayload) {
      theme = t;
      injectStyles();
    },

    goToPercent(p) {
      view.goToFraction?.(p);
    },

    goToOffset() { /* txt 专用，epub 忽略 */ },

    goToCfi(cfi) {
      view.goTo?.(cfi);
    },

    next() {
      view.renderer?.next?.();
    },

    prev() {
      view.renderer?.prev?.();
    },

    addAnnotation(a: HighlightRecord) {
      localAnnos.set(a.id, a);
      try {
        if (a.cfiRange) view.addAnnotation?.({ value: a.cfiRange });
      } catch { /* 注解绘制失败不阻断阅读 */ }
    },

    removeAnnotation(id) {
      const a = localAnnos.get(id);
      localAnnos.delete(id);
      try {
        if (a?.cfiRange) view.deleteAnnotation?.({ value: a.cfiRange });
      } catch { /* 忽略 */ }
    },

    exportAnnotations() {
      return [...localAnnos.values()];
    },

    destroy() {
      try { view.close?.(); } catch { /* 忽略 */ }
      view.remove();
    },
  };
}
