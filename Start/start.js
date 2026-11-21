// Dialup start page (2004 search engine style). Settings come from config.js (may be {}).
(() => {
  const cfg = window.DIALUP_START || {};
  const $ = (id) => document.getElementById(id);
  const isWeb = (u) => /^https?:\/\//i.test(String(u || ''));

  // Skin class (only the form buttons change per skin)
  const skin = ['luna', 'aqua', 'classic'].includes(cfg.skin) ? cfg.skin : 'luna';
  document.documentElement.classList.add(`skin-${skin}`);

  // The user's web search, with a DuckDuckGo fallback
  const web = cfg.search && isWeb(cfg.search.template) && String(cfg.search.template).includes('%s')
    ? cfg.search : { name: 'DuckDuckGo', template: 'https://duckduckgo.com/?q=%s' };
  const engineName = String(web.name || 'DuckDuckGo').slice(0, 30);
  const host = (() => { try { return new URL(web.template.replace('%s', 'x')).host; } catch (_) { return ''; } })();
  const ddg = /duckduckgo\.com$/.test(host), google = /google\./.test(host), bing = /bing\.com$/.test(host);

  // Tabs: what the box searches
  const tabs = {
    web: { template: web.template, label: engineName },
    images: { template: google ? 'https://www.google.com/search?tbm=isch&q=%s' : bing ? 'https://www.bing.com/images/search?q=%s' : 'https://duckduckgo.com/?q=%s&iax=images&ia=images', label: 'Images' },
    news: { template: google ? 'https://www.google.com/search?tbm=nws&q=%s' : bing ? 'https://www.bing.com/news/search?q=%s' : 'https://duckduckgo.com/?q=%s&iar=news&ia=news', label: 'News' },
    wikipedia: { template: 'https://en.wikipedia.org/w/index.php?search=%s', label: 'Wikipedia' },
    archive: { template: 'https://web.archive.org/web/*/%s', label: 'the Wayback Machine (type an address)' },
  };
  let current = 'web';
  const hint = () => {
    $('hint').textContent = `Searching ${current === 'web' ? `the Web with ${engineName}` : tabs[current].label}`;
  };
  // The current tab is plain bold text, the others are links, so "underline all links" can't
  // make the current one look clickable.
  const renderTabs = () => {
    for (const cell of document.querySelectorAll('.tabs td')) {
      const id = cell.dataset.tab;
      const label = cell.textContent;
      const node = document.createElement(id === current ? 'b' : 'a');
      node.textContent = label;
      if (id === current) node.className = 'on';
      else node.href = `#${id}`;
      cell.replaceChildren(node);
    }
  };
  document.querySelector('.tabs').addEventListener('click', (e) => {
    const link = e.target.closest('a');
    if (!link) return;
    e.preventDefault();
    current = link.closest('td').dataset.tab;
    renderTabs();
    hint();
    $('q').focus();
  });
  hint();

  const go = (template, q) => { location.href = template.replace('%s', current === 'archive' ? q : encodeURIComponent(q)); };
  $('search').addEventListener('submit', (e) => {
    e.preventDefault();
    const q = $('q').value.trim();
    if (q) go(tabs[current].template, q);
  });

  // Surprise Me: our "I'm Feeling Lucky". Empty box: a random page from the old web.
  const surprises = [
    'https://www.spacejam.com/1996/', 'https://neocities.org/browse', 'https://wiby.me/surprise/',
    'https://www.cameronsworld.net/', 'https://theuselessweb.com/', 'https://windows93.net/',
    'https://oldweb.today/', 'https://web.archive.org/web/2004/http://www.google.com/', 'https://www.zombo.com/',
  ];
  $('lucky').addEventListener('click', () => {
    const q = $('q').value.trim();
    if (q && ddg && current === 'web') location.href = `https://duckduckgo.com/?q=${encodeURIComponent('\\' + q)}`;
    else if (q) go(tabs[current].template, q);
    else location.href = surprises[Math.floor(Math.random() * surprises.length)];
  });

  // Greeting + favorites
  const links = (Array.isArray(cfg.quickLinks) ? cfg.quickLinks : []).filter((l) => l && isWeb(l.url));
  if (typeof cfg.name === 'string' && cfg.name.trim()) {
    const h = new Date().getHours();
    const part = h < 5 ? 'Good night' : h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
    $('greeting').textContent = `${part}, ${cfg.name.trim()}.${links.length ? ' Your Favorites:' : ''}`;
  } else if (links.length) {
    $('greeting').textContent = 'Your Favorites:';
  }
  if (links.length) {
    const favs = $('favorites');
    favs.hidden = false;
    links.forEach((link, i) => {
      if (i) favs.append(' - ');
      const a = document.createElement('a');
      a.href = link.url;
      a.textContent = link.title || link.url;
      favs.append(a);
    });
  }

  // Site of the Day + tip, picked by date
  const day = Math.floor(Date.now() / 86400000);
  const sites = [
    ['Space Jam (1996)', 'https://www.spacejam.com/1996/', 'The movie site that never changed.'],
    ["Cameron's World", 'https://www.cameronsworld.net/', 'A collage of the old personal web.'],
    ['Neocities', 'https://neocities.org/browse', 'Thousands of hand-made home pages.'],
    ['Windows 93', 'https://windows93.net/', 'An operating system that never was.'],
    ['Old Web Today', 'https://oldweb.today/', 'Old sites in emulated old browsers.'],
    ['Google in 2004', 'https://web.archive.org/web/2004/http://www.google.com/', 'Search, as it looked back then.'],
  ];
  const [title, url, text] = sites[day % sites.length];
  $('sotd-link').textContent = title;
  $('sotd-link').href = url;
  $('sotd-text').textContent = `- ${text}`;
  const tips = [
    'Press ⌘L to jump to the Address bar.',
    'The Wayback button shows any page as it looked years ago.',
    'Dial-up Mode (⇧⌘D) makes pictures trickle in like it\'s 1999.',
    'Press and hold Back to jump several pages at once.',
    'Use the Archive tab above with an address, like example.com.',
  ];
  $('tip').textContent = tips[day % tips.length];
})();
