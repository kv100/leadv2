#!/usr/bin/env bash
# leadv2-arm-receipts.sh — ARM-RECEIPTS-AND-HISTORICAL-IMPORT-01 (P3, Part A).
#
# Append-only observation ledger for what a launched arm actually cost, so
# the hand-written `cost:` numbers in plugins/leadv2/config/leadv2-routing.yaml
# (router_v2.capability_matrix) stop being the only input to a price. This
# lane changes NO decision -- it is pure instrumentation. A writer failure
# here must never break a caller: every entry point returns non-zero on
# failure instead of throwing, so a `|| true` at the call site is sufficient
# for a caller that wants to fail open.
#
# Ledger: ~/.claude/state/leadv2/arm-receipts.jsonl, OUTSIDE the git tree.
# A shared ledger committed inside the tree gets a stale copy per worktree
# -- measured 2026-09-06, 12 of 12 worktree copies were 11-76 lines shorter
# than the canonical file. A ledger with twelve divergent versions is not a
# ledger, so this one lives under $HOME, never under the repo.
#
# Append-only discipline: one JSON object per line, opened O_APPEND, ONE
# printf/write() call per record (the line is fully built in python3 first;
# bash then does exactly one `printf '%s\n' "$line" >> "$ledger"` -- never a
# loop, never a rewrite-in-place). Rotation, if ever added, is "rename and
# start a new file", never an edit of this one.
#
# Identity: (lane_id, decision_id, attempt_id). sig8 is NOT a key -- it is a
# short hash that collides and is reused across resume and arm-advance;
# joining on it silently merges two different attempts into one receipt and
# corrupts every number downstream.
#
# SEAM (documented, not wired here on purpose): lv2_arm_receipt_write below
# is the ONE named seam _dl_note (plugins/leadv2/scripts/leadv2-dispatch-code.sh:2164)
# is meant to call -- once at attempt-open (phase=open, usage fields empty:
# an open with no matching close is a real observation, a worker that died
# before reporting, and must stay visible as one, never backfilled with a
# synthetic close) and once at attempt-close (phase=close, usage populated).
# Wiring leadv2-dispatch-code.sh is a separate, serial lane's job (P1,
# ARMS-CANNOT-LAUNCH-THEMSELVES-01) -- this file only builds the mechanism.
#
# Bash 3.2 safe: no associative arrays, no ${var^^}, no mapfile, no readarray.

[[ -n "${__LEADV2_ARM_RECEIPTS_SH:-}" ]] && return 0
__LEADV2_ARM_RECEIPTS_SH=1

_lv2_ar_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# TESTS-POLLUTE-REAL-JOURNAL-01 pattern reused: detect test context so a
# suite that forgets to redirect LEADV2_ARM_RECEIPTS_LEDGER can never
# silently append fixture rows to the real, shared ledger every other repo
# on the host reads.
_LV2_AR_TEST_CONTEXT_SH="${_lv2_ar_lib_dir}/leadv2-test-context.sh"
[[ -f "${_LV2_AR_TEST_CONTEXT_SH}" ]] || _LV2_AR_TEST_CONTEXT_SH="${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}/plugins/leadv2/scripts/lib/leadv2-test-context.sh"
if [[ -f "${_LV2_AR_TEST_CONTEXT_SH}" ]]; then
  # shellcheck disable=SC1090
  source "${_LV2_AR_TEST_CONTEXT_SH}" || true
fi

# _lv2_ar_ledger_path -> stdout: the ledger path. LEADV2_ARM_RECEIPTS_LEDGER
# overrides for tests/fixtures/the importer's own idempotency probes.
_lv2_ar_ledger_path() {
  printf '%s\n' "${LEADV2_ARM_RECEIPTS_LEDGER:-${HOME}/.claude/state/leadv2/arm-receipts.jsonl}"
}

# _lv2_ar_build_json_line <23 fields, see lv2_arm_receipt_write> -> stdout:
# one JSON object, no trailing newline. Never shell-interpolates a field
# value into anything executed -- every value reaches python3 as an argv
# string and is encoded via json.dumps, so no field can break the record
# shape or escape into another key.
_lv2_ar_build_json_line() {
  python3 -c '
import json, sys
a = sys.argv[1:]
if len(a) != 23:
    sys.exit(1)
keys = ["lane_id", "decision_id", "attempt_id", "phase",
        "kind", "role", "arm", "model", "tier", "effort", "account_label",
        "ts_open", "ts_close", "duration_s",
        "tokens_in", "tokens_out", "cache_read_input_tokens", "cache_creation_input_tokens",
        "turns", "outcome", "fallback_depth", "usage_src", "usage_is_estimate"]
numeric = set(["duration_s", "tokens_in", "tokens_out", "cache_read_input_tokens",
               "cache_creation_input_tokens", "turns", "fallback_depth"])
rec = {}
for k, v in zip(keys, a):
    if k == "usage_is_estimate":
        rec[k] = v.strip().lower() in ("1", "true", "yes")
    elif k in numeric:
        if v == "":
            rec[k] = None
        else:
            try:
                rec[k] = int(v)
            except ValueError:
                try:
                    rec[k] = float(v)
                except ValueError:
                    rec[k] = None
    else:
        rec[k] = v if v != "" else None
sys.stdout.write(json.dumps(rec, sort_keys=False))
' "$@"
}

