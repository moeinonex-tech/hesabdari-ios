// Exact A4 pagination before printing. The iOS print engine cuts the page into slices of the printable height
// and ignores break-inside, so this pass moves every block that would straddle a page edge to the next page
// (with a spacer), repeats the table header on top of a new page, and lays out «.bd-flow» lists in 1–3 columns
// filled top-to-bottom, then the next column (column-major), page by page.
// H = printable page height in CSS px (1 CSS px = 1 pt in the iOS renderer).
window.paginate = function (H) {
  const body = document.body;
  const EPS = 1;
  const top = el => el.getBoundingClientRect().top + window.scrollY;
  const bottom = el => el.getBoundingClientRect().bottom + window.scrollY;
  const pageOf = y => Math.floor((y + EPS) / H);
  const spacer = () => { const s = document.createElement('div'); s.className = 'pg-spacer'; s.style.height = '0px'; return s; };
  // push el so that its top sits exactly at the start of the next page
  function pushToNextPage(el) {
    const target = (pageOf(top(el)) + 1) * H;
    const s = spacer();
    el.parentNode.insertBefore(s, el);
    // with a non-zero height the spacer stops margin collapsing, so the shift becomes exactly linear
    s.style.height = '1px';
    s.style.height = Math.max(1, 1.5 + target - top(el)) + 'px';   // +0.5: never a sub-pixel short of the edge
  }
  const crosses = el => { const t = top(el), b = bottom(el); return pageOf(t) !== pageOf(b - EPS * 2) && b - t <= H; };

  // ---- breakdown flows → page-aware column sets ----
  function layoutFlow(flow) {
    const n = flow.children.length;
    const cols = n <= 6 ? 1 : n <= 14 ? 2 : 3;
    const gap = 5, rowGap = 4;
    const W = flow.getBoundingClientRect().width;
    const cw = (W - gap * (cols - 1)) / cols;
    const cells = Array.from(flow.children);
    cells.forEach(c => c.classList.add('w' + cols));
    flow.style.width = cw + 'px';                    // measure every cell at its column width
    const hs = cells.map(c => c.getBoundingClientRect().height);
    flow.style.width = '';
    const parent = flow.parentNode;
    // take the list out of the flow first, so it does not push the column sets down while they are measured
    const holder = document.createElement('div');
    holder.style.cssText = 'position:absolute;visibility:hidden;width:' + cw + 'px';
    cells.forEach(c => holder.appendChild(c));
    body.appendChild(holder);
    let i = 0;
    while (i < n) {
      const set = document.createElement('div');
      set.className = 'bd-colset';
      parent.insertBefore(set, flow);
      let y = top(set);
      let avail = (pageOf(y) + 1) * H - y - 2;
      if (avail < Math.min(...hs.slice(i)) + 2) { pushToNextPage(set); y = top(set); avail = H - 2; }
      const R = n - i;
      const colH = (from, to) => { let s = 0; for (let k = from; k < to; k++) s += hs[k] + (k > from ? rowGap : 0); return s; };
      // balanced: ceil(R/cols) per column, if it fits the rest of this page
      const k = Math.ceil(R / cols);
      let ranges = [];
      let ok = true;
      for (let c = 0; c < cols; c++) {
        const a = i + c * k, b = Math.min(i + (c + 1) * k, n);
        if (a >= b) break;
        if (colH(a, b) > avail) { ok = false; break; }
        ranges.push([a, b]);
      }
      if (!ok) {
        // fill each column to the bottom of the page, then the next column
        ranges = [];
        let p = i;
        for (let c = 0; c < cols && p < n; c++) {
          let q = p;
          while (q < n && colH(p, q + 1) <= avail) q++;
          if (q === p) q = p + 1;      // a single cell taller than the space: never loop forever
          ranges.push([p, q]);
          p = q;
        }
      }
      for (const [a, b] of ranges) {
        const col = document.createElement('div');
        col.className = 'bd-col';
        col.style.width = cw + 'px';
        for (let q = a; q < b; q++) col.appendChild(cells[q]);
        set.appendChild(col);
      }
      for (let c = ranges.length; c < cols; c++) { const e = document.createElement('div'); e.className = 'bd-col'; e.style.width = cw + 'px'; set.appendChild(e); }
      i = ranges[ranges.length - 1][1];
    }
    flow.remove();
    holder.remove();
  }

  // ---- generic pass, in document order ----
  const ATOMIC = '.hdr,.head,.row,.empty,.total,.card,.bd-title,.bd-top,.bd-colset,.blk';
  let lastHead = null;
  const walk = () => Array.from(body.querySelectorAll(ATOMIC + ',.bd-flow,.newpage'));
  let list = walk();
  for (let idx = 0; idx < list.length; idx++) {
    const el = list[idx];
    if (!el.isConnected) continue;
    if (el.classList.contains('bd-flow')) {
      const before = el.previousElementSibling;
      layoutFlow(el);
      list = walk();
      idx = before ? list.indexOf(before) : -1;   // continue right after the flow's predecessor
      continue;
    }
    if (el.classList.contains('newpage')) {
      if (top(el) % H > 2 && !el.dataset.done) { el.dataset.done = '1'; pushToNextPage(el); }
      if (!el.matches(ATOMIC)) continue;
    }
    if (el.classList.contains('head')) lastHead = el;
    if (el.closest('.bd-colset') && !el.classList.contains('bd-colset')) continue;
    if (crosses(el)) {
      if (el.classList.contains('row') && lastHead) {
        // a row moving to a new page brings the table header with it
        const h = lastHead.cloneNode(true);
        el.parentNode.insertBefore(h, el);
        pushToNextPage(h);
      } else {
        pushToNextPage(el);
      }
    }
    // a section title must not be left alone at the bottom of a page
    if (el.classList.contains('bd-title')) {
      const next = el.nextElementSibling;
      if (next && pageOf(top(next)) === pageOf(top(el)) && crosses(next) && bottom(next) - top(el) <= H) pushToNextPage(el);
    }
  }
  return Math.ceil(body.getBoundingClientRect().height / H);
};
