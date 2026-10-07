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
    var extHost = document.getElementById("ext-list");
    var state = {
      method: "cli",
      os: "windows",
      shell: "cmd",
      python: "3.11",
      desktop: "yes",
      launch: "yes",
      ext: []
    };

    var FALLBACK_EXTS = [
      {
        name: "Retinal Layer Segmentation",
        package: "medics-ext-retinal-layer-segmentation",
        description: "AI-based retinal layer segmentation for OCT / OCTA volumes."
      }
    ];

    function cliArgs() {
      var a = ["--python " + state.python];
      if (state.desktop === "no") a.push("--no-desktop");
      if (state.launch === "no") a.push("--no-launch");
      if (state.ext.length) a.push("--ext " + state.ext.join(","));
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
      return "pip install " + ["medics"].concat(state.ext).join(" ");
    }

    function caption() {
      if (state.method === "pip") return "Run this command";
      if (state.os !== "windows") return "Run this command in your terminal";
      return state.shell === "powershell"
        ? "Run this command in PowerShell"
        : "Run this command in Command Prompt";
    }

    function render() {
      var isCli = state.method === "cli";

      selector.querySelectorAll("[data-when]").forEach(function (row) {
        var rowName = row.getAttribute("data-row");
        var show = isCli;
        if (rowName === "shell") show = show && state.os === "windows";
        row.hidden = !show;
      });

      selector.querySelectorAll("[data-row]").forEach(function (row) {
        var rowName = row.getAttribute("data-row");
        var irrelevant = !isCli && ["os", "shell", "python", "desktop", "launch"].indexOf(rowName) !== -1;
        row.classList.toggle("is-disabled", irrelevant);
      });

      if (cmdEl) cmdEl.textContent = isCli ? cliCommand() : pipCommand();
      if (capEl) capEl.textContent = caption();

      var note = "";
      var warn = false;
      if (!isCli) {
        note = "Requires Python 3.11+ already on your PATH. The CLI installer downloads a portable Python for you instead.";
      } else if (state.python !== "3.11") {
        note = "Published MedICS wheels target Python 3.11 — " + state.python +
          " may resolve to an older build that asks for a token at startup.";
        warn = true;
      }
      if (noteEl) {
        noteEl.textContent = note;
        noteEl.classList.toggle("is-warn", warn);
      }
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

    function renderExtensions(list) {
      if (!extHost) return;
      extHost.textContent = "";
      if (!list.length) {
        var empty = document.createElement("p");
        empty.className = "selector__empty";
        empty.textContent = "No optional extensions are published yet.";
        extHost.appendChild(empty);
        return;
      }
      list.forEach(function (ext) {
        var pkg = ext.package;
        var label = document.createElement("label");
        label.className = "check";

        var input = document.createElement("input");
        input.type = "checkbox";
        input.value = pkg;
        input.addEventListener("change", function () {
          if (input.checked) {
            if (state.ext.indexOf(pkg) === -1) state.ext.push(pkg);
          } else {
            state.ext = state.ext.filter(function (p) { return p !== pkg; });
          }
          render();
        });

        var text = document.createElement("span");
        var name = document.createElement("span");
        name.className = "check__name";
        name.textContent = ext.name || pkg;
        text.appendChild(name);
        var desc = ext.description;
        if (desc) {
          var d = document.createElement("span");
          d.className = "check__desc";
          d.textContent = desc;
          text.appendChild(d);
        }

        label.appendChild(input);
        label.appendChild(text);
        extHost.appendChild(label);
      });
    }

    function loadExtensions() {
      if (typeof fetch !== "function") {
        renderExtensions(FALLBACK_EXTS);
        return;
      }
      fetch("installer/catalog.json", { cache: "no-cache" })
        .then(function (res) {
          if (!res.ok) throw new Error("catalog unavailable");
          return res.json();
        })
        .then(function (data) {
          var list = (data && data.extensions) || [];
          renderExtensions(list.length ? list : FALLBACK_EXTS);
        })
        .catch(function () { renderExtensions(FALLBACK_EXTS); });
    }

    render();
    loadExtensions();
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
