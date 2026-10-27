/**
 * 纯文本 ↔ DOM 位置换算。
 *
 * TXT 与 EPUB 引擎共用同一套定位模型：全局字符偏移。
 * 所有遍历都按「文本节点行走」累计，因此高亮 span 的嵌套不影响后续计算
 * （splitText 只切分节点，字符总数与顺序不变）。
 */

/** 把（节点, 节点内偏移）换算成相对 root 的字符偏移 */
export function offsetOf(root: Node, node: Node, offset: number): number | null {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let total = 0;
  let n: Node | null;
  while ((n = walker.nextNode())) {
    if (n === node) return total + offset;
    total += (n.textContent ?? '').length;
  }
  return null;
}

/** 字符偏移 →（文本节点, 节点内偏移） */
export function locateTextNode(root: Node, target: number): { node: Text; offset: number } | null {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let acc = 0;
  let n = walker.nextNode() as Text | null;
  while (n) {
    const len = n.data.length;
    if (acc + len >= target) return { node: n, offset: target - acc };
    acc += len;
    n = walker.nextNode() as Text | null;
  }
  return null;
}

/**
 * 按字符区间 [s, e) 绘制高亮。
 * 跨越多个块级元素时逐段包裹（Range.surroundContents 在跨父节点时会抛错）。
 */
export function highlightRange(
  root: Node,
  s: number,
  e: number,
  className: string,
  annoId: string,
): void {
  if (e <= s) return;

  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const pieces: Array<{ node: Text; from: number; to: number }> = [];
  let acc = 0;
  let n = walker.nextNode() as Text | null;
  while (n) {
    const len = n.data.length;
    const from = Math.max(s - acc, 0);
    const to = Math.min(e - acc, len);
    if (from < to) pieces.push({ node: n, from, to });
    acc += len;
    n = walker.nextNode() as Text | null;
  }

  // 倒序处理：splitText 会改变当前节点，但不影响已收集的前序节点
  for (let i = pieces.length - 1; i >= 0; i--) {
    const { node, from, to } = pieces[i];
    let target = node;
    if (to < target.data.length) target.splitText(to);
    if (from > 0) target = target.splitText(from);

    const span = document.createElement('span');
    span.className = className;
    span.dataset.anno = annoId;
    target.parentNode?.insertBefore(span, target);
    span.appendChild(target);
  }
}

export function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function escapeAttr(s: string): string {
  return s.replace(/"/g, '&quot;');
}

/** 高亮色阶收敛到 1..5（与 renderer.ts 的 .ink-hl-N 对齐） */
export function clampColor(c: number): number {
  return Math.max(1, Math.min(5, Math.round(c) || 2));
}
