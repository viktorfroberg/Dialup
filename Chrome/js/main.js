import { host, onEvent } from './host.js';
import { showMenu, openDialog } from './overlay.js';
import { openSettings } from './settings.js';
import { openWizard } from './wizard.js';
import { initMenus, renderLinksBar } from './menus.js';
import './tooltips.js';
import { renderTabs } from './tabs.js';

const $ = (id) => document.getElementById(id);
const address = $('address');

let tab = { url: '', title: '', loading: false, progress: 0, canGoBack: false, canGoForward: false, statusText: null };
let hoverUrl = '';
let addressDirty = false; // user has typed something we shouldn't overwrite
let lastUrl = '';
let prefs = {};
let soundsOn = true;
const recentAddresses = []; // this session's addresses, for the address bar dropdown

// ---------- Rendering ----------

let dialInText = null; // dial-up mode "connecting…" sequence overrides the status bar

const itemsRemaining = () => (tab.items && tab.items.remaining) || 0;

function render() {
  $('btn-back').disabled = $('drop-back').disabled = !tab.canGoBack;
  $('btn-forward').disabled = $('drop-forward').disabled = !tab.canGoForward;
  $('btn-stop').disabled = !tab.loading;
  $('throbber').classList.toggle('busy', tab.loading || itemsRemaining() > 0 || dialInText != null);
  let progress = 0;
  if (tab.loading) progress = Math.max(5, Math.round(tab.progress * 100));
  else if (itemsRemaining() > 0) progress = Math.round(100 * (tab.items.total - itemsRemaining()) / tab.items.total);
  $('progress-bar').style.width = `${progress}%`;
  document.documentElement.style.setProperty('--load-progress', progress ? `${progress}%` : '0%');
  if (!addressDirty && address.value !== tab.url) address.value = tab.url;
  $('cell-secure').hidden = !tab.secure;
  $('window-title').textContent = `${tab.title || tab.url || 'Untitled'} - Dialup`;
  renderStatus();
}

function renderStatus() {
  let text;
  const n = itemsRemaining();
  if (dialInText) text = dialInText;
  else if (hoverUrl) text = hoverUrl;
  else if (tab.statusText) text = tab.statusText;
  else if (tab.loading) {
    // The era's status sequence, driven by load progress.
    let host = '';
    try { host = new URL(tab.url).host; } catch (_) {}
    if (tab.progress < 0.15) text = `Finding site: ${host || tab.url}...`;
    else if (tab.progress < 0.4) text = 'Web site found. Waiting for reply...';
    else text = `Opening page ${tab.url}...`;
  }
  else if (n > 0) text = `(${n} item${n === 1 ? '' : 's'} remaining) Downloading picture ${tab.items.url}...`;
  else text = 'Done';
  $('status-text').textContent = text;
}

onEvent('tab', (state) => {
  const navigated = state.url !== lastUrl;
  const started = state.loading && !tab.loading;
  tab = state;
  lastUrl = state.url;
  if (navigated && /^https?:/.test(state.url)) {
    const i = recentAddresses.indexOf(state.url);
    if (i >= 0) recentAddresses.splice(i, 1);
    recentAddresses.unshift(state.url);
    recentAddresses.length = Math.min(recentAddresses.length, 15);
  }
  // A new page: drop text typed but never submitted (unless the user is still typing),
  // and the hover URL of the link that was clicked.
  if (navigated && document.activeElement !== address) addressDirty = false;
  if (navigated || started) hoverUrl = '';
  render();
});
onEvent('hoverLink', ({ url }) => { hoverUrl = url; renderStatus(); });
onEvent('focusAddress', () => {
  if (document.body.classList.contains('overlay-open')) return; // a dialog has focus
  address.focus();
  address.select();
});

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
  const picked = await showMenu(entries.map((e) => ({ id: String(e.offset), title: e.title || e.url })), anchor.left, anchor.bottom + 1);
  if (picked != null) host.call('goHistory', { offset: Number(picked) });
}
$('drop-back').addEventListener('click', (e) => showHistoryMenu('back', e.currentTarget));
$('drop-forward').addEventListener('click', (e) => showHistoryMenu('forward', e.currentTarget));

