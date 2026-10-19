#!/usr/bin/env python3
"""WCAG contrast check for design tokens (doc 14 §1): text pairs >= 4.5:1, graphics pairs >= 3:1, both themes."""
from __future__ import annotations

import json
import sys
from pathlib import Path

TOKENS = Path(__file__).resolve().parents[2] / "shared/design-tokens/tokens.json"


def luminance(hex_color: str) -> float:
    h = hex_color.lstrip("#")
    rgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a: str, b: str) -> float:
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def check(tokens: dict) -> list[str]:
    colors = tokens["color"]
    failures = []
    for kind, minimum in (("text", 4.5), ("graphics", 3.0)):
        for fg, bg in tokens["contrast"][kind]:
            for theme in ("light", "dark"):
                ratio = contrast(colors[fg][theme], colors[bg][theme])
                if ratio < minimum:
                    failures.append(f"{theme}: {fg} on {bg} = {ratio:.2f}:1 (needs {minimum}:1)")
    return failures


if __name__ == "__main__":
    fails = check(json.loads(TOKENS.read_text()))
    for f in fails:
        print("FAIL", f)
    print("contrast check:", "failed" if fails else "ok")
    sys.exit(1 if fails else 0)
