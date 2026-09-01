#!/usr/bin/env bash
# leadv2-cache-truth.sh (CACHE-TRUTH-01) — measure prompt-cache hit rate per
# worker arm from the streamed JSONL a dispatch produces.
#
# WHY: nobody had ever measured whether the stable prefix (system prompt,
# brief, CLAUDE.md, MCP tool schemas) that every arm re-sends on every turn
# was actually being served from Anthropic's / GLM's / Kimi's prompt cache.
# 2026-09-01 founder ask. This script answers with numbers, not prose.
#
# Anthropic's `claude -p` reports cache_read_input_tokens and
# cache_creation_input_tokens on every assistant message's `usage` block in
# stream-json. Z.AI (GLM) and TokenRouter (freepool / kimi) either report
# their own cache fields there or report none at all — a MISSING field is
# itself a finding ("unreported"), never coerced to zero, because zero would
# silently claim "measured no cache" when the truth is "never told us".
#
# usage: leadv2-cache-truth.sh <run-dir|stream-file> [<run-dir|stream-file> ...]
#   run-dir     a dir containing journal.jsonl (glm/freepool/kimi cache runs)
#               or developer.stream.jsonl (docs/handoff/dispatch-*)
#   stream-file a JSONL file directly (any of the above shapes)
#
# Output: one TSV-ish row per input, printed to stdout:
#   arm  run  turns  input_tokens  cache_read  cache_creation  hit_ratio  first_break  reported
# Events are DE-DUPLICATED by message.id first (streaming deltas re-emit the
# same assistant message several times; the last event for a given id wins),
# so `turns` counts unique messages, not wire events (CACHE-TRUTH-01 round 2:
# without this, totals were inflated ~1.8x on real dispatch streams). Events
# with no message.id are each treated as their own unique turn (never
# collapsed together) since we cannot prove they are duplicates.
# hit_ratio is computed ONLY over REPORTED turns (those whose usage dict
# carries a cache_read_input_tokens or cache_creation_input_tokens key) =
# cache_read / (input + cache_read + cache_creation) summed across reported
# turns. "unreported" replaces hit_ratio and first_break when ZERO turns in
# the stream report cache fields — this is a per-run, not per-turn-1,
# decision: a stream that is a MIX of reported and unreported turns is
# classified using only the reported subset, and `reported` (last column)
# shows N/M so a mixed run is never silently rounded to "all reported" or
# "all unreported".
# first_break = 1-based index (within reported turns only, turn > 1) of the
# first reported turn whose PER-TURN ratio drops below 0.5, or "none".
#
# Bash 3.2 compatible: no associative arrays, no readarray. Parsing itself is
# delegated to python3 (repo convention — see leadv2-router-v2.py) because
# hand-rolled JSONL parsing in bash is exactly the kind of thing that lies
# quietly on malformed lines.
set -u

usage() {
  echo "usage: $(basename "$0") <run-dir|stream-file> [...]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage

_lv2_realpath() { python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }

# arm_for_path <path> — classify by directory convention. Never derived by
# counting ../ hops (GATE-WRONG-ROOT-FALSE-DEAD-01) — string containment on
# the resolved absolute path only.
arm_for_path() {
  local p="$1"
  case "$p" in
    */glm-runs/*) echo "glm" ;;
    */freepool-runs/*) echo "freepool" ;;
    */kimi-runs/*) echo "kimi" ;;
    */claude-runs/*) echo "claude-subsession" ;;
    */docs/handoff/dispatch-*) echo "claude-native" ;;
    *) echo "unknown" ;;
  esac
}

# resolve_stream <run-dir-or-file> — echoes the JSONL file to parse, or
# nothing + non-zero rc if none found.
resolve_stream() {
  local p="$1" real
  real="$(_lv2_realpath "$p")" || return 1
  if [[ -f "$real" ]]; then
    echo "$real"
    return 0
  fi
  if [[ -d "$real" ]]; then
    if [[ -f "$real/developer.stream.jsonl" ]]; then
      echo "$real/developer.stream.jsonl"
      return 0
    fi
    if [[ -f "$real/journal.jsonl" ]]; then
      echo "$real/journal.jsonl"
      return 0
    fi
  fi
  return 1
}

