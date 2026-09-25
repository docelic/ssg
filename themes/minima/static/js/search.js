// Client-side search: loads /index.json once and queries it with Fuse.js.
// Options come from the input's data-options attribute (params.search.fuse).
(function () {
  var input = document.getElementById("search-input");
  var result = document.getElementById("search-result");
  if (!input || !result) return;
  var fuse = null;

  fetch("/index.json").then(function (r) { return r.json(); }).then(function (docs) {
    fuse = new Fuse(docs, JSON.parse(input.dataset.options || "{}"));
    if (input.value) search();
  });

  function search() {
    if (!fuse) return;
    var html = "";
    fuse.search(input.value.trim()).forEach(function (hit) {
      html += '<li><a href="' + hit.item.permalink + '">' + hit.item.title + "</a></li>";
    });
    result.innerHTML = html;
  }

  input.addEventListener("input", search);
})();
