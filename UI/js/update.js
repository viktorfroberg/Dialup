// "Dialup Update": the retro face of the host's software updater (Sparkle). The host sends each
// step as an `update` event; buttons answer with `updateChoice`. See docs/host-api.md.

import { host, onEvent } from './host.js';
import { openDialog } from './overlay.js';
import { html, markup } from './dom.js';

let dialog = null;     // { phase, handle, … } for the open dialog
let rate = null;       // download speed estimate: { time, bytes, bps }

const mb = (bytes) => `${(bytes / 1048576).toFixed(1)} MB`;
const kb = (bytesPerSecond) => `${(bytesPerSecond / 1024).toFixed(bytesPerSecond < 102400 ? 1 : 0)} KB/sec`;

function closeDialog() {
  dialog?.handle.close();
  dialog = null;
}

/** Opens a fresh dialog for a step. A button sends its choice to the host and closes it. */
function show(phase, body, buttons = []) {
  closeDialog();
  const current = { phase };
  current.handle = openDialog({
    title: 'Dialup Update',
    width: 420,
    body,
    buttons,
    onButton: (value) => {
      if (value === 'notes') return false;
      if (dialog === current) dialog = null;
      host.call('updateChoice', { choice: value });
    },
  });
  dialog = current;
  return current;
}

function box(icon, content) {
  return html`<div class="icon-row update-box"><div class="big-icon ${icon}"></div><div class="grow">${content}</div></div>`;
}

function meter(label) {
  return markup`<div class="update-meter field"><div class="update-fill"></div></div><p class="update-detail hint">${label}</p>`;
}

function setMeter(fraction, detail) {
  const root = dialog?.handle.body;
  if (!root) return;
  root.querySelector('.update-fill').style.width = `${Math.round(Math.min(1, Math.max(0, fraction)) * 100)}%`;
  if (detail != null) root.querySelector('.update-detail').textContent = detail;
}

const steps = {
  checking() {
    show('checking', box('icon-update', markup`<p><b>Checking for updates…</b></p>${meter('Contacting the update server')}`),
      [{ label: 'Cancel', value: 'cancel', cancel: true }]);
    dialog.handle.body.querySelector('.update-meter').classList.add('busy');
  },

  found({ version, current, notesURL, downloaded }) {
    const body = box('icon-update', markup`
      <p><b>A new version of Dialup is available!</b></p>
      <p>Dialup ${version} is ready to ${downloaded ? 'install' : 'download'}. You have version ${current}.</p>
      ${notesURL ? markup`<p><a href="#" class="update-notes">What's new in Dialup ${version}?</a></p>` : ''}`);
    show('found', body, [
      { label: downloaded ? 'Install and Restart' : 'Install Update', value: 'install', primary: true },
      { label: 'Remind Me Later', value: 'dismiss', cancel: true },
      { label: 'Skip This Version', value: 'skip' },
    ]);
    dialog.handle.body.querySelector('.update-notes')?.addEventListener('click', (e) => {
      e.preventDefault();
      host.call('newTab', { url: notesURL });
    });
  },

  notFound({ current }) {
    show('notFound', box('icon-update', markup`<p><b>You're up to date!</b></p><p>Dialup ${current} is the newest version available.</p>`),
      [{ label: 'OK', value: 'dismiss', primary: true, cancel: true }]);
  },

  error({ message }) {
    show('error', box('icon-update-error', markup`<p><b>Dialup Update couldn't finish.</b></p><p>${message}</p><p class="hint">Check your connection and try again later.</p>`),
      [{ label: 'OK', value: 'dismiss', primary: true, cancel: true }]);
  },

  downloading({ received = 0, total = 0 }) {
    if (dialog?.phase !== 'downloading') {
      rate = { time: performance.now(), bytes: 0, bps: 0 };
      show('downloading', box('icon-update', markup`<p><b>Downloading the update…</b></p>${meter('Starting download')}`),
        [{ label: 'Cancel', value: 'cancel', cancel: true }]);
    }
    const now = performance.now();
    if (now - rate.time > 500) {
      const bps = ((received - rate.bytes) * 1000) / (now - rate.time);
      rate = { time: now, bytes: received, bps: rate.bps ? rate.bps * 0.7 + bps * 0.3 : bps };
    }
    if (!total) return setMeter(0, `${mb(received)} downloaded`);
    const left = rate.bps ? Math.ceil((total - received) / rate.bps) : null;
    const eta = left == null ? '' : left < 60 ? `, ${left} sec left` : `, ${Math.ceil(left / 60)} min left`;
    setMeter(received / total, `${mb(received)} of ${mb(total)}${rate.bps ? ` at ${kb(rate.bps)}` : ''}${eta}`);
  },

  extracting({ progress = 0 }) {
    if (dialog?.phase !== 'extracting') {
      show('extracting', box('icon-update', markup`<p><b>Checking and unpacking the update…</b></p>${meter('Verifying the digital signature')}`));
    }
    setMeter(progress);
  },

  ready() {
    show('ready', box('icon-update', markup`<p><b>The update is ready to install.</b></p><p>Dialup will close, install the new version and open again.</p>`), [
      { label: 'Install and Restart', value: 'install', primary: true },
      { label: 'Later', value: 'dismiss', cancel: true },
    ]);
  },

  installing() {
    show('installing', box('icon-update', markup`<p><b>Installing the update…</b></p>${meter('Dialup will restart in a moment')}`));
    dialog.handle.body.querySelector('.update-meter').classList.add('busy');
  },

  dismiss: closeDialog,
};

onEvent('update', (data) => steps[data.phase]?.(data));

/** Help → Check for Updates… */
export function checkForUpdates() {
  host.call('checkForUpdates');
}
