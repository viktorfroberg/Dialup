// A fake host so the chrome can be developed in any browser:
//   cd Chrome && python3 -m http.server 8000  →  http://localhost:8000/
// Lets skin and toolbar authors iterate without Xcode.

export function createMockHost(kikare) {
  const history = ['https://www.wikipedia.org/'];
  let index = 0;
  let timer = null;
  const tab = { url: history[0], title: 'Wikipedia', loading: false, progress: 0, canGoBack: false, canGoForward: false, statusText: null };

  const emit = (event, data) => kikare.receive({ event, data });
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
    ready: () => { queueMicrotask(showPlaceholder); return { apiVersion: 1, tab: { ...tab } }; },
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
    popupMenu: ({ items }) => {
      const choices = items.filter((i) => !i.separator);
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
