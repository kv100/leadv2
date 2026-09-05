#!/usr/bin/env python3
"""Classify every unselected suite into (a) dead / (b) connect / (c) declared.

Class is decided from EVIDENCE INSIDE THE SUITE, never from its name:
  * every production file the suite actually references (path-shaped mentions of
    plugins/leadv2/{scripts,scripts/lib,hooks}/*.sh, plus bare `leadv2-*.sh`
    basenames), split into those that exist at this sha and those that do not;
  * whether it needs the network or destroys the tree it runs in.

  (a) dead      — references at least one production file, and NONE of them exist
  (b) connect   — references at least one EXISTING production file -> triggers
  (c) declared  — needs network / writes over a production file / references no
                  production file at all (pure self-test or fixture-driven)
"""
import json, os, re, sys

ROOT = sys.argv[1]
SC = os.path.dirname(os.path.abspath(__file__))
census = json.load(open(os.path.join(SC, "census.json")))

PROD_DIRS = ["plugins/leadv2/scripts", "plugins/leadv2/scripts/lib",
             "plugins/leadv2/hooks"]
prod = {}
for d in PROD_DIRS:
    p = os.path.join(ROOT, d)
    if os.path.isdir(p):
        for f in os.listdir(p):
            if f.endswith(".sh") and os.path.isfile(os.path.join(p, f)):
                prod.setdefault(f, d + "/" + f)

REF = re.compile(r'([A-Za-z0-9_.-]+\.sh)')
NET = re.compile(r'\bcurl\b|\bgh api\b|\bssh \b|api\.anthropic|supabase\.co')
# a suite that writes over something in a production directory
VANDAL = re.compile(r'>\s*"?\$\{?(SCRIPTS?_DIR|PLUGIN_DIR|ROOT)\}?/[A-Za-z0-9_./-]*\.sh'
                    r'|cat\s*>\s*[^|]*plugins/leadv2/(scripts|hooks)/')

out = {"dead": [], "connect": [], "declared": []}
triggers = {}

for rel in census["unselected"]:
    src = open(os.path.join(ROOT, rel), errors="replace").read()
    body = "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("#"))
    refs = {r for r in REF.findall(body) if not r.startswith("test-")}
    exist = sorted({r for r in refs if r in prod})
    missing = sorted({r for r in refs if r not in prod
                      and (r.startswith("leadv2-") or r.startswith("codex-")
                           or r.startswith("glm-"))})

    if NET.search(body) or VANDAL.search(body):
        out["declared"].append((rel, "network_or_writes_production"))
    elif exist:
        out["connect"].append((rel, exist))
        triggers[rel] = [e[:-3] for e in exist]
    elif missing:
        out["dead"].append((rel, missing))
    else:
        out["declared"].append((rel, "references_no_production_file"))

print("unselected: %d" % len(census["unselected"]))
for k in ("connect", "dead", "declared"):
    print("  (%s) %-9s %d" % ({"dead": "a", "connect": "b", "declared": "c"}[k], k,
                              len(out[k])))
print()
print("sample (b) connect, with the triggers derived from the suite's own body:")
for rel, ex in out["connect"][:6]:
    print("   %-62s <- %s" % (rel.split("/")[-1], ",".join(e[:-3] for e in ex[:3])))
print()
print("sample (a) dead — every production file it names is gone:")
for rel, ms in out["dead"][:6]:
    print("   %-62s -> %s" % (rel.split("/")[-1], ",".join(ms[:3])))
print()
print("sample (c) declared:")
for rel, why in out["declared"][:6]:
    print("   %-62s %s" % (rel.split("/")[-1], why))

json.dump({k: [list(x) for x in v] for k, v in out.items()} | {"triggers": triggers},
          open(os.path.join(SC, "classify.json"), "w"), indent=1)
print("\n(written to classify.json)")
