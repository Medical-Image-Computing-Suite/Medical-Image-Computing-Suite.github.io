#!/usr/bin/env python3
"""Build search-index.json for the site's nav search.

The site is static and has no build step, so the search index is generated from
the pages and committed. Re-run this after editing page content:

    python tools/build-search-index.py

Each index entry is one heading-delimited section:

    {"page": "docs/interface.html", "pageTitle": "Interface & components",
     "section": "File Explorer", "id": "file-explorer",
     "url": "docs/interface.html#file-explorer", "text": "…"}

A heading without its own id falls back to the nearest ancestor that has one
(several pages put the id on the wrapping <section> instead of the <h2>), so
every entry can be linked to directly.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from bs4 import BeautifulSoup, Tag

# Pages to index, in nav order. (path, label)
PAGES = [
    ("index.html", "Introduction"),
    ("get-started.html", "Get started"),
    ("extensions.html", "Extensions"),
    ("document.html", "Documents"),
    ("docs/interface.html", "Interface & components"),
    ("docs/settings.html", "Settings & preferences"),
    ("docs/toolboxes.html", "Toolboxes"),
    ("docs/python-workspace.html", "Python console & workspace"),
    ("docs/ai-assistant.html", "AI assistant"),
]

# Elements whose text is navigation or chrome, not documentation.
DROP_SELECTORS = [
    "script",
    "style",
    "noscript",
    "header.nav",
    "footer",
    "aside.docs-side",
    "aside.docs-toc",
    "nav.docs-pager",
    "nav.nav__links",
    # The hub's card grid is navigation to the pages indexed below, so indexing
    # it would only add duplicate, anchor-less hits. Its group labels go too.
    "div.doc-cards",
    "h2.hub-group",
]

HEADINGS = ("h1", "h2", "h3", "h4")

#: Longest section body kept, to keep the index small.
MAX_TEXT = 600

WS = re.compile(r"\s+")


def clean(text: str) -> str:
    return WS.sub(" ", text).strip()


def nearest_id(node: Tag) -> str:
    """The node's own id, or the closest ancestor that has one."""
    for parent in (node, *node.parents):
        if isinstance(parent, Tag):
            ident = parent.get("id")
            if ident:
                return str(ident)
    return ""


def content_root(soup: BeautifulSoup) -> Tag:
    """The element to walk for sections.

    ``body`` is the fallback rather than a single ``section``: several pages are
    a series of sibling ``<section>`` blocks, and picking the first one would
    index only its content.
    """
    return (
        soup.select_one("article.docs-content")
        or soup.select_one("main")
        or soup.body
    )


def build() -> list[dict]:
    entries: list[dict] = []
    for path, label in PAGES:
        html = Path(path).read_text(encoding="utf-8")
        soup = BeautifulSoup(html, "html.parser")
        for selector in DROP_SELECTORS:
            for node in soup.select(selector):
                node.decompose()

        root = content_root(soup)
        if root is None:
            continue

        h1 = root.find("h1") or soup.find("h1")
        page_title = clean(h1.get_text(" ")) if h1 else label

        headings = [h for h in root.find_all(HEADINGS) if h.find_parent(HEADINGS) is None]
        for index, heading in enumerate(headings):
            section = clean(heading.get_text(" "))
            if not section:
                continue

            # Body text: everything up to the next heading.
            parts: list[str] = []
            for node in heading.next_elements:
                if isinstance(node, Tag) and node.name in HEADINGS:
                    break
                if isinstance(node, Tag):
                    continue
                parts.append(str(node))
            body = clean(" ".join(parts))[:MAX_TEXT]

            if heading.name == "h1":
                # The h1 is represented by the page itself.
                continue

            ident = heading.get("id") or nearest_id(heading)
            entries.append(
                {
                    "page": path,
                    "pageTitle": page_title,
                    "section": section,
                    "id": ident,
                    "url": f"{path}#{ident}" if ident else path,
                    "text": body,
                }
            )
    return entries


def main() -> None:
    entries = build()
    out = Path("search-index.json")
    payload = {"generatedFrom": len(PAGES), "entries": entries}
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8")

    size_kb = out.stat().st_size / 1024
    print(f"wrote {out} — {len(entries)} entries, {size_kb:.1f} KB")
    missing = [e for e in entries if not e["id"]]
    if missing:
        print(f"  {len(missing)} entries have no anchor id (link to the page top):")
        for e in missing[:10]:
            print(f"    {e['page']}: {e['section']}")


if __name__ == "__main__":
    main()
