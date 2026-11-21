// Edit → Find (⌘F): an IE-style Find dialog. ⌘G / ⇧⌘G repeat the last search without it.
// Searching itself happens in the host (WKWebView find), which answers with a `findResult` event.

import { host, onEvent } from './host.js';
import { openDialog } from './overlay.js';
import { el, html } from './dom.js';

let last = { text: '', caseSensitive: false, backwards: false };
let note = null; // the open dialog's result line, if any

export function openFind() {
  const body = el('div', 'settings find-dialog');
  body.append(html`
    <label class="row">Find what: <input type="text" class="field grow" id="find-text" spellcheck="false"></label>
    <div class="row find-options">
      <label class="choice"><input type="checkbox" id="find-case"> Match case</label>
      <fieldset class="find-direction"><legend>Direction</legend>
        <label class="choice"><input type="radio" name="find-dir" value="up"> Up</label>
        <label class="choice"><input type="radio" name="find-dir" value="down" checked> Down</label>
      </fieldset>
    </div>
    <p class="hint find-note" role="status"></p>`);
  const input = body.querySelector('#find-text');
  input.value = last.text;
  body.querySelector('#find-case').checked = last.caseSensitive;
  if (last.backwards) body.querySelector('input[value=up]').checked = true;
  note = body.querySelector('.find-note');

  const dialog = openDialog({
    title: 'Find',
    width: 380,
    body,
    buttons: [{ label: 'Find Next', value: 'next', primary: true }, { label: 'Cancel', value: 'cancel', cancel: true }],
    onButton: (value) => {
      if (value !== 'next') { note = null; return true; }
      last = {
        text: input.value,
        caseSensitive: body.querySelector('#find-case').checked,
        backwards: body.querySelector('input[name=find-dir]:checked').value === 'up',
      };
      search();
      return false; // stays open, like the original
    },
  });
  input.select();
  return dialog;
}

function search(backwards = last.backwards) {
  if (!last.text) { openFind(); return; }
  host.call('find', { text: last.text, backwards, caseSensitive: last.caseSensitive });
}

onEvent('openFind', () => openFind());
// ⌘G repeats in the dialog's direction; ⇧⌘G goes the other way.
onEvent('findAgain', ({ backwards }) => search(backwards ? !last.backwards : last.backwards));
onEvent('findResult', ({ found }) => {
  if (note?.isConnected) note.textContent = found ? '' : `Dialup has finished searching the page. "${last.text}" was not found.`;
  else if (!found) host.call('sound', { name: 'ding' });
});
