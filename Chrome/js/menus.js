// The in-window menu bar (File/Edit/View/Favorites/Tools/Help), Favorites, Links and About.
// Windows-style skins show the menu bar; Mac-style skins hide it (the real macOS menu bar is there).

import { host } from './host.js';
import { showMenu, openDialog } from './overlay.js';

let ctx = null;

/**
 * ctx: { getTab(), getPrefs(), getDialup(), getSounds(), setSounds(on), showSettings(tab), openWizard(), focusAddress() }
 */
export function initMenus(context) {
  ctx = context;
  for (const title of document.querySelectorAll('.menu-title')) {
    title.addEventListener('mousedown', (e) => { e.preventDefault(); openMenu(title); });
  }
  document.getElementById('btn-favorites').addEventListener('click', (e) => {
    const r = e.currentTarget.getBoundingClientRect();
    favoritesMenu(r.left, r.bottom + 1);
  });
  document.getElementById('links-chevron').addEventListener('click', async (e) => {
    const r = e.currentTarget.getBoundingClientRect();
    const links = ctx.getPrefs().quickLinks || [];
    const picked = await showMenu(links.length ? links.map((l, i) => ({ id: String(i), title: l.title }))
      : [{ title: '(Empty)', enabled: false }], r.left, r.bottom + 1);
    if (picked != null) host.call('navigate', { input: links[Number(picked)].url });
  });
}

/** Mac-style bookmarks bar under the toolbar. */
export function renderLinksBar(links = []) {
  const bar = document.getElementById('links-bar');
  bar.replaceChildren(...links.map((link) => {
    const b = document.createElement('button');
    b.textContent = link.title;
    b.dataset.tip = link.url;
    b.addEventListener('click', () => host.call('navigate', { input: link.url }));
    return b;
  }));
}

async function openMenu(title) {
  const r = title.getBoundingClientRect();
  const items = menus[title.dataset.menu]?.();
  if (!items) return;
  title.classList.add('open');
  const picked = await showMenu(items, r.left, r.bottom);
  title.classList.remove('open');
  if (picked != null) run(picked);
}

const menus = {
  file: () => [
    { id: 'action:newWindow', title: 'New Window' },
    { id: 'location', title: 'Open Location…' },
    { separator: true },
    { id: 'action:performClose', title: 'Close' },
  ],
  edit: () => [
    { id: 'action:cut', title: 'Cut' },
    { id: 'action:copy', title: 'Copy' },
    { id: 'action:paste', title: 'Paste' },
    { separator: true },
    { id: 'action:selectAll', title: 'Select All' },
  ],
  view: () => {
    const tab = ctx.getTab();
    return [
      { id: 'stop', title: 'Stop', enabled: !!tab.loading },
      { id: 'reload', title: 'Refresh' },
      { separator: true },
      { id: 'dialup', title: 'Dial-up Mode', checked: !!ctx.getDialup().enabled },
      { id: 'action:toggleFullScreen', title: 'Full Screen' },
    ];
  },
  favorites: () => [...favoritesItems()],
  tools: () => [
    { id: 'settings:general', title: 'Dialup Options…' },
    { id: 'wizard', title: 'Setup Wizard…' },
    { separator: true },
    { id: 'settings:privacy', title: 'Delete Browsing History…' },
    { id: 'sounds', title: 'Sounds', checked: ctx.getSounds() },
  ],
  help: () => [
    { id: 'tips', title: 'Tip of the Day' },
    { separator: true },
    { id: 'about', title: 'About Dialup' },
  ],
};

function favoritesItems() {
  const links = ctx.getPrefs().quickLinks || [];
  return [
    { id: 'fav:add', title: 'Add to Favorites…', enabled: /^https?:/.test(ctx.getTab().url || '') },
    { id: 'settings:startpage', title: 'Organize Favorites…' },
    { separator: true },
    ...(links.length ? links.map((l, i) => ({ id: `fav:${i}`, title: l.title })) : [{ title: '(Empty)', enabled: false }]),
  ];
}

async function favoritesMenu(x, y) {
  const picked = await showMenu(favoritesItems(), x, y);
  if (picked != null) run(picked);
}

function run(id) {
  const [kind, arg] = id.split(':');
  const tab = ctx.getTab();
  if (kind === 'action') host.call('menuAction', { action: arg });
  else if (kind === 'location') ctx.focusAddress();
  else if (kind === 'stop') host.call('stop');
  else if (kind === 'reload') host.call('reload');
  else if (kind === 'dialup') host.call('dialupModeSet', { enabled: !ctx.getDialup().enabled });
  else if (kind === 'settings') ctx.showSettings(arg);
  else if (kind === 'wizard') ctx.openWizard();
  else if (kind === 'sounds') ctx.setSounds(!ctx.getSounds());
  else if (kind === 'about') aboutDialog();
  else if (kind === 'tips') host.call('navigate', { input: 'about:home' });
  else if (kind === 'fav' && arg === 'add') addFavorite(tab);
  else if (kind === 'fav') {
    const link = (ctx.getPrefs().quickLinks || [])[Number(arg)];
    if (link) host.call('navigate', { input: link.url });
  }
}

function addFavorite(tab) {
  const body = document.createElement('div');
  body.className = 'settings';
  body.innerHTML = `
    <div class="icon-row">
      <div class="big-icon" style="background-image:url(img/favorites.svg)"></div>
      <div class="grow">
        <p>Dialup will add this page to your Favorites and your Start Page.</p>
        <label class="row">Name: <input type="text" class="field grow" id="fav-name"></label>
      </div>
    </div>`;
  const input = body.querySelector('#fav-name');
  input.value = tab.title || tab.url;
  openDialog({
    title: 'Add Favorite',
    width: 420,
    body,
    buttons: [{ label: 'OK', value: 'ok', primary: true }, { label: 'Cancel', value: 'cancel', cancel: true }],
    onButton: (v) => { if (v === 'ok') host.call('addFavorite', { title: input.value, url: tab.url }); },
  });
}

function aboutDialog() {
  const body = document.createElement('div');
  body.className = 'about';
  body.innerHTML = `
    <div class="about-banner"><div class="about-logo"></div><div><div class="about-name">Dialup</div><div class="about-tag">Version 1.0 (2003 Edition, built in 2026)</div></div></div>
    <div class="about-text">
      <p>Cipher Strength: 128-bit<br>Product ID: 55555-OEM-0001337-56K<br>Update Versions: SP1; dial-up</p>
      <p>Based on modern WebKit, wearing a 2003 outfit.<br>All artwork is original. No modems were harmed.</p>
      <p class="hint">Warning: this computer program is protected by nostalgia.</p>
    </div>`;
  openDialog({ title: 'About Dialup', width: 400, body, buttons: [{ label: 'OK', value: 'ok', primary: true }] });
}
