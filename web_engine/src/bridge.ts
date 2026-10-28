import {
  BridgeMessage,
  DartEvent,
} from './types';

// 事件名常量对外再导出：gesture / loader / txt_engine 统一从 bridge 单点取用，
// 避免各处再从 types 二次 import（types 只描述协议，不负责分发）。
export { DartEvent };

/** 上行报文标识：宿主只处理 source === INK_SOURCE 的 message 事件 */
export const INK_SOURCE = 'ink-reader';

/** 下行报文标识：宿主用 postMessage 下发命令时带 __ink: 'down' */
export const INK_DOWN = 'down';

/**
 * 桥接协议版本：onReady 时上报。
 * 宿主（lib/bridge/engine_host_web.dart 的 _engineProtocol）不一致就说明
 * assets/web/main.js 是旧产物，直接提示重建，而不是白屏。
 *
 * **改了 Dart↔TS 的 payload 字段就要同步 +1**（与宿主常量一起改）：
 * 3 = openBook 支持 `dataBase64`（web 端 EPUB 内嵌字节）
 * 4 = applyTheme 支持 `margin` / `indent` / `paraSpacing`（页边距等排版参数）
 */
export const ENGINE_PROTOCOL = 4;

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

/**
 * Web(chrome/edge) 下行通道：宿主 → iframe。
 *
 * 引擎跑在同源 iframe 里（assets/web/index.html），宿主拿不到 window.__reader，
 * 也不用 eval；命令统一 postMessage(JSON 字符串) 进来，这里解析后交给 dispatch。
 * 非 iframe 场景（Android file:// 顶层页面）不走这条通道，继续用 evaluateJavascript。
 */
function listenHostCommands(): void {
  if (window.parent === window) return;
  window.addEventListener('message', (event: MessageEvent) => {
    const msg = parseHostMessage(event.data);
    if (!msg || msg.__ink !== INK_DOWN || typeof msg.action !== 'string') return;
    try {
      handler?.(msg.action, msg.payload);
    } catch (e) {
      emit(DartEvent.onError, { message: String(e) });
    }
  });
}

interface HostCommand {
  __ink?: string;
  action?: string;
  payload?: unknown;
}

function parseHostMessage(raw: unknown): HostCommand | null {
  if (typeof raw === 'string') {
    try {
      return JSON.parse(raw) as HostCommand;
    } catch {
      return null; // 非 JSON 报文（Flutter 自身/浏览器扩展）直接忽略
    }
  }
  return raw && typeof raw === 'object' ? (raw as HostCommand) : null;
}

/** Dart → TS 下行分发注册 */
export function onDispatch(fn: (action: string, payload: unknown) => void): void {
  handler = fn;
}

export function installBridge(): void {
  // 全局脚本报错先接住：引擎抛错/hover 失败的 Promise 默认只打控制台，
  // release APK 上完全看不到（宿主那边有日志缓冲，能复制出来）
  window.addEventListener('error', (e: ErrorEvent) => {
    emit(DartEvent.onError, {
      message: `js error: ${e.message} @${e.filename}:${e.lineno}`,
    });
  });
  window.addEventListener('unhandledrejection', (e: PromiseRejectionEvent) => {
    emit(DartEvent.onError, { message: `unhandled rejection: ${String(e.reason)}` });
  });

  window.__reader = {
    dispatch: (msg: BridgeMessage) => {
      try {
        handler?.(msg.action, msg.payload);
      } catch (e) {
        emit(DartEvent.onError, { message: String(e) });
      }
    },
  };
  listenHostCommands();

  // 分支一：iframe（web 宿主）。同源 postMessage 就是通道，立即就绪
  if (window.parent !== window) {
    flushUp();
    emit(DartEvent.onReady, { protocol: ENGINE_PROTOCOL });
    return;
  }

  // 分支二：顶层页面（Android/iOS WebView）。flutter_inappwebview 是原生
  // 异步注入的，注入前 emit 只会进 upQueue（parent === window 没有 postMessage
  // 兜底），onReady 一丢 Dart 侧的 openBook 就永远留在队列里 → 手机白屏。
  // 所以这里必须轮询等注入，约 9s 无果才放弃。
  let tries = 0;
  const probe = (): void => {
    if (window.flutter_inappwebview) {
      flushUp();
      emit(DartEvent.onReady, { protocol: ENGINE_PROTOCOL });
      return;
    }
    if (++tries <= 300) {
      setTimeout(probe, 30);
      return;
    }
    console.warn('[ink] flutter_inappwebview 未注入，上行通道不可用');
  };
  probe();
}
