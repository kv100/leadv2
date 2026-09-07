#!/usr/bin/env bash
# leadv2-arm-receipts-import.sh — ARM-RECEIPTS-AND-HISTORICAL-IMPORT-01 (P3, Part A).
#
# One-shot historical importer. Walks the four stores that already hold real
# usage and are thrown away at the end of every run -- claude costs.yaml,
# glm/freepool meta.yaml, codex rollouts -- and appends phase=close records
# to the same ledger leadv2-arm-receipts.sh writes to, so the hand-written
# `cost:` numbers in leadv2-routing.yaml eventually have a real input.
#
# Join rule (non-negotiable, see /tmp/m-p3-lane.md section 4): a run is
# joined to a real decision ONLY by an identifier present on both sides --
# never nearest-timestamp, never title matching. Two lanes of the same arm
# run concurrently all day; nearest-timestamp matching would attribute one
# lane's burn to the other and the resulting number would look perfectly
# plausible and be wrong. A run that cannot be joined is written with
# usage_src=unjoined and COUNTED, never dropped.
#
# Idempotent: keyed on the same (lane_id, decision_id, attempt_id) triple as
# every other receipt; a candidate whose triple is already in the ledger is
# skipped. Re-running must add zero new records.
#
# Bash 3.2 safe. All parsing/joining/writing happens in one python3 process
# (not one per record) -- see PERFORMANCE note below the CLI arg parsing.

set -u

_lv2_ari_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# GATE-WRONG-ROOT-FALSE-DEAD-01: resolve the repo root via git, never by
# hop-counting "../" -- a script two directories deep looks identical to one
# three deep until it silently reads or writes the wrong tree.
_lv2_ari_repo_root="${LEADV2_ARM_RECEIPTS_REPO_ROOT:-}"
if [[ -z "${_lv2_ari_repo_root}" ]]; then
  _lv2_ari_repo_root="$(git -C "${_lv2_ari_script_dir}" rev-parse --show-toplevel 2>/dev/null)"
fi
if [[ -z "${_lv2_ari_repo_root}" ]]; then
  printf 'leadv2-arm-receipts-import: ERROR cannot_resolve_repo_root\n' >&2
  exit 1
fi

# shellcheck disable=SC1091
source "${_lv2_ari_script_dir}/lib/leadv2-arm-receipts.sh" || {
  printf 'leadv2-arm-receipts-import: ERROR cannot_source_arm_receipts_lib\n' >&2
  exit 1
}

_lv2_ari_ledger="$(_lv2_ar_ledger_path)"

# Reuse the same test-context guard the writer uses: a test suite that
# forgets to redirect LEADV2_ARM_RECEIPTS_LEDGER must never be able to run
# the real importer against the real ledger.
if declare -F lv2_test_context >/dev/null 2>&1 && lv2_test_context; then
  if [[ -z "${LEADV2_ARM_RECEIPTS_LEDGER:-}" ]]; then
    printf 'leadv2-arm-receipts-import: REFUSED: test context without LEADV2_ARM_RECEIPTS_LEDGER redirect\n' >&2
    exit 3
  fi
fi

mkdir -p "$(dirname "${_lv2_ari_ledger}")" 2>/dev/null || true

# PERFORMANCE: 4 stores, up to ~2100 codex rollout files (a cheap first-line
# cwd pre-filter cuts that to the ~750 that touch a worktree) and ~400
# claude costs.yaml files measured live in this repo on 2026-09-07. Shelling
# out to python3 once per candidate record (as the writer does for a single
# live attempt) would mean 1000+ process spawns for one import run; instead
# this whole walk+join+dedup+encode pass runs in ONE python3 process, and
# the ledger is opened exactly once for exactly one os.write() of the whole
# new-records blob -- still a single O_APPEND write() call, just of a batch
# instead of a line, which is what "one write() per record" is protecting
# against (partial-line interleaving) in the first place.
python3 - \
  "${_lv2_ari_repo_root}" \
  "${_lv2_ari_ledger}" \
  "${LEADV2_ARM_RECEIPTS_GLM_ROOT:-${HOME}/.claude/cache/glm-runs}" \
  "${LEADV2_ARM_RECEIPTS_FREEPOOL_ROOT:-${HOME}/.claude/cache/freepool-runs}" \
  "${LEADV2_ARM_RECEIPTS_CODEX_ROOT:-${HOME}/.codex/sessions}" <<'PY_ARM_RECEIPTS_IMPORT'
