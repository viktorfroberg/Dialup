// Retro menus and dialogs, drawn in HTML so skins can style them.
// While one is open, the host raises the (transparent) chrome above the page, so menus can
// cover the page without being clipped. Everything here is skinnable via CSS classes:
//   .menu .menu-item .menu-sep .menu-check .menu-label .menu-arrow
//   .dialog .dialog-titlebar .dialog-body .dialog-buttons .btn .tabs .tab .tab-panel

import { host } from './host.js';

const layer = document.getElementById('overlay');
let openCount = 0;

function acquire() {
  if (openCount++ === 0) {
    document.body.classList.add('overlay-open');
    host.call('overlay', { open: true });
  }
}

function release() {
  openCount = Math.max(0, openCount - 1);
  if (openCount === 0) {
    document.body.classList.remove('overlay-open');
    host.call('overlay', { open: false });
  }
}

const el = (tag, cls, text) => {
  const node = document.createElement(tag);
  if (cls) node.className = cls;
  if (text != null) node.textContent = text;
  return node;
};

/**
 * Shows a menu at (x, y) in window coordinates.
 * items: [{ id, title, enabled?, checked?, radio?, separator?, items? }]  (items = submenu)
 * Resolves with the picked id, or null.
 */
export function showMenu(items, x, y) {
  return new Promise((resolve) => {
    acquire();
    const shield = el('div', 'menu-shield');
    layer.append(shield);
    const menus = [];
    let done = false;

    const close = (value) => {
      if (done) return;
      done = true;
      document.removeEventListener('keydown', onKey, true);
      shield.remove();
      menus.forEach((m) => m.remove());
      release();
      resolve(value ?? null);
    };
    shield.addEventListener('mousedown', (e) => { e.preventDefault(); close(null); });

    const trim = (level) => { while (menus.length > level) menus.pop().remove(); };
    const rows = (menu) => [...menu.querySelectorAll(':scope > .menu-item:not(.disabled)')];
    const setActive = (menu, row) => {
      menu.querySelectorAll(':scope > .active').forEach((r) => r.classList.remove('active'));
      if (row) row.classList.add('active');
    };

    function openSub(row, level) {
      const r = row.getBoundingClientRect();
      const sub = build(row._item.items, level + 1);
      const w = sub.offsetWidth;
      const left = r.right + w - 2 > innerWidth ? r.left - w + 2 : r.right - 2;
      place(sub, left, r.top - 3);
      return sub;
    }

    function build(list, level) {
      trim(level);
      const menu = el('div', 'menu');
      menu.setAttribute('role', 'menu');
      for (const item of list) {
        if (item.separator) { menu.append(el('div', 'menu-sep')); continue; }
        const row = el('div', 'menu-item');
        row._item = item;
        if (item.enabled === false) row.classList.add('disabled');
        if (item.items) row.classList.add('has-sub');
        if (item.checked) row.classList.add(item.radio ? 'radio' : 'checked');
        row.append(el('span', 'menu-check'), el('span', 'menu-label', item.title), el('span', 'menu-arrow'));
        row.addEventListener('mouseenter', () => {
          setActive(menu, row);
          trim(level + 1);
          if (item.items && item.enabled !== false) openSub(row, level);
        });
        row.addEventListener('mouseup', () => {
          if (item.enabled === false || item.items) return;
          close(item.id);
        });
        menu.append(row);
      }
      layer.append(menu);
      menus.push(menu);
      return menu;
    }

    function place(menu, left, top) {
      const w = menu.offsetWidth, h = menu.offsetHeight;
      menu.style.left = `${Math.max(2, Math.min(left, innerWidth - w - 2))}px`;
      menu.style.top = `${Math.max(2, Math.min(top, innerHeight - h - 2))}px`;
    }

    function onKey(e) {
      const menu = menus[menus.length - 1];
      const list = rows(menu);
      const active = menu.querySelector(':scope > .active');
      const index = list.indexOf(active);
      const stop = () => { e.preventDefault(); e.stopPropagation(); };
      if (e.key === 'Escape') { stop(); if (menus.length > 1) trim(menus.length - 1); else close(null); }
      else if (e.key === 'ArrowDown') { stop(); setActive(menu, list[(index + 1) % list.length]); }
      else if (e.key === 'ArrowUp') { stop(); setActive(menu, list[(index - 1 + list.length) % list.length]); }
      else if (e.key === 'ArrowRight' && active?._item.items) { stop(); const sub = openSub(active, menus.length - 1); setActive(sub, rows(sub)[0]); }
      else if (e.key === 'ArrowLeft' && menus.length > 1) { stop(); trim(menus.length - 1); }
      else if (e.key === 'Enter' && active) {
        stop();
        if (active._item.items) { const sub = openSub(active, menus.length - 1); setActive(sub, rows(sub)[0]); }
        else close(active._item.id);
      }
    }
    document.addEventListener('keydown', onKey, true);

    place(build(items, 0), x, y);
  });
}

