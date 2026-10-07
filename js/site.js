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

  // ---- Install command builder (PyTorch-style selector) --------------------
  var selector = document.getElementById("install-selector");
  if (selector) {
    var SITE = "https://medical-image-computing-suite.github.io";
    var cmdEl = document.getElementById("install-cmd");
    var capEl = document.getElementById("run-caption");
    var noteEl = document.getElementById("install-note");
    var state = {
      method: "cli",
      os: "windows",
      shell: "cmd",
      python: "3.11",
      desktop: "yes",
      launch: "yes"
    };

    function cliArgs() {
      var a = ["--python " + state.python];
      if (state.desktop === "no") a.push("--no-desktop");
      if (state.launch === "no") a.push("--no-launch");
      return a;
    }

    function cliCommand() {
      var tail = " " + cliArgs().join(" ");
      if (state.os === "windows") {
        if (state.shell === "powershell") {
          return 'Invoke-WebRequest -Uri "' + SITE + '/installer/install.bat" ' +
            '-OutFile "$env:TEMP\\medics-install.bat"; & "$env:TEMP\\medics-install.bat"' + tail;
        }
        return 'curl -L -o "%TEMP%\\medics-install.bat" ' + SITE +
          '/installer/install.bat && "%TEMP%\\medics-install.bat"' + tail;
      }
      // macOS and Linux share the same one-liner; "--" forwards the flags.
      return "curl -fsSL " + SITE + "/installer/install.sh | bash -s --" + tail;
    }

    function pipCommand() {
      return "pip install medics";
    }

    function uvCommand() {
      return "uv tool install medics --python " + state.python;
    }

    function caption() {
      if (state.method !== "cli") return "Run this command in your terminal";
      if (state.os !== "windows") return "Run this command in your terminal";
      return state.shell === "powershell"
        ? "Run this command in PowerShell"
        : "Run this command in Command Prompt";
    }

    // Which option rows apply to each method (the shell row is refined below).
    var METHOD_ROWS = {
      cli: ["os", "python", "desktop", "launch"],
      uv: ["python"],
      pip: []
    };

    function render() {
      selector.querySelectorAll("[data-row]").forEach(function (row) {
        var rowName = row.getAttribute("data-row");
        if (rowName === "method") return;
        var visible;
        if (rowName === "shell") {
          visible = state.method === "cli" && state.os === "windows";
        } else {
          visible = METHOD_ROWS[state.method].indexOf(rowName) !== -1;
        }
        row.hidden = !visible;
      });

      var command = state.method === "cli" ? cliCommand()
        : state.method === "uv" ? uvCommand()
        : pipCommand();
      if (cmdEl) cmdEl.textContent = command;
      if (capEl) capEl.textContent = caption();

      var note = "";
      if (state.method === "pip") {
        note = "Requires Python 3.11+ already on your PATH. The CLI installer downloads a portable Python for you instead.";
      } else if (state.method === "uv") {
        note = "Installs medics as an isolated tool with uv and puts it on your PATH. Requires the uv package manager.";
      }
      if (noteEl) noteEl.textContent = note;
    }

    selector.querySelectorAll(".seg").forEach(function (group) {
      group.addEventListener("click", function (event) {
        var btn = event.target.closest ? event.target.closest(".seg__btn") : null;
        if (!btn || !group.contains(btn)) return;
        var opt = btn.getAttribute("data-opt");
        group.querySelectorAll(".seg__btn").forEach(function (b) {
          b.classList.toggle("is-active", b === btn);
        });
        state[opt] = btn.getAttribute("data-value");
        render();
      });
    });

    render();
  }

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
