import JSZip from 'jszip';

/**
 * EPUB 解析层：zip（JSZip）+ OPF/NCX/NAV（浏览器原生 DOMParser）。
 *
 * 只做「解析 + 资源重写」，排版与翻页交给 Pager，与 TXT 引擎共用一套。
 * 不做 CFI：定位统一使用 (spineIndex, 字符偏移)，与 TXT 引擎语义一致，
 * 因此 Flutter 侧与数据库无需任何改动。
 */

export interface EpubTocEntry {
  title: string;
  /** spine 索引；-1 表示无法定位（外链或排版不规范的目录项） */
  spineIndex: number;
  /** 章节内锚点（#fragment），无锚点时为空 */
  anchor: string;
  children: EpubTocEntry[];
}

export interface EpubBook {
  readonly title: string;
  readonly author: string;
  /** spine 章节数 */
  readonly chapterCount: number;
  /** 每章纯文本长度，用于全局进度换算 */
  readonly chapterLengths: readonly number[];
  /** 目录树 */
  readonly toc: readonly EpubTocEntry[];
  /**
   * 构建某一章可直接注入 DOM 的 HTML。
   * 资源已转为 blob: URL，内部链接已改写成 data-epub-href，元素 id 已加章前缀。
   */
  renderChapter(index: number): Promise<string>;
  destroy(): void;
}

const CONTAINER_PATH = 'META-INF/container.xml';
const MAX_INLINE_CSS_BYTES = 200 * 1024;

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------

export async function openEpub(data: ArrayBuffer | Blob): Promise<EpubBook> {
  const zip = await JSZip.loadAsync(data);
  const opfPath = await findOpfPath(zip);
  if (!opfPath) throw new Error('EPUB 损坏：找不到 OPF 文件');

  const opf = await parseOpf(zip, opfPath);
  if (!opf.spine.length) throw new Error('EPUB 损坏：spine 为空');

  // 规范路径 → spine 索引（目录跳转与内部链接都要用）
  const spineIndexByPath = new Map<string, number>();
  opf.spine.forEach((href, i) => {
    if (!spineIndexByPath.has(href)) spineIndexByPath.set(href, i);
  });

  // 章节文本长度：解析一次即可，避免为了算进度把全书都渲染一遍
  const chapterLengths: number[] = [];
  const cssCache = new Map<string, string>();
  const blobUrls = new Map<string, string>();

  const assetUrl = async (path: string): Promise<string | null> => {
    const hit = blobUrls.get(path);
    if (hit) return hit;
    const entry = zip.file(path);
    if (!entry) return null;
    const bytes = await entry.async('uint8array');
    const url = URL.createObjectURL(new Blob([toArrayBuffer(bytes)], { type: mimeOf(path) }));
    blobUrls.set(path, url);
    return url;
  };

  const cssText = async (path: string): Promise<string> => {
    const hit = cssCache.get(path);
    if (hit != null) return hit;
    const entry = zip.file(path);
    if (!entry) return '';
    const text = decodeText(await entry.async('uint8array'));
    const limited = text.length > MAX_INLINE_CSS_BYTES ? '' : text;
    cssCache.set(path, limited);
    return limited;
  };

  const renderChapter = async (index: number): Promise<string> => {
    if (index < 0 || index >= opf.spine.length) return '';
    const href = opf.spine[index];
    const raw = await readBytes(zip, href);
    if (!raw) return '';
    const doc = parseChapter(raw);
    if (!doc) return '';

    const base = dirOf(href);
    await rewriteChapter(doc, {
      spineIndex: index,
      resolvePath: (rel: string) => resolvePath(base, rel),
      spineIndexByPath,
      assetUrl,
      cssText,
    });

    const body = doc.body ?? doc.documentElement;
    return body ? body.innerHTML : '';
  };

  // 预扫描各章纯文本长度：全局进度换算需要全书长度，
  // 不能等到渲染某一章才知道它有多长（否则分母为 0，进度永远是 0）。
  // 这里只解析不重写资源，耗时远低于正式渲染。
  for (let i = 0; i < opf.spine.length; i++) {
    const raw = await readBytes(zip, opf.spine[i]);
    const doc = raw ? parseChapter(raw) : null;
    chapterLengths[i] = doc ? textLengthOf(doc) : 0;
  }

  const toc = await buildToc(zip, opf, spineIndexByPath);

  return {
    title: opf.title,
    author: opf.author,
    chapterCount: opf.spine.length,
    chapterLengths,
    toc,
    renderChapter,
    destroy() {
      for (const url of blobUrls.values()) URL.revokeObjectURL(url);
      blobUrls.clear();
      cssCache.clear();
    },
  };
}

