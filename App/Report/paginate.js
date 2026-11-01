// The app's own page engine (no print engine involved). The report HTML is a plain flow of blocks; this script pours
// it into real A4 pages — each a 595.28 × 841.89 box (1 CSS px = 1 pt) with its paper, its margins and its
// «صفحه i از n» pill — and the app then turns every page box into one PDF page. What you see is exactly what prints:
// a block never straddles a page, nothing is scaled, the table header is only on the first page, and every page is
// filled down to the same distance above its page-number pill.
window.paginate = function () {
  const PW = 595.28, PH = 841.89;
  const TOP = 26, SIDE = 24;
  const PILL_H = 22, PILL_BOTTOM = 12;
  const GAP_ABOVE_PILL = TOP - 8;                       // last row → pill ≈ the top margin
  const MAXH = PH - TOP - (PILL_BOTTOM + PILL_H + GAP_ABOVE_PILL);

  const body = document.body;
  // the flow: top-level blocks; a breakdown section is opened into its parts
  const flow = [];
  for (const el of Array.from(body.children)) {
    if (el.classList.contains('bd-sec')) {
      for (const c of Array.from(el.children)) flow.push(c);
    } else {
      flow.push(el);
    }
  }
  flow.forEach(el => el.remove());
  body.innerHTML = '';
  body.classList.add('paged');

  const pages = [];
  let content = null;
  function newPage() {
    const pg = document.createElement('div');
    pg.className = 'pg';
    const c = document.createElement('div');
    c.className = 'pg-content';
    c.style.top = TOP + 'px';
    c.style.left = SIDE + 'px';
    c.style.right = SIDE + 'px';
    pg.appendChild(c);
    body.appendChild(pg);
    pages.push(pg);
    content = c;
  }
  // used height of the current page = bottom of its last block (with that block's bottom margin)
  function used() {
    const last = content.lastElementChild;
    if (!last) return 0;
    const cs = getComputedStyle(last);
    return last.getBoundingClientRect().bottom - content.getBoundingClientRect().top + parseFloat(cs.marginBottom || 0);
  }
  const fits = () => used() <= MAXH + 0.01;

  newPage();
  for (let i = 0; i < flow.length; i++) {
    const el = flow[i];
    if (el.classList.contains('bd-flow')) { pourColumns(el); continue; }
    content.appendChild(el);
    if (fits()) continue;
    // does not fit: move it (and a lonely header / section title right above it) to a fresh page
    const carry = [el];
    const prev = el.previousElementSibling;
    if (prev && (prev.classList.contains('head') || prev.classList.contains('bd-title')) && prev !== content.firstElementChild) {
      carry.unshift(prev);
    }
    if (content.children.length > carry.length) {
      newPage();
      carry.forEach(c => content.appendChild(c));
    }
  }

  // ranked breakdown rows: 1–3 columns, numbered top-to-bottom then the next column, page by page
  function pourColumns(flowEl) {
    const cells = Array.from(flowEl.children);
    const n = cells.length;
    const cols = n <= 6 ? 1 : n <= 14 ? 2 : 3;
    const gap = 5, rowGap = 4;
    const W = PW - SIDE * 2;
    const cw = (W - gap * (cols - 1)) / cols;
    cells.forEach(c => c.classList.add('w' + cols));
    const probe = document.createElement('div');
    probe.style.cssText = 'position:absolute;visibility:hidden;left:0;top:0;width:' + cw + 'px';
    document.body.appendChild(probe);
    const hs = cells.map(c => { probe.appendChild(c); return c.getBoundingClientRect().height; });
    probe.remove();
    const colH = (a, b) => { let s = 0; for (let k = a; k < b; k++) s += hs[k] + (k > a ? rowGap : 0); return s; };
    let i = 0;
    while (i < n) {
      let avail = MAXH - used() - 6;
      if (avail < Math.min(...hs.slice(i)) && content.children.length) { newPage(); avail = MAXH; }
      const R = n - i, k = Math.ceil(R / cols);
      let ranges = [], ok = true;
      for (let c = 0; c < cols; c++) {
        const a = i + c * k, b = Math.min(i + (c + 1) * k, n);
        if (a >= b) break;
        if (colH(a, b) > avail) { ok = false; break; }
        ranges.push([a, b]);
      }
      if (!ok) {
        ranges = [];
        let p = i;
        for (let c = 0; c < cols && p < n; c++) {
          let q = p;
          while (q < n && colH(p, q + 1) <= avail) q++;
          if (q === p) q = p + 1;
          ranges.push([p, q]);
          p = q;
        }
      }
      const set = document.createElement('div');
      set.className = 'bd-colset';
      for (const [a, b] of ranges) {
        const col = document.createElement('div');
        col.className = 'bd-col';
        col.style.width = cw + 'px';
        for (let q = a; q < b; q++) col.appendChild(cells[q]);
        set.appendChild(col);
      }
      for (let c = ranges.length; c < cols; c++) { const e = document.createElement('div'); e.className = 'bd-col'; e.style.width = cw + 'px'; set.appendChild(e); }
      content.appendChild(set);
      i = ranges[ranges.length - 1][1];
      if (i < n) newPage();
    }
  }

  // page-number pills
  const total = pages.length;
  const fa = s => String(s).replace(/[0-9]/g, d => '۰۱۲۳۴۵۶۷۸۹'[d]);
  pages.forEach((pg, k) => {
    const pill = document.createElement('div');
    pill.className = 'pg-pill';
    pill.style.bottom = PILL_BOTTOM + 'px';
    pill.style.height = PILL_H + 'px';
    pill.textContent = 'صفحه ' + fa(k + 1) + ' از ' + fa(total);
    pg.appendChild(pill);
  });
  // where each page box really is (the app captures exactly these rectangles)
  window.__pageRects = pages.map(pg => { const r = pg.getBoundingClientRect(); return [r.left + window.scrollX, r.top + window.scrollY, r.width, r.height]; });
  return total;
};
