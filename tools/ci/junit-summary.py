#!/usr/bin/env python3
"""Summarise JUnit XML results (Gradle build/test-results) as one GitHub notice: tests per module."""
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
per = defaultdict(lambda: [0, 0, 0])  # tests, failures+errors, skipped
for f in root.glob("**/build/test-results/**/*.xml"):
    module = str(f.relative_to(root)).split("/build/")[0]
    s = ET.parse(f).getroot()
    per[module][0] += int(s.get("tests", 0))
    per[module][1] += int(s.get("failures", 0)) + int(s.get("errors", 0))
    per[module][2] += int(s.get("skipped", 0))
lines = [f"{m}: {t} tests, {fl} failed, {sk} skipped" for m, (t, fl, sk) in sorted(per.items())]
total = sum(v[0] for v in per.values())
lines.append(f"TOTAL: {total} tests")
print("::notice title=JUnit summary::" + "%0A".join(lines))
