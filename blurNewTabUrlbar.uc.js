(function () {
    function init() {
        gBrowser.tabContainer.addEventListener("TabOpen", () => {
            requestAnimationFrame(() => {
                gBrowser.selectedBrowser.focus();
            });
        });
    }
    if (document.readyState === "complete") {
        init();
    } else {
        window.addEventListener("DOMContentLoaded", init);
    }
})();

