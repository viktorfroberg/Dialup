import { host, onEvent } from './host.js';
import { showMenu } from './overlay.js';
import { openSettings } from './settings.js';
import { openWizard } from './wizard.js';

const $ = (id) => document.getElementById(id);
const address = $('address');

let tab = { url: '', title: '', loading: false, progress: 0, canGoBack: false, canGoForward: false, statusText: null };
let hoverUrl = '';
let addressDirty = false; // user has typed something we shouldn't overwrite

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
  $('window-title').textContent = `${tab.title || tab.url || 'Untitled'} - Dialup`;
  renderStatus();
}

function renderStatus() {
  let text;
  const n = itemsRemaining();
  if (dialInText) text = dialInText;
  else if (hoverUrl) text = hoverUrl;
  else if (tab.statusText) text = tab.statusText;
  else if (tab.loading) text = `Opening page ${tab.url}...`;
  else if (n > 0) text = `(${n} item${n === 1 ? '' : 's'} remaining) Downloading picture ${tab.items.url}...`;
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
  const picked = await showMenu(entries.map((e) => ({ id: String(e.offset), title: e.title || e.url })), anchor.left, anchor.bottom + 1);
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
  for (const step of steps) {
    dialInText = step;
    render();
    await new Promise((r) => setTimeout(r, 750));
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

function applyPrefs(prefs = {}) {
  const skin = prefs.skin || 'aqua';
  if (document.body.dataset.skin !== skin) {
    document.body.dataset.skin = skin;
    $('skin-css').href = `skins/${skin}.css`;
  }
}
onEvent('prefs', applyPrefs);

const showSettings = (tabId) => openSettings(tabId, { getCurrentUrl: () => tab.url });
onEvent('openSettings', ({ tab: tabId }) => showSettings(tabId || 'general'));
onEvent('openWizard', () => openWizard());

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
applyPrefs(init?.prefs);
if (init?.prefs && !init.prefs.onboarded) openWizard(); // first run
reportInsets();
