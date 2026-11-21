// Dialup start page. Settings come from config.js (generated from the user's preferences).
(() => {
  const cfg = window.DIALUP_START || {};
  const $ = (id) => document.getElementById(id);

  // Search
  const search = cfg.search || { name: 'DuckDuckGo', template: 'https://duckduckgo.com/?q=%s' };
  $('powered').textContent = `Powered by ${search.name}`;
  $('search').addEventListener('submit', (e) => {
    e.preventDefault();
    const q = $('q').value.trim();
    if (q) location.href = search.template.replace('%s', encodeURIComponent(q));
  });

  // Greeting + date
  const now = new Date();
  const hour = now.getHours();
  const part = hour < 5 ? 'Good night' : hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  $('greeting').textContent = cfg.name ? `${part}, ${cfg.name}!` : `${part}!`;
  $('date-line').textContent = `Today is ${now.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}.`;

  const tick = () => { $('clock').textContent = new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' }); };
  tick();
  setInterval(tick, 1000);

  // Tips
  const tips = [
    'Press ⌘L to jump to the Address bar.',
    'Dial-up Mode (⇧⌘D) makes pictures trickle in like it\'s 1999.',
    'You can change your home page and search engine in Settings (⌘,).',
    'Click the little ▾ next to Back to jump several pages at once.',
    'A 56k modem actually topped out at about 53,333 bits per second.',
    'Switch between the Aqua and Luna looks under Settings → Appearance.',
  ];
  $('tip').textContent = tips[Math.floor(Math.random() * tips.length)];

  // Favorite sites
  const list = $('links');
  for (const link of cfg.quickLinks || []) {
    const li = document.createElement('li');
    const a = document.createElement('a');
    a.href = link.url;
    a.textContent = link.title;
    li.append(a);
    list.append(li);
  }
  if (!list.children.length) list.innerHTML = '<li><i>No favorite sites yet.</i></li>';

  // Visitor counter (stored locally, of course)
  let count = 1337;
  try {
    count = Number(localStorage.getItem('visits') || 1336) + 1;
    localStorage.setItem('visits', String(count));
  } catch (_) {}
  $('counter').textContent = String(count).padStart(6, '0');
})();