// ---------------------------------------------------------------------------
// OPF / 目录
// ---------------------------------------------------------------------------

interface ManifestItem {
  href: string;
  mediaType: string;
  properties: string;
}

interface OpfData {
  title: string;
  author: string;
  /** 按 spine 顺序的规范路径 */
  spine: string[];
  manifest: Map<string, ManifestItem>;
  tocId: string | null;
}

async function findOpfPath(zip: JSZip): Promise<string> {
  const container = await readBytes(zip, CONTAINER_PATH);
  if (container) {
    const doc = parseXml(decodeText(container), 'application/xml');
    const full = doc?.querySelector('rootfile')?.getAttribute('full-path');
    if (full && zip.file(normalize(full))) return normalize(full);
  }
  // 容器文件缺失或路径对不上时兜底扫描（部分自制 epub 不规范）
  return Object.keys(zip.files).find(n => n.toLowerCase().endsWith('.opf')) ?? '';
}

async function parseOpf(zip: JSZip, opfPath: string): Promise<OpfData> {
  const bytes = await readBytes(zip, opfPath);
  const doc = bytes ? parseXml(decodeText(bytes), 'application/xml') : null;
  const base = dirOf(opfPath);

  const manifest = new Map<string, ManifestItem>();
  for (const el of all(doc, 'manifest > item')) {
    const id = el.getAttribute('id');
    const href = el.getAttribute('href');
    if (!id || !href) continue;
    manifest.set(id, {
      href: resolvePath(base, href),
      mediaType: el.getAttribute('media-type') ?? '',
      properties: el.getAttribute('properties') ?? '',
    });
  }

  const spine: string[] = [];
  for (const el of all(doc, 'spine > itemref')) {
    const idref = el.getAttribute('idref');
    if (!idref) continue;
    const item = manifest.get(idref);
    // linear="no" 的项（多为封面/附录）仍然保留，否则部分书会缺章
    if (item) spine.push(item.href);
  }

  const spineEl = doc?.querySelector('spine') ?? null;

  return {
    title: firstTextByLocalName(doc, 'title'),
    author: firstTextByLocalName(doc, 'creator'),
    spine,
    manifest,
    tocId: spineEl?.getAttribute('toc') ?? null,
  };
}

async function buildToc(
  zip: JSZip,
  opf: OpfData,
  spineIndexByPath: Map<string, number>,
): Promise<EpubTocEntry[]> {
  // EPUB3：manifest 中 properties 含 nav 的文档
  const navItem = [...opf.manifest.values()]
    .find(i => i.properties.split(/\s+/).includes('nav'));
  if (navItem) {
    const bytes = await readBytes(zip, navItem.href);
    const doc = bytes ? parseChapter(bytes) : null;
    if (doc) {
      const toc = parseNav(doc, dirOf(navItem.href), spineIndexByPath);
      if (toc.length) return toc;
    }
  }

  // EPUB2：spine 的 toc 属性指向 NCX
  const ncxItem = opf.tocId ? opf.manifest.get(opf.tocId) : undefined;
  if (ncxItem) {
    const bytes = await readBytes(zip, ncxItem.href);
    const doc = bytes ? parseXml(decodeText(bytes), 'application/xml') : null;
    if (doc) {
      const toc = parseNcx(doc, dirOf(ncxItem.href), spineIndexByPath);
      if (toc.length) return toc;
    }
  }

  // 兜底：没有目录时按 spine 生成一份「第 N 章」，保证目录功能可用
  return opf.spine.map((_, i) => ({
    title: `第 ${i + 1} 节`,
    spineIndex: i,
    anchor: '',
    children: [],
  }));
}

function parseNav(
  doc: Document,
  base: string,
  spineIndexByPath: Map<string, number>,
): EpubTocEntry[] {
  const navs = all(doc, 'nav');
  const nav = navs.find(n => {
    const type = n.getAttribute('epub:type')
      ?? n.getAttributeNS('http://www.idpf.org/2007/ops', 'type');
    return type === 'toc';
  }) ?? navs[0];
  if (!nav) return [];

  const walk = (ol: Element): EpubTocEntry[] => {
    const out: EpubTocEntry[] = [];
    for (const li of Array.from(ol.children)) {
      if (local(li) !== 'li') continue;
      const a = li.querySelector('a');
      const href = a?.getAttribute('href') ?? '';
      const [path, anchor] = splitHref(href);
      const entry: EpubTocEntry = {
        title: collapse((a ?? li).textContent ?? ''),
        spineIndex: spineIndexByPath.get(resolvePath(base, path)) ?? -1,
        anchor,
        children: [],
      };
      const sub = li.querySelector('ol');
      if (sub) entry.children = walk(sub);
      out.push(entry);
    }
    return out;
  };

  const root = nav.querySelector('ol');
  return root ? walk(root) : [];
}

