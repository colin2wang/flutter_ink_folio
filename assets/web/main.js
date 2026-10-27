/**
 * inkreader 免构建回退引擎（vanilla JS，无任何依赖）。
 *
 * 与 web_engine/src/txt_engine.ts 行为一致：CSS 多栏分页 + 字符偏移定位 +
 * 偏移高亮 + 章节正则目录。仅支持 TXT；EPUB 需用 web_engine 构建产物替换本目录。
 *
 * 协议与 web_engine 完全一致（统一 JSON 信封），Flutter 壳无需感知差异。
 */
(function () {
  'use strict';

  // ------------------------------------------------------------------ bridge
  var QUEUE = [];
  var bridgeReady = false;

  function emit(action, payload) {
    var msg = { action: action, payload: payload || {} };
    if (bridgeReady && window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('event', msg);
    } else {
      QUEUE.push(msg);
      setTimeout(flush, 50);
    }
  }

  function flush() {
    if (!window.flutter_inappwebview) return;
    bridgeReady = true;
    while (QUEUE.length) {
      window.flutter_inappwebview.callHandler('event', QUEUE.shift());
    }
  }

  // ------------------------------------------------------------------ theme
  function fgBg(mode) {
    if (mode === 'night') return ['#111111', '#C9C9C9'];
    if (mode === 'gray') return ['#ECECEC', '#1F1F1F'];
    return ['#FFFFFF', '#111111'];
  }

  function buildCss(t) {
    var pair = fgBg(t.mode);
    var bg = pair[0], fg = pair[1];
    var family;
    if (t.fontFamily === 'sans') {
      family = '"Noto Sans CJK SC","Source Han Sans SC",sans-serif';
    } else if (t.fontFamily && t.fontFamily.indexOf('custom:') === 0) {
      family = '"' + t.fontFamily.slice(7).replace(/"/g, '') + '","Noto Serif CJK SC",serif';
    } else {
      family = '"Noto Serif CJK SC","Source Han Serif SC",serif';
    }
    var face = '';
    if (t.fontPath) {
      var url = t.fontPath.indexOf('file:') === 0 ? t.fontPath : 'file://' + t.fontPath;
      face = '@font-face{font-family:"custom";src:url("' + url + '");font-display:swap;}';
    }
    return face +
      'html,body{background:' + bg + ' !important;transition:none !important;animation:none !important;}' +
      '.ink-book,.ink-book *{background:transparent !important;box-shadow:none !important;' +
      'text-shadow:none !important;filter:none !important;transition:none !important;animation:none !important;color:' + fg + ';}' +
      '.ink-book{font-family:' + family + ' !important;font-size:' + t.fontSize + 'px !important;' +
      'line-height:' + t.lineHeight + ' !important;text-align:justify;line-break:strict;' +
      'word-break:normal;overflow-wrap:anywhere;letter-spacing:0.02em;-webkit-hyphens:none;hyphens:none;}' +
      '.ink-hl{background:currentColor;opacity:0.28;border-radius:1px;}' +
      '.ink-hl-1{opacity:0.18;}.ink-hl-5{opacity:0.4;}';
  }

  var theme = { mode: 'paper', fontSize: 19, lineHeight: 1.7, fontFamily: 'serif', fontPath: null };
  var themeStyleEl = document.createElement('style');
  themeStyleEl.id = 'ink-theme-style';
  document.head.appendChild(themeStyleEl);

  function applyTheme(t) {
    if (t) theme = t;
    themeStyleEl.textContent = buildCss(theme);
    surface.style.background = fgBg(theme.mode)[0];
  }

  // ------------------------------------------------------------------ dom
  var surface = document.getElementById('page-container');
  var viewport = document.createElement('div');
  var content = document.createElement('div');
  viewport.className = 'ink-viewport';
  viewport.style.cssText = 'position:absolute;inset:0;overflow:hidden;';
  content.className = 'ink-book ink-txt';
  viewport.appendChild(content);
  surface.appendChild(viewport);

  // ------------------------------------------------------------------ state
  var text = '';
  var page = 0;
  var total = 1;
  var toc = [];
  var annos = {}; // id -> {start,end,color}

  // ------------------------------------------------------------------ toc
  var CHAPTER_RE = /^\s*(第[一二三四五六七八九十百千万零〇\d]+[章回卷节部篇]|楔子|序章|序言|尾声|后记|番外.{0,12}).{0,60}$/;

  function buildToc(t) {
    var list = [], off = 0;
    t.split('\n').forEach(function (line) {
      if (CHAPTER_RE.test(line.trim())) list.push({ title: line.trim().slice(0, 40), offset: off });
      off += line.length + 1;
    });
    return list;
  }

  function chapterAt(off) {
    var title = '';
    for (var i = 0; i < toc.length; i++) {
      if (toc[i].offset <= off) title = toc[i].title; else break;
    }
    return title;
  }

  // ------------------------------------------------------------------ render
  function escapeHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function buildHtml(t, annoList) {
    var sorted = annoList.filter(function (a) {
      return a.start != null && a.end != null && a.end > a.start;
    }).sort(function (a, b) { return a.start - b.start; });

    var marks = [];
    var cursor = -1;
    sorted.forEach(function (a) {
      if (a.start < cursor) return;
      marks.push({ at: a.start, open: true, id: a.id, color: a.color });
      marks.push({ at: a.end, open: false, id: a.id, color: a.color });
      cursor = a.end;
    });
    marks.sort(function (x, y) { return x.at - y.at || (x.open ? -1 : 1); });

    var html = '', pos = 0;
    marks.forEach(function (m) {
      html += escapeHtml(t.slice(pos, m.at));
      var c = Math.max(1, Math.min(5, Math.round(m.color) || 2));
      html += m.open
        ? '<span class="ink-hl ink-hl-' + c + '" data-anno="' + m.id + '">'
        : '</span>';
      pos = m.at;
    });
    html += escapeHtml(t.slice(pos));
    return html.split(/\n{2,}/).map(function (seg) {
      return '<p>' + seg.replace(/\n/g, '<br>') + '</p>';
    }).join('');
  }

  function render() {
    var list = Object.keys(annos).map(function (k) { return annos[k]; });
    content.innerHTML = buildHtml(text, list);
    relayout(false);
  }

  function relayout(keepRatio) {
    var vw = viewport.clientWidth, vh = viewport.clientHeight;
    if (!vw || !vh) return;
    var gap = Math.round(vw * 0.06);
    var s = content.style;
    s.height = vh + 'px';
    s.columnWidth = vw + 'px';
    s.columnGap = gap + 'px';
    s.columnFill = 'auto';
    s.position = 'relative';
    s.transition = 'none';
    s.willChange = 'transform';
    total = Math.max(1, Math.round(content.scrollWidth / (vw + gap)));
    if (keepRatio) page = Math.min(total - 1, page);
    goToPage(page, false);
  }

  function goToPage(p, notify) {
    page = Math.max(0, Math.min(total - 1, p));
    var vw = viewport.clientWidth;
    var gap = Math.round(vw * 0.06);
    content.style.transform = 'translateX(' + (-page * (vw + gap)) + 'px)';
    if (notify !== false) notifyChanged();
  }

  function notifyChanged() {
    var percent = total <= 1 ? 0 : page / (total - 1);
    var start = Math.floor(text.length * percent);
    emit('onPageChanged', {
      percent: percent, start: start,
      chapter: chapterAt(start), index: page, total: total,
    });
    emit('onNeedRefresh', { type: 'full' }); // 渲染完成 → 请求全刷（时序不可反）
  }

  // ------------------------------------------------------------------ offsets
  function offsetOf(node, offset) {
    var walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, null);
    var sum = 0, n;
    while ((n = walker.nextNode())) {
      if (n === node) return sum + offset;
      sum += (n.textContent || '').length;
    }
    return null;
  }

  function resolveSelection() {
    var sel = window.getSelection();
    if (!sel || sel.isCollapsed || sel.rangeCount === 0) return null;
    try {
      var r = sel.getRangeAt(0);
      if (!content.contains(r.startContainer)) return null;
      var s = offsetOf(r.startContainer, r.startOffset);
      var e = offsetOf(r.endContainer, r.endOffset);
      if (s == null || e == null) return null;
      return { text: sel.toString().trim(), start: Math.min(s, e), end: Math.max(s, e) };
    } catch (err) { return null; }
  }

  // ------------------------------------------------------------------ gestures
  var touchStartX = 0, touchStartY = 0, touchStartT = 0, moved = false, lpTimer = null;

  surface.addEventListener('click', function (ev) {
    var w = surface.clientWidth;
    if (ev.clientX < w * 0.3) api.prev();
    else if (ev.clientX > w * 0.7) api.next();
    else emit('onToggleChrome');
  });

  surface.addEventListener('touchstart', function (ev) {
    var t = ev.touches[0];
    touchStartX = t.clientX; touchStartY = t.clientY; touchStartT = Date.now();
    moved = false;
    lpTimer = setTimeout(function () {
      var sel = resolveSelection();
      if (sel) emit('onLongPress', sel);
    }, 480);
  }, { passive: true });

  surface.addEventListener('touchmove', function (ev) {
    var t = ev.touches[0];
    if (Math.abs(t.clientX - touchStartX) > 12 || Math.abs(t.clientY - touchStartY) > 12) {
      moved = true;
      if (lpTimer) { clearTimeout(lpTimer); lpTimer = null; }
    }
  }, { passive: true });

  surface.addEventListener('touchend', function () {
    if (lpTimer) { clearTimeout(lpTimer); lpTimer = null; }
    var dt = Date.now() - touchStartT;
    if (moved && dt < 600) {
      var dx = (lastTouchX - touchStartX);
      if (dx < -40) api.next(); else if (dx > 40) api.prev();
    } else if (!moved) {
      var sel = resolveSelection();
      if (sel) emit('onLongPress', sel);
    }
  }, { passive: true });

  var lastTouchX = 0;
  surface.addEventListener('touchmove', function (ev) {
    lastTouchX = ev.touches[0].clientX;
  }, { passive: true });

  surface.addEventListener('mouseup', function () {
    var sel = resolveSelection();
    if (sel) emit('onLongPress', sel);
  });

  window.addEventListener('keydown', function (ev) {
    if (ev.key === 'ArrowRight' || ev.key === 'PageDown') api.next();
    else if (ev.key === 'ArrowLeft' || ev.key === 'PageUp') api.prev();
    else if (ev.key === 'Escape') emit('onToggleChrome');
  });

  var resizeTimer = null;
  window.addEventListener('resize', function () {
    if (resizeTimer) clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () { relayout(true); notifyChanged(); }, 80);
  });

  // ------------------------------------------------------------------ api
  function loadFile(path) {
    return fetch(path.indexOf('file:') === 0 ? path : 'file://' + path).then(function (r) {
      return r.text();
    });
  }

  var api = {
    next: function () { if (page < total - 1) goToPage(page + 1); },
    prev: function () { if (page > 0) goToPage(page - 1); },
    goToPercent: function (p) {
      if (total <= 1) return;
      goToPage(Math.round(p * (total - 1)));
    },
    goToOffset: function (start) {
      var ratio = text.length ? start / text.length : 0;
      api.goToPercent(ratio);
    },
    addAnnotation: function (a) {
      if (a.start == null || a.end == null) return; // 回退引擎只支持偏移高亮
      annos[a.id] = { id: a.id, start: a.start, end: a.end, color: a.color };
      render();
      goToPage(page, false);
      emit('onNeedRefresh', { type: 'partial' });
    },
    removeAnnotation: function (id) {
      delete annos[id];
      render();
      goToPage(page, false);
      emit('onNeedRefresh', { type: 'partial' });
    },
    exportAnnotations: function () {
      return Object.keys(annos).map(function (k) { return annos[k]; });
    },
    openBook: function (p) {
      if (p.kind === 'epub') {
        emit('onError', {
          message: '当前为免构建回退引擎（仅 TXT）。EPUB 请执行 web_engine 构建：' +
            'cd web_engine && pnpm install && pnpm build，产物拷入 assets/web 后重装 App。',
        });
        emit('onNeedRefresh', { type: 'full' });
        return;
      }
      var proceed = function (content2) {
        text = content2;
        page = 0;
        toc = buildToc(text);
        annos = {};
        (p.highlights || []).forEach(function (h) {
          if (h.start != null) annos[h.id] = h;
        });
        render();
        applyTheme();
        emit('onMeta', { title: p.bookId, author: '' });
        emit('onToc', { items: toc });
        if (p.start && p.start > 0) api.goToOffset(p.start);
        else if (p.cfi) api.goToPercent(Number(p.cfi) || 0);
        notifyChanged();
      };
      if (p.text != null) proceed(p.text);
      else loadFile(p.filePath).then(proceed).catch(function (e) {
        emit('onError', { message: 'read txt failed: ' + e });
      });
    },
  };

  // ------------------------------------------------------------------ dispatch
  var handlers = {
    openBook: api.openBook,
    applyTheme: function (t) { applyTheme(t); relayout(true); notifyChanged(); },
    scrollToPercent: function (p) { api.goToPercent(p.percent); },
    scrollToOffset: function (p) { api.goToOffset(p.start); },
    nextPage: function () { api.next(); },
    prevPage: function () { api.prev(); },
    addAnnotation: api.addAnnotation,
    removeAnnotation: function (p) { api.removeAnnotation(p.id); },
    exportAnnotations: function () { emit('onAnnotationsExport', { list: api.exportAnnotations() }); },
  };

  window.__reader = {
    dispatch: function (msg) {
      try {
        var h = handlers[msg.action];
        if (h) h(msg.payload || {});
        else emit('onError', { message: 'unknown action: ' + msg.action });
      } catch (e) {
        emit('onError', { message: String(e) });
      }
    },
  };

  function probe() {
    if (window.flutter_inappwebview) { flush(); emit('onReady'); }
    else setTimeout(probe, 30);
  }
  probe();
})();
