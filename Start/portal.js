// Dialup start page. Settings come from config.js (generated from the user's preferences).
// Everything here is local: no network calls besides the links/search the user clicks.
// User-provided strings (name, favorites, guestbook) are only ever inserted with textContent.
(() => {
  'use strict';

  const raw = window.DIALUP_START;
  const cfg = raw && typeof raw === 'object' ? raw : {};
  const $ = (id) => document.getElementById(id);
  const str = (v, max) => (typeof v === 'string' ? v.trim() : '').slice(0, max);

  function el(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  // ---------- Storage (may be unavailable; never throw) ----------
  const store = {
    get(key, fallback) {
      try {
        const v = localStorage.getItem('dialup.' + key);
        return v === null ? fallback : JSON.parse(v);
      } catch (_) { return fallback; }
    },
    set(key, value) {
      try { localStorage.setItem('dialup.' + key, JSON.stringify(value)); return true; } catch (_) { return false; }
    },
  };

  // ---------- Deterministic randomness, seeded by date ----------
  function hash(s) {
    let h = 2166136261;
    for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
    return h >>> 0;
  }
  function rng(seed) {
    let a = hash(String(seed));
    return () => {
      a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const pick = (r, arr) => arr[Math.floor(r() * arr.length)];

  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const dayKey = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
  const dayNumber = Math.floor(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / 86400000);
  const weekNumber = Math.floor((dayNumber + 3) / 7); // Monday-based weeks since 1970
  const longDate = now.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });

  // ---------- Skin ----------
  const skin = str(cfg.skin, 30).toLowerCase();
  if (/^[a-z0-9-]+$/.test(skin)) document.body.classList.add('skin-' + skin);

  // ---------- Search ----------
  const DEFAULT_TEMPLATE = 'https://duckduckgo.com/?q=%s';
  const search = cfg.search && typeof cfg.search === 'object' ? cfg.search : {};
  const template = typeof search.template === 'string' && search.template.includes('%s') && /^https?:\/\//i.test(search.template)
    ? search.template : DEFAULT_TEMPLATE;
  const engineName = str(search.name, 60) || (template === DEFAULT_TEMPLATE ? 'DuckDuckGo' : 'your search engine');
  const searchURL = (q) => template.replace('%s', encodeURIComponent(q));

  $('powered').textContent = `Powered by ${engineName}`;
  $('search').addEventListener('submit', (e) => {
    e.preventDefault();
    const q = $('q').value.trim();
    if (q) location.href = searchURL(q);
  });

  const POPULAR = ['dial-up modem sounds', 'free screensavers', 'MIDI files', 'how to make a home page', 'webrings', 'Y2K bug', 'pixel art', 'virtual pets'];
  const popRand = rng('popular' + dayKey);
  const popular = POPULAR.slice().sort(() => popRand() - 0.5).slice(0, 4);
  const popBox = $('popular');
  popular.forEach((term, i) => {
    if (i) popBox.append(' · ');
    const a = el('a', null, term);
    a.href = searchURL(term);
    popBox.append(a);
  });

  // ---------- Greeting, date, clock ----------
  const name = str(cfg.name, 40);
  const hour = now.getHours();
  const part = hour < 5 ? 'Good night' : hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
  $('greeting').textContent = name ? `${part}, ${name}!` : `${part}, Web surfer!`;
  $('date-line').textContent = `Today is ${longDate}.`;
  $('mast-date').textContent = longDate;
  $('updated').textContent = longDate;

  const clock = $('clock');
  const tick = () => { clock.textContent = new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' }); };
  tick();
  setInterval(tick, 1000);

  // ---------- Site of the Day ----------
  const SITES = [
    { title: 'Space Jam (1996)', url: 'https://www.spacejam.com/1996/', blurb: 'A movie website frozen in amber since the mid-90s. Starfield background, planet buttons and all.' },
    { title: 'Neocities', url: 'https://neocities.org/', blurb: 'Free home pages, just like the old days. Go make one with a guestbook and a hit counter!' },
    { title: 'The Wayback Machine', url: 'https://web.archive.org/', blurb: 'Type in any address and travel back in time to see what it looked like years ago.' },
    { title: 'Windows 93', url: 'https://www.windows93.net/', blurb: 'An operating system that never was, running right inside your browser. Gloriously silly.' },
    { title: 'The Useless Web', url: 'https://theuselessweb.com/', blurb: 'Press one button, land on a pointless website. Repeat until lunch is over.' },
    { title: "Cameron's World", url: 'https://www.cameronsworld.net/', blurb: 'A giant collage of rescued home page bits: GIFs, buttons, banners and heartfelt text.' },
    { title: 'Poolsuite', url: 'https://poolsuite.net/', blurb: 'A sunny retro-desktop music player. Put it on and pretend it is summer.' },
    { title: 'The Million Dollar Homepage', url: 'https://www.milliondollarhomepage.com/', blurb: 'One million pixels, sold for a dollar each. A famous oddity of the early web.' },
    { title: 'GifCities', url: 'https://gifcities.org/', blurb: 'Search a huge pile of animated GIFs rescued from old personal home pages.' },
    { title: 'Wiby', url: 'https://wiby.me/', blurb: 'A search engine just for simple, old-fashioned, lightweight web pages.' },
    { title: 'Pointer Pointer', url: 'https://pointerpointer.com/', blurb: 'Move your mouse, wait a second, and someone in a photo will point right at it.' },
    { title: 'OldWeb.today', url: 'https://oldweb.today/', blurb: 'Surf archived sites inside emulated browsers from decades past.' },
  ];
  const site = SITES[dayNumber % SITES.length];
  const sotd = $('sotd-link');
  sotd.href = site.url;
  sotd.textContent = site.title;
  $('sotd-url').textContent = site.url.replace(/^https?:\/\/(www\.)?/, '').replace(/\/$/, '');
  $('sotd-blurb').textContent = site.blurb;

  // ---------- My Favorite Sites (http/https only) ----------
  function safeHref(u) {
    if (typeof u !== 'string') return null;
    try {
      const x = new URL(u.trim());
      return x.protocol === 'http:' || x.protocol === 'https:' ? x.href : null;
    } catch (_) { return null; }
  }
  const list = $('links');
  const quickLinks = Array.isArray(cfg.quickLinks) ? cfg.quickLinks : [];
  for (const link of quickLinks) {
    if (!link || typeof link !== 'object') continue;
    const href = safeHref(link.url);
    let title = str(link.title, 80);
    if (!title && href) { try { title = new URL(href).hostname; } catch (_) {} }
    if (!title) continue;
    const li = el('li');
    if (href) {
      const a = el('a', null, title);
      a.href = href;
      li.append(a);
    } else {
      li.append(el('span', 'blocked', title + ' (link not allowed)'));
    }
    list.append(li);
  }
  if (!list.children.length) {
    const li = el('li');
    li.append(el('i', null, 'No favorite sites yet. Click "Customize this page" to add some!'));
    list.append(li);
  }

  // ---------- Horoscope ----------
  const SIGNS = ['Aries', 'Taurus', 'Gemini', 'Cancer', 'Leo', 'Virgo', 'Libra', 'Scorpio', 'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces'];
  // Sun sign for a month/day, used as the default before the visitor picks one.
  function signFor(m, d) {
    const starts = [20, 19, 21, 20, 21, 21, 23, 23, 23, 23, 22, 22]; // day each month's second sign starts
    const idx = d >= starts[m] ? (m + 10) % 12 : (m + 9) % 12; // Jan 20+ = Aquarius (10)
    return SIGNS[idx];
  }
  const OPENERS = [
    'The stars are aligned with your modem today.',
    'Mercury is in retrograde, and so is your download.',
    'A comet passes close to your inbox.',
    'Jupiter smiles upon your bookmarks.',
    'The moon is full, and so is your hard drive.',
    'Saturn sends good vibes over a 56k line.',
    'Venus is feeling especially web-safe today.',
  ];
  const EVENTS = [
    'A long-lost chain e-mail will finally make sense.',
    'Someone special will sign your guestbook.',
    'You will discover a webring you never knew you needed.',
    'An unexpected pop-up brings surprising wisdom.',
    'Your page will load completely on the first try.',
    'A mysterious stranger will ask for your A/S/L. Do not answer.',
    'You will find the perfect spinning-globe GIF.',
    'Nobody will pick up the phone while you are online.',
  ];
  const ADVICE = [
    'Avoid clicking anything that blinks.',
    'Defragment your feelings before the weekend.',
    'Back up your floppies, just in case.',
    'Trust your instincts, but also your antivirus.',
    'Today is a good day to update your home page.',
    'Do not forward that e-mail to ten friends.',
    'Turn the MIDI music down a little.',
    'Wear sunscreen. Monitors glow brighter than you think.',
  ];
  const SAFE = ['00', '33', '66', '99', 'CC', 'FF'];
  const signSelect = $('sign');
  SIGNS.forEach((s) => signSelect.append(new Option(s, s)));
  const storedSign = store.get('sign', null);
  signSelect.value = SIGNS.includes(storedSign) ? storedSign : signFor(now.getMonth(), now.getDate());
  function renderHoroscope() {
    const sign = signSelect.value;
    const r = rng(`horo|${dayKey}|${sign}`);
    $('horo-text').textContent = `${pick(r, OPENERS)} ${pick(r, EVENTS)} ${pick(r, ADVICE)}`;
    const color = '#' + pick(r, SAFE) + pick(r, SAFE) + pick(r, SAFE);
    const lucky = $('horo-lucky');
    lucky.textContent = '';
    const sw = el('span', 'swatch');
    sw.style.background = color;
    lucky.append(`Lucky number: ${1 + Math.floor(r() * 99)} · Lucky color: `, sw, ` ${color}`);
  }
  signSelect.addEventListener('change', () => { store.set('sign', signSelect.value); renderHoroscope(); });
  renderHoroscope();

  // ---------- Poll of the Week ----------
  const POLLS = [
    { q: 'How fast is your connection?', a: ['14.4k (patience of a saint)', '28.8k', '56k', 'ISDN, I am fancy', 'Broadband, show-off'] },
    { q: 'Best thing on a home page?', a: ['The hit counter', 'The guestbook', 'Background MIDI', 'Animated flames', 'Under construction signs'] },
    { q: 'How many toolbars do you have installed?', a: ['None', 'One or two', 'Five or six', 'I can no longer see the page'] },
    { q: 'What will you do this weekend?', a: ['Surf the Web', 'Chat in a chat room', 'Burn a mix CD', 'Go outside (what is that?)'] },
    { q: 'Your favorite kind of screensaver?', a: ['Flying toasters-ish', 'Starfield', 'Pipes', '3D text', 'Blank screen, I am serious'] },
    { q: 'How do you organize bookmarks?', a: ['Neat folders', 'One giant list', 'I just remember URLs', 'What are bookmarks?'] },
    { q: 'Best sound in computing?', a: ['The modem handshake', 'The startup chime', 'The "you\'ve got mail" ding', 'Floppy drive grinding'] },
  ];
  const pollIndex = ((weekNumber % POLLS.length) + POLLS.length) % POLLS.length;
  const poll = POLLS[pollIndex];
  const pollKey = 'poll.' + weekNumber;
  $('poll-q').textContent = poll.q;
  const pollBody = $('poll-body');
  const pr = rng('pollvotes|' + weekNumber);
  const baseVotes = poll.a.map(() => 12 + Math.floor(pr() * 880));

  function renderPollForm() {
    pollBody.textContent = '';
    const form = el('form');
    poll.a.forEach((answer, i) => {
      const label = el('label', 'poll-opt');
      const input = document.createElement('input');
      input.type = 'radio';
      input.name = 'pollopt';
      input.value = String(i);
      label.append(input, ' ' + answer);
      form.append(label);
    });
    const vote = el('button', null, 'Vote!');
    vote.type = 'submit';
    const peek = el('button', 'linkish', 'view results');
    peek.type = 'button';
    peek.addEventListener('click', () => renderPollResults(null));
    form.append(vote, ' ', peek);
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const chosen = form.querySelector('input[name="pollopt"]:checked');
      if (!chosen) return;
      const i = Number(chosen.value);
      store.set(pollKey, i);
      renderPollResults(i);
    });
    pollBody.append(form);
  }

  function renderPollResults(mine) {
    pollBody.textContent = '';
    const votes = baseVotes.map((v, i) => v + (i === mine ? 1 : 0));
    const total = votes.reduce((a, b) => a + b, 0);
    const table = el('table', 'poll-res');
    table.cellSpacing = 0;
    poll.a.forEach((answer, i) => {
      const pct = Math.round((votes[i] / total) * 100);
      const row1 = table.insertRow();
      const label = row1.insertCell();
      label.colSpan = 2;
      label.textContent = answer + (i === mine ? ' (your vote)' : '');
      const row2 = table.insertRow();
      const barCell = row2.insertCell();
      barCell.className = 'bar-wrap';
      const bar = el('span', i === mine ? 'bar mine' : 'bar');
      bar.style.width = Math.max(pct, 1) + '%';
      barCell.append(bar);
      const pctCell = row2.insertCell();
      pctCell.textContent = ` ${pct}%`;
    });
    pollBody.append(table, el('div', 'poll-total', `Total votes: ${total.toLocaleString('en-US')}`));
    if (mine == null) {
      const back = el('button', 'linkish', 'back to voting');
      back.type = 'button';
      back.addEventListener('click', renderPollForm);
      pollBody.append(back);
    }
  }

  const myVote = store.get(pollKey, null);
  if (Number.isInteger(myVote) && myVote >= 0 && myVote < poll.a.length) renderPollResults(myVote);
  else renderPollForm();

  // ---------- Fake weather ----------
  const wr = rng('weather|' + dayKey);
  const CONDITIONS = [
    'Partly cloudy with a chance of pop-ups',
    'Scattered spam showers',
    'Clear skies, full bandwidth',
    'Foggy, like a 640×480 JPEG',
    'Light drizzle of banner ads',
    'Heavy cookie accumulation overnight',
    'Sunny with occasional busy signals',
    'Gusty winds of chain letters',
  ];
  const high = 55 + Math.floor(wr() * 30);
  const low = high - 8 - Math.floor(wr() * 12);
  const toC = (f) => Math.round((f - 32) * 5 / 9);
  $('wx-temp').textContent = `${high}°F / ${toC(high)}°C`;
  $('wx-cond').textContent = pick(wr, CONDITIONS);
  $('wx-extra').textContent = `Low ${low}°F · Wind: ${pick(wr, ['14.4', '28.8', '33.6', '56'])} kbps from the ${pick(wr, ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'])} · Chance of buffering: ${10 * (1 + Math.floor(wr() * 10))}%`;

  // ---------- Tip of the Day ----------
  const TIPS = [
    'Press ⌘L to jump to the Address bar.',
    'Dial-up Mode (⇧⌘D) makes pictures trickle in like it\'s 1999.',
    'You can change your home page and search engine in Dialup Options (⌘,).',
    'Click the little ▾ next to Back to jump several pages at once.',
    'A 56k modem actually topped out at about 53,333 bits per second.',
    'Switch between the Aqua, Luna and Classic looks under Dialup Options → Appearance.',
    'Add your own favorite sites with "Customize this page".',
    'Your guestbook, poll vote and hit counter are saved only on this computer.',
  ];
  $('tip').textContent = TIPS[dayNumber % TIPS.length];

  // ---------- Webring ----------
  const RING = [
    'https://neocities.org/',
    'https://www.cameronsworld.net/',
    'https://www.windows93.net/',
    'https://theuselessweb.com/',
    'https://www.spacejam.com/1996/',
    'https://web.archive.org/',
    'https://poolsuite.net/',
    'https://wiby.me/',
    'https://gifcities.org/',
    'https://oldweb.today/',
  ];
  const ri = dayNumber % RING.length;
  $('ring-prev').href = RING[(ri + RING.length - 1) % RING.length];
  $('ring-next').href = RING[(ri + 1) % RING.length];
  $('ring-random').href = RING[Math.floor(Math.random() * RING.length)];

  // ---------- Guestbook (local only, escaped via textContent) ----------
  const GB_MAX = 20;
  const gbList = $('gb-entries');
  const gbName = $('gb-name');
  const gbMsg = $('gb-msg');
  function loadGuestbook() {
    const v = store.get('guestbook', []);
    if (!Array.isArray(v)) return [];
    return v.filter((e) => e && typeof e.name === 'string' && typeof e.msg === 'string').slice(0, GB_MAX);
  }
  let entries = loadGuestbook();
  function renderGuestbook() {
    gbList.textContent = '';
    if (!entries.length) {
      gbList.append(el('div', 'gb-empty', 'Nobody has signed yet. Be the first!'));
      return;
    }
    for (const e of entries) {
      const box = el('div', 'gb-entry');
      box.append(el('span', 'gb-who', e.name.slice(0, 40)));
      const when = Number.isFinite(e.t) ? new Date(e.t).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '';
      if (when) box.append(' ', el('span', 'gb-when', when));
      box.append(el('div', 'gb-msg', e.msg.slice(0, 300)));
      gbList.append(box);
    }
  }
  const savedName = store.get('guestbook.name', '');
  if (typeof savedName === 'string' && savedName) gbName.value = savedName.slice(0, 40);
  else if (name) gbName.value = name;

  $('gb-form').addEventListener('submit', (e) => {
    e.preventDefault();
    const who = str(gbName.value, 40) || 'Anonymous';
    const msg = str(gbMsg.value, 300);
    if (!msg) { gbMsg.focus(); return; }
    entries.unshift({ name: who, msg, t: Date.now() });
    entries = entries.slice(0, GB_MAX);
    const ok = store.set('guestbook', entries);
    store.set('guestbook.name', who);
    $('gb-note').textContent = ok
      ? 'Thanks for signing! Entries are saved only on this computer. Max 20.'
      : 'Thanks! (This browser would not save it, so it will vanish when you leave.)';
    gbMsg.value = '';
    renderGuestbook();
  });
  $('gb-clear').addEventListener('click', () => {
    if (!entries.length || !confirm('Erase every guestbook entry?')) return;
    entries = [];
    store.set('guestbook', entries);
    renderGuestbook();
  });
  renderGuestbook();

  // ---------- Hit counter (stored locally, of course) ----------
  let count = 1337;
  try {
    const prev = parseInt(localStorage.getItem('visits'), 10);
    count = (Number.isFinite(prev) && prev >= 0 ? prev : 1336) + 1;
    localStorage.setItem('visits', String(count));
  } catch (_) {}
  const counter = $('counter');
  counter.textContent = '';
  for (const d of String(count).padStart(6, '0')) counter.append(el('span', 'digit', d));
})();
