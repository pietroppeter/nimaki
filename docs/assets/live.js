// nimaki drawing in the reader's browser: the script of the blocks `nbLive` and `nbPlayground`
// (docs/blocks.nim). It loads nimaki compiled to JavaScript (assets/nimaki.js, built from
// src/nimaki/web.nim when the pages are built) only on a page that has one of those blocks.
//
// - A live figure (`figure.live`) holds a drawing made at build time, its Mermaid text and the
//   options it was drawn with. Here nimaki draws the text again, puts its own drawing in place
//   of the one from the build, and says whether the two are the same bytes.
// - A playground (`.playground`) draws what is typed in its text area, as it is typed.
(() => {
  if (globalThis.nimakiLive) return;   // every live block adds this script: run once
  globalThis.nimakiLive = true;
  const figures = document.querySelectorAll('figure.live');
  const grounds = document.querySelectorAll('.playground');
  if (!figures.length && !grounds.length) return;
  const me = document.currentScript;
  const src = me.dataset.nimaki;

  const say = (el, text, cls) => { el.textContent = text; el.className = 'live-status ' + (cls || ''); };

  const draw = (text, options) => {
    const t0 = performance.now();
    const r = globalThis.nimaki.render(text, options);
    r.ms = Math.max(1, Math.round(performance.now() - t0));
    return r;
  };

  const liven = () => {
    for (const fig of figures) {
      const status = fig.querySelector('.live-status');
      const text = fig.querySelector('.live-source').textContent;
      const options = JSON.parse(fig.dataset.options || '{}');
      const built = fig.querySelector('.live-built').textContent;
      const r = draw(text, options);
      if (!r.ok) { say(status, 'nimaki could not draw it here: ' + r.message, 'bad'); continue; }
      fig.querySelector('.live-drawing').innerHTML = r.svg;
      if (r.svg === built) say(status, 'Drawn in your browser by nimaki in ' + r.ms + ' ms: the same bytes as at build time.', 'good');
      else say(status, 'Drawn in your browser by nimaki, but not the same bytes as at build time.', 'bad');
    }
    for (const g of grounds) {
      const area = g.querySelector('textarea');
      const out = g.querySelector('.playground-drawing');
      const status = g.querySelector('.live-status');
      const options = JSON.parse(g.dataset.options || '{}');
      let timer = 0;
      const update = () => {
        const r = draw(area.value, options);
        if (r.ok) { out.innerHTML = r.svg; say(status, 'Drawn by nimaki in your browser in ' + r.ms + ' ms.', 'good'); }
        else say(status, (r.code === 'unsupported' ? 'Not ported yet: ' : 'Not drawn: ') + r.message, 'bad');
      };
      area.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(update, 150); });
      update();
    }
  };

  for (const el of document.querySelectorAll('figure.live .live-status, .playground .live-status')) {
    say(el, 'Loading nimaki…');
  }
  const s = document.createElement('script');
  s.src = src;
  s.onload = liven;
  s.onerror = () => {
    for (const el of document.querySelectorAll('.live-status')) say(el, 'nimaki.js could not be loaded.', 'bad');
  };
  document.head.appendChild(s);
})();
