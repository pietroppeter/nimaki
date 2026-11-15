// nimaki drawing in the reader's browser: the script of the blocks `nbLive` and `nbPlayground`
// (docs/blocks.nim). It loads nimaki compiled to JavaScript (assets/nimaki.js, built from
// src/nimaki/web.nim when the pages are built) only on a page that has one of those blocks.
//
// - A live figure (`figure.live`) holds a drawing made at build time, its Mermaid text and the
//   options it was drawn with. Here nimaki draws the text again, puts its own drawing in place
//   of the one from the build, and says whether the two are the same bytes.
// - A playground (`.playground`) draws what is typed in its text area, as it is typed, with
//   nimaki's `mount`, Pele's browser side: the drawing fits the box, is drawn again when the box
//   changes width, keeps the last good drawing dimmed under an error, and can be zoomed when it
//   was shrunk to fit. It measures text with the page's own font (the browser's canvas), as Pele
//   does in a browser; a live figure measures as the build does, so that the bytes can agree.
(() => {
  if (globalThis.nimakiLive) return;   // every live block adds this script: run once
  globalThis.nimakiLive = true;
  const figures = document.querySelectorAll('figure.live');
  const grounds = document.querySelectorAll('.playground');
  if (!figures.length && !grounds.length) return;
  const me = document.currentScript;
  const src = me.dataset.nimaki;

  // A parse error's first line says where it is, and its last line what is wrong (Pele's mount.ts).
  const summary = (message) => {
    const lines = message.split('\n').filter((line) => line.trim() !== '');
    return lines.length > 1 ? lines[0] + ' ' + lines[lines.length - 1] : (lines[0] ?? '');
  };
  const say = (el, text, cls) => { el.textContent = text; el.className = 'live-status ' + (cls || ''); };

  const draw = (text, options) => {
    const t0 = performance.now();
    let r;
    try {
      r = globalThis.nimaki.render(text, { ...options, measurer: globalThis.nimaki.metricsMeasurer });
      r.ok = true;
    } catch (e) {
      r = { ok: false, code: e.code, message: e.message };
    }
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
      // The time of a drawing for new text; one for a new width or for fonts that loaded is not timed.
      let t0 = performance.now();
      const drawn = (r) => {
        const wide = Math.round(r.width) + ' pixels wide';
        if (t0 === 0) return say(status, 'Drawn again by nimaki for the room there is now, ' + wide + '.', 'good');
        say(status, 'Drawn by nimaki in your browser in ' + Math.max(1, Math.round(performance.now() - t0)) + ' ms, ' + wide + '.', 'good');
        t0 = 0;
      };
      const handle = globalThis.nimaki.mount(out, area.value, {
        ...options,
        onRender: drawn,
        onError: (e) => {
          t0 = 0;
          say(status, (e.code === 'unsupported-diagram' ? 'Not drawn: ' : 'Not drawn (the last drawing stays, dimmed): ') + summary(e.message), 'bad');
        },
      });
      let timer = 0;
      area.addEventListener('input', () => {
        clearTimeout(timer);
        timer = setTimeout(() => {
          t0 = performance.now();
          handle.update(area.value);
          t0 = 0;
        }, 150);
      });
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