# lv2_arm_receipt_write <lane_id> <decision_id> <attempt_id> <phase:open|close>
#   <kind> <role> <arm> <model> <tier> <effort> <account_label>
#   <ts_open> <ts_close> <duration_s>
#   <tokens_in> <tokens_out> <cache_read_input_tokens> <cache_creation_input_tokens>
#   <turns> <outcome> <fallback_depth> <usage_src> <usage_is_estimate>
#
# account_label is a LABEL ONLY ("personal"/"work") -- never an account id,
# email, or token. Any empty field is written as JSON null, never a
# fabricated zero or empty string dressed up as a real observation.
#
# Returns 1 on missing identity, bad phase, or a write failure. Returns 3 if
# refused by the test-context guard (see leadv2-test-context.sh). Never
# throws past this function.
lv2_arm_receipt_write() {
  if [[ $# -ne 23 ]]; then
    printf 'lv2_arm_receipt_write: ERROR wrong_arg_count got=%s want=23\n' "$#" >&2
    return 1
  fi
  local lane_id="$1" decision_id="$2" attempt_id="$3" phase="$4" \
        kind="$5" role="$6" arm="$7" model="$8" tier="$9" effort="${10}" \
        account_label="${11}" ts_open="${12}" ts_close="${13}" duration_s="${14}" \
        tokens_in="${15}" tokens_out="${16}" cache_read_input_tokens="${17}" \
        cache_creation_input_tokens="${18}" turns="${19}" outcome="${20}" \
        fallback_depth="${21}" usage_src="${22}" usage_is_estimate="${23}"

  if [[ -z "${lane_id}" || -z "${decision_id}" || -z "${attempt_id}" ]]; then
    printf 'lv2_arm_receipt_write: ERROR missing_identity lane_id=%s decision_id=%s attempt_id=%s\n' \
      "${lane_id}" "${decision_id}" "${attempt_id}" >&2
    return 1
  fi
  case "${phase}" in
    open|close) ;;
    *)
      printf 'lv2_arm_receipt_write: ERROR bad_phase phase=%s\n' "${phase}" >&2
      return 1 ;;
  esac

  local ledger
  ledger="$(_lv2_ar_ledger_path)"

  if declare -F lv2_test_context >/dev/null 2>&1 && lv2_test_context; then
    if [[ -z "${LEADV2_ARM_RECEIPTS_LEDGER:-}" ]]; then
      if declare -F lv2_refuse_test_write >/dev/null 2>&1; then
        lv2_refuse_test_write "lv2_arm_receipt_write" "${ledger}" "LEADV2_ARM_RECEIPTS_LEDGER"
      else
        printf 'lv2_arm_receipt_write: REFUSED: test context without LEADV2_ARM_RECEIPTS_LEDGER redirect -- refusing to append to %s\n' "${ledger}" >&2
      fi
      return 3
    fi
  fi

  mkdir -p "$(dirname "${ledger}")" 2>/dev/null || true

  local line
  line="$(_lv2_ar_build_json_line \
    "${lane_id}" "${decision_id}" "${attempt_id}" "${phase}" \
    "${kind}" "${role}" "${arm}" "${model}" "${tier}" "${effort}" "${account_label}" \
    "${ts_open}" "${ts_close}" "${duration_s}" \
    "${tokens_in}" "${tokens_out}" "${cache_read_input_tokens}" "${cache_creation_input_tokens}" \
    "${turns}" "${outcome}" "${fallback_depth}" "${usage_src}" "${usage_is_estimate}")" || return 1
  [[ -n "${line}" ]] || return 1

  printf '%s\n' "${line}" >> "${ledger}" 2>/dev/null || return 1
}

# lv2_arm_receipt_read <kind> <role> <arm> <model> <tier> <effort>
# stdout: "n=<count> tokens_in=<sum> tokens_out=<sum> cache_read_input_tokens=<sum> cache_creation_input_tokens=<sum>"
#
# Sums phase=close records matching the launch tuple EXACTLY. `n` is always
# printed alongside the sums (P3 spec: "reader returns sums AND n, always")
# so a caller can never mistake one sample for a measurement. No
# estimation, decay, or blending -- that is a later lane's job.
lv2_arm_receipt_read() {
  if [[ $# -ne 6 ]]; then
    printf 'lv2_arm_receipt_read: ERROR wrong_arg_count got=%s want=6\n' "$#" >&2
    return 1
  fi
  local kind="$1" role="$2" arm="$3" model="$4" tier="$5" effort="$6"
  local ledger
  ledger="$(_lv2_ar_ledger_path)"
  if [[ ! -f "${ledger}" ]]; then
    printf 'n=0 tokens_in=0 tokens_out=0 cache_read_input_tokens=0 cache_creation_input_tokens=0\n'
    return 0
  fi
  python3 -c '
import json, sys
kind, role, arm, model, tier, effort, path = sys.argv[1:8]
n = 0
sums = {"tokens_in": 0, "tokens_out": 0, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 0}
try:
    fh = open(path, "r", errors="replace")
except OSError:
    fh = None
if fh is not None:
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("phase") != "close":
                continue
            key = (rec.get("kind"), rec.get("role"), rec.get("arm"),
                   rec.get("model"), rec.get("tier"), rec.get("effort"))
            if key != (kind, role, arm, model, tier, effort):
                continue
            n += 1
            for k in sums:
                v = rec.get(k)
                if isinstance(v, (int, float)) and not isinstance(v, bool):
                    sums[k] += v
print("n=%d tokens_in=%d tokens_out=%d cache_read_input_tokens=%d cache_creation_input_tokens=%d" % (
    n, sums["tokens_in"], sums["tokens_out"],
    sums["cache_read_input_tokens"], sums["cache_creation_input_tokens"]))
' "${kind}" "${role}" "${arm}" "${model}" "${tier}" "${effort}" "${ledger}"
}
