// The tab strip. Shown when tabs are turned on and there are 2+ tabs (like Firefox 1.0).
// It's an ARIA tablist: the active tab is focusable, ←/→ move between tabs, Enter/Space select.
import { host, onEvent } from './host.js';
import { el } from './dom.js';

const strip = document.getElementById('tabstrip');
const list = document.getElementById('tabs-list');
const tabIdOf = new WeakMap();   // tab element → the host's tab id
list.setAttribute('role', 'tablist');
list.setAttribute('aria-label', 'Open pages');

function tabItem(t, active) {
  const item = el('div', `tab-item${active ? ' active' : ''}${t.loading ? ' loading' : ''}`);
  tabIdOf.set(item, t.id);
  item.dataset.tip = t.title;
  item.setAttribute('role', 'tab');
  item.setAttribute('aria-selected', String(active));
  item.tabIndex = active ? 0 : -1;

  const close = el('button', 'tab-close');
  close.tabIndex = -1;   // closing from the keyboard is ⌘W
  close.dataset.tip = 'Close Tab (⌘W)';
  close.addEventListener('click', (e) => { e.stopPropagation(); host.call('closeTab', { id: t.id }); });

  item.append(el('i', 'tab-icon'), el('span', 'tab-title', t.title || 'Untitled'), close);
  item.addEventListener('mousedown', (e) => {
    if (e.button === 1) { e.preventDefault(); host.call('closeTab', { id: t.id }); }   // middle-click closes
    else if (e.button === 0 && !e.target.closest('.tab-close')) host.call('selectTab', { id: t.id });
  });
  return item;
}

export function renderTabs(state = {}) {
  const tabs = state.tabs || [];
  const hadFocus = list.contains(document.activeElement);
  strip.hidden = state.enabled === false || tabs.length < 2;
  list.replaceChildren(...tabs.map((t) => tabItem(t, t.id === state.active)));
  if (hadFocus) list.querySelector('[aria-selected=true]')?.focus();
}

list.addEventListener('keydown', (e) => {
  const items = [...list.querySelectorAll('[role=tab]')];
  const i = items.indexOf(document.activeElement);
  if (i < 0) return;
  if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
    e.preventDefault();
    const next = items[(i + (e.key === 'ArrowRight' ? 1 : -1) + items.length) % items.length];
    items[i].tabIndex = -1;
    next.tabIndex = 0;
    next.focus();
  } else if (e.key === 'Enter' || e.key === ' ') {
    e.preventDefault();
    host.call('selectTab', { id: tabIdOf.get(items[i]) });
  }
});

onEvent('tabs', renderTabs);
document.getElementById('tab-new').addEventListener('click', () => host.call('newTab'));
// Double-click on the empty strip opens a new tab (Firefox habit).
strip.addEventListener('dblclick', (e) => { if (e.target === strip || e.target === list) host.call('newTab'); });
