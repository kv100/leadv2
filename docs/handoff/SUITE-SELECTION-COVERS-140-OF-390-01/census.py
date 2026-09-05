#!/usr/bin/env python3
"""SUITE-SELECTION-COVERS-140-OF-390-01 — exact census of suite selection.

Three mechanisms actually decide whether `tests/run-all.sh --scope changed`
runs a suite:

  A. `# run-all-triggers:` marker            (self-registration, scan_suite_triggers)
  B. name convention  test-<stem>.sh         (the stem-comparison loop: a changed
                                              production file X.sh looks for
                                              tests/test-X.sh and
                                              plugins/leadv2/scripts/tests/test-X.sh)
  C. EXTRA_SUITE_MAP                         (static rows in run-all.sh)

and one more decides whether `--scope all` / run-core-offline runs it:

  D. run-core-offline.sh SUITE_DEFS          (the static offline core list)
  E. `--scope all` discovery                 (every test-*.sh at maxdepth 1 of the
                                              four discovery dirs — no marker needed)

This script reports each set and every intersection, from the tree it is run in.
"""
import os, re, subprocess, sys, json

ROOT = sys.argv[1]
DIRS = ["plugins/leadv2/scripts/tests", ".claude/scripts/tests",
        "plugins/leadv2/tests", "tests"]


def depth1(d):
    p = os.path.join(ROOT, d)
    if not os.path.isdir(p):
        return []
    return sorted(os.path.join(d, f) for f in os.listdir(p)
                  if f.startswith("test-") and f.endswith(".sh")
                  and os.path.isfile(os.path.join(p, f)))


population = [f for d in DIRS for f in depth1(d)]          # set E
marked = set()                                              # set A
for rel in population:
    with open(os.path.join(ROOT, rel), errors="replace") as fh:
        for line in fh:
            if line.startswith("# run-all-triggers:"):
                marked.add(rel)
                break

# set C — EXTRA_SUITE_MAP rows
run_all = open(os.path.join(ROOT, "tests/run-all.sh"), errors="replace").read()
m = re.search(r'^EXTRA_SUITE_MAP="(.*?)"$', run_all, re.S | re.M)
extra_rows = [r for r in (m.group(1).splitlines() if m else []) if ":" in r]
extra = {r.split(":", 1)[1].strip() for r in extra_rows}

# set D — run-core-offline SUITE_DEFS
rco = open(os.path.join(ROOT, "plugins/leadv2/scripts/tests/run-core-offline.sh"),
           errors="replace").read()
defs_block = rco.split("SUITE_DEFS=(", 1)[1].split("\n)", 1)[0]
core = set(re.findall(r"test-[a-zA-Z0-9._-]+\.sh", defs_block))

# set B — name convention. A changed production file whose basename stem is X
# selects tests/test-X.sh and plugins/leadv2/scripts/tests/test-X.sh by NAME,
# with no marker at all. Which production files can reach that loop is decided
# by run-all.sh's own allowlist, so mirror it rather than guessing.
prod_stems = set()
for d in ["plugins/leadv2/scripts", "plugins/leadv2/scripts/lib",
          "plugins/leadv2/hooks"]:
    p = os.path.join(ROOT, d)
    if not os.path.isdir(p):
        continue
    for f in os.listdir(p):
        if f.endswith(".sh") and os.path.isfile(os.path.join(p, f)):
            prod_stems.add(f[:-3])

by_name = {rel for rel in population
           if os.path.basename(rel)[len("test-"):-len(".sh")] in prod_stems
           and (rel.startswith("tests/")
                or rel.startswith("plugins/leadv2/scripts/tests/"))}

selected_changed = marked | by_name | {r for r in population
                                       if os.path.basename(r) in
                                       {os.path.basename(e) for e in extra}}
unselected = [r for r in population if r not in selected_changed]

print("population (test-*.sh at maxdepth 1 of the four discovery dirs): %d" % len(population))
for d in DIRS:
    n = len(depth1(d))
    if n:
        print("   %-34s %d" % (d, n))
print()
print("A  marker `# run-all-triggers:`      : %d" % len(marked))
print("B  name convention test-<prod stem>  : %d" % len(by_name))
print("C  EXTRA_SUITE_MAP rows              : %d" % len(extra_rows))
print("D  run-core-offline SUITE_DEFS       : %d suite files" % len(core))
print("E  --scope all discovery             : %d (the whole population, no marker needed)"
      % len(population))
print()
print("A ∩ B (marked AND name-selectable)   : %d" % len(marked & by_name))
print("A ∪ B ∪ C  = selectable by --scope changed : %d" % len(selected_changed))
print("NOT selectable by --scope changed    : %d" % len(unselected))
print("   of those, in run-core-offline D   : %d"
      % len([r for r in unselected if os.path.basename(r) in core]))
print("   of those, selected by NOTHING but --scope all : %d"
      % len([r for r in unselected if os.path.basename(r) not in core]))

json.dump({"population": population, "marked": sorted(marked),
           "by_name": sorted(by_name), "core": sorted(core),
           "unselected": unselected},
          open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "census.json"), "w"), indent=1)
print("\n(sets written to census.json)")
