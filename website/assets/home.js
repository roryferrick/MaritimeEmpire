// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// The landing page's screenshot lightbox.
(function () {
  var box = document.getElementById("lightbox");
  if (!box) return;
  var img = box.querySelector("img");
  document.querySelectorAll(".gallery-grid a").forEach(function (a) {
    a.addEventListener("click", function (e) {
      e.preventDefault();
      img.src = a.getAttribute("href");
      img.alt = a.querySelector("img").alt;
      box.hidden = false;
    });
  });
  box.addEventListener("click", function () { box.hidden = true; });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") box.hidden = true; });
})();