/**
 * Opens a retro dialog window inside the browser window.
 * buttons: [{ label, value, primary?, cancel? }]. onButton(value) may return false to keep it open.
 * Returns { root, body, close }.
 */
export function openDialog({ title, width = 480, body, buttons = [{ label: 'OK', value: 'ok', primary: true }], onButton }) {
  acquire();
  const backdrop = el('div', 'dialog-backdrop');
  const dialog = el('div', 'dialog');
  dialog.style.width = `${width}px`;
  dialog.setAttribute('role', 'dialog');

  const bar = el('div', 'dialog-titlebar');
  const closeBtn = el('button', 'cap cap-close');
  closeBtn.title = 'Close';
  bar.append(el('span', 'dialog-title', title), el('span', 'dialog-caps'));
  bar.lastChild.append(closeBtn);

  const content = el('div', 'dialog-body');
  if (body) content.append(body);

  const footer = el('div', 'dialog-buttons');
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    document.removeEventListener('keydown', onKey, true);
    backdrop.remove();
    release();
  };
  const press = async (value) => {
    const keep = onButton ? await onButton(value) : undefined;
    if (keep !== false) close();
  };
  for (const b of buttons) {
    const button = el('button', `btn${b.primary ? ' primary' : ''}`, b.label);
    button.addEventListener('click', () => press(b.value));
    footer.append(button);
  }
  const cancelValue = buttons.find((b) => b.cancel)?.value ?? 'cancel';
  closeBtn.addEventListener('click', () => press(cancelValue));

  dialog.append(bar, content, footer);
  backdrop.append(dialog);
  layer.append(backdrop);

  // Centre, then allow dragging by the title bar (inside the browser window).
  const centre = () => {
    dialog.style.left = `${Math.max(8, (innerWidth - dialog.offsetWidth) / 2)}px`;
    dialog.style.top = `${Math.max(8, (innerHeight - dialog.offsetHeight) / 2.4)}px`;
  };
  centre();
  bar.addEventListener('mousedown', (e) => {
    if (e.button !== 0 || e.target.closest('button')) return;
    e.preventDefault();
    const startX = e.clientX - dialog.offsetLeft, startY = e.clientY - dialog.offsetTop;
    const move = (ev) => {
      dialog.style.left = `${Math.min(innerWidth - 60, Math.max(-dialog.offsetWidth + 80, ev.clientX - startX))}px`;
      dialog.style.top = `${Math.min(innerHeight - 30, Math.max(0, ev.clientY - startY))}px`;
    };
    const up = () => { removeEventListener('mousemove', move); removeEventListener('mouseup', up); };
    addEventListener('mousemove', move);
    addEventListener('mouseup', up);
  });

  function onKey(e) {
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); press(cancelValue); }
    else if (e.key === 'Enter' && !(e.target instanceof HTMLTextAreaElement) && !(e.target instanceof HTMLButtonElement)) {
      const primary = buttons.find((b) => b.primary);
      if (primary) { e.preventDefault(); press(primary.value); }
    }
  }
  document.addEventListener('keydown', onKey, true);

  const firstField = dialog.querySelector('input, select, textarea, button.btn.primary');
  setTimeout(() => firstField?.focus(), 0);
  return { root: dialog, body: content, close, recentre: centre };
}

/** Small message box: resolves true for OK, false for Cancel. */
export function confirmBox(title, message, okLabel = 'OK') {
  return new Promise((resolve) => {
    const body = el('div', 'message-box');
    body.append(el('div', 'message-icon'), el('p', null, message));
    openDialog({
      title,
      width: 380,
      body,
      buttons: [{ label: okLabel, value: true, primary: true }, { label: 'Cancel', value: false, cancel: true }],
      onButton: (v) => resolve(v === true),
    });
  });
}