import json
import os
import sys

repo_root, ledger_path, glm_root, freepool_root, codex_root = sys.argv[1:6]

SCHEMA_KEYS = [
    "lane_id", "decision_id", "attempt_id", "phase",
    "kind", "role", "arm", "model", "tier", "effort", "account_label",
    "ts_open", "ts_close", "duration_s",
    "tokens_in", "tokens_out", "cache_read_input_tokens", "cache_creation_input_tokens",
    "turns", "outcome", "fallback_depth", "usage_src", "usage_is_estimate",
]
NUMERIC_KEYS = set([
    "duration_s", "tokens_in", "tokens_out",
    "cache_read_input_tokens", "cache_creation_input_tokens",
    "turns", "fallback_depth",
])


def _num(v):
    if v is None or v == "":
        return None
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return v
    try:
        return int(v)
    except (TypeError, ValueError):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None


def make_row(**fields):
    row = {}
    for k in SCHEMA_KEYS:
        v = fields.get(k)
        if k in NUMERIC_KEYS:
            v = _num(v)
        row[k] = v
    return row


def row_to_json(row):
    return json.dumps(row, sort_keys=False)


# ---- tiny stdlib-only flat-YAML readers ------------------------------------
# Deliberately not PyYAML: no script in this repo imports it, and this
# plugin is symlinked, unmodified, into persona-engine/m3-market/respiro-ios
# -- adding a new third-party import here would be a dependency none of
# those repos asked for. Every file these readers touch is machine-written
# by this repo's own scripts (claude-subsession.sh, the glm/freepool run
# wrappers), one `key: value` per line, no nesting beyond one list level.

def _kv_into(d, line):
    if ":" not in line:
        return
    k, v = line.split(":", 1)
    k = k.strip()
    v = v.strip()
    if v == "" or v == "null" or v == "~":
        v = None
    elif len(v) >= 2 and v[0] == '"' and v[-1] == '"':
        v = v[1:-1]
    d[k] = v


def parse_flat_yaml(path):
    d = {}
    try:
        fh = open(path, "r", errors="replace")
    except OSError:
        return d
    with fh:
        for raw in fh:
            line = raw.rstrip("\n")
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            _kv_into(d, s)
    return d


def parse_yaml_list_of_flat_dicts(path):
    records = []
    cur = None
    try:
        fh = open(path, "r", errors="replace")
    except OSError:
        return records
    with fh:
        for raw in fh:
            line = raw.rstrip("\n")
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if line.startswith("- "):
                if cur is not None:
                    records.append(cur)
                cur = {}
                _kv_into(cur, line[2:].strip())
            elif line.startswith("  ") and cur is not None:
                _kv_into(cur, s)
    if cur is not None:
        records.append(cur)
    return records


# ---- the ONE join body: identifier must be present on both sides ----------
# NEGATIVE CONTROL 2 TARGET (E2E-KILLRATE-01): replacing the directory-
# existence check below with nearest-timestamp or title matching must turn
# test-arm-receipt-import-unjoined.sh red -- that suite asserts the tally,
# not just that rows exist, so a mutation here that fabricates a join still
# shows up as a wrong imported/unjoined split.
def resolve_decision_id(root, candidate):
    if not candidate:
        return None
    base = os.path.join(root, "docs", "handoff")
    direct = os.path.join(base, candidate)
    if os.path.isdir(direct):
        return candidate
    try:
        entries = os.listdir(base)
    except OSError:
        return None
    prefix = "dispatch-" + candidate
    for e in entries:
        if e == prefix or e.startswith(prefix + "-"):
            return candidate
    return None


