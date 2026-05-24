// ==UserScript==
// @name            Blur New Tab Urlbar
// @description     Focus the page instead of the urlbar when opening a new tab
// @author          nhatt
// ==/UserScript==

function init() {
  if (typeof gBrowser !== "undefined" && gBrowser.tabContainer) {
    gBrowser.tabContainer.addEventListener("TabOpen", () => {
      requestAnimationFrame(() => {
        if (gBrowser.selectedBrowser) {
          gBrowser.selectedBrowser.focus();
        }
      });
    });
  }
}

if (document.readyState === "complete") {
  init();
} else {
  window.addEventListener("DOMContentLoaded", init);
}
