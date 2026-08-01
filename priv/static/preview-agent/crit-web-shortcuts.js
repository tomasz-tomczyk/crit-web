// Crit Web-only shortcut forwarding for sandboxed preview iframes.
'use strict';
(function () {
  var script = document.currentScript;
  if (!script || !script.src) return;

  var parentOrigin;
  try { parentOrigin = new URL(script.src).origin; } catch (_) { return; }

  function isTextInput(el) {
    if (!el || !el.tagName) return false;
    var tag = el.tagName.toUpperCase();
    return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || el.isContentEditable;
  }

  function isInteractive(el) {
    return !!(el && el.closest && el.closest(
      'button, a[href], summary, [role="button"], [role="link"], [role="radio"], [role="checkbox"], [role="switch"], [role="tab"], [role="menuitem"], [role="option"], [role="slider"]'
    ));
  }

  document.addEventListener('keydown', function (event) {
    if (isTextInput(event.target)) return;
    if (isInteractive(event.target) && [
      ' ', 'Enter', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Home', 'End'
    ].indexOf(event.key) !== -1) return;

    try {
      window.parent.postMessage({
        type: 'crit-web-shortcut-key',
        key: event.key,
        code: event.code,
        ctrlKey: event.ctrlKey,
        altKey: event.altKey,
        shiftKey: event.shiftKey,
        metaKey: event.metaKey,
      }, parentOrigin);
    } catch (_) { /* noop */ }
  }, true);
})();
