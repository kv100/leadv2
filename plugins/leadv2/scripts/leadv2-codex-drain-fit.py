#!/usr/bin/env python3
"""Codex drain series + NNLS fit — CODEX-HAS-TOKENS-BUT-NO-DRAIN-SERIES-01.

leadv2-drain-weights.py prices Anthropic/GLM from ~/.claude/burn/history.db
(rate_limit_history for the Δpct drain, turn_events for per-model tokens).
Codex never touches that database — it runs under its own CLI, so it has
neither a drain snapshot table nor a turn_events row (this repo, measured
2026-09-14: `SELECT model FROM turn_events` has zero `gpt-5.6-*` rows).

The raw material exists in two DIFFERENT places that must not be confused:
  - The DRAIN side: the arbiter reads codex quota live on every routing
    decision (whichever arm it ends up picking) and journals it as
    `util_codex=<pct>` beside an ISO timestamp, in every task's
    `~/.claude/leadv2-state/<repo>/tasks/<sig8>/journal.md` (one shared
    codex account, so readings from EVERY task's journal belong to the SAME
    global window and merge into one time series).
  - The TOKEN side: a `route_resolved ... arm=codex` DECISION line is not
    proof codex ran — measured live 2026-09-14: every task whose journal
    named arm=codex in a decision line, when checked against that task's own
    `arm-registered` file, either never spawned codex at all (re-routed to
    glm/sonnet afterward) or the join otherwise failed 100% of the time via
    that proxy. `arm-registered`'s `arm=codex handle=<jobId> epoch=<epoch>`
    line is the only ground truth for "codex actually spawned, and when" —
    it is what `leadv2_lane_token_total` (lib/leadv2-cost-actuals.sh, the
    CODEX-LANES-PRODUCE-NO-TOKEN-READING-01 fix, 2026-09-13) itself joins to
    the job's threadId and its rollout file's cumulative token_usage_record.
    This tool discovers codex spawns the SAME way: by scanning
    `<repo-root>/docs/handoff/dispatch-*/arm-registered` for `arm=codex`
    lines, never by trusting a routing decision line.

Method — deliberately the SAME shape as leadv2-drain-weights.py, its NNLS
solver and Pearson helper imported directly rather than re-derived:
  - Intervals between consecutive util_codex readings (sorted by time,
    across ALL tasks/repos) with Δpct < 0 are window resets and are DROPPED
    (counted as dropped_reset) — a reset makes the reading jump down, and an
    interval spanning one is an artifact, not a drain.
  - Δpct == 0 with zero attributed tokens is idle and dropped (dropped_idle).
  - Token attribution is per-TASK, not per-handle: a task's total codex
    token count (summing every codex handle it ever spawned, via
    leadv2_lane_token_total) is assigned to the interval containing that
    task's LAST arm-registered `arm=codex` epoch. A task re-dispatched to
    codex twice within one interval is one bucket, not two — coarser than
    the anthropic/glm fit's per-event resolution, named here rather than
    silently inherited.
  - A task's per-model attribution (gpt-5.6-terra/sol/luna) comes from the
    job's OWN record: `request.model` inside
    `CODEX_GUARD_STATE_ROOT/*/jobs/<handle>.json` (see `_job_model` below) —
    NOT from journal.md's `arbiter_pick=codex model=...` decision lines,
    which measured live 2026-09-14 had a 0/118 hit rate against the
    arm-registered-confirmed codex spawns in this fit (every one of those
    118 tasks had zero `route_resolved` lines in its own journal.md). Used
    only when every codex handle a task spawned resolves to the SAME model;
    otherwise its tokens count toward the aggregate (provider-level) fit
    only, and the task is counted in mixed_model (or no_job_model when no
    handle's job json was readable).

Usage: leadv2-codex-drain-fit.py [--state-glob PATTERN] [--min-intervals N]
Env overrides (for tests): LEADV2_STATE_GLOB, LEADV2_CODEX_REPO_ROOTS
  (comma-separated absolute repo-root paths), LEADV2_COST_ACTUALS_SH,
  CODEX_GUARD_STATE_ROOT, CODEX_HOME.
"""
import bisect
import glob
import importlib.util
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))


