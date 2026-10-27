import {
  BridgeMessage,
  DartEvent,
} from './types';

// 事件名常量对外再导出：gesture / loader / txt_engine 统一从 bridge 单点取用，
// 避免各处再从 types 二次 import（types 只描述协议，不负责分发）。
export { DartEvent };

/** postMessage 上行报文的标识（web 平台专用通道） */
export const INK_SOURCE = 'ink-reader';

declare global {
  interface Window {
    /** flutter_inappwebview 注入的原生桥（Android/iOS 实现有；web 实现的 iframe 里没有） */
    flutter_inappwebview?: {
      callHandler: (name: string, ...args: unknown[]) => Promise<unknown>;
    };
    /** Dart 下行入口：JsBridge.evaluateJavascript 调用 */
    __reader?: { dispatch: (msg: BridgeMessage) => void };
  }
}

let handler: ((action: string, payload: unknown) => void) | null = null;
const upQueue: BridgeMessage[] = [];

/**
 * 上行通道是否可用。
 *
 * - Android/iOS：window.flutter_inappwebview.callHandler（原生 JS handler）。
 * - Web(chrome/edge)：flutter_inappwebview_web 未实现 addJavaScriptHandler，
 *   iframe 内也没有 callHandler，只能通过 parent.postMessage 上行
 *   （about:blank iframe 与宿主同源，postMessage 一定可达）。
 */
function hasUpstream(): boolean {
  if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function') {
    return true;
  }
  return window.parent !== window;
}

function post(msg: BridgeMessage): void {
  if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function') {
    window.flutter_inappwebview.callHandler(DartEvent.handlerName, msg);
    return;
  }
  // 宿主侧只认字符串：Dart 端 jsonDecode 后按 source 过滤
  window.parent.postMessage(
    JSON.stringify({ source: INK_SOURCE, action: msg.action, payload: msg.payload }),
    '*',
  );
}

/** TS → Dart 上行（带就绪前缓冲） */
export function emit(action: string, payload: unknown = {}): void {
  const msg: BridgeMessage = { action, payload };
  if (hasUpstream()) {
    post(msg);
    return;
  }
  upQueue.push(msg);
  // 兜底重试：桥晚注入也不丢事件
  setTimeout(flushUp, 50);
}

function flushUp(): void {
  if (!hasUpstream()) return;
  while (upQueue.length) {
    post(upQueue.shift()!);
  }
}

/** Dart → TS 下行分发注册 */
export function onDispatch(fn: (action: string, payload: unknown) => void): void {
  handler = fn;
}

export function installBridge(): void {
  window.__reader = {
    dispatch: (msg: BridgeMessage) => {
      try {
        handler?.(msg.action, msg.payload);
      } catch (e) {
        emit(DartEvent.onError, { message: String(e) });
      }
    },
  };
  // 不再轮询等 flutter_inappwebview：web 平台根本没有它，
  // 等下去 onReady 永远发不出（Dart 侧队列不 flush → 阅读页白屏）。
  flushUp();
  emit(DartEvent.onReady);
}