// Press and hold Back/Forward for the history menu (the Mac way; works in every skin).
for (const [id, direction] of [['btn-back', 'back'], ['btn-forward', 'forward']]) {
  const button = $(id);
  let holdTimer = null;
  let held = false;
  button.addEventListener('mousedown', (e) => {
    if (e.button !== 0 || button.disabled) return;
    held = false;
    holdTimer = setTimeout(() => { held = true; showHistoryMenu(direction, button); }, 500);
  });
  const cancel = () => clearTimeout(holdTimer);
  button.addEventListener('mouseup', cancel);
  button.addEventListener('mouseleave', cancel);
  button.addEventListener('click', (e) => { if (held) { e.stopImmediatePropagation(); held = false; } }, true);
}

// Address bar dropdown: recent addresses and favorites.
$('addr-drop').addEventListener('mousedown', async (e) => {
  e.preventDefault();
  const box = address.closest('.address-box').getBoundingClientRect();
  const links = prefs.quickLinks || [];
  const items = [
    ...recentAddresses.map((url) => ({ id: url, title: url })),
    ...(recentAddresses.length && links.length ? [{ separator: true }] : []),
    ...links.map((l) => ({ id: l.url, title: l.title })),
  ];
  // Like IE: a combo list exactly as wide as the address field, directly under it.
  const picked = await showMenu(items.length ? items : [{ title: '(No recent addresses)', enabled: false }],
    box.left, box.bottom, { minWidth: box.width, className: 'combo-list' });
  if (picked) host.call('navigate', { input: picked });
});

// Wayback: see this page as the Wayback Machine saw it in a given year.
$('btn-wayback').addEventListener('click', async (e) => {
  const r = e.currentTarget.getBoundingClientRect();
  const ok = /^https?:/.test(tab.url || '');
  const years = [1996, 1998, 2000, 2001, 2003, 2005, 2008, 2010, 2015];
  const picked = await showMenu(ok ? [
    { title: 'Show this page as it was in…', enabled: false },
    ...years.map((y) => ({ id: `year:${y}`, title: String(y) })),
    { separator: true },
    { id: 'all', title: 'All snapshots…' },
  ] : [{ title: 'Open a web page first', enabled: false }], r.left, r.bottom + 1);
  if (!picked) return;
  if (picked === 'all') host.call('navigate', { input: `https://web.archive.org/web/*/${tab.url}` });
  else host.call('wayback', { year: Number(picked.split(':')[1]) });
});

// Search field (Mac-style skins)
$('search-field').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && e.target.value.trim()) {
    e.preventDefault();
    host.call('search', { query: e.target.value.trim() });
  }
});

// Status bar: padlock (certificate details) and sound toggle
$('cell-secure').addEventListener('dblclick', async () => {
  const info = await host.call('securityInfo');
  if (!info) return;
  const body = document.createElement('div');
  body.className = 'settings';
  const rows = [['Issued to', info.subject], ['Issued by', info.issuer], ['Web site', info.host], ['Encryption', info.secure ? 'High (128-bit or better)' : 'Mixed content on this page']];
  body.innerHTML = `<div class="icon-row"><div class="big-icon" style="background-image:url(img/tango/lock.svg)"></div><div class="grow"><p><b>Certificate Information</b></p><table class="cert-table"></table><p class="hint">This certificate is intended to guarantee the identity of a remote computer.</p></div></div>`;
  const table = body.querySelector('table');
  for (const [k, v] of rows) {
    const tr = table.insertRow();
    tr.insertCell().textContent = `${k}:`;
    tr.insertCell().textContent = v || '—';
  }
  openDialog({ title: 'Certificate', width: 420, body, buttons: [{ label: 'OK', value: 'ok', primary: true }] });
});
function renderSounds() {
  document.body.classList.toggle('muted', !soundsOn);
  $('cell-sound').dataset.tip = soundsOn ? 'Sounds on. Click to mute.' : 'Sounds off. Click to unmute.';
}
function setSounds(on) {
  soundsOn = on;
  renderSounds();
  host.call('soundSet', { enabled: on });
}
$('cell-sound').addEventListener('click', () => setSounds(!soundsOn));

// ---------- Title bar ----------