def extract_worktree_candidate(cwd):
    if not cwd:
        return None
    marker = "/.claude/worktrees/"
    idx = cwd.find(marker)
    if idx == -1:
        return None
    rest = cwd[idx + len(marker):]
    seg = rest.split("/", 1)[0]
    return seg or None


# ---- store walkers: each returns a list of (row_dict, joined_bool) --------

def walk_claude(root):
    out = []
    base = os.path.join(root, "docs", "handoff")
    try:
        entries = sorted(os.listdir(base))
    except OSError:
        return out
    for e in entries:
        if not e.startswith("dispatch-"):
            continue
        costs_path = os.path.join(base, e, "costs.yaml")
        if not os.path.isfile(costs_path):
            continue
        decision_id = e[len("dispatch-"):]
        for rec in parse_yaml_list_of_flat_dicts(costs_path):
            session_id = rec.get("session_id")
            if not session_id:
                continue
            row = make_row(
                lane_id=decision_id, decision_id=decision_id, attempt_id=session_id,
                phase="close", kind="claude", role=rec.get("role"), arm="claude",
                model=rec.get("model"), tier=None, effort=None, account_label=None,
                ts_open=None, ts_close=rec.get("timestamp"), duration_s=rec.get("duration_sec"),
                tokens_in=rec.get("input_tokens"), tokens_out=rec.get("output_tokens"),
                cache_read_input_tokens=None, cache_creation_input_tokens=None,
                turns=None, outcome="unknown", fallback_depth=None,
                usage_src="imported", usage_is_estimate=False,
            )
            out.append((row, True))
    return out


def _outcome_from_status(status):
    if status in ("success", "ok", "won"):
        return "win"
    if status == "failed":
        return "fail"
    if status == "timeout":
        return "timeout"
    return "unknown"


def walk_meta_store(root, kind, repo_root):
    out = []
    try:
        entries = sorted(os.listdir(root))
    except OSError:
        return out
    for e in entries:
        meta_path = os.path.join(root, e, "meta.yaml")
        if not os.path.isfile(meta_path):
            continue
        rec = parse_flat_yaml(meta_path)
        run_id = rec.get("run_id") or e
        candidate = extract_worktree_candidate(rec.get("cwd"))
        decision_id = resolve_decision_id(repo_root, candidate)
        joined = decision_id is not None
        is_estimate = str(rec.get("usage_is_estimate", "")).strip().lower() in ("1", "true", "yes")
        row = make_row(
            lane_id=decision_id, decision_id=decision_id, attempt_id=run_id,
            phase="close", kind=kind, role=None, arm=kind,
            model=rec.get("model"), tier=None, effort=None, account_label=None,
            ts_open=rec.get("started_at"), ts_close=rec.get("finished_at"),
            duration_s=rec.get("duration_s"),
            tokens_in=rec.get("tokens_in"), tokens_out=rec.get("tokens_out"),
            cache_read_input_tokens=rec.get("cache_read_input_tokens"),
            cache_creation_input_tokens=rec.get("cache_creation_input_tokens"),
            turns=rec.get("turns"), outcome=_outcome_from_status(rec.get("status")),
            fallback_depth=None, usage_src=("imported" if joined else "unjoined"),
            usage_is_estimate=is_estimate,
        )
        out.append((row, joined))
    return out


def _codex_first_line_cwd(path):
    try:
        with open(path, "r", errors="replace") as fh:
            first = fh.readline()
    except OSError:
        return None
    try:
        d = json.loads(first)
    except ValueError:
        return None
    return (d.get("payload") or {}).get("cwd")


def _iso_to_epoch(ts):
    if not ts:
        return None
    try:
        import datetime
        s = ts.replace("Z", "+00:00")
        return datetime.datetime.fromisoformat(s).timestamp()
    except (ValueError, TypeError):
        return None


