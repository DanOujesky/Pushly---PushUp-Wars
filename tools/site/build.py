#!/usr/bin/env python3
"""Builds the public legal/support site (GitHub Pages) from docs/legal/*.md.

Usage: python3 tools/site/build.py [out_dir]   (default: build/site)
Needs: pip install markdown
"""
from __future__ import annotations

import html
import pathlib
import re
import sys

import markdown

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "docs" / "legal"
OUT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "site"

# source file -> published page (these URLs are linked from the apps and the store listings: keep them stable)
PAGES = {
    "privacy-policy.md": "privacy.html",
    "privacy-policy.cs.md": "privacy-cs.html",
    "terms.md": "terms.html",
    "terms.cs.md": "terms-cs.html",
    "community-guidelines.md": "community.html",
    "delete-account.md": "delete-account.html",
    "support.md": "support.html",
}

CSS = """
:root{--bg:#0A0A10;--surface:#14141E;--stroke:#23233A;--text:#F4F4F8;--text2:#A8A8BC;--flame:#FF7A45;--volt:#9B84FF}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
header{border-bottom:1px solid var(--stroke);padding:14px 16px}
header .in,main,footer .in{max-width:860px;margin:0 auto}
header a.brand{color:var(--text);font-weight:800;letter-spacing:.02em;text-decoration:none;font-size:18px}
header a.brand span{color:var(--flame)}
nav{display:flex;flex-wrap:wrap;gap:4px 16px;margin-top:6px;font-size:14px}
nav a{color:var(--text2);text-decoration:none}
nav a:hover,nav a[aria-current]{color:var(--text)}
main{padding:24px 16px 48px}
h1{font-size:28px;line-height:1.2;margin:8px 0 8px}
h2{font-size:20px;margin:32px 0 8px}
a{color:var(--volt)}
strong{color:#fff}
p,li{color:var(--text)}
code{background:var(--surface);padding:1px 5px;border-radius:4px}
.table{overflow-x:auto;margin:12px 0;border:1px solid var(--stroke);border-radius:10px}
table{border-collapse:collapse;width:100%;font-size:14px;min-width:640px}
th,td{text-align:left;vertical-align:top;padding:8px 10px;border-bottom:1px solid var(--stroke)}
th{background:var(--surface);color:var(--text2);font-weight:600}
tr:last-child td{border-bottom:0}
footer{border-top:1px solid var(--stroke);padding:16px;color:var(--text2);font-size:13px}
.cards{display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));margin-top:24px}
.cards a{display:block;background:var(--surface);border:1px solid var(--stroke);border-radius:12px;padding:16px;
  color:var(--text);text-decoration:none;font-weight:600}
.cards a span{display:block;color:var(--text2);font-weight:400;font-size:14px;margin-top:4px}
"""

NAV = [("privacy.html", "Privacy"), ("terms.html", "Terms"), ("community.html", "Community"),
       ("delete-account.html", "Delete account"), ("support.html", "Support")]


def front_matter(text: str) -> tuple[dict[str, str], str]:
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}, text
    meta = dict(line.split(":", 1) for line in m.group(1).splitlines() if ":" in line)
    return {k.strip(): v.strip() for k, v in meta.items()}, text[m.end():]


def page(title: str, body: str, current: str, lang: str = "en") -> str:
    nav = "".join(
        f'<a href="{href}"{" aria-current=page" if href == current else ""}>{label}</a>' for href, label in NAV)
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · Pushly</title>
<meta name="description" content="Pushly — the push-up alarm and battle game. {html.escape(title)}.">
<meta name="color-scheme" content="dark">
<style>{CSS}</style>
</head>
<body>
<header><div class="in"><a class="brand" href="index.html">PUSH<span>LY</span></a><nav>{nav}</nav></div></header>
<main>
{body}
</main>
<footer><div class="in">Pushly · Daniel Oujeský, Prague, Czech Republic ·
<a href="mailto:dany.oujesky@gmail.com">dany.oujesky@gmail.com</a></div></footer>
</body>
</html>
"""


def render(md_text: str) -> str:
    out = markdown.markdown(md_text, extensions=["tables", "sane_lists"])
    return out.replace("<table>", '<div class="table"><table>').replace("</table>", "</table></div>")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for src, dst in PAGES.items():
        meta, body = front_matter((SRC / src).read_text(encoding="utf-8"))
        (OUT / dst).write_text(page(meta.get("title", "Pushly"), render(body), dst, meta.get("lang", "en")),
                               encoding="utf-8")
    index = """<h1>Pushly — PushUp Wars</h1>
<p>The alarm that only stops after real push-ups, counted by your phone's camera on the device. Battle friends,
join a clan, climb the leaderboards.</p>
<div class="cards">
<a href="privacy.html">Privacy Policy<span>What we process and why. Camera video never leaves your phone.</span></a>
<a href="terms.html">Terms of Use<span>The rules for using Pushly, health and fair play.</span></a>
<a href="community.html">Community Guidelines<span>Do your own reps, respect people.</span></a>
<a href="delete-account.html">Delete your account<span>In the app or by email.</span></a>
<a href="support.html">Support<span>Help with alarms, rep counting and your account.</span></a>
</div>"""
    (OUT / "index.html").write_text(page("Pushly", index, "index.html"), encoding="utf-8")
    (OUT / ".nojekyll").write_text("", encoding="utf-8")
    print(f"site built: {OUT} ({len(PAGES) + 1} pages)")


if __name__ == "__main__":
    main()
