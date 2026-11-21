// Dialup start page. Settings come from config.js (generated from your preferences; may be {}).
(() => {
  const cfg = window.DIALUP_START || {};
  const $ = (id) => document.getElementById(id);
  const isWeb = (url) => /^https?:\/\//i.test(String(url || ''));

  // Search with the user's engine (falls back to DuckDuckGo).
  const search = cfg.search && isWeb(cfg.search.template) && String(cfg.search.template).includes('%s')
    ? cfg.search : { name: 'DuckDuckGo', template: 'https://duckduckgo.com/?q=%s' };
  const engineName = typeof search.name === 'string' && search.name.trim() ? search.name.trim().slice(0, 40) : 'your search engine';
  $('engine').textContent = engineName;

  // Look: follow the browser skin (luna is the default palette).
  const skin = typeof cfg.skin === 'string' ? cfg.skin.toLowerCase() : '';
  document.body.classList.add('skin-' + (skin === 'aqua' || skin === 'classic' ? skin : 'luna'));

  // Today's date in the top bar, the way home pages used to stamp it.
  $('today').textContent = new Date().toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  $('search').addEventListener('submit', (e) => {
    e.preventDefault();
    const q = $('q').value.trim();
    if (q) location.href = search.template.replace('%s', encodeURIComponent(q));
  });

  // A quiet greeting, only if we know your name.
  if (typeof cfg.name === 'string' && cfg.name.trim()) {
    const h = new Date().getHours();
    const part = h < 5 ? 'Good night' : h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
    $('greeting').textContent = `${part}, ${cfg.name.trim().slice(0, 60)}.`;
  }

  // Favourites as a plain row of links.
  const favs = $('favorites');
  const links = (Array.isArray(cfg.quickLinks) ? cfg.quickLinks : []).filter((l) => l && isWeb(l.url));
  if (links.length) favs.hidden = false;
  links.forEach((link, i) => {
    if (i) favs.append(' · ');
    const a = document.createElement('a');
    a.href = link.url;
    a.textContent = (typeof link.title === 'string' && link.title.trim()) || String(link.url);
    favs.append(a);
  });

  // surprise me... a random page from the small, old-fashioned web.
  const surprises = [
    'https://www.spacejam.com/1996/',
    'https://neocities.org/browse',
    'https://wiby.me/surprise/',
    'https://www.cameronsworld.net/',
    'https://theuselessweb.com/',
    'https://windows93.net/',
    'https://oldweb.today/',
    'https://web.archive.org/web/1997/http://www.yahoo.com/',
    'https://www.zombo.com/',
    'https://poolsuite.net/',
  ];
  const surpriseMe = (e) => {
    e.preventDefault();
    location.href = surprises[Math.floor(Math.random() * surprises.length)];
  };
  $('surprise').addEventListener('click', surpriseMe);
  $('ring-random').addEventListener('click', surpriseMe);

  // Site of the Day: picked by date, so it's the same all day.
  const sites = [
    ['Space Jam (1996)', 'https://www.spacejam.com/1996/', 'The movie site that never changed. Still online, still glorious.'],
    ["Cameron's World", 'https://www.cameronsworld.net/', 'A collage of the old personal web, stitched together from GeoCities.'],
    ['Neocities', 'https://neocities.org/browse', 'Thousands of hand-made home pages, alive and well.'],
    ['Windows 93', 'https://windows93.net/', 'An operating system that never was, in your browser.'],
    ['The Useless Web', 'https://theuselessweb.com/', 'One button. Infinite pointless websites.'],
    ['Old Web Today', 'https://oldweb.today/', 'Browse old sites in emulated old browsers.'],
    ['Yahoo! in 1997', 'https://web.archive.org/web/1997/http://www.yahoo.com/', 'The front page of the Web, as the Wayback Machine saw it.'],
  ];
  const day = Math.floor(Date.now() / 86400000);
  const [title, url, text] = sites[day % sites.length];
  $('sotd-link').textContent = title;
  $('sotd-link').href = url;
  $('sotd-text').textContent = text;

  const tips = [
    'Press ⌘L to jump to the Address bar.',
    'Dial-up Mode (⇧⌘D) makes pictures trickle in like it\'s 1999.',
    'The Wayback button shows any page as it looked years ago.',
    'Press and hold Back to jump several pages at once.',
    'A "56k" modem really topped out at about 53,333 bits per second.',
    'Switch looks (Windows, Mac or Classic) in Settings → Appearance.',
  ];
  $('tip').textContent = tips[day % tips.length];

  // Visitor counter (stored locally, of course).
  let count = 1337;
  try {
    count = Number(localStorage.getItem('visits') || 1336) + 1;
    localStorage.setItem('visits', String(count));
  } catch (_) {}
  $('counter').textContent = String(count).padStart(6, '0');
})();
