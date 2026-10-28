/**
 * 本地/远程资源读取。TXT 与 EPUB 引擎共用。
 *
 * **为什么不能直接用 fetch 读 file://**
 * Android WebView（Blink）的 Fetch 实现直接拒绝非 http(s) 的 scheme，
 * 控制台报 `Fetch API cannot load file:///... URL scheme "file" is not supported`，
 * 这跟 WebView 的 allowFileAccessFromFileURLs 无关——`fetch` 根本不实现 file。
 * 老牌的 XMLHttpRequest 则受 allowFileAccessFromFileURLs 控制，
 * 宿主把它设为 true 后就能读同源 file:// 文件，所以这里走 XHR。
 *
 * web（http/https）下仍用 fetch。
 */

/** 补全成 file:// URL；已经是带 scheme 的地址（http/blob/data）原样返回 */
export function toFileUrl(p: string): string {
  if (!p) return p;
  return /^[a-z][a-z0-9+.-]*:/i.test(p) ? p : `file://${p}`;
}

/**
 * base64 → ArrayBuffer。
 *
 * web 端没有沙盒路径可读（fetch 不支持 file:，也没有 file:// 目录），
 * EPUB 的字节只能由宿主（Dart）读下来、以 base64 内嵌进 openBook 下发。
 */
export function base64ToBuffer(b64: string): ArrayBuffer {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer as ArrayBuffer;
}

/** 读二进制（EPUB 等）。失败会 throw，由调用方上报 onError */
export function loadBinary(path: string): Promise<ArrayBuffer> {
  const url = toFileUrl(path);
  if (url.startsWith('file:')) return xhrBinary(url);
  return fetch(url).then(async res => {
    if (!res.ok) throw new Error(`HTTP ${res.status} ${url}`);
    return await res.arrayBuffer();
  });
}

/** 读纯文本（TXT 兜底路径）。按 UTF-8 解码，与 fetch().text() 行为一致 */
export async function loadText(path: string): Promise<string> {
  const url = toFileUrl(path);
  if (url.startsWith('file:')) {
    return new TextDecoder('utf-8').decode(await xhrBinary(url));
  }
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} ${url}`);
  return await res.text();
}

function xhrBinary(url: string): Promise<ArrayBuffer> {
  return new Promise<ArrayBuffer>((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.responseType = 'arraybuffer';
    xhr.onload = () => {
      // file:// 成功时 status 常常是 0（不是 200），失败也是 0，
      // 所以只能靠 response 是否存在来判断
      const buf = xhr.response as ArrayBuffer | null;
      if (buf && (xhr.status === 200 || xhr.status === 0)) {
        resolve(buf);
      } else {
        reject(new Error(`读取失败 status=${xhr.status} ${url}`));
      }
    };
    xhr.onerror = () => reject(new Error(`读取失败（XHR error）${url}`));
    xhr.ontimeout = () => reject(new Error(`读取超时 ${url}`));
    xhr.send();
  });
}
