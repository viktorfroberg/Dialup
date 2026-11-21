// A fake host so the chrome can be developed in any browser:
//   cd Chrome && python3 -m http.server 8000  →  http://localhost:8000/
// Lets skin and toolbar authors iterate without Xcode.

export function createMockHost(dialup) {
  const history = ['https://www.wikipedia.org/'];
  let index = 0;
  let timer = null;
  const tab = { url: history[0], title: 'Wikipedia', loading: false, progress: 0, canGoBack: false, canGoForward: false, statusText: null };

  const win = { key: true, zoomed: false, fullscreen: false };
  const dialupMode = { enabled: false, connection: 'modem56k', colors: 'gifImages', resolution: 'retina', scanlines: true, oldFonts: false, includeChrome: false,
    retroPage: true, squareCorners: true, noShadows: false, noAnimations: false, underlineLinks: false };
  const presets = {
    1998: { enabled: true, connection: 'modem56k', colors: 'gifImages', resolution: 'retina', scanlines: true, oldFonts: true, includeChrome: false,
      retroPage: true, squareCorners: true, noShadows: true, noAnimations: false, underlineLinks: true },
    2003: { enabled: true, connection: 'dsl', colors: 'millions', resolution: 'retina', scanlines: false, oldFonts: false, includeChrome: false,
      retroPage: true, squareCorners: true, noShadows: false, noAnimations: false, underlineLinks: false },
  };
  const prefs = {
    skin: new URLSearchParams(location.search).get('skin') || 'luna',
    onboarded: new URLSearchParams(location.search).has('onboarded'),
    homePage: 'start', searchEngine: 'duckduckgo', name: '',
    quickLinks: [{ title: 'Wikipedia', url: 'https://www.wikipedia.org/' }, { title: 'Neocities', url: 'https://neocities.org/' }],
    // Mirrors Preferences.catalog in Host/App/Preferences.swift (the real source of truth).
    catalog: {
      skins: [{ id: 'luna', name: 'Luna (Windows, 2001)' }, { id: 'aqua', name: 'Aqua (Mac, 2003)' }],
      searchEngines: [{ id: 'duckduckgo', name: 'DuckDuckGo' }, { id: 'google', name: 'Google' }, { id: 'bing', name: 'Bing' }, { id: 'wikipedia', name: 'Wikipedia' }],
      defaultLinks: [{ title: 'Wikipedia', url: 'https://www.wikipedia.org/' }, { title: 'Neocities', url: 'https://neocities.org/' }],
      connectionSpeeds: { modem56k: 53333, isdn: 128000, dsl: 512000, off: 0 },
      pictureCapMs: 2500,
      dialupPresets: {},
    },
  };
  prefs.catalog.dialupPresets = presets;
  const emit = (event, data) => dialup.receive({ event, data });
  const sync = () => {
    tab.url = history[index];
    tab.title = new URL(tab.url).host;
    tab.canGoBack = index > 0;
    tab.canGoForward = index < history.length - 1;
    emit('tab', { ...tab });
  };

  const fakeLoad = () => {
    clearInterval(timer);
    tab.loading = true;
    tab.progress = 0.1;
    sync();
    timer = setInterval(() => {
      tab.progress = Math.min(1, tab.progress + 0.15);
      if (tab.progress >= 1) { tab.loading = false; clearInterval(timer); }
      sync();
    }, 150);
  };

  const showPlaceholder = () => {
    const vp = document.getElementById('viewport');
    if (!vp || vp.childElementCount) return;
    vp.innerHTML = `<div class="mock-page"><b>Mock host</b><span>The page web view renders here in the real app.</span>
      <span>Hover me: <a href="https://example.com/hello">example.com/hello</a></span></div>`;
    const link = vp.querySelector('a');
    link.addEventListener('mouseenter', () => emit('hoverLink', { url: link.href }));
    link.addEventListener('mouseleave', () => emit('hoverLink', { url: '' }));
    link.addEventListener('click', (e) => { e.preventDefault(); go(link.href); });
  };

  const go = (url) => {
    history.splice(index + 1);
    history.push(url);
    index = history.length - 1;
    fakeLoad();
  };

  const resolve = (input) => {
    const s = input.trim();
    if (/^[a-z]+:/i.test(s)) return s;
    if (!/\s/.test(s) && s.includes('.')) return `https://${s}`;
    return `https://duckduckgo.com/?q=${encodeURIComponent(s)}`;
  };

  const commands = {
    ready: () => { queueMicrotask(showPlaceholder); return { apiVersion: 1, tab: { ...tab }, window: { ...win }, dialupMode: { ...dialupMode }, prefs: structuredClone(prefs) }; },
    setInsets: () => null,
    navigate: ({ input }) => { if (input?.trim()) go(resolve(input)); return null; },
    back: () => { if (index > 0) { index--; fakeLoad(); } return null; },
    forward: () => { if (index < history.length - 1) { index++; fakeLoad(); } return null; },
    reload: () => { fakeLoad(); return null; },
    stop: () => { clearInterval(timer); tab.loading = false; sync(); return null; },
    home: () => { go('https://www.wikipedia.org/'); return null; },
    focusPage: () => null,
    history: ({ direction }) => {
      const list = direction === 'forward' ? history.slice(index + 1) : history.slice(0, index).reverse();
      return list.map((url, i) => ({ offset: (i + 1) * (direction === 'forward' ? 1 : -1), title: new URL(url).host, url }));
    },
    goHistory: ({ offset }) => { index = Math.max(0, Math.min(history.length - 1, index + offset)); fakeLoad(); return null; },
    prefsGet: () => structuredClone(prefs),
    prefsSet: (patch) => { Object.assign(prefs, patch, { catalog: prefs.catalog }); emit('prefs', structuredClone(prefs)); return null; },
    overlay: () => null,
    clearData: () => null,
    windowClose: () => null,
    windowMinimize: () => null,
    windowZoom: () => { win.zoomed = !win.zoomed; emit('windowState', { ...win }); return null; },
    windowDrag: () => null,
    titlebarDoubleClick: () => commands.windowZoom(),
    dialupModeGet: () => ({ ...dialupMode }),
    dialupModeSet: (patch) => { Object.assign(dialupMode, patch); emit('dialupMode', { ...dialupMode }); return null; },
    dialupModePreset: ({ id }) => { Object.assign(dialupMode, presets[id] ?? {}); emit('dialupMode', { ...dialupMode }); return null; },
    popupMenu: ({ items }) => {
      const flat = (list) => list.flatMap((i) => (i.items ? flat(i.items) : [i]));
      const choices = flat(items).filter((i) => !i.separator && i.id);
      const answer = prompt(choices.map((c, n) => `${n + 1}. ${c.title}`).join('\n'), '1');
      return choices[Number(answer) - 1]?.id ?? null;
    },
  };

  return {
    isMock: true,
    async call(cmd, args = {}) {
      const fn = commands[cmd];
      if (!fn) { console.warn('mock host: unknown command', cmd); return null; }
      return fn(args);
    },
  };
}
