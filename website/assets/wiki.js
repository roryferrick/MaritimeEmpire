// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// The wiki's search box (over window.WIKI_INDEX, written by
// tools/build_website.gd) and the phone-width "All topics" toggle.
(function () {
  var input = document.getElementById("search");
  var box = document.getElementById("results");
  var toggle = document.getElementById("side-toggle");
  var sidebar = document.getElementById("sidebar");
  var selected = -1;

  if (toggle && sidebar) {
    toggle.addEventListener("click", function () {
      var open = sidebar.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
  }
  if (!input || !box) return;

  function escape(s) {
    return s.replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; });
  }
  function mark(text, words) {
    var html = escape(text);
    words.forEach(function (w) {
      html = html.replace(new RegExp("(" + w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")", "gi"), "<mark>$1</mark>");
    });
    return html;
  }
  // A bit of the page's text round the first word found.
  function snippet(text, words) {
    var lower = text.toLowerCase();
    var at = -1;
    for (var i = 0; i < words.length && at < 0; i++) at = lower.indexOf(words[i]);
    if (at < 0) return text.slice(0, 140);
    var start = Math.max(0, at - 60);
    return (start > 0 ? "..." : "") + text.slice(start, start + 160) + "...";
  }

  function search() {
    var index = window.WIKI_INDEX || [];
    var q = input.value.trim().toLowerCase();
    selected = -1;
    if (q.length < 2) { box.hidden = true; return; }
    var words = q.split(/\s+/);
    var hits = [];
    index.forEach(function (page) {
      var title = page.t.toLowerCase();
      var body = page.x.toLowerCase();
      var score = 0;
      for (var i = 0; i < words.length; i++) {
        var w = words[i];
        var inTitle = title.indexOf(w) >= 0;
        var count = body.split(w).length - 1;
        if (!inTitle && !count) return;
        score += (inTitle ? 50 : 0) + Math.min(count, 20);
      }
      hits.push({ page: page, score: score });
    });
    hits.sort(function (a, b) { return b.score - a.score; });
    if (!hits.length) {
      box.innerHTML = "<p>Nothing found for “" + escape(input.value.trim()) + "”.</p>";
    } else {
      box.innerHTML = hits.slice(0, 12).map(function (h) {
        return '<a href="' + h.page.u + '"><small>' + escape(h.page.p) + "</small>" + mark(h.page.t, words) +
          "<span>" + mark(snippet(h.page.x, words), words) + "</span></a>";
      }).join("");
    }
    box.hidden = false;
  }

  input.addEventListener("input", search);
  input.addEventListener("keydown", function (e) {
    var links = box.querySelectorAll("a");
    if (e.key === "Escape") { box.hidden = true; input.blur(); return; }
    if (!links.length) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      selected = (selected + (e.key === "ArrowDown" ? 1 : -1) + links.length) % links.length;
      links.forEach(function (a, i) { a.classList.toggle("sel", i === selected); });
      links[selected].scrollIntoView({ block: "nearest" });
    } else if (e.key === "Enter") {
      window.location.href = links[Math.max(selected, 0)].getAttribute("href");
    }
  });
  document.addEventListener("click", function (e) {
    if (!box.contains(e.target) && e.target !== input) box.hidden = true;
  });
  input.addEventListener("focus", function () { if (input.value.trim().length >= 2) search(); });
  // "/" jumps to the search box, as on many wikis.
  document.addEventListener("keydown", function (e) {
    if (e.key === "/" && document.activeElement !== input) { e.preventDefault(); input.focus(); }
  });
})();
