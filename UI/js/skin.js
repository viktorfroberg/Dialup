// Switching skins: one stylesheet (skins/<id>.css) on top of base.css.
import { markup } from './dom.js';

/** Shows the given skin. Used for saved preferences and for the live preview in Dialup Options. */
export function applySkin(id = 'luna') {
  if (document.body.dataset.skin === id) return;
  document.body.dataset.skin = id;
  document.getElementById('skin-css').href = `skins/${id}.css`;
}

/** A tiny window preview; wrap it in an element with class skin-<id> to dress it as that skin. */
export const miniWindow = markup`
  <div class="mini-window" aria-hidden="true">
    <div class="mini-titlebar"><i></i><i></i><i></i><span>Dialup</span></div>
    <div class="mini-toolbar"><b></b><b></b><b></b><em></em></div>
    <div class="mini-page"><s></s><s></s><s></s></div>
  </div>`;