def _load(name, relpath):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, relpath))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Reuse, never re-derive: the NNLS solver, Pearson helper, timestamp parser
# and the MIN_INTERVALS threshold all come from the sibling fitter.
_drain = _load("leadv2_drain_weights", "leadv2-drain-weights.py")
nnls = _drain.nnls
_pearson = _drain._pearson
_ts_to_epoch = _drain._ts_to_epoch
MIN_INTERVALS = _drain.MIN_INTERVALS

DEFAULT_ARM_REGISTERED_GLOBS = [
    "~/Projects/*/docs/handoff/dispatch-*/arm-registered",
    "~/MythicalGames/*/docs/handoff/dispatch-*/arm-registered",
    "~/MythicalGames/*/*/docs/handoff/dispatch-*/arm-registered",
]

READING_RE = re.compile(
    r"^- (?P<ts>\S+) \[decision\] route_resolved\b.*?\butil_codex=(?P<util>-?\d+)\b"
)
ARM_CODEX_RE = re.compile(r"^arm=codex\s+handle=(?P<handle>\S+)\s+epoch=(?P<epoch>\d+)\b")


def _arm_registered_files():
    override = os.environ.get("LEADV2_CODEX_ARM_REGISTERED_GLOBS")
    patterns = override.split(",") if override else DEFAULT_ARM_REGISTERED_GLOBS
    files = []
    for pat in patterns:
        files.extend(glob.glob(os.path.expanduser(pat)))
    return sorted(set(files))


def _state_root():
    return os.path.expanduser(os.environ.get("LEADV2_STATE_ROOT", "~/.claude/leadv2-state"))


def _readings_glob():
    override = os.environ.get("LEADV2_STATE_GLOB")
    if override:
        return override
    return os.path.join(_state_root(), "*", "tasks", "*", "journal.md")


def _job_model(handle):
    """The job's OWN record (CODEX_GUARD_STATE_ROOT/<slug>/jobs/<jobId>.json)
    carries `request.model` -- the launcher's own record of which of
    gpt-5.6-{terra,sol,luna} it invoked for THIS handle. Far more reliable
    than a journal.md decision line (see module docstring): live-sampled
    2026-09-14, 118/118 codex-armed tasks in this fit had ZERO
    `arbiter_pick=codex` lines in their own journal.md (dispatched via a
    path that never logged a route_resolved decision), while every sampled
    job json had `request.model` populated. Same glob join
    leadv2_lane_token_total already performs for the rollout file, one hop
    shorter (no threadId indirection needed -- the model lives on the job
    record itself, not the rollout)."""
    state_root = os.path.expanduser(
        os.environ.get("CODEX_GUARD_STATE_ROOT")
        or "~/.claude/plugins/data/codex-openai-codex/state"
    )
    matches = glob.glob(os.path.join(state_root, "*", "jobs", handle + ".json"))
    if len(matches) != 1:
        return None
    try:
        with open(matches[0]) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    model = (data.get("request") or {}).get("model")
    if not isinstance(model, str) or not model:
        return None
    # gpt-6-astra is the dispatch LAUNCHER's own default alias (leadv2-routing.yaml
    # router.dispatch_ladder / channels: id=codex, model: gpt-6-astra) — it is what
    # gets SENT in the request, not proof of which real tier codex resolved it to.
    # The mission is explicit: astra is not a fourth model. Treat it as unresolved.
    if model == "gpt-6-astra":
        return None
    return model


def _lib_path():
    return os.environ.get(
        "LEADV2_COST_ACTUALS_SH", os.path.join(HERE, "lib", "leadv2-cost-actuals.sh")
    )