function renderWindowState(w = {}) {
  document.body.classList.toggle('inactive', w.key === false);
  document.body.classList.toggle('zoomed', !!w.zoomed);
  document.body.classList.toggle('fullscreen', !!w.fullscreen);
  $('cap-max').dataset.tip = w.zoomed ? 'Restore Down' : 'Maximize';
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

// ---------- Dial-up mode ----------

let dialupMode = {};
const CONNECT_SPEED = { modem56k: '53,333 bps', isdn: '128,000 bps', dsl: '512 Kbps', off: '10 Mbps' };

function renderDialupMode(s, { announce = false } = {}) {
  const turnedOn = announce && s.enabled && !dialupMode.enabled;
  dialupMode = s;
  $('btn-dialup-mode').classList.toggle('on', !!s.enabled);
  document.body.classList.toggle('dialup-mode', !!s.enabled);
  if (turnedOn) dialIn(s);
}
onEvent('dialupMode', (s) => renderDialupMode(s, { announce: true }));

// A little "connecting" moment in the status bar when the mode is switched on.
async function dialIn(s) {
  const steps = s.connection === 'dsl' || s.connection === 'off'
    ? ['Obtaining network address...', `Connected at ${CONNECT_SPEED[s.connection]}`]
    : ['Dialing 555-0199...', 'Verifying username and password...', 'Logging on to network...',
       `Connected at ${CONNECT_SPEED[s.connection] ?? '53,333 bps'}`];
  // The modem handshake sound (host side) lasts ~7 s; pace the messages to match it.
  const pace = s.connection === 'modem56k' || s.connection === 'isdn' ? 1700 : 750;
  for (const step of steps) {
    dialInText = step;
    render();
    await new Promise((r) => setTimeout(r, pace));
    if (!dialupMode.enabled) break;
  }
  dialInText = null;
  render();
}

$('btn-dialup-mode').addEventListener('click', () => host.call('dialupModeSet', { enabled: !dialupMode.enabled }));
$('drop-dialup-mode').addEventListener('click', async (e) => {
  // Read the anchor before any await: e.currentTarget is null once the event has dispatched.
  const anchor = e.currentTarget.closest('.split').getBoundingClientRect();
  const s = await host.call('dialupModeGet');
  const radio = (key, value, title) => ({ id: `set:${key}:${value}`, title, checked: s[key] === value, radio: true });
  const picked = await showMenu([
    { id: 'toggle', title: 'Dial-up Mode', checked: s.enabled },
    { separator: true },
    { id: 'preset:1998', title: '1998: 56k Modem, Old Fonts, CRT' },
    { id: 'preset:2003', title: '2003: Broadband' },
    { separator: true },
    { title: 'Connection', items: [
      radio('connection', 'modem56k', '56k Modem'),
      radio('connection', 'isdn', 'ISDN (128 Kbps)'),
      radio('connection', 'dsl', 'Broadband (512 Kbps)'),
      radio('connection', 'off', 'No Slowdown'),
    ] },
    { id: 'flip:scanlines', title: 'CRT Scanlines', checked: s.scanlines },
    { separator: true },
    { id: 'settings', title: 'Dial-up Mode Settings…' },
  ], anchor.left, anchor.bottom + 1);
  if (picked == null) return;
  const [kind, key, value] = picked.split(':');
  if (kind === 'toggle') host.call('dialupModeSet', { enabled: !s.enabled });
  else if (kind === 'preset') host.call('dialupModePreset', { id: key });
  else if (kind === 'set') host.call('dialupModeSet', { [key]: value, enabled: true });
  else if (kind === 'flip') host.call('dialupModeSet', { [key]: !s[key], enabled: true });
  else if (kind === 'settings') showSettings('dialup');
});

// ---------- Preferences, skins, settings ----------

function applyPrefs(next = {}) {
  prefs = next;
  renderLinksBar(prefs.quickLinks || []);
  const skin = prefs.skin || 'luna';
  if (document.body.dataset.skin !== skin) {
    document.body.dataset.skin = skin;
    $('skin-css').href = `skins/${skin}.css`;
  }
}
onEvent('prefs', applyPrefs);

const showSettings = (tabId) => openSettings(tabId, { getCurrentUrl: () => tab.url });
onEvent('openSettings', ({ tab: tabId }) => showSettings(tabId || 'general'));
onEvent('openWizard', () => openWizard());
onEvent('sounds', ({ enabled }) => { soundsOn = !!enabled; renderSounds(); });

initMenus({
  getTab: () => tab,
  getPrefs: () => prefs,
  getDialup: () => dialupMode,
  getSounds: () => soundsOn,
  setSounds,
  showSettings: (tabId) => showSettings(tabId),
  openWizard: () => openWizard(),
  focusAddress: () => { address.focus(); address.select(); },
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
renderDialupMode(init?.dialupMode ?? {});
renderTabs(init?.tabs);
applyPrefs(init?.prefs);
soundsOn = init?.sounds !== false;
renderSounds();
if (init?.prefs && !init.prefs.onboarded) openWizard(); // first run
reportInsets();