def walk_codex(root, repo_root):
    out = []
    matched_paths = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if not (fn.startswith("rollout-") and fn.endswith(".jsonl")):
                continue
            p = os.path.join(dirpath, fn)
            cwd = _codex_first_line_cwd(p)
            if cwd and "/.claude/worktrees/" in cwd:
                matched_paths.append((p, cwd))

    for p, cwd in matched_paths:
        attempt_id = None
        model = None
        ts_open = None
        ts_close = None
        turns = 0
        final_usage = None
        try:
            fh = open(p, "r", errors="replace")
        except OSError:
            continue
        with fh:
            for raw in fh:
                line = raw.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                ts = d.get("timestamp")
                if ts:
                    if ts_open is None:
                        ts_open = ts
                    ts_close = ts
                t = d.get("type")
                payload = d.get("payload") or {}
                if t == "session_meta" and attempt_id is None:
                    attempt_id = payload.get("id") or payload.get("session_id")
                elif t == "turn_context" and model is None:
                    model = payload.get("model")
                elif t == "event_msg" and payload.get("type") == "task_complete":
                    turns += 1
                elif t == "event_msg" and payload.get("type") == "token_count":
                    info = payload.get("info") or {}
                    usage = info.get("total_token_usage")
                    if usage:
                        final_usage = usage

        if attempt_id is None:
            continue
        candidate = extract_worktree_candidate(cwd)
        decision_id = resolve_decision_id(repo_root, candidate)
        joined = decision_id is not None
        tokens_in = None
        tokens_out = None
        cache_read = None
        if final_usage:
            tokens_in = final_usage.get("input_tokens")
            out_tok = final_usage.get("output_tokens")
            reasoning_tok = final_usage.get("reasoning_output_tokens")
            if out_tok is not None or reasoning_tok is not None:
                tokens_out = (out_tok or 0) + (reasoning_tok or 0)
            cache_read = final_usage.get("cached_input_tokens")
        eo, ec = _iso_to_epoch(ts_open), _iso_to_epoch(ts_close)
        duration_s = (ec - eo) if (eo is not None and ec is not None) else None
        row = make_row(
            lane_id=decision_id, decision_id=decision_id, attempt_id=attempt_id,
            phase="close", kind="codex", role=None, arm="codex",
            model=model, tier=None, effort=None, account_label=None,
            ts_open=ts_open, ts_close=ts_close, duration_s=duration_s,
            tokens_in=tokens_in, tokens_out=tokens_out,
            cache_read_input_tokens=cache_read, cache_creation_input_tokens=None,
            turns=turns, outcome="unknown", fallback_depth=None,
            usage_src=("imported" if joined else "unjoined"), usage_is_estimate=False,
        )
        out.append((row, joined))
    return out


# ---- existing-ledger identity set, for idempotency ------------------------

def load_existing_identities(path):
    seen = set()
    if not os.path.isfile(path):
        return seen
    try:
        fh = open(path, "r", errors="replace")
    except OSError:
        return seen
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            seen.add((rec.get("lane_id"), rec.get("decision_id"), rec.get("attempt_id")))
    return seen


def main():
    claude_rows = walk_claude(repo_root)
    glm_rows = walk_meta_store(glm_root, "glm", repo_root)
    freepool_rows = walk_meta_store(freepool_root, "freepool", repo_root)
    codex_rows = walk_codex(codex_root, repo_root)

    all_rows = claude_rows + glm_rows + freepool_rows + codex_rows

    imported_n = sum(1 for _row, joined in all_rows if joined)
    unjoined_n = sum(1 for _row, joined in all_rows if not joined)

    existing = load_existing_identities(ledger_path)
    new_lines = []
    for row, _joined in all_rows:
        ident = (row["lane_id"], row["decision_id"], row["attempt_id"])
        if ident in existing:
            continue
        existing.add(ident)
        new_lines.append(row_to_json(row))

    if new_lines:
        blob = ("\n".join(new_lines) + "\n").encode("utf-8")
        fd = os.open(ledger_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
        try:
            os.write(fd, blob)
        finally:
            os.close(fd)

    print(
        "imported=%d unjoined=%d stores=claude:%d,glm:%d,freepool:%d,codex:%d"
        % (
            imported_n, unjoined_n,
            len(claude_rows), len(glm_rows), len(freepool_rows), len(codex_rows),
        )
    )
    print("new_records=%d" % len(new_lines))


main()
PY_ARM_RECEIPTS_IMPORT