function parseNcx(
  doc: Document,
  base: string,
  spineIndexByPath: Map<string, number>,
): EpubTocEntry[] {
  const walk = (parent: Element): EpubTocEntry[] => {
    const out: EpubTocEntry[] = [];
    for (const np of Array.from(parent.children)) {
      if (local(np) !== 'navpoint') continue;
      const label = np.querySelector('navLabel') ?? null;
      const src = np.querySelector('content')?.getAttribute('src') ?? '';
      const [path, anchor] = splitHref(src);
      out.push({
        title: collapse(label?.textContent ?? ''),
        spineIndex: spineIndexByPath.get(resolvePath(base, path)) ?? -1,
        anchor,
        children: walk(np),
      });
    }
    return out;
  };

  const map = doc.querySelector('navMap');
  return map ? walk(map) : [];
}

// ---------------------------------------------------------------------------
// 章节清洗与资源重写
// ---------------------------------------------------------------------------

interface RewriteContext {
  spineIndex: number;
  resolvePath(rel: string): string;
  spineIndexByPath: Map<string, number>;
  assetUrl(path: string): Promise<string | null>;
  cssText(path: string): Promise<string>;
}

async function rewriteChapter(doc: Document, ctx: RewriteContext): Promise<void> {
  const prefix = `ink-c${ctx.spineIndex}-`;

  // 1) 样式归位：章节自带的 <style> + 外链 CSS 内联。
  //    引擎只取 body.innerHTML 注入页面，样式留在 head 里会被丢弃，故统一搬进 body。
  const body = doc.body ?? doc.documentElement;
  const frag = doc.createDocumentFragment();
  for (const style of all(doc, 'head > style')) frag.appendChild(style);

  const css: string[] = [];
  for (const link of all(doc, 'link[rel~="stylesheet"], link[rel="stylesheet"]')) {
    const href = link.getAttribute('href');
    if (!href) continue;
    const text = await ctx.cssText(ctx.resolvePath(href));
    if (text) css.push(text);
    link.remove();
  }
  if (css.length) {
    const style = doc.createElement('style');
    style.textContent = css.join('\n');
    frag.appendChild(style);
  }
  if (frag.firstChild) body.insertBefore(frag, body.firstChild);

  // 2) 图片资源 → blob: URL（img / svg image）
  const images = [...all(doc, 'img'), ...all(doc, 'image')];
  for (const el of images) {
    const attr = el.hasAttribute('xlink:href') ? 'xlink:href' : 'href';
    const raw = el.getAttribute('src') ?? el.getAttribute(attr);
    if (!raw || isExternal(raw)) continue;
    const url = await ctx.assetUrl(ctx.resolvePath(raw));
    if (!url) continue;
    if (el.hasAttribute('src')) el.setAttribute('src', url);
    else el.setAttribute(attr, url);
    // 图片是异步解码的，加载完成后页数会变，由引擎统一重排
    el.setAttribute('data-ink-asset', '1');
  }

  // 3) 内部链接 → data-epub-href（引擎做事件委托跳转）；外链直接禁用
  for (const a of all(doc, 'a[href]')) {
    const href = a.getAttribute('href') ?? '';
    if (isExternal(href)) {
      a.setAttribute('href', '#');
      a.setAttribute('data-epub-external', '1');
      continue;
    }
    const [path, anchor] = splitHref(href);
    const target = ctx.spineIndexByPath.get(ctx.resolvePath(path));
    if (target == null) {
      a.setAttribute('href', '#');
      continue;
    }
    a.setAttribute('href', '#');
    a.setAttribute('data-epub-href', `${target}#${anchor}`);
  }

  // 4) id / 锚点加章前缀，避免与外壳及其他章节冲突
  for (const el of all(doc, '[id]')) {
    const id = el.getAttribute('id');
    if (id) el.setAttribute('id', prefix + id);
  }
  for (const a of all(doc, 'a[href^="#"]')) {
    const href = a.getAttribute('href') ?? '';
    if (href.length > 1) a.setAttribute('href', `#${prefix}${href.slice(1)}`);
  }
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

async function readBytes(zip: JSZip, path: string): Promise<Uint8Array | null> {
  const entry = zip.file(path);
  if (!entry) return null;
  try {
    return await entry.async('uint8array');
  } catch {
    return null;
  }
}

/** XHTML 优先按 XML 解析；不规范的文档回退 HTML 解析器（容错更好） */
function parseChapter(bytes: Uint8Array): Document | null {
  const text = decodeText(bytes);
  return parseXml(text, 'application/xhtml+xml') ?? parseXml(text, 'text/html');
}

function parseXml(text: string, mime: DOMParserSupportedType): Document | null {
  const doc = new DOMParser().parseFromString(text, mime);
  if (doc.querySelector('parsererror')) return null;
  return doc;
}

/**
 * 编码探测：EPUB 允许声明任意编码，JSZip 的 async('string') 只会按 UTF-8 解，
 * 中文自制书里 GBK 很常见，这里按 BOM → XML 声明 → meta charset 依次判断。
 */
function decodeText(bytes: Uint8Array): string {
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    return new TextDecoder('utf-8').decode(bytes.subarray(3));
  }
  if (bytes[0] === 0xff && bytes[1] === 0xfe) return new TextDecoder('utf-16le').decode(bytes);
  if (bytes[0] === 0xfe && bytes[1] === 0xff) return new TextDecoder('utf-16be').decode(bytes);

  const head = new TextDecoder('utf-8').decode(bytes.subarray(0, 2048));
  const enc =
    /<\?xml[^>]*encoding\s*=\s*["']([\w-]+)["']/i.exec(head)?.[1]
    ?? /<meta[^>]*charset\s*=\s*["']?([\w-]+)/i.exec(head)?.[1]
    ?? 'utf-8';
  try {
    return new TextDecoder(enc.toLowerCase()).decode(bytes);
  } catch {
    return new TextDecoder('utf-8').decode(bytes);
  }
}

function textLengthOf(doc: Document): number {
  const body = doc.body ?? doc.documentElement;
  return collapse(body?.textContent ?? '').length;
}

function dirOf(p: string): string {
  const i = p.lastIndexOf('/');
  return i < 0 ? '' : p.slice(0, i + 1);
}

/**
 * 相对 href → zip 内规范路径。
 * href 常被 URL 编码（空格 %20、中文 %E4%…），zip 内文件名是原始字符，故先解码。
 */
function resolvePath(base: string, rel: string): string {
  const [rawPath] = splitHref(rel);
  if (!rawPath || isExternal(rawPath)) return '';
  let decoded = rawPath;
  try {
    decoded = decodeURIComponent(rawPath);
  } catch { /* 非法百分号转义：原样使用 */ }
  const combined = decoded.startsWith('/') ? decoded.slice(1) : base + decoded;
  return normalize(combined);
}

function normalize(p: string): string {
  const out: string[] = [];
  for (const seg of p.split('/')) {
    if (!seg || seg === '.') continue;
    if (seg === '..') out.pop();
    else out.push(seg);
  }
  return out.join('/');
}

function splitHref(href: string): [string, string] {
  const clean = (href ?? '').trim().split('?')[0];
  const i = clean.indexOf('#');
  return i < 0 ? [clean, ''] : [clean.slice(0, i), clean.slice(i + 1)];
}

function isExternal(href: string): boolean {
  return /^[a-z][a-z0-9+.-]*:/i.test(href.trim()) && !href.trim().startsWith('blob:');
}

function collapse(s: string): string {
  return s.replace(/\s+/g, ' ').trim();
}

function local(el: Element): string {
  return (el.localName ?? el.nodeName).toLowerCase();
}

function all(root: ParentNode | null, selector: string): Element[] {
  return root ? Array.from(root.querySelectorAll(selector)) : [];
}

function firstTextByLocalName(doc: Document | null, name: string): string {
  for (const el of all(doc, '*')) {
    if (local(el) === name) {
      const t = collapse(el.textContent ?? '');
      if (t) return t;
    }
  }
  return '';
}

/**
 * JSZip 的 async('uint8array') 返回 Uint8Array<ArrayBufferLike>，
 * 而 BlobPart 要求 ArrayBuffer-backed 视图（TS 5.7 起 Uint8Array 带 buffer 泛型，
 * SharedArrayBuffer 不再兼容）。拷贝一次即可，顺带规避 byteOffset 非 0 的情况。
 */
function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

function mimeOf(path: string): string {
  const ext = path.toLowerCase().split('.').pop() ?? '';
  switch (ext) {
    case 'jpg': case 'jpeg': return 'image/jpeg';
    case 'png': return 'image/png';
    case 'gif': return 'image/gif';
    case 'webp': return 'image/webp';
    case 'svg': return 'image/svg+xml';
    case 'css': return 'text/css';
    case 'otf': return 'font/otf';
    case 'ttf': return 'font/ttf';
    case 'woff': return 'font/woff';
    case 'woff2': return 'font/woff2';
    default: return 'application/octet-stream';
  }
}
