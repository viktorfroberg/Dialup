// The tab strip. Shown when tabs are turned on and there are 2+ tabs (like Firefox 1.0).
import { host, onEvent } from './host.js';

const strip = document.getElementById('tabstrip');
const list = document.getElementById('tabs-list');

export function renderTabs(state = {}) {
  const tabs = state.tabs || [];
  strip.hidden = state.enabled === false || tabs.length < 2;
  list.replaceChildren(...tabs.map((t) => {
    const item = document.createElement('div');
    item.className = `tab-item${t.id === state.active ? ' active' : ''}${t.loading ? ' loading' : ''}`;
    item.dataset.tip = t.title;
    const icon = document.createElement('i');
    icon.className = 'tab-icon';
    const title = document.createElement('span');
    title.className = 'tab-title';
    title.textContent = t.title || 'Untitled';
    const close = document.createElement('button');
    close.className = 'tab-close';
    close.dataset.tip = 'Close Tab (⌘W)';
    close.addEventListener('click', (e) => { e.stopPropagation(); host.call('closeTab', { id: t.id }); });
    item.append(icon, title, close);
    item.addEventListener('mousedown', (e) => {
      if (e.button === 1) { e.preventDefault(); host.call('closeTab', { id: t.id }); }   // middle-click closes
      else if (e.button === 0 && !e.target.closest('.tab-close')) host.call('selectTab', { id: t.id });
    });
    return item;
  }));
}

onEvent('tabs', renderTabs);
document.getElementById('tab-new').addEventListener('click', () => host.call('newTab'));
// Double-click on the empty strip opens a new tab (Firefox habit).
strip.addEventListener('dblclick', (e) => { if (e.target === strip || e.target === list) host.call('newTab'); });
