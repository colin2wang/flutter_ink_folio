import { DartEvent, emit } from './bridge';

export interface GestureHooks {
  prev(): void;
  next(): void;
  /** 返回选区的 {start,end}（全局字符偏移），null 表示无法定位 */
  resolveSelection(sel: Selection): { start?: number; end?: number; cfiRange?: string } | null;
  getContentRoot(): HTMLElement | null;
}

/**
 * 手势层：左右点击翻页 / 中央呼出菜单 / 横滑翻页 / 长按选区上报。
 * 无任何触摸动画与滚动惯性。
 */
export function attachGestures(surface: HTMLElement, hooks: GestureHooks): () => void {
  let touchStartX = 0;
  let touchStartY = 0;
  let touchStartT = 0;
  let longPressTimer: number | undefined;
  let moved = false;

  const onClick = (ev: MouseEvent) => {
    const w = surface.clientWidth;
    const x = ev.clientX;
    if (x < w * 0.3) hooks.prev();
    else if (x > w * 0.7) hooks.next();
    else emit(DartEvent.onToggleChrome);
  };

  const onTouchStart = (ev: TouchEvent) => {
    const t = ev.touches[0];
    touchStartX = t.clientX;
    touchStartY = t.clientY;
    touchStartT = Date.now();
    moved = false;
    // 长按 480ms 由系统文本选择接管，这里不弹自定义菜单：
    // 选区确定后由 selection 上报流程发 onLongPress
    longPressTimer = window.setTimeout(() => reportSelection(), 480);
  };

  const onTouchMove = (ev: TouchEvent) => {
    const t = ev.touches[0];
    if (Math.abs(t.clientX - touchStartX) > 12 || Math.abs(t.clientY - touchStartY) > 12) {
      moved = true;
      if (longPressTimer) window.clearTimeout(longPressTimer);
    }
  };

  const onTouchEnd = (ev: TouchEvent) => {
    if (longPressTimer) window.clearTimeout(longPressTimer);
    const dt = Date.now() - touchStartT;
    if (moved) {
      // 轻扫翻页：横向位移 > 50px 且时长 < 600ms（纵向位移大时不算）
      const t = ev.changedTouches[0];
      const dx = t.clientX - touchStartX;
      const dy = t.clientY - touchStartY;
      if (dt < 600 && Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) {
        if (dx < 0) hooks.next();
        else hooks.prev();
        return;
      }
      reportSelection();
    }
  };

  const reportSelection = () => {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !hooks.getContentRoot()) return;
    const root = hooks.getContentRoot()!;
    if (!root.contains(sel.anchorNode)) return;
    const text = sel.toString().trim();
    if (!text) return;
    const loc = hooks.resolveSelection(sel);
    if (!loc) return;
    emit(DartEvent.onLongPress, {
      text,
      start: loc.start,
      end: loc.end,
      cfiRange: loc.cfiRange,
    });
  };

  const onKey = (ev: KeyboardEvent) => {
    // web 调试用：方向键翻页
    if (ev.key === 'ArrowRight' || ev.key === 'PageDown') hooks.next();
    else if (ev.key === 'ArrowLeft' || ev.key === 'PageUp') hooks.prev();
    else if (ev.key === 'Escape') emit(DartEvent.onToggleChrome);
  };

  const onSelectionDone = () => {
    // 鼠标选区（web 调试）与触摸选区收尾
    reportSelection();
  };

  surface.addEventListener('click', onClick);
  surface.addEventListener('touchstart', onTouchStart, { passive: true });
  surface.addEventListener('touchmove', onTouchMove, { passive: true });
  surface.addEventListener('touchend', onTouchEnd);
  surface.addEventListener('mouseup', onSelectionDone);
  window.addEventListener('keydown', onKey);

  return () => {
    surface.removeEventListener('click', onClick);
    surface.removeEventListener('touchstart', onTouchStart);
    surface.removeEventListener('touchmove', onTouchMove);
    surface.removeEventListener('touchend', onTouchEnd);
    surface.removeEventListener('mouseup', onSelectionDone);
    window.removeEventListener('keydown', onKey);
  };
}
