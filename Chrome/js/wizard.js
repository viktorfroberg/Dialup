// First-run "Dialup Setup Wizard", in the style of the old Internet Connection Wizard.
// Lets new users pick the look (Windows- or Mac-style), how retro the browsing should feel,
// and a couple of profile basics. Re-run any time from Help → Setup Wizard….

import { host } from './host.js';
import { openDialog } from './overlay.js';

let running = false;

const EXPERIENCES = {
  looks: { enabled: false },
  broadband: { enabled: true, connection: 'dsl', colors: 'millions', resolution: 'retina', scanlines: false, oldFonts: false,
    retroPage: true, squareCorners: true, noShadows: false, noAnimations: false, underlineLinks: false },
  full: { enabled: true, connection: 'modem56k', colors: 'gifImages', resolution: 'retina', scanlines: true, oldFonts: true,
    retroPage: true, squareCorners: true, noShadows: true, noAnimations: false, underlineLinks: true },
};

export async function openWizard() {
  if (running) return;
  running = true;
  const prefs = await host.call('prefsGet');
  const original = { skin: prefs.skin };
  const choice = { skin: prefs.skin || 'luna', experience: 'broadband', name: prefs.name || '', searchEngine: prefs.searchEngine || 'duckduckgo' };
  const engines = prefs.catalog?.searchEngines || [{ id: 'duckduckgo', name: 'DuckDuckGo' }];

  const root = document.createElement('div');
  root.className = 'wizard';
  root.innerHTML = `
    <div class="wizard-banner"><div class="wizard-logo"></div><div class="wizard-brand">Dialup</div></div>
    <div class="wizard-main"><div class="wizard-page"></div></div>
    <div class="wizard-footer">
      <span class="grow"></span>
      <button class="btn" data-nav="back">&lt; Back</button>
      <button class="btn primary" data-nav="next">Next &gt;</button>
      <button class="btn wizard-cancel" data-nav="cancel">Cancel</button>
    </div>`;
  const page = root.querySelector('.wizard-page');
  const back = root.querySelector('[data-nav=back]');
  const next = root.querySelector('[data-nav=next]');

  const steps = [
    () => `
      <h1>Welcome to the Dialup Setup Wizard</h1>
      <p>This wizard helps you set up Dialup so it looks and feels the way you remember the Web.</p>
      <p>You'll choose a look, decide how retro your browsing should be, and tell us a little about yourself.
         You can change everything later in <b>Settings</b>.</p>
      <p class="wizard-continue">To continue, click Next.</p>`,
    () => `
      <h1>Choose your look</h1>
      <p>Which computer did you grow up with? This changes the title bar, buttons, menus and dialogs.</p>
      <div class="wizard-cards">
        ${card('skin', 'luna', 'Windows style', 'Blue title bar, buttons on the right. The classic 2001 look.', 'skin-luna')}
        ${card('skin', 'aqua', 'Mac style', 'Brushed metal and glossy buttons on the left. Very 2003.', 'skin-aqua')}
      </div>
      <p class="hint">Click one to try it. The window behind this wizard changes right away.</p>`,
    () => `
      <h1>How retro should browsing feel?</h1>
      <p>Dial-up Mode makes pictures trickle in and gives pages a period feel. Text always stays readable.</p>
      <div class="wizard-options">
        ${option('experience', 'looks', 'Just the looks', 'Retro browser, modern speed. Dial-up Mode stays off.')}
        ${option('experience', 'broadband', 'Early broadband (2003)', 'Quick, with retro scrollbars and square corners. Recommended.')}
        ${option('experience', 'full', 'The full 1999 experience', '56k modem: pictures load line by line, old fonts, CRT lines.')}
      </div>
      <p class="hint">Switch any time with the <b>Dial-up</b> button in the toolbar.</p>`,
    () => `
      <h1>Tell us about yourself</h1>
      <p>Your Start Page will greet you and search with your favourite search engine.</p>
      <div class="wizard-form">
        <label>Your name: <input type="text" class="field" id="wiz-name" placeholder="Optional" value="${escape(choice.name)}"></label>
        <label>Search with:
          <select class="field" id="wiz-engine">${engines.map((e) => `<option value="${e.id}"${e.id === choice.searchEngine ? ' selected' : ''}>${escape(e.name)}</option>`).join('')}</select>
        </label>
      </div>
      <p class="hint">Your name stays on this computer.</p>`,
    () => `
      <h1>Completing the Dialup Setup Wizard</h1>
      <p>You have successfully completed the Dialup Setup Wizard. You chose:</p>
      <ul class="wizard-summary">
        <li>Look: <b>${choice.skin === 'aqua' ? 'Mac style (Aqua)' : 'Windows style (Luna)'}</b></li>
        <li>Browsing: <b>${{ looks: 'Just the looks', broadband: 'Early broadband (2003)', full: 'The full 1999 experience' }[choice.experience]}</b></li>
        <li>Search: <b>${escape(engines.find((e) => e.id === choice.searchEngine)?.name || 'DuckDuckGo')}</b></li>
      </ul>
      <p class="wizard-continue">To close this wizard and start surfing, click Finish.</p>`,
  ];

  let step = 0;
  const render = () => {
    page.innerHTML = steps[step]();
    back.disabled = step === 0;
    next.textContent = step === steps.length - 1 ? 'Finish' : 'Next >';
    for (const input of page.querySelectorAll('input[type=radio]')) {
      input.checked = choice[input.name] === input.value;
      input.addEventListener('change', () => {
        choice[input.name] = input.value;
        if (input.name === 'skin') host.call('prefsSet', { skin: input.value }); // live preview
      });
    }
    page.querySelector('#wiz-name')?.addEventListener('input', (e) => { choice.name = e.target.value; });
    page.querySelector('#wiz-engine')?.addEventListener('change', (e) => { choice.searchEngine = e.target.value; });
    page.querySelector('input')?.focus();
  };

  const finish = async () => {
    await host.call('prefsSet', { skin: choice.skin, name: choice.name, searchEngine: choice.searchEngine, onboarded: true });
    await host.call('dialupModeSet', EXPERIENCES[choice.experience]);
    dialog.close();
    running = false;
  };
  const cancel = async () => {
    await host.call('prefsSet', { skin: original.skin, onboarded: true });
    dialog.close();
    running = false;
  };

  back.addEventListener('click', () => { if (step > 0) { step--; render(); } });
  next.addEventListener('click', () => { if (step < steps.length - 1) { step++; render(); } else finish(); });
  root.querySelector('[data-nav=cancel]').addEventListener('click', cancel);

  const dialog = openDialog({
    title: 'Dialup Setup Wizard',
    width: 600,
    body: root,
    buttons: [],
    onButton: () => { cancel(); return false; }, // title bar close / Esc
  });
  dialog.root.classList.add('wizard-dialog');
  render();
  dialog.recentre();
}

function card(name, value, title, text, cls) {
  return `<label class="wizard-card ${cls}">
    <input type="radio" name="${name}" value="${value}">
    <div class="mini-window">
      <div class="mini-titlebar"><i></i><i></i><i></i><span>Dialup</span></div>
      <div class="mini-toolbar"><b></b><b></b><b></b><em></em></div>
      <div class="mini-page"><s></s><s></s><s></s></div>
    </div>
    <div class="wizard-card-title">${title}</div>
    <div class="hint">${text}</div>
  </label>`;
}

function option(name, value, title, text) {
  return `<label class="wizard-option"><input type="radio" name="${name}" value="${value}">
    <span><b>${title}</b><br><span class="hint">${text}</span></span></label>`;
}

function escape(v) {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
