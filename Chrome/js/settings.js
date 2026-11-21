// "Dialup Options": the settings dialog. Tabs: General, Start Page, Appearance, Dial-up Mode, Privacy.
// Edits go to a draft. Apply/OK send it to the host; Cancel throws it away.

import { host } from './host.js';
import { openDialog, confirmBox } from './overlay.js';

const SAMPLE = 'img/sample.svg';
const SPEEDS = { modem56k: 53333, isdn: 128000, dsl: 512000, off: 0 };
const PICTURE_BYTES = 40 * 1024; // "a typical 40 KB photo"
const PICTURE_CAP_MS = 2500;     // same cap the page script uses

let current = null; // the open dialog, so ⌘, twice doesn't stack dialogs

export async function openSettings(startTab = 'general', { getCurrentUrl } = {}) {
  if (current) { current.select(startTab); return; }
  const [prefs, dialup] = await Promise.all([host.call('prefsGet'), host.call('dialupModeGet')]);
  const catalog = prefs.catalog || { skins: [], searchEngines: [] };
  const draft = {
    prefs: structuredClone({ ...prefs, catalog: undefined }),
    dialup: structuredClone(dialup),
  };

  const tabs = [
    ['general', 'General', generalTab],
    ['startpage', 'Start Page', startPageTab],
    ['appearance', 'Appearance', appearanceTab],
    ['dialup', 'Dial-up Mode', dialupTab],
    ['privacy', 'Privacy', privacyTab],
  ];

  const root = document.createElement('div');
  root.className = 'settings';
  const strip = document.createElement('div');
  strip.className = 'tabs';
  const panels = document.createElement('div');
  panels.className = 'tab-panels';
  root.append(strip, panels);

  const ctx = { draft, catalog, getCurrentUrl, refresh: [] };
  const byId = {};
  for (const [id, label, build] of tabs) {
    const tab = document.createElement('button');
    tab.className = 'tab';
    tab.textContent = label;
    tab.addEventListener('click', () => select(id));
    strip.append(tab);
    const panel = document.createElement('div');
    panel.className = 'tab-panel';
    panel.append(build(ctx));
    panels.append(panel);
    byId[id] = { tab, panel };
  }

  function select(id) {
    for (const [key, { tab, panel }] of Object.entries(byId)) {
      tab.classList.toggle('selected', key === id);
      panel.hidden = key !== id;
    }
  }
  select(byId[startTab] ? startTab : 'general');

  const apply = async () => {
    await host.call('prefsSet', draft.prefs);
    await host.call('dialupModeSet', draft.dialup);
  };

  const dialog = openDialog({
    title: 'Dialup Options',
    width: 580,
    body: root,
    buttons: [
      { label: 'OK', value: 'ok', primary: true },
      { label: 'Cancel', value: 'cancel', cancel: true },
      { label: 'Apply', value: 'apply' },
    ],
    onButton: async (value) => {
      if (value === 'apply') { await apply(); return false; }
      if (value === 'ok') await apply();
      current = null;
      return true;
    },
  });
  current = { select };
  dialog.recentre();
}

// ---------- helpers ----------

function html(strings, ...values) {
  const t = document.createElement('template');
  t.innerHTML = String.raw({ raw: strings }, ...values.map(escape)).trim();
  return t.content;
}

