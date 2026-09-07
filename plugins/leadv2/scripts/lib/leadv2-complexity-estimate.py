#!/usr/bin/env python3
"""leadv2-complexity-estimate.py -- P6a, PHASES-ARE-NOT-SCALED-BY-COMPLEXITY-01 (row f33ff575078f).

Standalone complexity estimator: the missing INPUT for the already-live
complexity_gate_applied branch (leadv2-dispatch-code.sh:4290-4536). That gate
only ever received complexity_source=flag/heuristic, so the branch it draws
(plan_first vs brief_direct, review_rounds 1-3) never actually varied on the
input this file supplies. Wiring this into leadv2-dispatch-code.sh is
explicitly NOT this file's job (held by a live lane) -- this is a standalone,
directly-callable estimator a shell caller or a test can invoke without
importing Python.

Output vocabulary matches the existing complexity_gate_applied consumer
exactly (leadv2-dispatch-code.sh:4330-4357,4536), so a future wiring lane can
adopt this verdict without inventing a translation layer:
  complexity        trivial | simple | standard | complex
  complexity_source flag | estimate | unknown
  pipeline_route    plan_first | brief_direct
  review_rounds     1 | 2 | 3

Design doc: ~/Projects/persona-engine/docs/handoff/SMART-ARBITER-DESIGN-20260907/PLAN.md §8.
"""
import argparse
import sys

COMPLEX_KEYWORDS = (
    "migration", "migrate", "rewrite", "refactor across", "multi-subsystem",
    "several files", "breaking change", "across services", "multiple subsystems",
)
TRIVIAL_KEYWORDS = (
    "typo", "one-line", "one line", "docs only", "doc-only", "comment only",
    "rename only",
)

# declared-class -> implied complexity floor. Same table leadv2-dispatch-code.sh
# uses at _gate_depth_apply's flag-floor block (:4322-4330), so an operator
# override (--flag) resolves to a value the existing consumer already understands.
DECLARED_CLASS_FLOOR = {
    "trivial": "simple", "light": "simple",
    "standard": "standard",
    "heavy": "complex", "strategic": "complex",
}


def _route_and_rounds(complexity):
    route = "plan_first" if complexity in ("standard", "complex") else "brief_direct"
    rounds = {"trivial": 1, "simple": 1, "standard": 2, "complex": 3}[complexity]
    return route, rounds


def _subsystem_count(write_set, override):
    if override is not None:
        return override
    if not write_set:
        return 0
    tops = set()
    for f in write_set:
        tops.add(f.split("/", 1)[0] if "/" in f else "")
    return len(tops)


def _resolve_flag(declared_class):
    key = (declared_class or "").strip().lower()
    # off-vocabulary flag can't license depth either -- mirrors GATE-DEPTH §3's
    # "unknown provenance" rule: an unrecognized value is never trusted at face value.
    complexity = DECLARED_CLASS_FLOOR.get(key, "standard")
    reason = "operator declared class=%r (explicit override)" % (declared_class,)
    return complexity, "flag", reason


def _resolve_unknown():
    # Rule 2 (asymmetry): no signal at all resolves to the DEEPER floor, never
    # to brief_direct/1 -- unknown provenance can never license shallow depth.
    return "standard", "unknown", "no mission text or write-set given; nothing to estimate from, deeper floor applied"


def _resolve_estimate(mission_text, write_set, subsystem_count):
    lower = mission_text.lower()
    text_len = len(mission_text)

    score = 0.0
    score += min(len(write_set), 10) * 0.5
    score += max(subsystem_count - 1, 0) * 4.0
    if text_len > 3000:
        score += 3
    elif text_len > 1200:
        score += 1
    complex_hit = next((k for k in COMPLEX_KEYWORDS if k in lower), None)
    if complex_hit:
        score += 3
    trivial_hit = next((k for k in TRIVIAL_KEYWORDS if k in lower), None)
    if trivial_hit:
        score -= 2

    if score <= 0:
        complexity = "trivial"
    elif score <= 2:
        complexity = "simple"
    elif score <= 6:
        complexity = "standard"
    else:
        complexity = "complex"

    reason = (
        "score=%g files=%d subsystems=%d text_len=%d complex_kw=%s trivial_kw=%s"
        % (score, len(write_set), subsystem_count, text_len, complex_hit or "-", trivial_hit or "-")
    )
    return complexity, "estimate", reason


def estimate(mission_text, write_set, subsystem_count_override=None,
             declared_class=None, is_flag=False):
    mission_text = mission_text or ""
    write_set = [f.strip() for f in (write_set or []) if f.strip()]
    subsystem_count = _subsystem_count(write_set, subsystem_count_override)

    if is_flag and declared_class:
        complexity, source, reason = _resolve_flag(declared_class)
    elif not write_set and not mission_text.strip():
        complexity, source, reason = _resolve_unknown()
    else:
        complexity, source, reason = _resolve_estimate(mission_text, write_set, subsystem_count)

    route, rounds = _route_and_rounds(complexity)
    return {
        "complexity": complexity,
        "complexity_source": source,
        "pipeline_route": route,
        "review_rounds": rounds,
        "reason": reason,
    }


def format_line(result):
    return (
        "complexity=%s complexity_source=%s pipeline_route=%s review_rounds=%s reason=\"%s\""
        % (result["complexity"], result["complexity_source"], result["pipeline_route"],
           result["review_rounds"], result["reason"])
    )


def main(argv=None):
    ap = argparse.ArgumentParser(description="Standalone task-complexity estimator (P6a).")
    ap.add_argument("--mission", default=None, help="mission text")
    ap.add_argument("--mission-file", default=None, help="path to a file containing the mission text")
    ap.add_argument("--write-set", default="", help="comma-separated list of paths the task will write")
    ap.add_argument("--subsystem-count", type=int, default=None,
                    help="override the subsystem count instead of deriving it from --write-set")
    ap.add_argument("--declared-class", default=None,
                    help="operator-declared task class (Trivial|Light|Standard|Heavy|Strategic)")
    ap.add_argument("--flag", action="store_true",
                    help="treat --declared-class as an explicit operator override (complexity_source=flag)")
    ap.add_argument("--json", action="store_true", help="print a JSON object instead of a log line")
    args = ap.parse_args(argv)

    mission_text = args.mission
    if mission_text is None and args.mission_file:
        with open(args.mission_file, "r", encoding="utf-8") as fh:
            mission_text = fh.read()

    write_set = [f for f in args.write_set.split(",") if f.strip()] if args.write_set else []

    result = estimate(
        mission_text=mission_text,
        write_set=write_set,
        subsystem_count_override=args.subsystem_count,
        declared_class=args.declared_class,
        is_flag=args.flag,
    )
    if args.json:
        import json
        print(json.dumps(result))
    else:
        print(format_line(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
