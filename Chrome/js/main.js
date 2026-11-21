import { host, onEvent } from './host.js';

const $ = (id) => document.getElementById(id);
const address = $('address');

let tab = { url: '', title: '', loading: false, progress: 0, canGoBack: false, canGoForward: false, statusText: null };
let hoverUrl = '';
let addressDirty = false; // user has typed something we shouldn't overwrite

// ---------- Rendering ----------

function render() {
  $('btn-back').disabled = $('drop-back').disabled = !tab.canGoBack;
  $('btn-forward').disabled = $('drop-forward').disabled = !tab.canGoForward;
  $('btn-stop').disabled = !tab.loading;
  $('throbber').classList.toggle('busy', tab.loading);
  $('progress-bar').style.width = tab.loading ? `${Math.max(5, Math.round(tab.progress * 100))}%` : '0';
  if (!addressDirty && address.value !== tab.url) address.value = tab.url;
  $('window-title').textContent = `${tab.title || tab.url || 'Untitled'} - Dialup`;
  renderStatus();
}

function renderStatus() {
  let text;
  if (hoverUrl) text = hoverUrl;
  else if (tab.statusText) text = tab.statusText;
  else if (tab.loading) text = `Opening page ${tab.url}...`;
  else text = 'Done';
  $('status-text').textContent = text;
}

onEvent('tab', (state) => { tab = state; render(); });
onEvent('hoverLink', ({ url }) => { hoverUrl = url; renderStatus(); });
onEvent('focusAddress', () => { address.focus(); address.select(); });

// ---------- Address bar ----------

function go() {
  addressDirty = false;
  host.call('navigate', { input: address.value });
}

address.addEventListener('input', () => { addressDirty = true; });
address.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    e.preventDefault();
    go();
  } else if (e.key === 'Escape') {
    e.preventDefault();
    if (addressDirty) {           // first Esc: revert what was typed
      addressDirty = false;
      address.value = tab.url;
      address.select();
    } else {                      // second Esc: hand focus back to the page
      host.call('focusPage');
    }
  }
});
address.addEventListener('focus', () => requestAnimationFrame(() => address.select()));
$('btn-go').addEventListener('click', go);

// ---------- Buttons ----------

$('btn-back').addEventListener('click', () => host.call('back'));
$('btn-forward').addEventListener('click', () => host.call('forward'));
$('btn-stop').addEventListener('click', () => host.call('stop'));
$('btn-reload').addEventListener('click', () => host.call('reload'));
$('btn-home').addEventListener('click', () => host.call('home'));

async function showHistoryMenu(direction, button) {
  const entries = await host.call('history', { direction });
  if (!entries?.length) return;
  const anchor = button.closest('.split').getBoundingClientRect();
  const picked = await host.call('popupMenu', {
    items: entries.map((e) => ({ id: String(e.offset), title: e.title || e.url })),
    x: anchor.left,
    y: anchor.bottom + 2,
  });
  if (picked != null) host.call('goHistory', { offset: Number(picked) });
}
$('drop-back').addEventListener('click', (e) => showHistoryMenu('back', e.currentTarget));
$('drop-forward').addEventListener('click', (e) => showHistoryMenu('forward', e.currentTarget));

// ---------- Title bar ----------

function renderWindowState(w = {}) {
  document.body.classList.toggle('inactive', w.key === false);
  document.body.classList.toggle('zoomed', !!w.zoomed);
  document.body.classList.toggle('fullscreen', !!w.fullscreen);
  $('cap-max').title = w.zoomed ? 'Restore Down' : 'Maximize';
}
onEvent('windowState', renderWindowState);

$('titlebar').addEventListener('mousedown', (e) => {
  if (e.button !== 0 || e.target.closest('button')) return;
  if (e.detail === 2) host.call('titlebarDoubleClick');
  else host.call('windowDrag');
});
$('cap-min').addEventListener('click', () => host.call('windowMinimize'));
$('cap-max').addEventListener('click', () => host.call('windowZoom'));
$('cap-close').addEventListener('click', () => host.call('windowClose'));

// ---------- Extreme mode ----------

let extreme = {};
function renderExtreme(s) {
  extreme = s;
  $('btn-extreme').classList.toggle('on', !!s.enabled);
  document.body.classList.toggle('extreme', !!s.enabled);
}
onEvent('extreme', renderExtreme);

$('btn-extreme').addEventListener('click', () => host.call('extremeSet', { enabled: !extreme.enabled }));
$('drop-extreme').addEventListener('click', async (e) => {
  const s = await host.call('extremeGet');
  const radio = (key, value, title) => ({ id: `set:${key}:${value}`, title, checked: s[key] === value });
  const anchor = e.currentTarget.closest('.split').getBoundingClientRect();
  const picked = await host.call('popupMenu', {
    x: anchor.left,
    y: anchor.bottom + 2,
    items: [
      { id: 'toggle', title: 'Extreme Mode', checked: s.enabled },
      { separator: true },
      { id: 'preset:1998', title: '1998: 56k on a 15" CRT' },
      { id: 'preset:2003', title: '2003: Broadband at 1024×768' },
      { separator: true },
      { title: 'Colours', items: [
        radio('colors', 'millions', 'Millions of Colours (off)'),
        radio('colors', 'thousands', 'Thousands of Colours (16-bit)'),
        radio('colors', 'websafe', '256 Colours (web-safe)'),
        radio('colors', 'websafeDither', '256 Colours, Dithered'),
      ] },
      { title: 'Resolution', items: [
        radio('resolution', 'retina', 'Retina (off)'),
        radio('resolution', 'classic', 'Classic Pixels'),
        radio('resolution', 'chunky', 'Chunky Pixels'),
      ] },
      { id: 'flip:scanlines', title: 'CRT Scanlines', checked: s.scanlines },
      { id: 'flip:oldFonts', title: 'Old Fonts (may break some icons)', checked: s.oldFonts },
      { id: 'flip:includeChrome', title: 'Apply to Toolbars Too', checked: s.includeChrome },
      { separator: true },
      { title: 'Connection Speed (coming soon)', enabled: false },
    ],
  });
  if (picked == null) return;
  const [kind, key, value] = picked.split(':');
  if (kind === 'toggle') host.call('extremeSet', { enabled: !s.enabled });
  else if (kind === 'preset') host.call('extremePreset', { id: key });
  else if (kind === 'set') host.call('extremeSet', { [key]: value, enabled: true });
  else if (kind === 'flip') host.call('extremeSet', { [key]: !s[key], enabled: true });
});

// ---------- Layout: tell the host where the page goes ----------

const viewport = $('viewport');
let lastInsets = '';
function reportInsets() {
  const r = viewport.getBoundingClientRect();
  const insets = {
    top: Math.round(r.top),
    left: Math.round(r.left),
    right: Math.round(window.innerWidth - r.right),
    bottom: Math.round(window.innerHeight - r.bottom),
  };
  const key = JSON.stringify(insets);
  if (key === lastInsets) return;
  lastInsets = key;
  host.call('setInsets', insets);
}
new ResizeObserver(reportInsets).observe(viewport);
window.addEventListener('resize', reportInsets);

// The chrome is an app, not a page: no context menu except in text fields.
document.addEventListener('contextmenu', (e) => {
  if (!(e.target instanceof HTMLInputElement)) e.preventDefault();
});

// ---------- Start ----------

const init = await host.call('ready');
if (init?.tab) { tab = init.tab; render(); }
renderWindowState(init?.window);
renderExtreme(init?.extreme ?? {});
reportInsets();
