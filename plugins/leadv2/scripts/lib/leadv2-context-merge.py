#!/usr/bin/env python3
"""leadv2-context-merge.py — ONE-PATH-PLAN-RUN-01 deterministic skeleton/arm merge.

Folds model-authored judgment fields from arm YAML drafts into the engine-owned
skeleton context.yaml. Engine-owned keys ALWAYS win — a model cannot overwrite
id, mission, reads, writes, lane_writes, or acceptance.authored_at (design §3.2.5,
R1 mitigation).

After merge, checks REQUIRED_FIELDS are present. Exits 0 on success, 1 on
missing required fields (reasons on stderr).

Usage:
    python3 leadv2-context-merge.py --skeleton <ctx.yaml> --arm <draft.yaml>... --out <merged.yaml>
"""
import sys
import yaml

# Engine-owned keys: any value an arm emits for these is DISCARDED.
ENGINE_OWNED_TOP = {"id", "mission", "reads", "writes", "lane_writes"}
ENGINE_OWNED_ACCEPTANCE = {"authored_at"}

# Fields that MUST be present after merge (design §3.2.5 / leadv2-plan.js:402).
REQUIRED_FIELDS = [
    "id", "mission", "reads", "writes", "acceptance",
    "decisions", "off_limits", "plan",
]


def deep_merge(skeleton: dict, arm: dict) -> dict:
    """Merge arm judgment fields into skeleton. Engine-owned keys always win."""
    result = dict(skeleton)  # shallow copy — we handle nesting explicitly

    for key, val in arm.items():
        if key in ENGINE_OWNED_TOP:
            continue  # engine owns these — discard arm value
        if key == "acceptance" and isinstance(val, dict) and isinstance(result.get("acceptance"), dict):
            # Merge acceptance sub-keys, but engine owns authored_at
            for ak, av in val.items():
                if ak in ENGINE_OWNED_ACCEPTANCE:
                    continue
                result["acceptance"][ak] = av
        elif key not in result or key not in ENGINE_OWNED_TOP:
            # Judgment field from the arm — arm wins (skeleton has no opinion)
            result[key] = val

    return result


def check_required(doc: dict) -> list:
    """Return list of missing required field names."""
    missing = []
    for field in REQUIRED_FIELDS:
        val = doc.get(field)
        if val is None:
            missing.append(field)
        elif isinstance(val, str) and not val.strip():
            missing.append(field)
        elif isinstance(val, list) and len(val) == 0:
            missing.append(field)
    return missing


def main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--skeleton", required=True)
    ap.add_argument("--arm", action="append", default=[],
                    help="Arm YAML draft (repeatable)")
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    # Load skeleton
    try:
        with open(args.skeleton) as f:
            skeleton = yaml.safe_load(f) or {}
    except Exception as exc:
        print("merge: cannot parse skeleton %s: %s" % (args.skeleton, exc), file=sys.stderr)
        return 1

    if not isinstance(skeleton, dict):
        print("merge: skeleton is not a mapping", file=sys.stderr)
        return 1

    # Fold each arm draft into the skeleton in order
    merged = dict(skeleton)
    for arm_path in args.arm:
        try:
            with open(arm_path) as f:
                arm_doc = yaml.safe_load(f) or {}
        except Exception:
            # An unreadable arm draft is treated as empty — the REQUIRED_FIELDS
            # check below will catch the consequence.
            continue
        if isinstance(arm_doc, dict):
            merged = deep_merge(merged, arm_doc)

    # Check required fields
    missing = check_required(merged)
    if missing:
        print("merge: missing required fields: %s" % ", ".join(missing), file=sys.stderr)
        return 1

    # Write merged output atomically
    import os
    tmp = args.out + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as f:
        yaml.dump(merged, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    os.rename(tmp, args.out)
    print("merge: ok -> %s" % args.out, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
