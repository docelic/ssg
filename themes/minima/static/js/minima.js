// Colour-scheme switch, text selectability, and comment-widget theme sync.
// Configuration comes from window.minima, set inline in the page head.
(function () {
  var cfg = window.minima || {};
  var LIGHT = cfg.theme === "system" ? "light" : (cfg.theme || "light");
  var DARK = "dark";
  var icons = cfg.switch || ["🌚", "🌝"];
  var schemes = ["light", "dark", "sand", "rock"];

  function current() {
    try { return localStorage.getItem("theme") || LIGHT; } catch (e) { return LIGHT; }
  }

  function apply(next) {
    var html = document.documentElement;
    schemes.forEach(function (s) { html.classList.remove(s); });
    html.classList.add(next);
    try { localStorage.setItem("theme", next); } catch (e) {}
    var toggler = document.getElementById("theme-switch");
    if (toggler) toggler.textContent = next === LIGHT ? icons[1] : icons[0];
    syncComments(next);
  }

  function syncComments(theme) {
    var dark = theme === DARK;
    var utterances = document.querySelector("iframe.utterances-frame");
    if (utterances) {
      utterances.contentWindow.postMessage({type: "set-theme", theme: dark ? "github-dark" : "github-light"}, "https://utteranc.es");
    }
    var giscus = document.querySelector("iframe.giscus-frame");
    if (giscus) {
      giscus.contentWindow.postMessage({giscus: {setConfig: {theme: dark ? "dark" : "light"}}}, "https://giscus.app");
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    apply(current());
    var toggler = document.getElementById("theme-switch");
    if (toggler) {
      toggler.addEventListener("click", function () {
        apply(current() === LIGHT ? DARK : LIGHT);
      });
    }
    if (cfg.selectable === false) document.documentElement.style.userSelect = "none";
  });
})();
