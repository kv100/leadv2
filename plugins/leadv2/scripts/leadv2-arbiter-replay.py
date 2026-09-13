#!/usr/bin/env python3
"""Replay a recorded arbiter decision on one complexity axis.

Only schema-v2 rows contain the candidate pool and fit inputs required for a
counterfactual.  Refusing older rows is deliberate: treating an output-only
record as replayable would fabricate evidence.
"""
import argparse
import json
import math
from pathlib import Path
import sys


ORDINAL = {"trivial": 1.0, "simple": 2.0, "standard": 3.0, "complex": 4.0}
CONFIDENCE = {"judge": 0.9, "flag": 0.7, "heuristic": 0.4, "unknown": 0.0}


def req_eff(complexity, source, prior):
    value = ORDINAL.get(complexity)
    if value is None:
        return prior
    if value >= prior:
        return value
    return CONFIDENCE.get(source, 0.0) * value + (1.0 - CONFIDENCE.get(source, 0.0)) * prior


def replay(row, complexity):
    candidates = row.get("candidate_set")
    if not isinstance(candidates, list) or not candidates:
        return None
    prior = float(row.get("fit_prior", 3.0))
    slack = float(row.get("fit_slack", 0.5))
    effective = req_eff(complexity, row.get("complexity_source", "unknown"), prior)
    scored = []
    for candidate in candidates:
        try:
            capability = float(candidate["capability"])
            cost = float(candidate["effective_cost"])
            arm = str(candidate["arm"])
            tier = str(candidate.get("tier", "standard"))
        except (KeyError, TypeError, ValueError):
            return None
        bucket = max(0, int(math.ceil(effective - capability - slack)))
        key = ((bucket, cost, arm, tier) if row.get("fit_mode") == "on" else
               (cost, arm, tier))
        scored.append((key, arm, bucket))
    scored.sort()
    return scored[0][1], effective, scored[0][2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("decisions", type=Path)
    parser.add_argument("--complexity", required=True, choices=sorted(ORDINAL))
    args = parser.parse_args()
    replayable = old = malformed = moved = 0
    for line in args.decisions.read_text().splitlines():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            malformed += 1
            continue
        if row.get("record_schema_version") != 2:
            old += 1
            continue
        result = replay(row, args.complexity)
        if result is None:
            malformed += 1
            continue
        replayable += 1
        arm, effective, bucket = result
        changed = arm != row.get("arm")
        moved += int(changed)
        print("task=%s original=%s replay=%s complexity=%s req_eff=%.2f fit_bucket=%d moved=%d" % (
            row.get("task", ""), row.get("arm", ""), arm, args.complexity,
            effective, bucket, int(changed)))
    print("SUMMARY replayable=%d movement=%d old_schema_refused=%d malformed=%d" %
          (replayable, moved, old, malformed))
    return 0 if replayable else 2


if __name__ == "__main__":
    sys.exit(main())
