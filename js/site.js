(function () {
  "use strict";

  // ---- Shared navigation ---------------------------------------------------
  // Every page carries an empty <header class="nav" id="site-nav">. This fills
  // it, so the bar (links, external buttons, theme switcher, active state) is
  // defined in exactly one place and cannot drift between pages. Pages keep a
  // <noscript> fallback for the no-JS case.
  var NAV_LINKS = [
    { label: "Introduction", href: "index.html", files: ["", "index.html"] },
    { label: "Get started", href: "get-started.html", files: ["get-started.html"] },
    { label: "Extensions", href: "extensions.html", files: ["extensions.html"] },
    { label: "Documents", href: "document.html", files: ["document.html"], docs: true }
  ];
  var WIKI_URL = "https://github.com/Medical-Image-Computing-Suite/MedICS-Community/wiki";
  var GITHUB_URL = "https://github.com/medical-image-computing-suite";
  var THEME_ICONS =
    '<svg class="theme-toggle__icon theme-toggle__icon--sun" viewBox="0 0 24 24" aria-hidden="true" focusable="false">' +
      '<circle cx="12" cy="12" r="4.5"></circle>' +
      '<path d="M12 1.5v2.5M12 20v2.5M3.9 3.9l1.8 1.8M18.3 18.3l1.8 1.8M1.5 12H4M20 12h2.5M3.9 20.1l1.8-1.8M18.3 5.7l1.8-1.8"></path>' +
    "</svg>" +
    '<svg class="theme-toggle__icon theme-toggle__icon--moon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">' +
      '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"></path>' +
    "</svg>";

  var SEARCH_ICON =
    '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false" fill="none" stroke="currentColor" ' +
      'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      '<circle cx="10.5" cy="10.5" r="6.5"></circle><path d="M15.4 15.4 21 21"></path>' +
    "</svg>";

  // The site is served from a domain root, so a page in docs/ reaches the same
  // files one level up.
  var IN_DOCS = /\/docs\//.test(window.location.pathname);
  var PREFIX = IN_DOCS ? "../" : "";

  function renderNav() {
    var host = document.getElementById("site-nav");
    if (!host) return;

    var inDocs = IN_DOCS;
    var prefix = PREFIX;
    var page = (window.location.pathname.split("/").pop() || "index.html").toLowerCase();

    var items = NAV_LINKS.map(function (link) {
      var active = link.files.indexOf(page) !== -1 || (link.docs && inDocs);
      return '<li><a' + (active ? ' class="is-active"' : "") +
        ' href="' + prefix + link.href + '">' + link.label + "</a></li>";
    }).join("");

    // The Wiki and GitHub entries lead off-site, so they read as buttons rather
    // than as another page of this site.
    host.innerHTML =
      '<div class="container nav__inner">' +
        '<a class="nav__logo" href="' + prefix + 'index.html">' +
          '<img src="' + prefix + 'icon/icon.png" alt="" width="32" height="32" />' +
          "<em>MedICS</em>Medical Image Computing Suite</a>" +
        '<button class="nav__hamburger" id="hamburger" aria-label="Open menu">' +
          "<span></span><span></span><span></span></button>" +
        '<ul class="nav__links">' + items +
          '<li><a class="btn btn--ghost btn--sm" href="' + WIKI_URL +
            '" target="_blank" rel="noopener">MedICS Wiki</a></li>' +
          '<li><a class="btn btn--ghost btn--sm" href="' + GITHUB_URL +
            '" target="_blank" rel="noopener">GitHub</a></li>' +
          '<li class="nav__search">' +
            '<button class="search-toggle" id="search-toggle" type="button"' +
              ' aria-label="Search the documentation" aria-expanded="false"' +
              ' title="Search the documentation (Ctrl+K)">' + SEARCH_ICON + "</button>" +
          "</li>" +
          '<li class="nav__theme">' +
            '<button class="theme-toggle" id="theme-toggle" type="button" aria-label="Switch theme"' +
              ' title="Switch between dark and light theme">' + THEME_ICONS + "</button>" +
          "</li>" +
        "</ul>" +
      "</div>";
  }

  renderNav();

  // ---- Theme (dark / light) ------------------------------------------------
  // The head of each page applies the saved theme before paint; this keeps it in
  // sync, wires the switcher, and remembers the choice.
  var THEME_KEY = "medics-theme";
  var root = document.documentElement;

  function currentTheme() {
    var saved = null;
    try { saved = localStorage.getItem(THEME_KEY); } catch (e) { /* ignore */ }
    if (saved === "light" || saved === "dark") return saved;
    return root.getAttribute("data-theme") === "light" ? "light" : "dark";
  }

  function applyTheme(theme) {
    root.setAttribute("data-theme", theme);
    var btn = document.getElementById("theme-toggle");
    if (!btn) return;
    var goesLight = theme === "dark";
    btn.setAttribute("aria-label", goesLight ? "Switch to light theme" : "Switch to dark theme");
    btn.setAttribute("aria-pressed", goesLight ? "false" : "true");
  }

  var theme = currentTheme();
  applyTheme(theme);

  var themeToggle = document.getElementById("theme-toggle");
  if (themeToggle) {
    themeToggle.addEventListener("click", function () {
      theme = theme === "dark" ? "light" : "dark";
      applyTheme(theme);
      try { localStorage.setItem(THEME_KEY, theme); } catch (e) { /* ignore */ }
    });
  }

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

  // ---- In-page table of contents (scroll spy) ------------------------------
  // Marks the section the reader is in, so the right-hand column stays useful
  // as a position indicator rather than just a list of links.
  var toc = document.querySelector(".docs-toc");
  if (toc) {
    var entries = [];
    toc.querySelectorAll('a[href^="#"]').forEach(function (a) {
      var el = document.getElementById(decodeURIComponent(a.getAttribute("href").slice(1)));
      if (el) entries.push({ link: a, el: el });
    });

    if (entries.length) {
      var offset = function () {
        var raw = getComputedStyle(document.documentElement).getPropertyValue("--nav-h");
        var navH = parseFloat(raw) || 64;
        return navH + 48; // clear the sticky nav plus a line of breathing room
      };
      var ticking = false;

      var updateToc = function () {
        ticking = false;
        var line = offset();
        var active = entries[0].link;
        entries.forEach(function (entry) {
          if (entry.el.getBoundingClientRect().top - line <= 0) active = entry.link;
        });
        entries.forEach(function (entry) {
          entry.link.classList.toggle("is-active", entry.link === active);
        });
      };

      window.addEventListener("scroll", function () {
        if (ticking) return;
        ticking = true;
        window.requestAnimationFrame(updateToc);
      }, { passive: true });
      window.addEventListener("resize", updateToc);
      updateToc();
    }
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

  // ---- Documentation search ------------------------------------------------
  // The index is generated from the pages (tools/build-search-index.py) and
  // fetched on first use, so it costs nothing until someone actually searches.
  var searchToggle = document.getElementById("search-toggle");
  if (searchToggle) {
    var overlay = document.createElement("div");
    overlay.className = "search-overlay";
    overlay.hidden = true;
    overlay.innerHTML =
      '<div class="search-dialog" role="dialog" aria-modal="true" aria-label="Search the documentation">' +
        '<div class="search-field">' +
          '<span class="search-field__icon" aria-hidden="true">' + SEARCH_ICON + "</span>" +
          '<input class="search-input" id="search-input" type="search" spellcheck="false"' +
            ' autocomplete="off" placeholder="Search the documentation…"' +
            ' aria-controls="search-results" aria-label="Search the documentation" />' +
          '<kbd class="search-kbd">Esc</kbd>' +
        "</div>" +
        '<div class="search-results" id="search-results" role="listbox" aria-label="Search results"></div>' +
        '<p class="search-foot" id="search-foot">Type to search &middot; &uarr;&darr; to navigate &middot; Enter to open</p>' +
      "</div>";
    document.body.appendChild(overlay);

    var searchInput = overlay.querySelector("#search-input");
    var resultsEl = overlay.querySelector("#search-results");
    var footEl = overlay.querySelector("#search-foot");
    var index = null;
    var hits = [];
    var active = -1;

    var escapeHtml = function (value) {
      return String(value).replace(/[&<>"']/g, function (ch) {
        return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch];
      });
    };

    var highlight = function (text, terms) {
      var safe = escapeHtml(text);
      if (!terms.length) return safe;
      var pattern = terms
        .map(function (t) { return t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); })
        .join("|");
      return safe.replace(new RegExp("(" + pattern + ")", "gi"), "<mark>$1</mark>");
    };

    var loadIndex = function () {
      if (index) return Promise.resolve(index);
      return fetch(PREFIX + "search-index.json", { cache: "force-cache" })
        .then(function (response) {
          if (!response.ok) throw new Error("HTTP " + response.status);
          return response.json();
        })
        .then(function (data) {
          index = (data && data.entries) || [];
          return index;
        });
    };

    // Snippet: a window of text around the first matching term.
    var snippet = function (text, terms) {
      var lower = text.toLowerCase();
      var at = -1;
      terms.forEach(function (term) {
        var found = lower.indexOf(term);
        if (found !== -1 && (at === -1 || found < at)) at = found;
      });
      if (at === -1) return text.slice(0, 150);
      var start = Math.max(0, at - 50);
      var end = Math.min(text.length, start + 150);
      return (start > 0 ? "…" : "") + text.slice(start, end) + (end < text.length ? "…" : "");
    };

    var search = function (query) {
      var terms = query.toLowerCase().split(/\s+/).filter(Boolean);
      if (!terms.length || !index) return [];

      var scored = [];
      index.forEach(function (entry) {
        var section = entry.section.toLowerCase();
        var title = entry.pageTitle.toLowerCase();
        var text = entry.text.toLowerCase();
        var score = 0;
        var complete = true;

        terms.forEach(function (term) {
          if (text.indexOf(term) === -1 && section.indexOf(term) === -1 && title.indexOf(term) === -1) {
            complete = false;
            return;
          }
          if (section.indexOf(term) !== -1) score += 12;
          if (title.indexOf(term) !== -1) score += 4;
          // Occurrences in the body, capped so a long section cannot dominate.
          var occurrences = text.split(term).length - 1;
          score += Math.min(occurrences, 5);
        });

        if (complete && score > 0) scored.push({ entry: entry, score: score });
      });

      scored.sort(function (a, b) { return b.score - a.score; });
      return scored.slice(0, 12).map(function (item) { return item.entry; });
    };

    var setActive = function (next) {
      var items = resultsEl.querySelectorAll(".search-result");
      if (!items.length) return;
      active = (next + items.length) % items.length;
      items.forEach(function (item, i) {
        item.classList.toggle("is-active", i === active);
        if (i === active) item.scrollIntoView({ block: "nearest" });
      });
    };

    var render = function () {
      var query = searchInput.value.trim();
      hits = query ? search(query) : [];
      active = hits.length ? 0 : -1;
      resultsEl.textContent = "";
      searchInput.setAttribute("aria-expanded", hits.length ? "true" : "false");

      if (!query) {
        footEl.textContent = "Type to search · ↑↓ to navigate · Enter to open";
        return;
      }
      if (!hits.length) {
        resultsEl.innerHTML = '<p class="search-empty">No matches for “' + escapeHtml(query) + '”.</p>';
        footEl.textContent = "";
        return;
      }

      var terms = query.toLowerCase().split(/\s+/).filter(Boolean);
      footEl.textContent = hits.length + (hits.length === 1 ? " result" : " results");

      hits.forEach(function (entry, i) {
        var link = document.createElement("a");
        link.className = "search-result" + (i === active ? " is-active" : "");
        link.setAttribute("role", "option");
        link.href = PREFIX + entry.url;
        link.innerHTML =
          '<span class="search-result__where">' +
            escapeHtml(entry.pageTitle) +
            '<span class="search-result__sep">›</span><span class="search-result__section">' +
            highlight(entry.section, terms) + "</span>" +
          "</span>" +
          '<span class="search-result__text">' + highlight(snippet(entry.text, terms), terms) + "</span>";
        link.addEventListener("mouseenter", function () {
          active = i;
          resultsEl.querySelectorAll(".search-result").forEach(function (el, j) {
            el.classList.toggle("is-active", j === i);
          });
        });
        resultsEl.appendChild(link);
      });
    };

    var openSearch = function () {
      if (!overlay.hidden) return;
      overlay.hidden = false;
      document.body.classList.add("is-searching");
      searchToggle.setAttribute("aria-expanded", "true");
      searchInput.value = "";
      render();
      searchInput.focus();
      // The index may still be in flight; re-render once it lands so a query
      // typed immediately is not left showing "no matches".
      loadIndex()
        .then(function () {
          if (!overlay.hidden) render();
        })
        .catch(function () {
          footEl.textContent = "Search index unavailable.";
        });
    };

    var closeSearch = function () {
      if (overlay.hidden) return;
      overlay.hidden = true;
      document.body.classList.remove("is-searching");
      searchToggle.setAttribute("aria-expanded", "false");
      searchToggle.focus();
    };

    searchToggle.addEventListener("click", function () {
      if (overlay.hidden) openSearch();
      else closeSearch();
    });
    overlay.addEventListener("click", function (event) {
      if (event.target === overlay) closeSearch();
    });
    searchInput.addEventListener("input", render);
    searchInput.addEventListener("keydown", function (event) {
      if (event.key === "ArrowDown") { event.preventDefault(); setActive(active + 1); }
      else if (event.key === "ArrowUp") { event.preventDefault(); setActive(active - 1); }
      else if (event.key === "Enter" && active >= 0 && hits[active]) {
        event.preventDefault();
        window.location.href = PREFIX + hits[active].url;
      }
    });

    var isTyping = function (el) {
      if (!el) return false;
      var tag = el.tagName;
      return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable;
    };

    document.addEventListener("keydown", function (event) {
      if ((event.ctrlKey || event.metaKey) && String(event.key).toLowerCase() === "k") {
        event.preventDefault();
        openSearch();
        return;
      }
      if (event.key === "Escape" && !overlay.hidden) {
        event.preventDefault();
        closeSearch();
        return;
      }
      // "/" is the other conventional shortcut, but must not hijack typing.
      if (event.key === "/" && overlay.hidden && !isTyping(event.target)) {
        event.preventDefault();
        openSearch();
      }
    });
  }

  // ---- Documentation feedback footer --------------------------------------
  // A VS Code-style footer on every documentation page: a "was this page
  // helpful?" vote, links to where to ask for help, and an "Edit this page"
  // link back to the page's source. Only the documentation articles carry a
  // .docs-main column, so that is the gate: the top-level pages are skipped.
  var DOCS_REPO =
    "https://github.com/Medical-Image-Computing-Suite/Medical-Image-Computing-Suite.github.io";
  var COMMUNITY_WIKI =
    "https://github.com/Medical-Image-Computing-Suite/MedICS-Community/wiki";
  var COMMUNITY_ISSUES =
    "https://github.com/Medical-Image-Computing-Suite/MedICS-Community/issues/new";
  var DOCS_ISSUES = DOCS_REPO + "/issues/new";
  var FEEDBACK_KEY = "medics-doc-feedback";

  // ---- Where a vote is sent ------------------------------------------------
  // The MedICS Documents Feedback Google Form. Votes POST to its formResponse
  // endpoint; the entry.* ids below map each payload key to a form question.
  // (See FEEDBACK_GOOGLE_ENTRIES for how they were obtained.)
  var FEEDBACK_ENDPOINT =
    "https://docs.google.com/forms/d/e/1FAIpQLSecPdE_EmoSBXWCcPOOk73at1pxb4c7j4IyzmyJdu3jUpOifQ/formResponse";

  // Google Forms field map: payload key -> the form's "entry.<id>". Read from
  // the form's FB_PUBLIC_LOAD_DATA_ (or via ⋮ → "Get pre-filled link"):
  //   Page -> entry.211603439 · Helpful -> entry.1982313513 · Comment -> entry.681201604
  // A key with no entry (here "kind") is dropped, so it is never sent.
  var FEEDBACK_GOOGLE_ENTRIES = {
    page: "entry.211603439",
    helpful: "entry.1982313513",
    comment: "entry.681201604"
  };

  // Fire-and-forget POST. Never throws and never blocks the page: a blocked or
  // offline request simply leaves the local vote as the only record. The
  // endpoint may also be set at runtime with `window.MEDICS_FEEDBACK_ENDPOINT`,
  // which is handy for testing without editing this file.
  function postFeedback(payload) {
    var endpoint = FEEDBACK_ENDPOINT || window.MEDICS_FEEDBACK_ENDPOINT || "";
    if (!endpoint) return;

    var isGoogle = /docs\.google\.com\/forms/.test(endpoint);
    var body;
    var headers;

    if (isGoogle) {
      var params = new URLSearchParams();
      Object.keys(payload).forEach(function (key) {
        var entry = FEEDBACK_GOOGLE_ENTRIES[key];
        if (entry && String(payload[key]).length) params.append(entry, payload[key]);
      });
      body = params.toString();
      headers = { "Content-Type": "application/x-www-form-urlencoded" };
    } else {
      body = JSON.stringify(payload);
      headers = { "Content-Type": "application/json", "Accept": "application/json" };
    }

    try {
      // sendBeacon keeps the request alive if the click is the last thing the
      // visitor does. It cannot set a JSON content-type, so only use it for the
      // non-Google endpoints, where the Blob type is honoured.
      if (!isGoogle && navigator.sendBeacon) {
        if (navigator.sendBeacon(endpoint, new Blob([body], { type: "application/json" }))) {
          return;
        }
      }
      fetch(endpoint, {
        method: "POST",
        headers: headers,
        body: body,
        keepalive: true,
        // A Google Form reply carries no CORS headers, so the response is opaque.
        mode: isGoogle ? "no-cors" : "cors"
      }).catch(function () { /* offline / blocked — the vote stays local */ });
    } catch (e) { /* never let feedback break the page */ }
  }

  // Small line icons, matching the stroke style of the nav search icon.
  var ICON = function (paths) {
    return (
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"' +
      ' stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' +
      paths + "</svg>"
    );
  };
  var FEEDBACK_ICONS = {
    community: ICON(
      '<path d="M21 11.5a8.4 8.4 0 0 1-8.4 8.4 8.6 8.6 0 0 1-3.8-.9L3.5 21l1.9-5.2a8.4 8.4 0 0 1-.8-3.6A8.4 8.4 0 0 1 12.6 3.1 8.4 8.4 0 0 1 21 11.5z"></path>'
    ),
    feature: ICON(
      '<path d="M9 18h6"></path><path d="M10 21h4"></path>' +
        '<path d="M12 3a6 6 0 0 0-3.5 10.9c.6.5 1 1.3 1 2.1h5c0-.8.4-1.6 1-2.1A6 6 0 0 0 12 3z"></path>'
    ),
    issue: ICON(
      '<rect x="8" y="6" width="8" height="14" rx="4"></rect>' +
        '<path d="M12 6V3M8 11H4M8 16H4M16 11h4M16 16h4M9 8 7 5M15 8l2-3M9 18l-2 3M15 18l2 3"></path>'
    )
  };

  function renderDocsFeedback() {
    var main = document.querySelector(".docs-main");
    if (!main || main.querySelector(".docs-feedback")) return;

    // Repo-relative source path, e.g. "docs/settings.html". The site is served
    // from the domain root (a user/org GitHub Pages site), so the pathname is
    // already the file's path in the repository.
    var sourcePath = (window.location.pathname || "").replace(/^\/+/, "");
    var editUrl = sourcePath ? DOCS_REPO + "/edit/main/" + sourcePath : DOCS_REPO;

    var section = document.createElement("section");
    section.className = "docs-feedback";
    section.setAttribute("aria-label", "Page feedback");
    section.innerHTML =
      '<div class="docs-feedback__col">' +
        '<h2 class="docs-feedback__title">Was this page helpful?</h2>' +
        '<div class="docs-feedback__actions">' +
          '<button class="btn btn--primary btn--sm docs-feedback__btn" type="button" data-feedback="yes">Yes</button>' +
          '<button class="btn btn--secondary btn--sm docs-feedback__btn" type="button" data-feedback="no">No</button>' +
        "</div>" +
        '<div class="docs-feedback__after" id="docs-feedback-after" hidden>' +
          '<p class="docs-feedback__thanks" id="docs-feedback-thanks">Thanks for your feedback.</p>' +
          '<div class="docs-feedback__comment" id="docs-feedback-comment" hidden>' +
            '<label class="docs-feedback__comment-label" for="docs-feedback-note">' +
              "What could be better? (optional)</label>" +
            '<textarea class="docs-feedback__note" id="docs-feedback-note" rows="3"' +
              ' placeholder="Tell us what is missing or unclear…"></textarea>' +
            '<div class="docs-feedback__comment-actions">' +
              '<button class="btn btn--primary btn--sm" type="button" data-feedback-send>Send</button>' +
              '<button class="btn btn--ghost btn--sm" type="button" data-feedback-skip>Skip</button>' +
            "</div>" +
          "</div>" +
        "</div>" +
      "</div>" +
      '<div class="docs-feedback__col">' +
        '<h2 class="docs-feedback__title">Still need help?</h2>' +
        '<ul class="docs-feedback__links">' +
          '<li><a href="' + COMMUNITY_WIKI + '" target="_blank" rel="noopener">' +
            FEEDBACK_ICONS.community + "<span>Ask the community</span></a></li>" +
          '<li><a href="' + COMMUNITY_ISSUES + '" target="_blank" rel="noopener">' +
            FEEDBACK_ICONS.feature + "<span>Request features</span></a></li>" +
          '<li><a href="' + DOCS_ISSUES + '" target="_blank" rel="noopener">' +
            FEEDBACK_ICONS.issue + "<span>Report issues</span></a></li>" +
        "</ul>" +
      "</div>" +
      '<div class="docs-feedback__col">' +
        '<h2 class="docs-feedback__title">Help us improve</h2>' +
        '<a class="btn btn--primary docs-feedback__edit" href="' + editUrl + '"' +
          ' target="_blank" rel="noopener">Edit this page</a>' +
      "</div>";

    main.appendChild(section);

    var actions = section.querySelector(".docs-feedback__actions");
    var after = section.querySelector(".docs-feedback__after");
    var thanks = section.querySelector(".docs-feedback__thanks");
    var commentWrap = section.querySelector(".docs-feedback__comment");
    var note = section.querySelector(".docs-feedback__note");
    var pageId = sourcePath || "index.html";

    var post = function (kind, helpful, comment) {
      postFeedback({
        kind: kind,
        page: pageId,
        pageTitle: document.title,
        helpful: helpful,
        comment: comment || "",
        url: window.location.href
      });
    };

    // `send` is false when a returning visitor's stored vote is being restored:
    // the vote is remembered, not re-sent.
    var vote = function (value, send) {
      try { localStorage.setItem(FEEDBACK_KEY + ":" + pageId, value); } catch (e) { /* ignore */ }
      actions.hidden = true;
      after.hidden = false;
      if (!send) return;
      post("vote", value, "");
      // A "No" is the one worth explaining, so ask for an optional note. The
      // vote above is already recorded, so a skipped note loses nothing.
      if (value === "no") commentWrap.hidden = false;
    };

    // Reflect a vote cast on an earlier visit, so the buttons do not reappear.
    var stored = null;
    try { stored = localStorage.getItem(FEEDBACK_KEY + ":" + pageId); } catch (e) { /* ignore */ }
    if (stored === "yes" || stored === "no") vote(stored, false);

    actions.addEventListener("click", function (event) {
      var btn = event.target.closest ? event.target.closest("button[data-feedback]") : null;
      if (btn) vote(btn.getAttribute("data-feedback"), true);
    });

    after.addEventListener("click", function (event) {
      var target = event.target;
      if (!target.closest) return;
      if (target.closest("button[data-feedback-send]")) {
        var text = (note.value || "").trim();
        if (text) post("comment", "no", text);
        commentWrap.hidden = true;
        thanks.textContent = "Thanks — your note has been sent.";
      } else if (target.closest("button[data-feedback-skip]")) {
        commentWrap.hidden = true;
      }
    });
  }

  renderDocsFeedback();
})();
