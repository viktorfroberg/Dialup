// Small DOM helpers shared by the chrome's modules.

const ENTITIES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

/** Escapes text for use inside HTML (element content or a quoted attribute). */
export const escape = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ENTITIES[c]);

/** Markup built by `markup` (already escaped), so it can be nested without being escaped twice. */
class SafeHtml {
  constructor(value) { this.value = value; }
  toString() { return this.value; }
}

const render = (value) => {
  if (value instanceof SafeHtml) return value.value;
  if (Array.isArray(value)) return value.map(render).join('');
  return escape(value);
};

/**
 * Tagged template for a piece of markup. Interpolated values are escaped; nested `markup`
 * results and arrays of them are inserted as-is. Use it for reusable snippets inside `html`.
 */
export const markup = (strings, ...values) => new SafeHtml(String.raw({ raw: strings }, ...values.map(render)));

/** Tagged template that returns a DocumentFragment. Same escaping rules as `markup`. */
export function html(strings, ...values) {
  const template = document.createElement('template');
  template.innerHTML = markup(strings, ...values).value.trim();
  return template.content;
}

/** Creates an element with an optional class name and text. */
export function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

/** True for http(s) addresses: pages that can be bookmarked or looked up in the Wayback Machine. */
export const isWeb = (url) => /^https?:/i.test(String(url ?? ''));

let nextId = 0;
/** A document-unique id for ARIA references (aria-labelledby, aria-activedescendant). */
export const uniqueId = (prefix) => `${prefix}-${++nextId}`;
