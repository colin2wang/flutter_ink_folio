import { installBridge, onDispatch, emit } from './bridge';
import { DartEvent, TsAction, BookEngine, OpenBookPayload, ThemePayload } from './types';
import { attachGestures } from './gesture';
import { TxtEngine } from './txt_engine';
import { createFoliateEngine } from './loader';

/**
 * 引擎主入口：
 * - epub → foliate 引擎（loader.ts）
 * - txt → 自研 TXT 引擎（txt_engine.ts，回退引擎同源实现）
 */
let engine: BookEngine | null = null;
let txtEngine: TxtEngine | null = null;
let detachGestures: (() => void) | null = null;

const surface = document.getElementById('page-container')!;

async function ensureTxtEngine(): Promise<TxtEngine> {
  txtEngine ??= new TxtEngine(surface);
  return txtEngine;
}

async function ensureEpubEngine(): Promise<BookEngine> {
  if (!engine) {
    engine = await createFoliateEngine(surface);
  }
  return engine;
}

onDispatch(async (action, rawPayload) => {
  const payload = (rawPayload ?? {}) as any;
  switch (action) {
    case TsAction.openBook: {
      const p = payload as OpenBookPayload;
      // 换书先销毁旧引擎，防状态串台
      detachGestures?.(); detachGestures = null;
      engine?.destroy(); engine = null;
      txtEngine?.destroy(); txtEngine = null;
      surface.innerHTML = '';
      try {
        if (p.kind === 'epub') {
          const e = await ensureEpubEngine();
          installGestures(e);
          await e.open(p);
        } else {
          const e = await ensureTxtEngine();
          installGestures(e);
          await e.open(p);
        }
      } catch (err) {
        emit(DartEvent.onError, { message: `openBook failed: ${String(err)}` });
        emit(DartEvent.onNeedRefresh, { type: 'full' });
      }
      break;
    }
    case TsAction.applyTheme: {
      const t = payload as ThemePayload;
      engine?.applyTheme(t);
      txtEngine?.applyTheme(t);
      break;
    }
    case TsAction.scrollToPercent:
      engine?.goToPercent(payload.percent);
      txtEngine?.goToPercent(payload.percent);
      break;
    case TsAction.scrollToOffset:
      txtEngine?.goToOffset(payload.start);
      break;
    case TsAction.scrollToCfi:
      engine?.goToCfi(payload.cfi);
      txtEngine?.goToCfi(String(payload.cfi ?? ''));
      break;
    case TsAction.nextPage:
      engine?.next(); txtEngine?.next();
      break;
    case TsAction.prevPage:
      engine?.prev(); txtEngine?.prev();
      break;
    case TsAction.addAnnotation:
      engine?.addAnnotation(payload);
      txtEngine?.addAnnotation(payload);
      break;
    case TsAction.removeAnnotation:
      engine?.removeAnnotation(payload.id);
      txtEngine?.removeAnnotation(payload.id);
      break;
    case TsAction.exportAnnotations: {
      const list = txtEngine ? txtEngine.exportAnnotations() : (engine?.exportAnnotations() ?? []);
      emit(DartEvent.onAnnotationsExport, { list });
      break;
    }
    default:
      emit(DartEvent.onError, { message: `unknown action: ${action}` });
  }
});

function installGestures(e: BookEngine): void {
  detachGestures?.();
  detachGestures = attachGestures(surface, {
    prev: () => e.prev(),
    next: () => e.next(),
    getContentRoot: () => (e instanceof TxtEngine ? e.contentRoot : surface),
    resolveSelection: sel =>
      e instanceof TxtEngine
        ? e.resolveSelection(sel)
        : resolveCfiSelection(sel),
  });
}

/** foliate 模式选区 → CFI（最佳努力） */
function resolveCfiSelection(sel: Selection): { cfiRange?: string } | null {
  try {
    const anySel = sel as unknown as { getRangeAt(i: number): Range & { cfi?: string } };
    const range = anySel.getRangeAt(0);
    // foliate-js 会在 Range 原型上挂 cfi getter（文档加载后）
    const cfi = (range as unknown as { cfi?: string }).cfi;
    return cfi ? { cfiRange: cfi } : null;
  } catch {
    return null;
  }
}

installBridge();
