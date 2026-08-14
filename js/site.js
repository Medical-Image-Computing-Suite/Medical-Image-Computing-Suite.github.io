(function () {
  "use strict";

  var hamburger = document.getElementById("hamburger");
  var links = document.querySelector(".nav__links");
  if (hamburger && links) {
    hamburger.addEventListener("click", function () {
      links.classList.toggle("is-open");
    });
    links.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () {
        links.classList.remove("is-open");
      });
    });
  }

  document.querySelectorAll(".copy-btn").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var block = btn.closest(".code-block");
      var code = btn.getAttribute("data-code") || (block && block.querySelector("code") && block.querySelector("code").innerText) || "";
      navigator.clipboard.writeText(code).then(function () {
        var orig = btn.textContent;
        btn.textContent = "Copied";
        btn.classList.add("copied");
        setTimeout(function () {
          btn.textContent = orig;
          btn.classList.remove("copied");
        }, 1600);
      });
    });
  });

  var tabBtns = document.querySelectorAll("[data-tab]");
  if (tabBtns.length) {
    tabBtns.forEach(function (btn) {
      btn.addEventListener("click", function () {
        var group = btn.closest(".tabs");
        var target = btn.getAttribute("data-tab");
        group.querySelectorAll("[data-tab]").forEach(function (b) { b.classList.remove("is-active"); });
        group.querySelectorAll(".tab-pane").forEach(function (p) { p.classList.remove("is-active"); });
        btn.classList.add("is-active");
        var pane = group.querySelector("#tab-" + target);
        if (pane) pane.classList.add("is-active");
      });
    });
  }
})();