function escape(v) {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

/** Two-way bind inputs with data-bind="prefs.key" / "dialup.key" to the draft. */
function bind(root, draft, onChange) {
  for (const input of root.querySelectorAll('[data-bind]')) {
    const [group, key] = input.dataset.bind.split('.');
    const read = () => draft[group][key];
    if (input.type === 'checkbox') input.checked = !!read();
    else if (input.type === 'radio') input.checked = read() === input.value;
    else input.value = read() ?? '';
    input.addEventListener(input.type === 'text' ? 'input' : 'change', () => {
      if (input.type === 'checkbox') draft[group][key] = input.checked;
      else if (input.type === 'radio') { if (input.checked) draft[group][key] = input.value; }
      else draft[group][key] = input.value;
      onChange?.(group, key);
    });
  }
}

function sync(root, draft) {
  for (const input of root.querySelectorAll('[data-bind]')) {
    const [group, key] = input.dataset.bind.split('.');
    if (input.type === 'checkbox') input.checked = !!draft[group][key];
    else if (input.type === 'radio') input.checked = draft[group][key] === input.value;
  }
}

// ---------- General ----------

function generalTab({ draft, catalog, getCurrentUrl }) {
  const isStart = draft.prefs.homePage === 'start';
  const frag = html`
    <fieldset>
      <legend>Home page</legend>
      <div class="icon-row">
        <div class="big-icon icon-home"></div>
        <div class="grow">
          <p class="hint">The page that opens with new windows and when you click Home.</p>
          <label class="choice"><input type="radio" name="home" value="start"> Dialup Start Page <span class="hint">(search, favorite sites, visitor counter)</span></label>
          <label class="choice"><input type="radio" name="home" value="url"> This page:</label>
          <div class="indent row">
            <input type="text" class="field grow" id="home-url" spellcheck="false" placeholder="https://www.example.com/">
            <button class="btn small" id="use-current">Use Current</button>
          </div>
        </div>
      </div>
    </fieldset>
    <fieldset>
      <legend>Searching</legend>
      <div class="icon-row">
        <div class="big-icon icon-search"></div>
        <div class="grow">
          <label class="row">Search the Web with:
            <select data-bind="prefs.searchEngine" class="field">
              ${''}
            </select>
          </label>
          <p class="hint">Used when you type words (not an address) in the Address bar, and on the Start Page.</p>
        </div>
      </div>
    </fieldset>
    <fieldset>
      <legend>Your profile</legend>
      <div class="icon-row">
        <div class="big-icon icon-user"></div>
        <div class="grow">
          <label class="row">Your name: <input type="text" class="field grow" data-bind="prefs.name" placeholder="Optional"></label>
          <p class="hint">Used to greet you on the Start Page. It never leaves this computer.</p>
        </div>
      </div>
    </fieldset>`;
  const root = document.createElement('div');
  root.append(frag);

  const select = root.querySelector('select');
  for (const engine of catalog.searchEngines) select.append(new Option(engine.name, engine.id));

  const url = root.querySelector('#home-url');
  const radios = root.querySelectorAll('input[name=home]');
  url.value = isStart ? '' : draft.prefs.homePage;
  radios.forEach((r) => { r.checked = (r.value === 'start') === isStart; });
  const updateHome = () => {
    const mode = root.querySelector('input[name=home]:checked').value;
    draft.prefs.homePage = mode === 'start' || !url.value.trim() ? 'start' : url.value.trim();
    url.disabled = mode === 'start';
  };
  radios.forEach((r) => r.addEventListener('change', updateHome));
  url.addEventListener('input', updateHome);
  root.querySelector('#use-current').addEventListener('click', () => {
    const current = getCurrentUrl?.();
    if (current && !current.startsWith('about:')) {
      url.value = current;
      radios.forEach((r) => { r.checked = r.value === 'url'; });
      updateHome();
    }
  });
  url.disabled = isStart;
  bind(root, draft);
  return root;
}

// ---------- Start Page ----------

function startPageTab({ draft }) {
  const root = document.createElement('div');
  root.append(html`
    <fieldset>
      <legend>My Favorite Sites</legend>
      <p class="hint">These links appear on your Start Page. Up to 12.</p>
      <div class="link-table">
        <div class="link-head"><span>Name</span><span>Address</span><span></span></div>
        <div class="link-rows"></div>
      </div>
      <div class="row"><button class="btn small" id="add-link">Add Site</button><span class="grow"></span><button class="btn small" id="reset-links">Restore Defaults</button></div>
    </fieldset>
    <p class="hint">Tip: the Start Page also greets you by name (General tab) and searches with your chosen search engine.</p>`);
  const rowsEl = root.querySelector('.link-rows');
  const defaults = structuredClone(draft.prefs.quickLinks);

  const render = () => {
    rowsEl.replaceChildren();
    draft.prefs.quickLinks.forEach((link, i) => {
      const row = document.createElement('div');
      row.className = 'link-row';
      row.append(html`
        <input type="text" class="field" value="${link.title}" placeholder="Name">
        <input type="text" class="field" value="${link.url}" placeholder="https://" spellcheck="false">
        <button class="btn tiny" title="Remove">✕</button>`);
      const [title, url, remove] = row.children;
      title.addEventListener('input', () => { link.title = title.value; });
      url.addEventListener('input', () => { link.url = url.value; });
      remove.addEventListener('click', () => { draft.prefs.quickLinks.splice(i, 1); render(); });
      rowsEl.append(row);
    });
    root.querySelector('#add-link').disabled = draft.prefs.quickLinks.length >= 12;
  };
  root.querySelector('#add-link').addEventListener('click', () => {
    draft.prefs.quickLinks.push({ title: '', url: '' });
    render();
    rowsEl.lastElementChild?.querySelector('input')?.focus();
  });
  root.querySelector('#reset-links').addEventListener('click', () => {
    draft.prefs.quickLinks = structuredClone(defaults);
    render();
  });
  render();
  return root;
}

// ---------- Appearance ----------

function appearanceTab({ draft, catalog }) {
  const root = document.createElement('div');
  root.append(html`
    <fieldset>
      <legend>Skin</legend>
      <p class="hint">Changes the whole browser: title bar, buttons, toolbars, menus and dialogs.</p>
      <div class="skin-cards"></div>
    </fieldset>
    <p class="hint">Want to make your own? Skins are plain CSS files in <code>Chrome/skins/</code>.</p>`);
  const cards = root.querySelector('.skin-cards');
  for (const skin of catalog.skins) {
    const card = document.createElement('label');
    card.className = `skin-card skin-${skin.id}`;
    card.append(html`
      <input type="radio" name="skin" value="${skin.id}" data-bind="prefs.skin">
      <div class="mini-window">
        <div class="mini-titlebar"><i></i><i></i><i></i><span>Dialup</span></div>
        <div class="mini-toolbar"><b></b><b></b><b></b><em></em></div>
        <div class="mini-page"><s></s><s></s><s></s></div>
      </div>
      <div class="skin-name">${skin.name}</div>`);
    cards.append(card);
  }
  bind(root, draft);
  return root;
}

// ---------- Dial-up Mode ----------

function dialupTab({ draft }) {
  const root = document.createElement('div');
  root.className = 'dialup-tab';
  root.append(html`
    <label class="choice big"><input type="checkbox" data-bind="dialup.enabled"> <b>Use Dial-up Mode</b> <span class="hint">browse like it's 1999 (⇧⌘D)</span></label>
    <div class="row presets">
      <span>Quick setup:</span>
      <button class="btn small" data-preset="1998">1998 · 56k modem</button>
      <button class="btn small" data-preset="2003">2003 · Broadband</button>
    </div>

    <fieldset>
      <legend>Connection speed</legend>
      <div class="split-row">
        <div class="grow">
          <label class="choice"><input type="radio" name="connection" value="modem56k" data-bind="dialup.connection"> 56k modem</label>
          <label class="choice"><input type="radio" name="connection" value="isdn" data-bind="dialup.connection"> ISDN (128 Kbps)</label>
          <label class="choice"><input type="radio" name="connection" value="dsl" data-bind="dialup.connection"> Broadband (512 Kbps)</label>
          <label class="choice"><input type="radio" name="connection" value="off" data-bind="dialup.connection"> No slowdown</label>
          <p class="hint" id="speed-explain"></p>
        </div>
        <div class="preview-box">
          <div class="trickle"><img src="${SAMPLE}" alt="" id="trickle-img"></div>
          <div class="preview-caption" id="trickle-caption"></div>
        </div>
      </div>
    </fieldset>

    <fieldset>
      <legend>Colours</legend>
      <div class="option-cards" id="colour-cards"></div>
    </fieldset>

    <fieldset>
      <legend>Pixels</legend>
      <div class="option-cards" id="pixel-cards"></div>
    </fieldset>

    <fieldset>
      <legend>Page touches</legend>
      <p class="hint">Small style changes to web pages. The first ones are safe; the rest can change how some sites look.</p>
      <div class="split-row">
        <div class="grow">
          <label class="choice"><input type="checkbox" data-bind="dialup.retroPage"> Retro basics <span class="hint">classic scrollbars, no dark mode, dotted focus, no smooth scrolling</span></label>
          <label class="choice"><input type="checkbox" data-bind="dialup.squareCorners"> Square corners <span class="hint">no rounded boxes and buttons</span></label>
          <label class="choice"><input type="checkbox" data-bind="dialup.noShadows"> No drop shadows <span class="risk">may hide some borders</span></label>
          <label class="choice"><input type="checkbox" data-bind="dialup.noAnimations"> No smooth animations <span class="risk">things snap instead of slide</span></label>
          <label class="choice"><input type="checkbox" data-bind="dialup.underlineLinks"> Underline all links <span class="risk">menus get underlined too</span></label>
        </div>
        <div class="preview-box touches-preview" id="touches-preview">
          <div class="tp-card"><div class="tp-avatar"></div><div class="tp-lines"><s></s><s></s></div></div>
          <div class="tp-row"><span class="tp-button">Sign up</span><a class="tp-link">Learn more</a></div>
          <div class="preview-caption">Preview</div>
        </div>
      </div>
    </fieldset>

    <fieldset>
      <legend>Extras</legend>
      <div class="split-row">
        <div class="grow">
          <label class="choice"><input type="checkbox" data-bind="dialup.scanlines"> CRT scanlines <span class="hint">faint lines like an old monitor</span></label>
          <label class="choice"><input type="checkbox" data-bind="dialup.oldFonts"> Old fonts <span class="hint">Verdana &amp; Times, no smoothing (may break some icons)</span></label>
          <label class="choice"><input type="checkbox" data-bind="dialup.includeChrome"> Apply effects to the toolbars too</label>
        </div>
        <div class="preview-box fonts-preview">
          <div class="font-sample modern">Hello, World!</div>
          <div class="font-sample old">Hello, World!</div>
          <div class="preview-caption">Modern · Old fonts</div>
        </div>
      </div>
    </fieldset>`);

  const colourOptions = [
    ['millions', 'Millions', 'Modern colours.'],
    ['gifImages', '256 for pictures', 'Pictures look like old GIFs. Text stays sharp. Recommended.'],
    ['thousands', 'Thousands', 'Hard mode: the whole page in 16-bit colour.', true],
    ['websafe', '256 web-safe', 'Hard mode: the whole page in 216 colours.', true],
    ['websafeDither', '256 dithered', 'Hard mode: dotted, like a 1996 monitor.', true],
  ];
  const pixelOptions = [
    ['retina', 'Sharp', 'Your normal Retina screen.'],
    ['classic', 'Classic CRT', 'Hard mode: one pixel per point, like a 2003 screen.', true],
    ['chunky', 'Chunky', 'Hard mode: big blocky pixels. Hard to read.', true],
  ];

  const cards = (container, key, options) => {
    for (const [value, title, text, hard] of options) {
      const card = document.createElement('label');
      card.className = `option-card${hard ? ' hard' : ''}`;
      card.append(html`
        <input type="radio" name="${key}" value="${value}" data-bind="dialup.${key}">
        <canvas width="150" height="92"></canvas>
        <div class="option-title">${title}${hard ? ' <span class="hard-badge">HARD</span>' : ''}</div>
        <div class="option-text">${text}</div>`);
      // html`` escapes values; restore the badge markup we added on purpose.
      card.querySelector('.option-title').innerHTML = escape(title) + (hard ? ' <span class="hard-badge">HARD</span>' : '');
      container.append(card);
      const canvas = card.querySelector('canvas');
      const settings = key === 'colors' ? { colors: value, resolution: 'retina' } : { colors: 'millions', resolution: value };
      whenSampleReady((img) => drawPreview(canvas, img, settings));
    }
  };
  cards(root.querySelector('#colour-cards'), 'colors', colourOptions);
  cards(root.querySelector('#pixel-cards'), 'resolution', pixelOptions);

  // Connection speed explanation + trickle animation
  const explain = root.querySelector('#speed-explain');
  const caption = root.querySelector('#trickle-caption');
  const trickleImg = root.querySelector('#trickle-img');
  let anim = null;
  const updateSpeed = () => {
    const bps = SPEEDS[draft.dialup.connection] ?? 0;
    if (!bps) {
      explain.textContent = 'Pictures appear as fast as your real connection allows.';
      caption.textContent = 'Instant';
    } else {
      const real = (PICTURE_BYTES * 8) / bps;
      explain.textContent = `Back then, a 40 KB photo took about ${real.toFixed(1)} seconds. Dial-up Mode caps each picture at ${PICTURE_CAP_MS / 1000} s so pages stay usable.`;
      caption.textContent = `40 KB photo: ${real.toFixed(1)} s`;
    }
    playTrickle();
  };
  const playTrickle = () => {
    anim?.cancel();
    const bps = SPEEDS[draft.dialup.connection] ?? 0;
    const ms = bps ? Math.min(PICTURE_CAP_MS * 2, (PICTURE_BYTES * 8 / bps) * 1000) : 1;
    anim = trickleImg.animate([
      { clipPath: 'inset(0 0 100% 0)', filter: 'blur(3px)', offset: 0 },
      { clipPath: 'inset(0 0 0 0)', filter: 'blur(0px)', offset: ms / (ms + 1500) },
      { clipPath: 'inset(0 0 0 0)', filter: 'blur(0px)', offset: 1 },
    ], { duration: ms + 1500, iterations: Infinity, easing: `steps(${Math.max(4, Math.round(ms / 60))}, end)` });
  };

  const touches = root.querySelector('#touches-preview');
  const updateTouches = () => {
    touches.classList.toggle('square', !!draft.dialup.squareCorners);
    touches.classList.toggle('flat', !!draft.dialup.noShadows);
    touches.classList.toggle('underline', !!draft.dialup.underlineLinks);
  };
  bind(root, draft, (group, key) => { if (key === 'connection') updateSpeed(); updateTouches(); });
  for (const button of root.querySelectorAll('[data-preset]')) {
    button.addEventListener('click', () => {
      const presets = {
        1998: { enabled: true, connection: 'modem56k', colors: 'gifImages', resolution: 'retina', scanlines: true, oldFonts: true,
          retroPage: true, squareCorners: true, noShadows: true, noAnimations: false, underlineLinks: true },
        2003: { enabled: true, connection: 'dsl', colors: 'millions', resolution: 'retina', scanlines: false, oldFonts: false,
          retroPage: true, squareCorners: true, noShadows: false, noAnimations: false, underlineLinks: false },
      };
      Object.assign(draft.dialup, presets[button.dataset.preset]);
      sync(root, draft);
      updateSpeed();
      updateTouches();
    });
  }
  updateSpeed();
  updateTouches();
  return root;
}

// ---------- Privacy ----------

function privacyTab() {
  const root = document.createElement('div');
  root.append(html`
    <fieldset>
      <legend>Temporary Internet files</legend>
      <div class="icon-row">
        <div class="big-icon icon-files"></div>
        <div class="grow">
          <p>Pages and pictures you've viewed are stored for quick viewing later.</p>
          <button class="btn" id="clear-cache">Delete Files…</button>
          <span class="hint" id="cache-done"></span>
        </div>
      </div>
    </fieldset>
    <fieldset>
      <legend>Cookies and site data</legend>
      <div class="icon-row">
        <div class="big-icon icon-cookie"></div>
        <div class="grow">
          <p>Websites store cookies and data to remember you. Deleting them signs you out of sites.</p>
          <button class="btn" id="clear-site-data">Delete Cookies…</button>
          <span class="hint" id="site-done"></span>
        </div>
      </div>
    </fieldset>`);
  root.querySelector('#clear-cache').addEventListener('click', async () => {
    if (await confirmBox('Delete Files', 'Delete all files in the Temporary Internet Files folder?')) {
      await host.call('clearData', { what: 'cache' });
      root.querySelector('#cache-done').textContent = 'Deleted.';
    }
  });
  root.querySelector('#clear-site-data').addEventListener('click', async () => {
    if (await confirmBox('Delete Cookies', 'Delete all cookies and website data? You will be signed out of websites.')) {
      await host.call('clearData', { what: 'all' });
      root.querySelector('#site-done').textContent = 'Deleted.';
    }
  });
  return root;
}

// ---------- Previews (real pixel processing, same maths as the window filters) ----------

let sample = null;
const waiting = [];
function whenSampleReady(fn) {
  if (sample?.complete && sample.naturalWidth) { fn(sample); return; }
  waiting.push(fn);
  if (sample) return;
  sample = new Image();
  sample.onload = () => waiting.splice(0).forEach((f) => f(sample));
  sample.src = SAMPLE;
}

const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

function drawPreview(canvas, img, { colors, resolution }) {
  const W = canvas.width, H = canvas.height;
  const dpr = window.devicePixelRatio || 2;
  const scale = resolution === 'retina' ? dpr : resolution === 'classic' ? 1 : 0.5;
  const w = Math.round(W * scale), h = Math.round(H * scale);
  const off = document.createElement('canvas');
  off.width = w;
  off.height = h;
  const g = off.getContext('2d');
  g.scale(scale, scale);
  g.fillStyle = '#fff';
  g.fillRect(0, 0, W, H);
  const imgH = 58;
  g.drawImage(img, 0, 0, W, imgH);
  g.fillStyle = '#123';
  g.font = 'bold 11px Verdana, sans-serif';
  g.fillText('Welcome to my page!', 6, imgH + 15);
  g.fillStyle = '#0033cc';
  g.font = '10px Verdana, sans-serif';
  g.fillText('Click here for more', 6, imgH + 29);

  const levels = { gifImages: 6, thousands: 32, websafe: 6, websafeDither: 6 }[colors];
  if (levels) {
    const regionH = colors === 'gifImages' ? Math.round(imgH * scale) : h;
    const data = g.getImageData(0, 0, w, regionH);
    const step = 255 / (levels - 1);
    const dither = colors === 'websafeDither';
    for (let y = 0; y < regionH; y++) {
      for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4;
        const bias = dither ? (BAYER[(y % 4) * 4 + (x % 4)] / 16 - 0.5) * step : 0;
        for (let c = 0; c < 3; c++) {
          data.data[i + c] = Math.round(Math.min(255, Math.max(0, data.data[i + c] + bias)) / step) * step;
        }
      }
    }
    g.putImageData(data, 0, 0);
  }

  canvas.width = W * dpr;
  canvas.height = H * dpr;
  const out = canvas.getContext('2d');
  out.imageSmoothingEnabled = false;
  out.drawImage(off, 0, 0, canvas.width, canvas.height);
}
