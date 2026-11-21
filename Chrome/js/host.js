// Bridge between the chrome UI and the native host.
//   host.call(cmd, args) -> Promise   (chrome → host)
//   onEvent(name, fn)                 (host → chrome, via window.dialup.receive)
// Without a native host (opened in a normal browser) a mock host is used instead.

const listeners = new Map();

export function onEvent(name, fn) {
  if (!listeners.has(name)) listeners.set(name, []);
  listeners.get(name).push(fn);
}

window.dialup = {
  receive(msg) {
    for (const fn of listeners.get(msg?.event) ?? []) {
      try { fn(msg.data ?? {}); } catch (err) { console.error(`dialup event ${msg.event}`, err); }
    }
  },
};

const native = window.webkit?.messageHandlers?.host;

export const host = native
  ? { call: (cmd, args = {}) => native.postMessage({ apiVersion: 1, cmd, args }), isMock: false }
  : (await import('./mock-host.js')).createMockHost(window.dialup);

// Surface chrome errors in the app log (Console.app / terminal), so failures aren't silent.
if (native) {
  const report = (message) => native.postMessage({ apiVersion: 1, cmd: 'log', args: { message: String(message) } }).catch(() => {});
  window.addEventListener('error', (e) => report(`${e.message} (${e.filename}:${e.lineno})`));
  window.addEventListener('unhandledrejection', (e) => report(`Unhandled rejection: ${e.reason?.stack ?? e.reason}`));
  document.addEventListener('securitypolicyviolation', (e) => report(`CSP blocked ${e.violatedDirective}: ${e.blockedURI}`));
}
