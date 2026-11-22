// Skinnable tooltips for chrome elements with data-tip (replaces native title tooltips).
// The chrome sits under the page, so tips are kept inside the chrome area (above the cursor
// when they would otherwise fall onto the page).

import { onEvent } from './host.js';

const tip = document.getElementById('tooltip');
let timer = null;
let current = null;

const delay = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--tip-delay')) || 500;

function hide() {
  clearTimeout(timer);
  timer = null;
  current = null;
  tip.classList.remove('show');
}

function showFor(target, x, y) {
  tip.textContent = target.dataset.tip;
  tip.classList.add('show');
  const viewport = document.getElementById('viewport').getBoundingClientRect();
  const w = tip.offsetWidth, h = tip.offsetHeight;
  let top = y + 20;
  // Below the cursor would land on the page (hidden under the page view) → show above instead.
  if (top + h > viewport.top && y < viewport.top) top = y - h - 6;
  // In the status bar, always above.
  if (y > viewport.bottom) top = y - h - 8;
  tip.style.left = `${Math.max(2, Math.min(x, innerWidth - w - 4))}px`;
  tip.style.top = `${Math.max(2, top)}px`;
}

document.addEventListener('mouseover', (e) => {
  const target = e.target.closest?.('[data-tip]');
  if (target === current) return;
  hide();
  if (!target || document.body.classList.contains('overlay-open')) return;
  current = target;
  const { clientX, clientY } = e;
  timer = setTimeout(() => showFor(target, clientX, clientY), delay());
});
document.addEventListener('mousedown', hide, true);
// The pointer moved onto the page (which covers the chrome there): no more mouse events reach us.
onEvent('pointerOnPage', hide);
document.addEventListener('mouseleave', hide);

// Icon-only buttons get their tooltip as their accessible name. Buttons whose text label a skin
// may hide (.label) count as icon-only too. Kept in sync when tips change or buttons are added.
function labelFromTip(node) {
  if (!(node instanceof HTMLButtonElement) || node.dataset.tip == null) return;
  if (!node.textContent.trim() || node.querySelector('.label')) node.setAttribute('aria-label', node.dataset.tip);
}
document.querySelectorAll('button[data-tip]').forEach(labelFromTip);
new MutationObserver((records) => {
  for (const record of records) {
    if (record.type === 'attributes') labelFromTip(record.target);
    for (const node of record.addedNodes) {
      if (node.nodeType !== Node.ELEMENT_NODE) continue;
      labelFromTip(node);
      node.querySelectorAll('button[data-tip]').forEach(labelFromTip);
    }
  }
}).observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ['data-tip'] });
