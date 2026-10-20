#!/usr/bin/env python3
"""Import a real pose recording (exported by the debug Pose recorder, roadmap P3-04) into the shared push-up vectors.

    python3 tools/pose-recorder/import.py ~/Downloads/real-side-12-20261020T190000Z.json [--known-gap "reason"]

Validates the file, runs the reference engine, adds the `reference` block (parity check on iOS + Android) and writes
shared/test-vectors/pushup/<id>.json.gz. If the reference engine disagrees with the human count beyond
`toleranceCounted`, the import stops — unless you pass --known-gap, which keeps the vector as a tracked accuracy gap
(parity is still checked; accuracy is not, until the engine is tuned). Only landmarks are stored, never video.
"""
from __future__ import annotations

import argparse
import gzip
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/reference"))

from pushly_ref import rep_engine  # noqa: E402

OUT = ROOT / "shared/test-vectors/pushup"
TAGS = {"normal", "cheat", "half", "knees", "sag", "pike", "fast", "slow", "edge", "loose-clothing", "dim-light",
        "rear-camera", "two-people", "screen-replay"}


def validate(v: dict) -> list[str]:
    errs = []
    if not str(v.get("id", "")).startswith("real-"):
        errs.append("id must start with real-")
    meta = v.get("meta", {})
    for key in ("placement", "camera", "imageWidth", "imageHeight", "tags", "humanCount"):
        if key not in meta:
            errs.append(f"meta.{key} missing")
    if meta.get("placement") not in ("side", "front"):
        errs.append("meta.placement must be side|front")
    unknown = set(meta.get("tags", [])) - TAGS
    if unknown:
        errs.append(f"unknown tags {sorted(unknown)}")
    if "cheat" in meta.get("tags", []) and v.get("expected", {}).get("counted") != 0:
        errs.append("a cheat recording must expect 0")
    frames = v.get("frames", [])
    if len(frames) < 30:
        errs.append("fewer than 30 frames")
    last = -1
    for i, f in enumerate(frames):
        if f["t"] <= last:
            errs.append(f"frame {i}: time not increasing")
            break
        last = f["t"]
        if len(f["lm"]) != 33 or len(f["w"]) != 33:
            errs.append(f"frame {i}: expected 33 landmarks")
            break
    return errs


def finish(v: dict) -> bytes:
    """Adds the reference block; deterministic bytes (also used by build_vectors --check)."""
    v = {k: val for k, val in v.items() if k != "reference"}
    result = rep_engine.run(v)
    v["reference"] = {"counted": result["counted"], "rejected": result["rejected"], "events": result["events"]}
    return (json.dumps(v, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("file", type=Path)
    ap.add_argument("--known-gap", help="keep a vector the engine currently gets wrong (reason)")
    args = ap.parse_args()
    v = json.loads(args.file.read_text())
    errs = validate(v)
    if errs:
        print("Invalid recording:", *errs, sep="\n  ")
        return 1
    exp = v["expected"]
    raw = finish(v)
    ref = json.loads(raw)["reference"]
    gap = abs(ref["counted"] - exp["counted"]) > exp.get("toleranceCounted", 0)
    print(f"{v['id']}: human {exp['counted']}, engine {ref['counted']}, rejected {ref['rejected']}")
    if gap and not args.known_gap:
        print("Engine disagrees with the human count. Tune the engine, or re-run with --known-gap \"why\".")
        return 2
    if gap:
        v["expected"]["knownGap"] = args.known_gap
        raw = finish(v)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{v['id']}.json.gz"
    path.write_bytes(gzip.compress(raw, compresslevel=9, mtime=0))
    print(f"wrote {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
