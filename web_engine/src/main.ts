import { installBridge, onDispatch, emit } from './bridge';
import { DartEvent, TsAction, BookEngine, OpenBookPayload, ThemePayload } from './types';
import { attachGestures } from './gesture';
import { TxtEngine } from './txt_engine';
import { EpubEngine } from './epub_engine';

/**
 * 引擎主入口：
 * - epub → EpubEngine（JSZip 解析 OPF/NCX/NAV + 多栏分页）
 * - txt  → TxtEngine（纯文本 + 多栏分页）
 *
 * 两者共用 Pager 与「全局字符偏移」定位模型，且都实现 BookEngine，
 * 因此分发层无需区分引擎类型，也不再依赖 CFI。
 */
let engine: BookEngine | null = null;
let detachGestures: (() => void) | null = null;

const surface = document.getElementById('page-container')!;

function createEngine(kind: OpenBookPayload['kind']): BookEngine {
  return kind === 'epub' ? new EpubEngine(surface) : new TxtEngine(surface);
}

onDispatch(async (action, rawPayload) => {
  const payload = (rawPayload ?? {}) as any;
  switch (action) {
    case TsAction.openBook: {
      const p = payload as OpenBookPayload;
      // 换书先销毁旧引擎，防状态串台
      detachGestures?.(); detachGestures = null;
      engine?.destroy(); engine = null;
      surface.innerHTML = '';
      try {
        const e = createEngine(p.kind);
        installGestures(e);
        engine = e;
        await e.open(p);
      } catch (err) {
        emit(DartEvent.onError, { message: `openBook failed: ${String(err)}` });
        emit(DartEvent.onNeedRefresh, { type: 'full' });
      }
      break;
    }
    case TsAction.applyTheme:
      engine?.applyTheme(payload as ThemePayload);
      break;
    case TsAction.scrollToPercent:
      engine?.goToPercent(payload.percent);
      break;
    case TsAction.scrollToOffset:
      engine?.goToOffset(payload.start);
      break;
    case TsAction.scrollToCfi:
      engine?.goToCfi(String(payload.cfi ?? ''));
      break;
    case TsAction.nextPage:
      engine?.next();
      break;
    case TsAction.prevPage:
      engine?.prev();
      break;
    case TsAction.addAnnotation:
      engine?.addAnnotation(payload);
      break;
    case TsAction.removeAnnotation:
      engine?.removeAnnotation(payload.id);
      break;
    case TsAction.exportAnnotations:
      emit(DartEvent.onAnnotationsExport, { list: engine?.exportAnnotations() ?? [] });
      break;
    default:
      emit(DartEvent.onError, { message: `unknown action: ${action}` });
  }
});

function installGestures(e: BookEngine): void {
  detachGestures?.();
  detachGestures = attachGestures(surface, {
    prev: () => e.prev(),
    next: () => e.next(),
    getContentRoot: () => e.contentRoot,
    resolveSelection: sel => e.resolveSelection(sel),
  });
}

installBridge();
