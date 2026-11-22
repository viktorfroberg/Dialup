// Dial-up Mode page script. Injected by Host/DialupMode/DialupModePageScript.swift into every
// page frame, in an isolated content world (page scripts can't see or tamper with it).
//
// - Images trickle in line by line at the simulated connection speed (capped), and report
//   { remaining, total, url } to the host for the status bar's "(n items remaining)".
// - GIF-style image colours, old fonts and the "page touches" (retro scrollbars per skin,
//   square corners, no shadows/animations, underlined links) as one injected style sheet.
//
// The placeholder assigned to `cfg` below is replaced with the JSON config from
// DialupModePageScript.config(for:skin:) before injection. Running the script again only calls update(cfg) on the existing instance.
(() => {
  const cfg = __CFG__;
  const api = window.__dialupMode || (window.__dialupMode = create());
  api.update(cfg);

  function create() {
    let cfg = {};
    const queue = [];
    const seen = new WeakSet();
    let active = 0, total = 0, currentUrl = '', style = null, svg = null, lastPost = 0, postTimer = null;
    const MAX_PARALLEL = 4;   // browsers of the era opened a few connections at once
    const CSS_HIDE = 'img:not([data-dialup-shown]){visibility:hidden!important}';
    const CSS_GIF = 'img{filter:url(#dialup-websafe)}';
    // Old fonts: text in Times New Roman, the browser default most pages of the dial-up era showed,
    // and code in Courier New. Elements are tagged by kind (see tagFonts). Headlines keep the site's
    // font: many are sized to fit it exactly, line by line, and another font could overflow and get clipped.
    const HEADLINES = 'h1,h2,h3,h4,h5,h6,[class*="headline" i],[class*="heading" i]'
    const CSS_FONTS = ':is([data-dialup-font=sans],[data-dialup-font=serif]){font-family:"Times New Roman",Times,serif!important}'
      + '[data-dialup-font=mono]{font-family:"Courier New",Courier,monospace!important}'
      + '*{-webkit-font-smoothing:none!important}';

    // Page touches. Safe set first; the rest are opt-in because they can change layouts.
    const svgArrow = (d) => `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='8' height='8'%3E%3Cpath d='${d}' fill='%234d6185'/%3E%3C/svg%3E")`;
    const SCROLLBARS = {
      // XP: light track, blue rounded thumb with a grip, blue arrow buttons at both ends.
      // WebKit only draws buttons whose position is declared (start:decrement / end:increment).
      luna: '::-webkit-scrollbar{width:17px!important;height:17px!important;background:#fdfdfa!important}'
        + '::-webkit-scrollbar-track{background:linear-gradient(90deg,#f3f1ec,#fefefe 40%,#f7f6f2)!important;box-shadow:none!important}'
        + '::-webkit-scrollbar-track:horizontal{background:linear-gradient(#f3f1ec,#fefefe 40%,#f7f6f2)!important}'
        + '::-webkit-scrollbar-thumb{border:1px solid #6d8be0!important;border-radius:3px!important;box-shadow:inset 1px 1px 0 #f0f5ff,inset -1px -1px 0 #9cb3ee!important}'
        + '::-webkit-scrollbar-thumb:vertical{background:repeating-linear-gradient(#f0f5ff 0 1px,#7f9de8 1px 2px) center/7px 8px no-repeat,linear-gradient(90deg,#bdd0fb,#a7bff8 55%,#9db6f5)!important}'
        + '::-webkit-scrollbar-thumb:horizontal{background:repeating-linear-gradient(90deg,#f0f5ff 0 1px,#7f9de8 1px 2px) center/8px 7px no-repeat,linear-gradient(#bdd0fb,#a7bff8 55%,#9db6f5)!important}'
        + '::-webkit-scrollbar-thumb:hover{filter:brightness(1.06)!important}'
        + '::-webkit-scrollbar-thumb:active{filter:brightness(.94)!important}'
        + '::-webkit-scrollbar-button{display:none!important}'
        + '::-webkit-scrollbar-button:vertical:start:decrement,::-webkit-scrollbar-button:vertical:end:increment,'
        + '::-webkit-scrollbar-button:horizontal:start:decrement,::-webkit-scrollbar-button:horizontal:end:increment'
        + '{display:block!important;width:17px!important;height:17px!important;border:1px solid #6d8be0!important;border-radius:3px!important;'
        + 'box-shadow:inset 1px 1px 0 #f0f5ff,inset -1px -1px 0 #9cb3ee!important;background-repeat:no-repeat!important;background-position:center!important}'
        + `::-webkit-scrollbar-button:vertical:start:decrement{background:${svgArrow('M0 6 4 2 8 6z')} center no-repeat,linear-gradient(90deg,#bdd0fb,#a7bff8)!important}`
        + `::-webkit-scrollbar-button:vertical:end:increment{background:${svgArrow('M0 2 4 6 8 2z')} center no-repeat,linear-gradient(90deg,#bdd0fb,#a7bff8)!important}`
        + `::-webkit-scrollbar-button:horizontal:start:decrement{background:${svgArrow('M6 0 2 4 6 8z')} center no-repeat,linear-gradient(#bdd0fb,#a7bff8)!important}`
        + `::-webkit-scrollbar-button:horizontal:end:increment{background:${svgArrow('M2 0 6 4 2 8z')} center no-repeat,linear-gradient(#bdd0fb,#a7bff8)!important}`
        + '::-webkit-scrollbar-corner{background:#f3f1ec!important}',
      // Windows 98/2000: grey 3D buttons and thumb, dithered track.
      classic: '::-webkit-scrollbar{width:16px!important;height:16px!important;background:#d4d0c8!important}'
        + '::-webkit-scrollbar-track{background:repeating-conic-gradient(#d4d0c8 0 25%,#fff 0 50%) 0 0/2px 2px!important;box-shadow:none!important}'
        + '::-webkit-scrollbar-thumb{background:#d4d0c8!important;border:1px solid!important;border-color:#dfdfdf #404040 #404040 #dfdfdf!important;border-radius:0!important;box-shadow:inset 1px 1px 0 #fff,inset -1px -1px 0 #808080!important}'
        + '::-webkit-scrollbar-button{display:none!important}'
        + '::-webkit-scrollbar-button:vertical:start:decrement,::-webkit-scrollbar-button:vertical:end:increment,'
        + '::-webkit-scrollbar-button:horizontal:start:decrement,::-webkit-scrollbar-button:horizontal:end:increment'
        + '{display:block!important;width:16px!important;height:16px!important;border:1px solid!important;border-color:#dfdfdf #404040 #404040 #dfdfdf!important;border-radius:0!important;box-shadow:inset 1px 1px 0 #fff,inset -1px -1px 0 #808080!important}'
        + `::-webkit-scrollbar-button:vertical:start:decrement{background:${svgArrow('M0 6 4 2 8 6z').replace('%234d6185','%23000')} center no-repeat,#d4d0c8!important}`
        + `::-webkit-scrollbar-button:vertical:end:increment{background:${svgArrow('M0 2 4 6 8 2z').replace('%234d6185','%23000')} center no-repeat,#d4d0c8!important}`
        + `::-webkit-scrollbar-button:horizontal:start:decrement{background:${svgArrow('M6 0 2 4 6 8z').replace('%234d6185','%23000')} center no-repeat,#d4d0c8!important}`
        + `::-webkit-scrollbar-button:horizontal:end:increment{background:${svgArrow('M2 0 6 4 2 8z').replace('%234d6185','%23000')} center no-repeat,#d4d0c8!important}`
        + '::-webkit-scrollbar-button:active{border-color:#808080!important;box-shadow:none!important}'
        + '::-webkit-scrollbar-corner{background:#d4d0c8!important}',
      aqua: '::-webkit-scrollbar{width:15px!important;height:15px!important;background:#ececec!important}'
        + '::-webkit-scrollbar-track{background:linear-gradient(90deg,#cfcfcf,#f2f2f2 40%,#fbfbfb)!important;box-shadow:inset 1px 0 2px rgba(0,0,0,.25)!important}'
        + '::-webkit-scrollbar-track:horizontal{background:linear-gradient(#cfcfcf,#f2f2f2 40%,#fbfbfb)!important}'
        + '::-webkit-scrollbar-thumb{background:linear-gradient(90deg,#3f84ea,#a6d4ff 30%,#5ea6ff 55%,#2f74e0)!important;border:1px solid #2a5fa8!important;border-radius:8px!important}'
        + '::-webkit-scrollbar-thumb:horizontal{background:linear-gradient(#3f84ea,#a6d4ff 30%,#5ea6ff 55%,#2f74e0)!important}'
        + '::-webkit-scrollbar-button:start{display:none!important}'
        + '::-webkit-scrollbar-button:end{display:block!important;width:15px!important;height:15px!important;background:linear-gradient(90deg,#e8e8e8,#fafafa)!important;border:1px solid #b0b0b0!important;background-repeat:no-repeat!important;background-position:center!important}'
        + `::-webkit-scrollbar-button:vertical:end:decrement{background-image:${svgArrow('M0 6 4 2 8 6z')},linear-gradient(90deg,#e8e8e8,#fafafa)!important}`
        + `::-webkit-scrollbar-button:vertical:end:increment{background-image:${svgArrow('M0 2 4 6 8 2z')},linear-gradient(90deg,#e8e8e8,#fafafa)!important}`
        + `::-webkit-scrollbar-button:horizontal:end:decrement{background-image:${svgArrow('M6 0 2 4 6 8z')},linear-gradient(#e8e8e8,#fafafa)!important}`
        + `::-webkit-scrollbar-button:horizontal:end:increment{background-image:${svgArrow('M2 0 6 4 2 8z')},linear-gradient(#e8e8e8,#fafafa)!important}`
        + '::-webkit-scrollbar-corner{background:#ececec!important}',
    };
    const CSS_RETRO = (skin) => '*{scrollbar-color:auto!important;scrollbar-width:auto!important;text-shadow:none!important}'
      + 'html{scroll-behavior:auto!important}'
      + '::selection{background:#316ac5!important;color:#fff!important}'
      + ':focus-visible{outline:1px dotted currentColor!important;outline-offset:1px!important}'
      + (SCROLLBARS[skin] || SCROLLBARS.luna);
    const CSS_SQUARE = '*,*::before,*::after{border-radius:0!important}';
    const CSS_NO_SHADOWS = '*,*::before,*::after{box-shadow:none!important}';
    // 0.01ms, not 0: with 0 no transitionend/animationend fires and some sites wait forever.
    const CSS_NO_MOTION = '*,*::before,*::after{transition-duration:.01ms!important;transition-delay:0s!important;animation-duration:.01ms!important;animation-delay:0s!important;animation-iteration-count:1!important}';
    const CSS_LINKS = 'a[href]{text-decoration:underline!important}';

    const show = (img) => img.setAttribute('data-dialup-shown', '');
    const remaining = () => queue.length + active;

    function post(force) {
      const now = Date.now();
      if (!force && now - lastPost < 120) {
        if (!postTimer) postTimer = setTimeout(() => { postTimer = null; post(true); }, 120);
        return;
      }
      lastPost = now;
      try {
        window.webkit.messageHandlers.dialupLoading.postMessage({ remaining: remaining(), total, url: currentUrl });
      } catch (_) {}
    }

    function attach(node) {
      const parent = document.head || document.documentElement;
      if (parent) parent.appendChild(node);
      else document.addEventListener('readystatechange', () => attach(node), { once: true });
    }

    function ensureSvg() {
      if (svg && svg.isConnected) return;
      if (!document.body) { document.addEventListener('DOMContentLoaded', ensureSvg, { once: true }); return; }
      svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('width', '0');
      svg.setAttribute('height', '0');
      svg.setAttribute('aria-hidden', 'true');
      svg.style.position = 'absolute';
      // Real GIFs chose their 256 colours per picture, so photos kept most of their tones.
      // 10 levels per channel gives that look; the strict web-safe 216 is a separate "hard" option.
      const t = 'type="discrete" tableValues="0 .111 .222 .333 .444 .556 .667 .778 .889 1"';
      svg.innerHTML = `<filter id="dialup-websafe" color-interpolation-filters="sRGB"><feComponentTransfer>`
        + `<feFuncR ${t}/><feFuncG ${t}/><feFuncB ${t}/></feComponentTransfer></filter>`;
      document.body.appendChild(svg);
    }

    function bytes(img) {
      const src = img.currentSrc || img.src;
      const entry = performance.getEntriesByName(src)[0];
      const size = entry && (entry.encodedBodySize || entry.transferSize);
      return size > 0 ? size : Math.max(2000, img.naturalWidth * img.naturalHeight * 0.3);
    }

    function pump() {
      while (active < MAX_PARALLEL && queue.length) {
        const img = queue.shift();
        if (!img.isConnected) { show(img); continue; }
        active++;
        currentUrl = img.currentSrc || img.src;
        // Real speed, but capped, and the cap shrinks as the backlog grows: fun, not annoying.
        const cap = Math.max(300, (cfg.capMs || 2500) - queue.length * 100);
        const ms = Math.min(cap, Math.max(150, bytes(img) * 8 / cfg.bps * 1000));
        const base = cfg.gifImages ? 'url(#dialup-websafe) ' : '';
        show(img);
        const anim = img.animate([
          { clipPath: 'inset(0 0 100% 0)', filter: base + 'blur(3px)' },
          { clipPath: 'inset(0 0 0 0)', filter: base + 'blur(0px)' },
        ], { duration: ms, easing: `steps(${Math.max(4, Math.round(ms / 50))}, end)` });
        // A timer drives the queue (WebKit pauses animations in hidden windows);
        // the animation is just the look.
        let finished = false;
        const finish = () => {
          if (finished) return;
          finished = true;
          try { anim.finish(); } catch (_) {}
          active--;
          pump();
        };
        anim.onfinish = finish;
        anim.oncancel = finish;
        setTimeout(finish, ms + 50);
      }
      post(remaining() === 0);
    }

    function schedule(img) {
      if (seen.has(img)) return;
      seen.add(img);
      if (!cfg.enabled || !cfg.bps || img.naturalWidth * img.naturalHeight <= 4) { show(img); return; }
      total++;
      queue.push(img);
      pump();
    }

    document.addEventListener('load', (e) => { if (e.target instanceof HTMLImageElement) schedule(e.target); }, true);
    document.addEventListener('error', (e) => { if (e.target instanceof HTMLImageElement) show(e.target); }, true);

    // Images loaded while detached (new Image(), lightboxes, lazy loaders, clones) never fire a
    // load event the document can see, so catch them when they're inserted.
    const adopt = (img) => {
      if (seen.has(img) || !img.complete) return; // incomplete ones get a load event later
      if (img.naturalWidth) schedule(img); else show(img); // broken: show alt/box
    };
    const SERIF_NAMES = /^(-webkit-standard|serif|times|georgia|garamond|palatino|book antiqua|cambria|baskerville|didot|bodoni|caslon|charter|new york|minion|merriweather|lora|playfair|libre baskerville|source serif|pt serif|noto serif|droid serif|iowan)/;
    const MONO_NAMES = /^(monospace|courier|consolas|menlo|monaco|sf mono|ui-monospace|andale mono|lucida console|source code|fira code|fira mono|jetbrains|roboto mono|ibm plex mono|dejavu sans mono)/;
    const ICON_NAMES = /icon|awesome|material|symbol|glyph|dashicons|octicons|bootstrap-icons|emoji/;
    /** "sans", "serif" or "mono" for a computed font-family list; null for icon fonts. */
    function fontKind(family) {
      const names = family.toLowerCase().split(',').map((n) => n.trim().replace(/^["']|["']$/g, ''));
      const first = names[0] || '';
      if (ICON_NAMES.test(first)) return null; // icon fonts stay, or their glyphs turn into letters
      if (MONO_NAMES.test(first) || /\bmono\b/.test(first)) return 'mono';
      if (SERIF_NAMES.test(first) || (/serif/.test(first) && !/sans/.test(first))) return 'serif';
      if (!/sans/.test(first) && names.includes('serif') && !names.includes('sans-serif')) return 'serif';
      return 'sans';
    }
    const NO_FONT = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'svg', 'IMG', 'VIDEO', 'CANVAS', 'IFRAME', 'BR']);
    /** Tags elements whose font differs from their parent's with its kind. Children that inherit need no tag. */
    function tagFonts(roots) {
      const found = [];
      for (const root of roots) {
        if (!root || !root.isConnected || !root.querySelectorAll) continue;
        for (const el of [root, ...root.querySelectorAll('*')]) {
          if (!(el instanceof Element) || NO_FONT.has(el.tagName) || el.hasAttribute('data-dialup-font') || el.closest(HEADLINES)) continue;
          const family = getComputedStyle(el).fontFamily;
          const parent = el.parentElement;
          if (parent && parent !== document.documentElement && getComputedStyle(parent).fontFamily === family) continue;
          const kind = fontKind(family);
          if (kind) found.push([el, kind]);
        }
      }
      // Read everything first, then tag: tagging changes what children inherit, and mixing reads
      // and writes would make WebKit recalculate styles again and again.
      for (const [el, kind] of found) el.setAttribute('data-dialup-font', kind);
    }
    // New content (infinite scroll, ads, live updates) is tagged in one batch when the page is idle.
    let fontQueue = [];
    let fontScheduled = false;
    function queueFonts(node) {
      fontQueue.push(node);
      if (fontScheduled) return;
      fontScheduled = true;
      const run = () => { fontScheduled = false; tagFonts(fontQueue.splice(0)); };
      if (window.requestIdleCallback) requestIdleCallback(run, { timeout: 400 }); else setTimeout(run, 100);
    }
    document.addEventListener('DOMContentLoaded', () => { if (cfg.enabled && cfg.oldFonts) tagFonts([document.body]); });
    new MutationObserver((records) => {
      if (!cfg.enabled || !cfg.oldFonts) return;
      for (const record of records) for (const node of record.addedNodes) if (node.nodeType === 1) queueFonts(node);
    }).observe(document, { childList: true, subtree: true });

    new MutationObserver((records) => {
      if (!cfg.enabled || !cfg.bps) return;
      for (const record of records) {
        for (const node of record.addedNodes) {
          if (node instanceof HTMLImageElement) adopt(node);
          else if (node.querySelectorAll) node.querySelectorAll('img').forEach(adopt);
        }
      }
    }).observe(document, { childList: true, subtree: true });

    return {
      update(next) {
        // Our own start page keeps its design: only the retro scrollbars apply there.
        if (location.protocol === 'dialup-start:') {
          next = Object.assign({}, next, { oldFonts: false, squareCorners: false, noShadows: false,
                                            noAnimations: false, underlineLinks: false, gifImages: false });
        }
        const wasActive = !!(cfg.enabled && cfg.bps);
        cfg = next;
        if (!cfg.enabled) {
          if (style) style.remove();
          if (svg) svg.remove();
          queue.splice(0).forEach(show);
          post(true);
          return;
        }
        if (!style) { style = document.createElement('style'); style.id = 'dialup-mode-style'; }
        style.textContent = (cfg.bps ? CSS_HIDE : '') + (cfg.gifImages ? CSS_GIF : '') + (cfg.oldFonts ? CSS_FONTS : '')
          + (cfg.retroPage ? CSS_RETRO(cfg.skin) : '') + (cfg.squareCorners ? CSS_SQUARE : '')
          + (cfg.noShadows ? CSS_NO_SHADOWS : '') + (cfg.noAnimations ? CSS_NO_MOTION : '') + (cfg.underlineLinks ? CSS_LINKS : '');
        if (!style.isConnected) attach(style);
        if (cfg.gifImages) ensureSvg();
        if (cfg.oldFonts && document.body) tagFonts([document.body]);
        // Turned on mid-page: don't re-hide what's already loaded; the next page trickles in.
        if (!wasActive) document.querySelectorAll('img').forEach((img) => { if (img.complete) { seen.add(img); show(img); } });
        if (!cfg.bps) queue.splice(0).forEach(show);
        post(true); // a fresh page always reports, so a stale "(n items remaining)" clears
      },
    };
  }
})();
