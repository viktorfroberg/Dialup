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
reportInsets();
