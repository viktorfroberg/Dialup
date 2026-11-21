// Skinnable tooltips for chrome elements with data-tip (replaces native title tooltips).
// The chrome sits under the page, so tips are kept inside the chrome area (above the cursor
// when they would otherwise fall onto the page).

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
document.addEventListener('mouseleave', hide);
