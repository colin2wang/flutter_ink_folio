import {
  BridgeMessage,
  DartEvent,
} from './types';

// 事件名常量对外再导出：gesture / loader / txt_engine 统一从 bridge 单点取用，
// 避免各处再从 types 二次 import（types 只描述协议，不负责分发）。
export { DartEvent };

declare global {
  interface Window {
    /** flutter_inappwebview 注入的原生桥（Android/iOS/web 实现均有） */
    flutter_inappwebview?: {
      callHandler: (name: string, ...args: unknown[]) => Promise<unknown>;
    };
    /** Dart 下行入口：JsBridge.evaluateJavascript 调用 */
    __reader?: { dispatch: (msg: BridgeMessage) => void };
  }
}

let handler: ((action: string, payload: unknown) => void) | null = null;
const upQueue: BridgeMessage[] = [];
let flutterBridgeReady = false;

/** TS → Dart 上行（带就绪前缓冲） */
export function emit(action: string, payload: unknown = {}): void {
  const msg: BridgeMessage = { action, payload };
  if (flutterBridgeReady && window.flutter_inappwebview) {
    window.flutter_inappwebview.callHandler(DartEvent.handlerName, msg);
  } else {
    upQueue.push(msg);
    // 兜底重试：桥晚注入也不丢事件
    setTimeout(flushUp, 50);
  }
}

function flushUp(): void {
  if (!window.flutter_inappwebview) return;
  flutterBridgeReady = true;
  while (upQueue.length) {
    const m = upQueue.shift()!;
    window.flutter_inappwebview.callHandler(DartEvent.handlerName, m);
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
  // flutter_inappwebview 注入时机不定：轮询握手
  const probe = () => {
    if (window.flutter_inappwebview) {
      flushUp();
      emit(DartEvent.onReady);
    } else {
      setTimeout(probe, 30);
    }
  };
  probe();
}