printf 'arm\trun\tturns\tinput_tokens\tcache_read\tcache_creation\thit_ratio\tfirst_break\treported\n'

rc=0
for arg in "$@"; do
  stream="$(resolve_stream "$arg")"
  if [[ -z "$stream" ]]; then
    printf '%s\t%s\tERROR: no journal.jsonl or developer.stream.jsonl found\n' "unknown" "$arg" >&2
    rc=1
    continue
  fi
  arm="$(arm_for_path "$stream")"
  run="$(basename "$(dirname "$stream")")"
  python3 - "$stream" "$arm" "$run" <<'PYEOF'
import json, sys

stream_path, arm, run = sys.argv[1], sys.argv[2], sys.argv[3]

# De-dup by message.id: a stream-json file re-emits the same assistant
# message several times (streaming deltas + final); keep only the LAST event
# seen for a given id (CACHE-TRUTH-01 round 2 finding: undeduped totals were
# inflated ~1.8x on real dispatch streams). Events without an id (or with a
# non-hashable/empty id) are each kept as their own unique turn — we cannot
# prove they are duplicates, so never collapse them together.
by_id = {}   # id -> (inp, cr, cc, has_cache_key)
unkeyed = []  # list of (inp, cr, cc, has_cache_key) for events without an id
order = []   # insertion order of ids, for stable first_break/turn ordering

with open(stream_path, "r", errors="replace") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") != "assistant":
            continue
        msg = d.get("message") or {}
        usage = msg.get("usage")
        if not isinstance(usage, dict):
            continue
        inp = usage.get("input_tokens", 0) or 0
        has_cache_key = ("cache_read_input_tokens" in usage) or ("cache_creation_input_tokens" in usage)
        cr = usage.get("cache_read_input_tokens", 0) or 0
        cc = usage.get("cache_creation_input_tokens", 0) or 0
        mid = msg.get("id")
        rec = (inp, cr, cc, has_cache_key)
        if mid:
            if mid not in by_id:
                order.append(mid)
            by_id[mid] = rec  # last event for this id wins
        else:
            unkeyed.append(rec)

# Reassemble unique turns in first-seen order (ids) followed by unkeyed
# events in stream order — ordering only matters for first_break, and any
# unkeyed events are, by construction, never duplicates of each other.
turns = [by_id[mid] for mid in order] + unkeyed

if not turns:
    print("%s\t%s\t0\t0\t0\t0\tunreported\tnone\t0/0" % (arm, run))
    sys.exit(0)

reported_turns = [t for t in turns if t[3]]
n_reported = len(reported_turns)
n_total = len(turns)
reported_col = "%d/%d" % (n_reported, n_total)

if n_reported == 0:
    total_in = sum(t[0] for t in turns)
    print("%s\t%s\t%d\t%d\t0\t0\tunreported\tunreported\t%s" % (arm, run, n_total, total_in, reported_col))
    sys.exit(0)

total_in = sum(t[0] for t in reported_turns)
total_cr = sum(t[1] for t in reported_turns)
total_cc = sum(t[2] for t in reported_turns)
denom = total_in + total_cr + total_cc
overall_ratio = (total_cr / denom) if denom > 0 else 0.0

first_break = "none"
for idx, (inp, cr, cc, _hk) in enumerate(reported_turns, start=1):
    if idx == 1:
        continue  # turn 1 never has cache to read from - not a break
    d = inp + cr + cc
    if d <= 0:
        continue
    ratio = cr / d
    if ratio < 0.5:
        first_break = str(idx)
        break

print("%s\t%s\t%d\t%d\t%d\t%d\t%.4f\t%s\t%s" % (
    arm, run, n_total, total_in, total_cr, total_cc, overall_ratio, first_break, reported_col
))
PYEOF
  pyrc=$?
  if [[ $pyrc -ne 0 ]]; then
    rc=1
  fi
done

exit $rc