def _token_total(repo_root, sig8):
    """Shell to the SAME leadv2_lane_token_total the dispatch/observed-cost
    loop uses — a second reader here must never drift from that join."""
    lib = _lib_path()
    if not repo_root or not os.path.isdir(repo_root) or not os.path.isfile(lib):
        return None
    try:
        proc = subprocess.run(
            ["bash", "-c", 'source "$0"; leadv2_lane_token_total "$1" "$2"', lib, repo_root, sig8],
            capture_output=True, text=True, timeout=10, env=os.environ.copy(),
        )
    except (subprocess.TimeoutExpired, OSError):
        return None
    out = (proc.stdout or "").strip()
    if not out or out == "-" or not out.isdigit():
        return None
    tot = int(out)
    return tot if tot > 0 else None


def _scan_util_readings(state_glob):
    """All util_codex snapshots across every task's journal.md, regardless
    of which arm that decision picked -- the arbiter reads live codex quota
    on EVERY consult, so this is the full shared-window time series."""
    readings = []
    for path in sorted(glob.glob(state_glob)):
        try:
            with open(path, errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        for line in lines:
            rm = READING_RE.search(line)
            if not rm:
                continue
            epoch = _ts_to_epoch(rm.group("ts"))
            if epoch is None:
                continue
            readings.append((epoch, int(rm.group("util"))))
    readings.sort()
    return readings


def _scan_codex_spawns():
    """Ground-truth codex spawns from arm-registered (never from a routing
    decision line -- see module docstring). Returns {(repo_root, sig8):
    [(epoch, handle), ...]}."""
    tasks = {}
    for path in _arm_registered_files():
        m = re.search(r"^(?P<root>.+)/docs/handoff/dispatch-(?P<sig8>[^/]+)/arm-registered$", path)
        if not m:
            continue
        root, sig8 = m.group("root"), m.group("sig8")
        try:
            with open(path, errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        events = [(int(am.group("epoch")), am.group("handle")) for am in
                  (ARM_CODEX_RE.match(line) for line in lines) if am]
        if events:
            tasks[(root, sig8)] = events
    return tasks


def build_intervals(readings, task_events):
    """task_events: list of (epoch, tokens, model_or_None). Mirrors
    leadv2-drain-weights.py's interval loop exactly (bisect over a sorted
    event-epoch list; delta<0 -> dropped_reset; delta==0 & no tokens ->
    dropped_idle), sourced from journal.md instead of rate_limit_history/
    turn_events."""
    task_events = sorted(task_events)
    event_epochs = [e for e, _tok, _model in task_events]
    intervals, dropped_reset, dropped_idle = [], 0, 0
    for (e0, p0), (e1, p1) in zip(readings, readings[1:]):
        # tokens in (e0, e1]: bisect_right excludes e0 (owned by the
        # previous interval) and includes e1, exactly as the sibling fitter.
        lo = bisect.bisect_right(event_epochs, e0)
        hi = bisect.bisect_right(event_epochs, e1)
        by_model = {}
        for _e, tok, model in task_events[lo:hi]:
            key = model or "unknown"
            by_model[key] = by_model.get(key, 0) + tok
        delta = p1 - p0
        if delta < 0:
            dropped_reset += 1
            continue
        tokens = sum(by_model.values())
        if delta == 0 and tokens == 0:
            dropped_idle += 1
            continue
        intervals.append((delta, by_model))
    return intervals, dropped_reset, dropped_idle


def _fit(intervals, models):
    y = [d for d, _bm in intervals]
    X = [[float(bm.get(m, 0)) for m in models] for _d, bm in intervals]
    w = nnls(X, y)
    pred = [sum(X[i][k] * w[k] for k in range(len(models))) for i in range(len(y))]
    mean_y = sum(y) / len(y)
    sst = sum((v - mean_y) ** 2 for v in y)
    sse = sum((y[i] - pred[i]) ** 2 for i in range(len(y)))
    r2 = (1 - sse / sst) if sst > 0 else float("nan")
    max_abs_corr, degenerate_pairs = 0.0, 0
    for a in range(len(models)):
        for b in range(a + 1, len(models)):
            ca = [X[i][a] for i in range(len(y))]
            cb = [X[i][b] for i in range(len(y))]
            r = _pearson(ca, cb)
            if r is None:
                degenerate_pairs += 1
            else:
                max_abs_corr = max(max_abs_corr, abs(r))
    return w, r2, max_abs_corr, degenerate_pairs


def main(argv):
    state_glob = _readings_glob()
    min_intervals = MIN_INTERVALS
    args = argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--state-glob" and i + 1 < len(args):
            state_glob = args[i + 1]
            i += 2
        elif args[i] == "--min-intervals" and i + 1 < len(args):
            min_intervals = int(args[i + 1])
            i += 2
        else:
            print("usage: leadv2-codex-drain-fit.py [--state-glob PATTERN] "
                  "[--min-intervals N]", file=sys.stderr)
            return 2

    readings = _scan_util_readings(state_glob)
    codex_spawns = _scan_codex_spawns()

    task_events = []
    resolved, unresolved_token, mixed_model, no_job_model = 0, 0, 0, 0
    for (root, sig8), events in codex_spawns.items():
        tokens = _token_total(root, sig8)
        if tokens is None:
            unresolved_token += 1
            continue
        resolved += 1
        last_epoch = max(e for e, _h in events)
        models = {m for m in (_job_model(h) for _e, h in events) if m}
        if len(models) == 1:
            model = next(iter(models))
        elif len(models) == 0:
            model, no_job_model = None, no_job_model + 1
        else:
            model, mixed_model = None, mixed_model + 1
        task_events.append((last_epoch, tokens, model))

    intervals, dropped_reset, dropped_idle = build_intervals(readings, task_events)
    kept = len(intervals)
    base = ("kept=%d threshold=%d dropped_reset=%d dropped_idle=%d "
            "codex_tasks_resolved=%d codex_tasks_unresolved_token=%d "
            "codex_tasks_mixed_model=%d codex_tasks_no_job_model=%d "
            "readings=%d"
            % (kept, min_intervals, dropped_reset, dropped_idle, resolved,
               unresolved_token, mixed_model, no_job_model, len(readings)))

    if kept < min_intervals:
        print("provider=codex %s NOT-ENOUGH-DATA" % base)
        return 0

    # (1) Aggregate provider-level fit: one column, total codex tokens.
    agg_models = ["codex_total"]
    agg_intervals = [(d, {"codex_total": sum(bm.values())}) for d, bm in intervals]
    w_agg, r2_agg, mac_agg, dp_agg = _fit(agg_intervals, agg_models)
    # Single-column fit: max_abs_corr/degenerate_pairs are trivially 0/0
    # (no pair exists to correlate) — printed anyway, per the binding method
    # rule to report them on EVERY fit quoted, not just the multi-column one.
    print("provider=codex %s r2=%.4f max_abs_corr=%.3f degenerate_pairs=%d "
          "weights=codex_total=%.8f"
          % (base, r2_agg, mac_agg, dp_agg, w_agg[0]))
    print("  codex_total weight=%.8f Δpct per token (per 1M tokens: %+.4f)"
          % (w_agg[0], w_agg[0] * 1e6))

    # (2) Per-model fit (terra/sol/luna), only over clean (non-mixed) tasks.
    per_model_models = sorted({m for _d, bm in intervals for m in bm if m != "unknown"})
    if len(per_model_models) >= 2:
        clean_intervals = [
            (d, {m: t for m, t in bm.items() if m != "unknown"})
            for d, bm in intervals
            if sum(v for k, v in bm.items() if k != "unknown") > 0
        ]
        w_pm, r2_pm, mac_pm, dp_pm = _fit(clean_intervals, per_model_models)
        print("provider=codex per_model kept=%d r2=%.4f max_abs_corr=%.3f "
              "degenerate_pairs=%d weights=%s"
              % (len(clean_intervals), r2_pm, mac_pm, dp_pm,
                 ",".join("%s=%.8f" % (m, w_pm[k]) for k, m in enumerate(per_model_models))))
        for k, m in enumerate(per_model_models):
            print("  %-16s weight=%.8f Δpct per token (per 1M tokens: %+.4f)"
                  % (m, w_pm[k], w_pm[k] * 1e6))
    else:
        print("provider=codex per_model NOT-ENOUGH-DATA distinct_models=%d"
              % len(per_model_models))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
