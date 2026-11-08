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
  // the flow: the top-level blocks of the report
  const flow = Array.from(body.children);
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
    content.appendChild(el);
    if (fits()) continue;
    // does not fit: move it (and a lonely header right above it) to a fresh page
    const carry = [el];
    const prev = el.previousElementSibling;
    if (prev && prev.classList.contains('head') && prev !== content.firstElementChild) {
      carry.unshift(prev);
    }
    if (content.children.length > carry.length) {
      newPage();
      carry.forEach(c => content.appendChild(c));
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
