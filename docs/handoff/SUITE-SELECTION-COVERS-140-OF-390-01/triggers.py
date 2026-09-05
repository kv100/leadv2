#!/usr/bin/env python3
"""Derive a SIGNAL trigger set per class-(b) suite, and write the markers.

A suite sources shared helpers (leadv2-temp.sh, leadv2-state-path.sh, ...) that
say nothing about what it tests. Triggering on those would select ~all 235
suites on any helper edit — technically a dependency, practically noise, and
noise is how a selection gate stops being read. So:

  * count how many suites reference each production file;
  * a file referenced by more than UBIQUITY_PCT of the population is
    INFRASTRUCTURE — never a trigger on its own;
  * the trigger set is the remaining referenced files, most-mentioned first,
    capped at MAX_TRIGGERS;
  * if nothing survives, the suite keeps its single most-mentioned reference,
    whatever it is — a noisy trigger beats no trigger.

Run with --write to insert the marker lines.
"""
import collections, json, os, re, sys

ROOT = sys.argv[1]
WRITE = "--write" in sys.argv
SC = os.path.dirname(os.path.abspath(__file__))
cls = json.load(open(os.path.join(SC, "classify.json")))
census = json.load(open(os.path.join(SC, "census.json")))

UBIQUITY_PCT = 0.25
MAX_TRIGGERS = 4

connect = {rel: refs for rel, refs in cls["connect"]}
freq = collections.Counter()
for refs in connect.values():
    freq.update(set(refs))
limit = max(2, int(len(connect) * UBIQUITY_PCT))
infra = {f for f, n in freq.items() if n > limit}

print("class-(b) suites: %d" % len(connect))
print("infrastructure refs (in >%d suites, never a trigger alone): %s"
      % (limit, ", ".join(sorted(f[:-3] for f in infra)) or "(none)"))

plan = {}
for rel, refs in connect.items():
    body = open(os.path.join(ROOT, rel), errors="replace").read()
    counts = {r: body.count(r) for r in refs}
    signal = sorted((r for r in refs if r not in infra),
                    key=lambda r: (-counts[r], r))[:MAX_TRIGGERS]
    if not signal:
        signal = [max(refs, key=lambda r: (counts[r], r))]
    plan[rel] = [s[:-3] for s in signal]

hist = collections.Counter(len(v) for v in plan.values())
print("triggers per suite: " + ", ".join("%d->%d" % (k, hist[k]) for k in sorted(hist)))
print("\nsample:")
for rel in sorted(plan)[:8]:
    print("   %-58s <- %s" % (rel.split("/")[-1], " ".join(plan[rel])))

json.dump(plan, open(os.path.join(SC, "trigger-plan.json"), "w"), indent=1)

if not WRITE:
    print("\n(dry run — pass --write to insert the markers)")
    sys.exit(0)

MARK = ("# run-all-triggers: %s\n"
        "#\n"
        "# SUITE-SELECTION-COVERS-140-OF-390-01: this suite carried no trigger\n"
        "# marker and matched no name convention, so `run-all.sh --scope changed`\n"
        "# never selected it — it could only ever run under `--scope all`. The\n"
        "# triggers are the production files the suite's own body references most,\n"
        "# with shared helpers excluded so a helper edit does not select everything.\n")

written = 0
for rel, trig in sorted(plan.items()):
    p = os.path.join(ROOT, rel)
    src = open(p, errors="replace").read()
    if "# run-all-triggers:" in src:
        continue
    lines = src.split("\n")
    # insert after the shebang and any immediately-following comment block, i.e.
    # at the end of the file's own header — never in the middle of code.
    i = 1 if lines and lines[0].startswith("#!") else 0
    while i < len(lines) and (lines[i].startswith("#") or lines[i].strip() == ""):
        i += 1
    while i > 0 and lines[i - 1].strip() == "":
        i -= 1
    lines.insert(i, MARK % " ".join(trig))
    open(p, "w").write("\n".join(lines))
    written += 1

print("\nmarkers written: %d" % written)
