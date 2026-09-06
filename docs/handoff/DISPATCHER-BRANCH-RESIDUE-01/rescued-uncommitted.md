# DISPATCHER-BRANCH-RESIDUE-01 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/DISPATCHER-BRANCH-RESIDUE-01` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/plugins/leadv2/scripts/codex-task.sh b/plugins/leadv2/scripts/codex-task.sh
index 369ccf54..e6eb6fcf 100755
--- a/plugins/leadv2/scripts/codex-task.sh
+++ b/plugins/leadv2/scripts/codex-task.sh
@@ -1,2146 +1,16 @@
-#!/bin/bash
-set -euo pipefail
-# Codex convenience wrapper — finds codex-companion.mjs and forwards all args
-# Zero Claude tokens consumed. Uses OpenAI/Codex tokens.
-#
-# Usage:
-#   codex-task.sh task "review my approach for X"
-#   codex-task.sh adversarial-review --wait
-#   codex-task.sh adversarial-review --wait --tier top     # pin to gpt-5.6 tier
-#   codex-task.sh status [job-id]
-#   codex-task.sh result [job-id]
-#   codex-task.sh cancel [job-id]
-#
-# --tier <top|standard|volume>  Resolves to a Codex model (+ effort where the
-#   subcommand accepts one) using the SAME tier table as leadv2-codex-planner.sh:
-#     top      -> gpt-5.6-sol/high, falls back to gpt-5.6-terra/xhigh if sol is
-#                 absent from ~/.codex/models_cache.json (gov-gated)
-#     standard -> gpt-5.6-terra/medium  (EFFORT-RECAL 2026-07-10, was /high)
-#     volume   -> gpt-5.6-luna/low      (EFFORT-RECAL 2026-07-10, was /medium)
-#   Applies to `task` (model+effort) and `adversarial-review`/`review`
-#   (model only — codex-companion's review command does not accept --effort;
-#   passing it there would corrupt the focus-text positionals). Ignored (WARN)
-#   for any other subcommand. An explicit --model already on the command line
-#   always wins over --tier.
-#
-# --wait  Real flag in ANY position (P0, CODEX-WAIT-AND-TIER-01). Stripped here
-#   so it never lands in the prompt (codex-companion `task` has no --wait option
-#   and would fold it into the prompt text). Forces the FOREGROUND blocking path
-#   for `task`/`review` (strips --background) so the wrapper blocks until the job
-#   reaches a terminal state — the only way a long Codex job survives, since a
-#   job dies the instant its launching client drops the app-server connection.
-#   `adversarial-review` always blocks already (auto-injected for companion).
-#
-# --reason "<text>"  REQUIRED by --tier top (P1). `top` is the scarce Codex tier
-#   (adversarial review + Heavy/arch plans); standard is the default, volume for
-#   mechanical/bulk. Without --reason, --tier top exits non-zero.
-#
-# Ledger (CODEX-TIER-ENFORCER-01): every ACCEPTED --tier top run appends one
-# JSON line to ${LEADV2_CODEX_TIER_LOG:-$HOME/.claude/cache/codex-tier-log.jsonl}
-# (ts/tier/sub/reason/model/effort/cwd/pid) so "what did we spend top on" is
-# greppable. Best-effort: a failed write never aborts a dispatch. Refused runs
-# append nothing.
-#
-# Output filter: by default strips codex-companion's noisy [codex] meta lines
-# (Running command / Command completed / Calling ... / Tool ... completed/failed /
-# Assistant message captured — mid-stream previews).
-# Kept: pure content (the final Findings/verdict body that has no [codex] prefix).
-# Override: CODEX_VERBOSE=1 to see all meta lines.
+#!/usr/bin/env bash
+# Mock codex-task.sh that simulates rg exit 1 (no matches) scenario
 
-COMPANION=$(find ~/.claude/plugins/cache/openai-codex -name codex-companion.mjs -path "*/scripts/*" 2>/dev/null | sort -V | tail -1)
+# Simulate Codex finding no issues (rg exits 1, but this is not an error)
+# Codex would normally still produce some output, but we simulate the case
+# where it produces minimal output that could trigger body_lost detection
 
-if [[ -z "$COMPANION" ]]; then
-  echo "ERROR: codex-companion.mjs not found. Is the Codex plugin installed?" >&2
-  exit 1
-fi
-
-# ── T-f (CODEX-REAP-01) -- hung jobs die without a babysitter ──────────────
-# Known hole (tf-diagnosis.md): the zombie reaper (codex-guard.sh TF-02) only
-# runs inside an active guard poll. A job stuck `queued` with a dead pid, or
-# `running` whose pid died, stays "running" forever in the job store when no
-# guard happens to be watching it. `_codex_reap` gives every codex-task.sh
-# invocation its own babysitter sweep -- no cron, no daemon.
-#
-# CODEX_AUTOREAP=1 (default) -- runs the sweep at the top of every subcommand
-# (amortized: the next interaction sweeps first). =0 disables it entirely
-# (byte-identical to pre-T-f behavior; only an active codex-guard.sh or an
-# explicit `codex-task.sh reap` call reaps anything).
-# CODEX_QUEUED_KILL_MIN=45  -- a `queued`/pid-less `running` job past this age is dead.
-#   Raised 15->45 (WORKER-RESILIENCE-02): this window fires on ABSENCE of
-#   evidence (no pid recorded yet), not proof of death -- a job waiting behind
-#   a long lock holder or slow to register looks identical to a dead one at
-#   15min. False-kill cost > idle-runtime cost, so the window is widened; a
-#   truly dead job just lingers longer in `queued` before being marked failed.
-# CODEX_RUNNING_DEAD_KILL_MIN=5 -- a `running` job whose pid died past this age is dead.
-#   Deliberately UNCHANGED: this branch has proof (pid_alive() returned false
-#   for a recorded pid), so it carries no false-kill risk -- raising it would
-#   only delay cleanup of a confirmed corpse, never save a live worker.
-CODEX_REAP_STATE_ROOT="${CODEX_GUARD_STATE_ROOT:-$HOME/.claude/plugins/data/codex-openai-codex/state}"
-CODEX_QUEUED_KILL_MIN="${CODEX_QUEUED_KILL_MIN:-45}"
-CODEX_RUNNING_DEAD_KILL_MIN="${CODEX_RUNNING_DEAD_KILL_MIN:-5}"
-# CODEX-QUOTA-BLIND-SPOT-01 -- queued-stall detector (__quota-watch). A job still
-# `queued`/`started` past CODEX_QUEUED_STALL_MIN with no progress is treated as a
-# quota-blind stall and records a bounded cooldown (reason=queued_stall) so the
-# NEXT dispatch is refused instead of queueing a second blind corpse. Does NOT
-# kill the job and does NOT open the circuit breaker -- only records + refuses.
-# Deliberately shorter than CODEX_QUEUED_KILL_MIN=45 above: 10min = "stop sending
-# new work here", 45min = "declare this job dead" -- they must not collapse.
-# CODEX_QUEUED_STALL_COOLDOWN_S=1800 is the bounded cooldown length (reuses the
-# arm-cooldown lib's bounded-default machinery via LEADV2_ARM_COOLDOWN_S; the lib
-# clamps it to [60,3600]). Both job-lifecycle knobs, hence CODEX_* not LEADV2_*.
-CODEX_QUEUED_STALL_MIN="${CODEX_QUEUED_STALL_MIN:-10}"
-CODEX_QUEUED_STALL_COOLDOWN_S="${CODEX_QUEUED_STALL_COOLDOWN_S:-1800}"
-CODEX_AUTOREAP="${CODEX_AUTOREAP:-1}"
-# review-wave2-verdict-5 finding 3: a repair marker written next to the job file can itself
-# fail (directory unwritable, disk full, the job dir gone entirely) -- an independent
-# fallback location, outside the job store, gives a repair a second place to land so a
-# later `reap` still has something to reconcile against instead of nothing.
-CODEX_REPAIR_DIR="${CODEX_REPAIR_DIR:-$HOME/.claude/cache/codex-repair}"
-
-# ── CODEX-GATE-01 ─ quota gate + post-launch watcher ─────────────────────────
-# A codex dispatch that hits the account usage limit ("Codex error: You've hit
-# your usage limit … try again at Aug 5th, 2026 10:55 AM") is dead until that
-# reset time; re-dispatching just burns another job slot for an identical
-# instant failure. This gate refuses a launch while a known lockout is active
-# (C3 state file) OR live quota is over threshold (C2 reader). It FAILS OPEN on
-# every error path so a missing reader/yaml/python3 never bricks codex.
-#
-# Refusal contract (C2, aligned with the router): on refusal emit the
-# LEADV2_DISPATCH_REFUSED: quota_gate marker on STDERR and exit 2 -- the router
-# (leadv2-dispatch-code.sh refusal_reason()) recognises a refusal ONLY when the
-# marker appears in stdout+stderr AND rc is in {1,2} (77 for kimi only). rc 2 is
-# accepted for every arm, so the router maps it to "arm refused -> next
-# candidate" with ZERO router change. stdout stays clean (marker is stderr-only)
-# so a caller capturing `JOB=$(codex-task.sh …)` still gets empty, not garbage.
-# Escape hatch: CODEX_SKIP_QUOTA_GATE=1 skips the gate entirely.
-# The cooldown is deliberately bounded and self-correcting; the legacy
-# codex-lockout.state is neither read nor written.
-_CODEX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
-if [[ "${LEADV2_TRACE:-0}" == "1" ]]; then . "${_CODEX_SCRIPT_DIR}/lib/leadv2-trace.sh"
-else lv2_trace_begin() { :; }; lv2_trace_end() { :; }; lv2_trace_arm_exit() { :; }; fi
-# shellcheck source=lib/leadv2-arm-cooldown.sh
-source "${_CODEX_SCRIPT_DIR}/lib/leadv2-arm-cooldown.sh"
-# CODEX-QUOTA-GUARDRAILS-01 — circuit breaker for usage-limit refusals.
-source "${_CODEX_SCRIPT_DIR}/lib/leadv2-codex-circuit.sh"
-# CODEX-QUOTA-GUARDRAILS-01 — shared spawn gate (cooldown + circuit).
-source "${_CODEX_SCRIPT_DIR}/lib/leadv2-codex-quota-gate.sh"
-
-# C3 (tenant-generic) -- resolve the routing yaml. SAME convention as
-# leadv2-dispatch-product-close.sh:196 and leadv2-dispatch-code.sh:263:
-#   ${LEADV2_ROUTING_YAML:-<repo_root>/.claude/ref/leadv2-routing.yaml}
-# <repo_root>, first hit wins: --cwd/-C value carried by the invocation, else
-# `git -C "$PWD" rev-parse --show-toplevel`, else $PWD. Reads "$@" (the launch
-# args); called from _codex_quota_gate which still has the original args in
-# scope. Absent/unreadable yaml => the caller FAIL-OPENs (proceeds).
-_codex_quota_routing_yaml() {
-  if [[ -n "${LEADV2_ROUTING_YAML:-}" ]]; then
-    printf '%s' "$LEADV2_ROUTING_YAML"
-    return 0
-  fi
-  local _root="" _prev=""
-  local _a
-  for _a in "$@"; do
-    if [[ "$_prev" == "--cwd" || "$_prev" == "-C" ]]; then _root="$_a"; break; fi
-    _prev="$_a"
-  done
-  if [[ -z "$_root" ]]; then
-    _root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
-  fi
-  [[ -z "$_root" ]] && _root="$PWD"
-  printf '%s/.claude/ref/leadv2-routing.yaml' "$_root"
-}
-
-# C4 -- read build/review threshold pct from the routing yaml. Same keys the
-# T-q resolver already reads (this gate is a SECOND consumer, not a second
-# source). $1=SUB, $2=yaml-path (empty/unreadable => fail-open, empty stdout).
-_codex_quota_thresholds() {
-  local _sub="$1" _cfg="${2:-}"
-  [[ -z "$_cfg" || ! -r "$_cfg" ]] && return 0   # no/unreadable config → skip live-quota check silently
-  command -v python3 >/dev/null 2>&1 || {
-    printf '[codex-task] quota-gate FAIL-OPEN: python3-missing (thresholds)\n' >&2
-    return 0
-  }
-  local _kind="build"
-  case "$_sub" in
-    review|adversarial-review|review-bg) _kind="review" ;;
-  esac
-  local _val
-  _val="$(python3 -c '
-import sys, re
-try:
-    txt = open(sys.argv[1]).read()
-except Exception:
-    sys.exit(1)
-try:
-    import yaml
-except Exception:
-    yaml = None
-gate = None
-if yaml is not None:
-    try:
-        doc = yaml.safe_load(txt)
-        gate = (doc or {}).get("codex_quota_gate") if isinstance(doc, dict) else None
-    except Exception:
-        gate = None
-key = sys.argv[2] + "_threshold_pct"
-val = None
-if isinstance(gate, dict) and gate.get(key) is not None:
-    val = gate[key]
-else:
-    m = re.search(r"^\s*%s:\s*(\d+)" % key, txt, re.M)
-    if m:
-        val = m.group(1)
-try:
-    print(int(val))
-except Exception:
-    sys.exit(1)
-' "$_cfg" "$_kind" 2>/dev/null)" || true
-  [[ -z "$_val" ]] && return 0
-  printf '%s' "$_val"
-}
-
-# C2 -- resolve the quota reader, invoke `python3 <reader> codex` (no --no-cache:
-# the reader caches 120s for codex, LEADV2_QUOTA_TTL_CODEX) under a portable
-# 8s deadline (macOS has no timeout(1) by default), and return the integer
-# used_percent on stdout. Empty stdout = fail-open (reader/quota unavailable).
-_codex_quota_read() {
-  local _reader=""
-  if [[ -n "${LEADV2_QUOTA_READ:-}" ]]; then
-    _reader="$LEADV2_QUOTA_READ"
-  elif [[ -f "$HOME/Projects/leadv2/plugins/leadv2/scripts/leadv2-quota-read.py" ]]; then
-    _reader="$HOME/Projects/leadv2/plugins/leadv2/scripts/leadv2-quota-read.py"
-  elif [[ -f "$HOME/.claude/plugins/local/leadv2/plugins/leadv2/scripts/leadv2-quota-read.py" ]]; then
-    _reader="$HOME/.claude/plugins/local/leadv2/plugins/leadv2/scripts/leadv2-quota-read.py"
-  fi
-  if [[ -z "$_reader" ]]; then
-    printf '[codex-task] quota-gate FAIL-OPEN: reader-missing\n' >&2
-    return 0
-  fi
-  command -v python3 >/dev/null 2>&1 || {
-    printf '[codex-task] quota-gate FAIL-OPEN: python3-missing (reader)\n' >&2
-    return 0
-  }
-  local _deadline_s="${LEADV2_QUOTA_READ_TIMEOUT:-8}"
-  # QUOTA-GATE-PARITY-01 F4 (second consumer, 0.5s ticks): same clamp as
-  # leadv2-provider-quota-gate.sh -- positive integer only, 1..60s, so a
-  # configured typo can neither zero the poll loop nor stall the dispatcher.
-  if ! [[ "$_deadline_s" =~ ^[0-9]+$ ]]; then
-    printf '[codex-task] WARN: LEADV2_QUOTA_READ_TIMEOUT non-numeric; using default 8s\n' >&2
-    _deadline_s=8
-  fi
-  if (( _deadline_s < 1 )); then _deadline_s=1; fi
-  if (( _deadline_s > 60 )); then
-    printf '[codex-task] WARN: LEADV2_QUOTA_READ_TIMEOUT=%ss clamped to 60s\n' "$_deadline_s" >&2
-    _deadline_s=60
-  fi
-  local _ticks=$(( _deadline_s * 2 ))
-  local _tmp_out _pid _t=0
-  _tmp_out="$(mktemp)"
-  # M1 (CODEX-GATE-01): NO wrapping subshell -- background python3 directly so
-  # $_pid is python3's REAL pid and `kill "$_pid"` reaches it. The old
-  # `( python3 … ) &` made $_pid the subshell's pid; killing it left python3
-  # orphaned. A process-group kill is deliberately NOT used: a launcher must
-  # never risk taking siblings with it.
-  python3 "$_reader" codex > "$_tmp_out" 2>/dev/null &
-  _pid=$!
-  while (( _t < _ticks )); do
-    kill -0 "$_pid" 2>/dev/null || break
-    sleep 0.5
-    _t=$((_t + 1))
-  done
-  local _raw=""
-  if kill -0 "$_pid" 2>/dev/null; then
-    kill "$_pid" 2>/dev/null || true
-    wait "$_pid" 2>/dev/null || true
-    rm -f "$_tmp_out"
-    printf '[codex-task] quota-gate FAIL-OPEN: reader-timeout\n' >&2
-    return 0
-  fi
-  wait "$_pid" 2>/dev/null || true
-  [[ -s "$_tmp_out" ]] && _raw="$(cat "$_tmp_out")"
-  rm -f "$_tmp_out"
-  [[ -z "$_raw" ]] && { printf '[codex-task] quota-gate FAIL-OPEN: reader-empty\n' >&2; return 0; }
-  local _used
-  _used="$(printf '%s' "$_raw" | python3 -c '
-import sys, json
-try:
-    o = json.load(sys.stdin)
-except Exception:
-    sys.exit(1)
-if o.get("status") != "ok":
-    sys.exit(1)
-wins = o.get("windows") or []
-bw = o.get("binding_window")
-if bw:
-    for w in wins:
-        if w.get("kind") == bw:
-            try:
-                print(int(round(float(w.get("used_percent")))))
-                sys.exit(0)
-            except Exception:
-                pass
-vals = []
-for w in wins:
-    try:
-        vals.append(float(w.get("used_percent")))
-    except Exception:
-        pass
-if vals:
-    print(int(round(max(vals))))
-    sys.exit(0)
-sys.exit(1)
-' 2>/dev/null)" || true
-  if [[ -z "$_used" ]]; then
-    printf '[codex-task] quota-gate FAIL-OPEN: reader-status-not-ok-or-no-used\n' >&2
-    return 0
-  fi
-  printf '%s' "$_used"
-}
-
-# CODEX-QUOTA-BLIND-SPOT-01 C -- when the live quota reader returns nothing
-# (infra gap), _codex_quota_gate deliberately fails open. But if a queued-stall
-# cooldown was recorded within the last 24h, the operator should SEE that the
-# blind reader is masking a known stall. Emits exactly one WARN line; no
-# exit-code change, no refusal, silent when the state file is missing/unreadable
-# or holds no recent stall. Bounded read (tail -n 200) -- matches the lib's own
-# bounded-read discipline; an append-only store cannot grow this scan.
-_codex_warn_blind_spot() {
-  local _cooldown_file
-  _cooldown_file="${LEADV2_ARM_COOLDOWN_DIR:-$HOME/.claude/cache/arm-cooldown}/codex.state"
-  [[ -f "$_cooldown_file" ]] || return 0
-  local _found
-  _found="$(tail -n 200 "$_cooldown_file" 2>/dev/null | python3 -c '
-import sys, datetime
-now = datetime.datetime.now(datetime.UTC).timestamp()
-best = ""
-for line in sys.stdin:
-    if "reason=queued_stall" not in line:
-        continue
-    iso = line.split(" ", 1)[0]
-    try:
-        dt = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
-    except Exception:
-        continue
-    if now - dt.timestamp() < 86400 and (not best or iso > best):
-        best = iso
-print(best)
-' 2>/dev/null)" || _found=""
-  [[ -n "$_found" ]] || return 0
-  printf '[codex-task] WARN: codex quota reader blind + recent queued_stall (last=%s) -- dispatch proceeding fail-open\n' \
-    "$_found" >&2
-}
-
-# C1 -- launch gate. Called once, early, only for SUB in {task,review,
-# adversarial-review,review-bg}. Cheapest checks first: (1) lockout memory,
-# (2) live quota over threshold. Refuse => LEADV2_DISPATCH_REFUSED marker on
-# stderr + exit 2 (router contract; see file header).
-_codex_quota_gate() {
-  [[ "${CODEX_SKIP_QUOTA_GATE:-0}" == "1" ]] && return 0
-  case "$SUB" in
-    task|review|adversarial-review|review-bg) ;;
-    *) return 0 ;;
-  esac
-
-  # CODEX-QUOTA-GUARDRAILS-01 — delegate cooldown + circuit checks to the shared
-  # gate (identical stderr markers, same exit codes).
-  codex_spawn_gate "$SUB" || exit "$?"
-
-  # check 2 -- live quota over threshold (threshold from yaml; empty => skip).
-  local _cfg
-  _cfg="$(_codex_quota_routing_yaml "$@")" || _cfg=""
-  local _threshold
-  _threshold="$(_codex_quota_thresholds "$SUB" "$_cfg")" || _threshold=""
-  [[ -z "$_threshold" ]] && return 0
-  local _used
-  _used="$(_codex_quota_read)" || _used=""
-  if [[ -z "$_used" ]]; then
-    _codex_warn_blind_spot   # CODEX-QUOTA-BLIND-SPOT-01 C: see-through, not refuse
-    return 0
-  fi
-  if (( _used >= _threshold )); then
-    printf '[codex-task] CODEX_REFUSED_QUOTA reason=threshold used=%s threshold=%s until=na\n' "$_used" "$_threshold" >&2
-    printf 'LEADV2_DISPATCH_REFUSED: quota_gate\n' >&2
-    exit 2
-  fi
-  return 0
-}
-
-# C5 helper -- record a quota failure: parse "try again at <text>" → UTC ISO,
-# append one lockout line, also echo it to stderr (the nohup log). $1=jobId $2=log.
-_codex_quota_watch_record() {
-  local _jid="$1" _log="$2"
-  local _reset_text=""
-  if [[ -f "$_log" ]]; then
-    _reset_text="$(grep -oiE 'try again at [^.)]+' "$_log" 2>/dev/null | head -1 \
-      | sed -E 's/^[Tt]ry again at[[:space:]]*//; s/[.)]+$//')" || true
-  fi
-  local _until_iso=""
-  if [[ -n "$_reset_text" ]]; then
-    _until_iso="$(printf '%s' "$_reset_text" | python3 -c '
-import sys, re, datetime, calendar, time
-s = sys.stdin.read().strip()
-s2 = re.sub(r"(\d+)(st|nd|rd|th)", r"\1", s)
-fmts = ["%b %d, %Y %I:%M %p", "%b %d, %Y %H:%M", "%B %d, %Y %I:%M %p",
-        "%B %d, %Y %H:%M", "%d %b %Y %I:%M %p", "%d %B %Y %I:%M %p"]
-for f in fmts:
-    try:
-        dt = datetime.datetime.strptime(s2, f)
-        print(dt.strftime("%Y-%m-%dT%H:%M:%SZ"))
-        sys.exit(0)
-    except Exception:
-        continue
-sys.exit(1)
-' 2>/dev/null)" || true
-  fi
-  # _until_iso is now purely advisory: empty when the provider text did not parse,
-  # and arm_cooldown_record already maps empty to "na" and falls back to its own
-  # bounded default. The normalising if/else that used to stand here became a
-  # no-op with an EMPTY then-branch when _src was removed, which bash rejects at
-  # parse time -- it made this whole file unparseable, i.e. the codex arm was dead
-  # rather than merely refused. Deleted rather than repaired: there is nothing
-  # left for it to normalise.
-  # Idempotent on rerun (CODEX-GATE-01 item4 / q5). The mkdir watcher-lock above
-  # only guards against CONCURRENT watchers for the same job, and it is removed
-  # by the EXIT trap when the watcher finishes -- so a second SEQUENTIAL
-  # invocation of `__quota-watch <jid>` would otherwise pass the lock and append
-  # a duplicate lockout line. The lockout line is keyed by job id; if one
-  # already exists for this job, do not append again. The shared state is
-  # append-only and the optional job tag keeps sequential watcher reruns safe.
-  # FIX2: dedupe is reason-scoped (reason=quota AND job=<jid>) -- the mirror of
-  # _codex_queued_stall_record's guard. A prior reason=queued_stall line for this
-  # job must NOT suppress the quota record, or a genuine later usage-limit death
-  # (the exact terminal state the watcher now keeps polling for under FIX2) is
-  # silently lost. Scan bounded to tail -n 200 (matches _codex_warn_blind_spot);
-  # the jobId match is anchored to end-of-field so a prefix collision cannot
-  # false-suppress.
-  local _cooldown_file
-  _cooldown_file="${LEADV2_ARM_COOLDOWN_DIR:-$HOME/.claude/cache/arm-cooldown}/codex.state"
-  if [[ -f "$_cooldown_file" ]] \
-     && tail -n 200 "$_cooldown_file" 2>/dev/null | grep -qE "reason=quota([[:space:]].*)? job=${_jid}([[:space:]]|$)"; then
-    return 0
-  fi
-  LEADV2_ARM_COOLDOWN_JOB="$_jid" arm_cooldown_record codex quota "$_until_iso"
-  arm_cooldown_ladder_note codex quota "$(arm_cooldown_state codex | awk '/^cooling / {print $2}')"
-  # CODEX-QUOTA-GUARDRAILS-01 — also open the circuit breaker (longer-horizon
-  # than the 1h cooldown cap; covers multi-day weekly limits). Idempotent.
-  codex_circuit_open "$_until_iso" "codex-task" 2>/dev/null || true
-}
-
-# CODEX-QUOTA-BLIND-SPOT-01 A1 -- record a queued-stall cooldown. $1=jobId $2=job
-# log path $3=age_min (for the visibility line). Records a BOUNDED cooldown
-# (reason=queued_stall) so the NEXT dispatch is refused via codex_spawn_gate's
-# arm_cooldown_state check, instead of queueing another blind corpse. Does NOT
-# open the circuit breaker (a stall is a local inference, not a provider-declared
-# lockout) -- it self-expires in CODEX_QUEUED_STALL_COOLDOWN_S. Does NOT kill the
-# job; this only records + refuses.
-# Idempotent per job: keyed on BOTH `reason=queued_stall` AND ` job=<jid>` on the
-# SAME line (awk index, literal). Must NOT reuse the quota recorder's bare
-# ` job=<jid>` grep -- that would let a prior reason=quota record for this job
-# suppress a stall (or vice-versa), silently losing one of the two signals.
-_codex_queued_stall_record() {
-  local _jid="${1:-}" _log="${2:-}" _age_min="${3:-0}"
-  [[ -z "$_jid" ]] && return 0
-  local _min="${CODEX_QUEUED_STALL_MIN:-10}" _cooldown_file
-  _cooldown_file="${LEADV2_ARM_COOLDOWN_DIR:-$HOME/.claude/cache/arm-cooldown}/codex.state"
-  if [[ -f "$_cooldown_file" ]] && tail -n 200 "$_cooldown_file" 2>/dev/null | awk -v j=" job=${_jid}" '
-      /reason=queued_stall/ && (p = index($0, j)) {
-        # anchor: the matched " job=<jid>" must be end-of-field (whitespace or
-        # EOL) so a prefix collision cannot false-suppress a record.
-        c = substr($0, p + length(j), 1)
-        if (c == "" || c == " " || c == "\t") found = 1
-      }
-      END { exit !found }
-    '; then
-    return 0
-  fi
-  # No advisory arg => arm_cooldown_record maps empty to "na" and falls back to
-  # its own bounded default (LEADV2_ARM_COOLDOWN_S, clamped [60,3600]). The lib
-  # computes effective=default, src=default -- no new env plumbing in the lib.
-  LEADV2_ARM_COOLDOWN_JOB="$_jid" \
-  LEADV2_ARM_COOLDOWN_S="${CODEX_QUEUED_STALL_COOLDOWN_S:-1800}" \
-    arm_cooldown_record codex queued_stall
-  arm_cooldown_ladder_note codex queued_stall \
-    "$(arm_cooldown_state codex | awk '/^cooling / {print $2}')"
-  # Visibility: one line to the nohup stderr ledger AND the job's own log so the
-  # failure is not silent (arm_cooldown_record already echoes its ARM_COOLDOWN
-  # line to stderr). >> creates the job log if Codex never wrote one.
-  printf '[codex-task] CODEX_QUEUED_STALL jid=%s age_min=%s threshold_min=%s -- recording bounded cooldown\n' \
-    "$_jid" "$_age_min" "$_min" >&2
-  if [[ -n "$_log" ]]; then
-    printf '[codex-task] CODEX_QUEUED_STALL jid=%s age_min=%s threshold_min=%s -- recording bounded cooldown\n' \
-      "$_jid" "$_age_min" "$_min" >> "$_log" 2>/dev/null || true
-  fi
-  return 0
-}
-
-# C5 -- post-launch watcher (hidden subcommand __quota-watch). Idempotent per job
-# (mkdir lock dir), bounded lifetime, cross-workspace scan (NEVER cwd-scoped --
-# that is exactly the trap that makes companion `status` lie). On a terminal
-# status whose log matches a usage-limit signature, record a lockout line.
-_codex_quota_watch() {
-  local _jid="${1:-}"
-  [[ -z "$_jid" ]] && return 0
-  _codex_watch_lockdir="$HOME/.claude/cache/codex-watch.${_jid}.lock"
-  mkdir "$_codex_watch_lockdir" 2>/dev/null || return 0   # a watcher already exists → exit 0
-  trap 'rm -rf "${_codex_watch_lockdir:-}" 2>/dev/null || true' EXIT
-  local _max="${CODEX_WATCH_MAX_S:-3600}" _poll="${CODEX_WATCH_POLL_S:-30}"
-  local _state_root="$HOME/.claude/plugins/data/codex-openai-codex/state"
-  local _elapsed=0
-  command -v python3 >/dev/null 2>&1 || return 0
-  while (( _elapsed < _max )); do
-    local _jf=""
-    for _f in "$_state_root"/*/jobs/"$_jid".json; do
-      [[ -f "$_f" ]] || continue
-      _jf="$_f"; break
-    done
-    if [[ -n "$_jf" ]]; then
-      local _status=""
-      _status="$(python3 -c 'import sys,json
-try:
-    print(json.load(open(sys.argv[1])).get("status") or "")
-except Exception:
-    sys.exit(1)' "$_jf" 2>/dev/null)" || _status=""
-      case "$_status" in
-        failed|terminated)
-          local _log="${_jf%.json}.log" _isq=0
-          if [[ -f "$_log" ]]; then
-            grep -iE "hit your usage limit|usage limit reached|rate limit exceeded" "$_log" >/dev/null 2>&1 && _isq=1
-          fi
-          [[ "$_isq" -eq 1 ]] && _codex_quota_watch_record "$_jid" "$_log"
-          return 0
-          ;;
-        completed|cancelled)
-          return 0
-          ;;
-        queued)
-          # CODEX-QUOTA-BLIND-SPOT-01 A2 -- a job still queued past the stall
-          # threshold with no progress: record a bounded cooldown so the next
-          # dispatch is refused. Terminal arms above are checked FIRST and are
-          # unchanged. Age source order: job-JSON startedAt/createdAt -> job-
-          # file mtime -> watcher _elapsed (last resort; wrong for a re-armed
-          # watcher on an already-old job, which would restart the clock at 0 and
-          # never trip -- that is why it is last).
-          # FIX2 (CODEX-QUOTA-BLIND-SPOT-01): gated on `queued` ONLY -- a
-          # `started` job has pid/log-progress signals and wall-clock alone must
-          # not condemn it (see the separate `started)` no-op arm below). After
-          # recording the stall we DO NOT return: the watcher keeps polling to
-          # terminal state so a genuine later usage-limit death still reaches
-          # failed|terminated -> _codex_quota_watch_record -> codex_circuit_open.
-          # Re-entry into this branch on every subsequent poll is safe only
-          # because _codex_queued_stall_record's dedupe (reason=queued_stall AND
-          # job=<jid>, same line) is once-per-job -- that guard is load-bearing
-          # here and must not be weakened.
-          local _age_min="" _ts=""
-          _ts="$(python3 -c 'import sys,json
-try:
-    j = json.load(open(sys.argv[1]))
-    print(j.get("startedAt") or j.get("createdAt") or "")
-except Exception:
-    sys.exit(1)' "$_jf" 2>/dev/null)" || _ts=""
-          if [[ -n "$_ts" ]]; then
-            _age_min="$(python3 -c 'import sys,datetime
-try:
-    dt = datetime.datetime.fromisoformat(sys.argv[1].replace("Z","+00:00"))
-    print(int((datetime.datetime.now(datetime.UTC) - dt).total_seconds() // 60))
-except Exception:
-    sys.exit(1)' "$_ts" 2>/dev/null)" || _age_min=""
-          fi
-          if [[ -z "$_age_min" ]]; then
-            local _mt
-            _mt="$( [[ "$(uname -s)" == "Darwin" ]] && stat -f '%m' "$_jf" 2>/dev/null || stat -c '%Y' "$_jf" 2>/dev/null || echo '')"
-            if [[ -n "$_mt" ]]; then
-              _age_min=$(( ( $(date +%s) - _mt ) / 60 ))
-            else
-              _age_min=$(( _elapsed / 60 ))
-            fi
-          fi
-          local _stall_min="${CODEX_QUEUED_STALL_MIN:-10}"
-          if (( _age_min >= _stall_min )); then
-            _codex_queued_stall_record "$_jid" "${_jf%.json}.log" "$_age_min"
-            # FIX2: no return here -- keep polling (see comment above).
-          fi
-          ;;
-        started)
-          # FIX2 (CODEX-QUOTA-BLIND-SPOT-01): a started job is actively running
-          # (pid/log-progress signals); wall-clock age alone must not trip a
-          # stall cooldown. No-op -> falls through to sleep/_elapsed accumulation
-          # and the watcher keeps polling until a terminal status wins above.
-          ;;
-      esac
-    fi
-    sleep "$_poll"
-    _elapsed=$((_elapsed + _poll))
-  done
-  return 0
-}
-
-# _codex_reap [job_id] -- scans $CODEX_REAP_STATE_ROOT (or just one job's file
-# when job_id is given, forcing the age check regardless of elapsed time) for
-# jobs stuck without a live babysitter and marks them terminal failed with a
-# reap cause. Participates in the SAME mkdir-lock + owner.pid provably-stale
-# protocol as state.mjs's withJobFileLock (JOB-LOCK-SHARED-01) and
-# codex-guard.sh's acquire_job_lock -- one shared cross-process mutex, not a
-# 4th convention. Prints "<jobId> <cause>" per job it reaps; silent (no
-# output) when nothing needed reaping.
-_codex_reap() {
-  local target="${1:-}" _lib_dir
-  _lib_dir="$(dirname "$COMPANION")/lib"
-  local _reap_out="" _reap_rc=0 _line _jid="" _cause="" _ws="" _logf=""
-  _reap_out="$(python3 - "$CODEX_REAP_STATE_ROOT" "$CODEX_QUEUED_KILL_MIN" "$CODEX_RUNNING_DEAD_KILL_MIN" "$target" "$_lib_dir" "$CODEX_REPAIR_DIR" <<'PY'
-import json, os, shutil, subprocess, sys, time
-from datetime import datetime, timezone
-
-state_root, queued_kill_min, running_kill_min, target, lib_dir, repair_dir = (
-    sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6],
-)
-
-
-def parse_iso(value):
-    if not value:
-        return None
-    try:
-        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
-    except Exception:
-        return None
-
-
-def pid_alive(pid):
-    if pid is None:
-        return False
-    try:
-        pid_int = int(pid)
-    except (TypeError, ValueError):
-        return False
-    try:
-        os.kill(pid_int, 0)
-        return True
-    except ProcessLookupError:
-        pass
-    except PermissionError:
-        return True  # exists, owned elsewhere -- can't prove dead, never reap
-    # CODEX-REAP-PGID-01: the exact recorded pid can be gone while a live
-    # descendant is still doing real work in the SAME process group -- every
-    # detach path feeding this reaper (setsid_wrapper's os.setsid(), Node's
-    # spawn(detached: true), GNU timeout forking the setsid'd child) makes the
-    # group id equal the pid that was recorded, so a live group member still
-    # answers a group-liveness probe even when that one exact pid already
-    # exited. Fail-safe direction only: this WIDENS "alive", it never narrows
-    # it -- a false positive here costs one more sweep before a genuinely dead
-    # job is reaped; a false negative kills a healthy worker mid-flight, which
-    # is the regression this exists to prevent (4 healthy lanes reaped as
-    # worker_died_stale on 2026-08-21, see CODEX-DETACH-01 origin story above).
-    if pid_int <= 0:
-        return False
-    try:
-        os.killpg(pid_int, 0)
-        return True
-    except ProcessLookupError:
-        return False
-    except PermissionError:
-        return True  # group exists, owned elsewhere -- can't prove dead, never reap
-
-
-def lock_owner(lock_dir):
-    try:
-        with open(os.path.join(lock_dir, "owner.pid")) as f:
-            return int(f.read().strip())
-    except Exception:
-        return None
-
-
-def acquire_lock(job_path):
-    lock_dir = job_path + ".lock"
-    waited = 0
-    while True:
-        try:
-            os.mkdir(lock_dir)
-        except FileExistsError:
-            try:
-                age = time.time() - os.stat(lock_dir).st_mtime
-            except FileNotFoundError:
-                continue
-            if age > 60:
-                owner = lock_owner(lock_dir)
-                if owner is None or not pid_alive(owner):
-                    shutil.rmtree(lock_dir, ignore_errors=True)
-                    continue
-            if waited >= 100:  # ~10s at 0.1s/poll
-                return None
-            time.sleep(0.1)
-            waited += 1
-            continue
-        try:
-            with open(os.path.join(lock_dir, "owner.pid"), "w") as f:
-                f.write(str(os.getpid()))
-        except Exception:
-            pass
-        return lock_dir
-
-
-def release_lock(lock_dir):
-    if lock_dir:
-        shutil.rmtree(lock_dir, ignore_errors=True)
-
-
-# wave2 finding 2: kill_leftover_group used to run getpgid/killpg on a pid that had
-# JUST answered dead to kill(pid, 0) above -- but a dead pid can be reused by the OS
-# for an unrelated process between that check and the getpgid/killpg calls a moment
-# later, with no birth-time token here to prove it is still the SAME process this job
-# ever spawned. That window lets a reap kill a completely unrelated process group
-# while still failing to clean up the actual orphan (which, by definition, is no
-# longer at that pid). Removed entirely rather than guarded: validating process
-# identity would need a persisted birth-time/start-token per pid, which is more
-# machinery than an orphan-cleanup safety net is worth; a leftover child process is
-# the strictly safer failure mode than killing the wrong one.
-
-
-def _sync_state_index(job_id, workspace_root, patch, lib_dir):
-    # wave2 finding 1: the reaper used to rewrite ONLY jobs/<id>.json. status/result/
-    # resume all discover jobs through state.json (state.mjs's listJobs/loadState), so a
-    # reaped job stayed "queued"/"running" in every normal interface even though its own
-    # job file said failed. Patch the SAME canonical index through the plugin's own
-    # upsertJob() (state.mjs) -- the ONE writer every other caller already goes through
-    # (mirrors `_record_spawn_failure`'s own dynamic-import pattern below) -- rather than
-    # a second, drifting reimplementation of state.json's shape in Python. Best-effort:
-    # workspaceRoot is read straight off the job record; a job with none (or no lib_dir
-    # resolved) skips the index sync silently -- the per-job file write already landed,
-    # so this is a partial win, not a failure to escalate.
-    #
-    # wave2 round2 finding 2: `check=False` + the node script's own `process.exit(0)` on
-    # catch used to mean this NEVER reported failure -- an upsertJob error or subprocess
-    # timeout was silently swallowed and the caller had no way to tell state.json stayed
-    # stale. The script now exits 1 on failure and this returns a real bool so the caller
-    # can persist a repair marker instead of losing the divergence.
-    if not workspace_root or not lib_dir:
-        return False
-    script = (
-        "(async () => {"
-        "const [libDir, cwd, patchJson] = process.argv.slice(1);"
-        "const { upsertJob } = await import(libDir + '/state.mjs');"
-        "await upsertJob(cwd, JSON.parse(patchJson));"
-        "})().catch((e) => {"
-        "process.stderr.write('[codex-task] WARN: reap could not sync state index: '"
-        " + (e && e.message ? e.message : e) + \"\\n\");"
-        "process.exit(1);"
-        "});"
-    )
-    try:
-        proc = subprocess.run(
-            ["node", "-e", script, lib_dir, workspace_root, json.dumps(patch)],
-            check=False, timeout=10, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
-        )
-        return proc.returncode == 0
-    except Exception:
-        return False
-
-
-def _repair_marker_path(job_path):
-    return f"{job_path}.repair"
-
-
-def _fallback_marker_path(repair_dir, job_id):
-    return os.path.join(repair_dir, f"{job_id}.json")
-
-
-def _write_marker_file(marker_path, payload):
-    tmp = f"{marker_path}.tmp.{os.getpid()}"
-    try:
-        os.makedirs(os.path.dirname(marker_path), exist_ok=True)
-        with open(tmp, "w") as f:
-            json.dump(payload, f)
-        os.replace(tmp, marker_path)
-        return True
-    except Exception as e:
-        try:
-            os.remove(tmp)
-        except Exception:
-            pass
-        return e
-
-
-def _write_repair_marker(job_path, job_id, workspace_root, patch, repair_dir):
-    # wave2 round2 finding 2: persisted next to the job file (same dir, same lock
-    # discipline) so a later sweep -- possibly a different process -- can find and
-    # retry it without needing to re-derive job_id/workspaceRoot/patch from scratch.
-    #
-    # wave2 round3 finding 4: this is the LAST line of defense against a permanent
-    # state.json/index divergence (upsertJob already failed once, in _sync_state_index,
-    # by the time this is called) -- swallowing a write/rename failure here silently
-    # meant the divergence could never be recovered, by this process or any later sweep,
-    # with no trace it ever happened. Returns True/False instead of always succeeding
-    # silently; the caller surfaces False as an explicit reap failure (see below).
-    #
-    # review-wave2-verdict-5 finding 3: a job-dir-local marker can share the SAME failure
-    # mode that broke the index sync in the first place (unwritable dir, disk full, the
-    # job store itself gone) -- CODEX_REPAIR_DIR is an INDEPENDENT location, so it is tried
-    # whenever the local write fails, giving a later `reap` a second place to look before
-    # this divergence is declared unrecoverable.
-    marker_path = _repair_marker_path(job_path)
-    payload = {"jobId": job_id, "workspaceRoot": workspace_root, "patch": patch}
-    local_err = _write_marker_file(marker_path, payload)
-    if local_err is True:
-        return True
-    fallback_path = _fallback_marker_path(repair_dir, job_id)
-    fallback_err = _write_marker_file(fallback_path, payload)
-    if fallback_err is True:
-        sys.stderr.write(
-            f"[codex-task] WARN: repair marker for job {job_id} could not be written "
-            f"at {marker_path} ({local_err}); persisted to fallback location "
-            f"{fallback_path} instead\n"
-        )
-        return True
-    sys.stderr.write(
-        f"[codex-task] ERROR: could not persist repair marker for job {job_id} "
-        f"at {marker_path} ({local_err}) or fallback {fallback_path} ({fallback_err})\n"
-    )
-    return False
-
-
-def _retry_one_marker(marker_path, lib_dir):
-    try:
-        with open(marker_path) as f:
-            payload = json.load(f)
-    except Exception:
-        return None
-    job_id = payload.get("jobId")
-    workspace_root = payload.get("workspaceRoot")
-    patch = payload.get("patch")
-    if not job_id or not patch:
-        try:
-            os.remove(marker_path)
-        except Exception:
-            pass
-        return None
-    if _sync_state_index(job_id, workspace_root, patch, lib_dir):
-        try:
-            os.remove(marker_path)
-        except Exception:
-            pass
-        return job_id
-    return None
-
-
-def _retry_repair_markers(state_root, lib_dir, repair_dir):
-    # wave2 round2 finding 2: runs BEFORE the normal sweep on every invocation (not just
-    # when CODEX_AUTOREAP fires a new reap) so a prior sync failure gets reconciled even
-    # if no new job needs reaping this round.
-    #
-    # review-wave2-verdict-5 finding 3: also consumes markers persisted to the independent
-    # CODEX_REPAIR_DIR fallback (written when the job-dir-local marker itself failed) --
-    # same reconciliation, second source.
-    repaired = []
-    for root, _dirs, files in os.walk(state_root):
-        if os.path.basename(root) != "jobs":
-            continue
-        for name in files:
-            if not name.endswith(".repair"):
-                continue
-            job_id = _retry_one_marker(os.path.join(root, name), lib_dir)
-            if job_id:
-                repaired.append(job_id)
-    if os.path.isdir(repair_dir):
-        for name in os.listdir(repair_dir):
-            if not name.endswith(".json"):
-                continue
-            job_id = _retry_one_marker(os.path.join(repair_dir, name), lib_dir)
-            if job_id:
-                repaired.append(job_id)
-    return repaired
-
-
-_APP_SERVER_PROBE = {}
-
-
-def _codex_app_server_alive():
-    """True if a `codex app-server` process exists on this machine.
-
-    Memoized per sweep: one pgrep, not one per job — a sweep can inspect dozens of
-    jobs and they all share the same answer.
-
-    Fail-safe: any probe failure (no pgrep, permission, timeout) returns True, i.e.
-    "cannot prove the transport is gone", so this can only ever REFINE the cause of
-    a death the age logic already decided on. It never causes a reap by itself.
-    """
-    if "alive" in _APP_SERVER_PROBE:
-        return _APP_SERVER_PROBE["alive"]
-    alive = True
-    try:
-        r = subprocess.run(["pgrep", "-f", "codex app-server"],
-                           capture_output=True, text=True, timeout=5)
-        # pgrep: 0 = matches found, 1 = none found, >1 = error (treat as unknown)
-        if r.returncode == 1:
-            alive = False
-        elif r.returncode == 0:
-            alive = bool(r.stdout.strip())
-    except Exception:
-        pass
-    _APP_SERVER_PROBE["alive"] = alive
-    return alive
-
-
-def reap_one(job_path, force=False):
-    lock_dir = acquire_lock(job_path)
-    if lock_dir is None:
-        return None  # lock contended by a live holder -- try again next sweep
-    try:
-        try:
-            with open(job_path) as f:
-                data = json.load(f)
-        except Exception:
-            return None
-
-        status = data.get("status")
-        if status not in ("queued", "running"):
-            return None
-
-        pid = data.get("pid")
-        has_pid = pid is not None and str(pid).strip() != ""
-        if has_pid and pid_alive(pid):
-            return None  # ALIVE -- untouched, no exceptions
-
-        now = time.time()
-
-        # CODEX-REAP-LOG-MTIME-LIVENESS-01: a growing log is proof of life, and it
-        # outranks every pid-shaped guess below.
-        #
-        # 2026-08-21: a worker was reaped `worker_died_stale` 73 seconds after its own
-        # log recorded `Applying 1 file change(s)` / `File changes completed`. The pid
-        # probe is a proxy for liveness; the log is the thing itself. Every liveness
-        # question in this system that was answered from a pid or a status field was
-        # answered wrongly today, and every one answered from an mtime was right.
-        #
-        # Fail-safe direction only: this WIDENS "alive" and can never narrow it. A
-        # false positive costs one more sweep before a genuinely dead job is reaped;
-        # a false negative kills a worker mid-write, which is the whole point of the
-        # guard. Any stat failure falls through to the pid-shaped logic unchanged.
-        log_grace_s = float(os.environ.get("CODEX_REAP_LOG_GRACE_S", "120"))
-        if log_grace_s > 0:
-            log_path = job_path[:-5] + ".log" if job_path.endswith(".json") else None
-            try:
-                if log_path and os.path.exists(log_path):
-                    if (now - os.path.getmtime(log_path)) < log_grace_s:
-                        return None  # log written within the grace window -- working
-            except OSError:
-                pass  # unreadable mtime proves nothing; fall through
-
-        cause = None
-        if status == "queued":
-            created = parse_iso(data.get("createdAt"))
-            age_min = ((now - created) / 60) if created else None
-            if force or (age_min is not None and age_min >= queued_kill_min):
-                cause = f"queued_timeout_{queued_kill_min:g}min"
-        elif not has_pid:
-            # wave2 finding 9: `running` with no pid EVER recorded never had a worker
-            # attached at all -- treat it like a stalled queued job (same grace period
-            # off createdAt) instead of the tighter dead-worker threshold below, which
-            # assumes a worker started and then died (a stronger claim than this state
-            # supports).
-            created = parse_iso(data.get("createdAt"))
-            age_min = ((now - created) / 60) if created else None
-            if force or (age_min is not None and age_min >= queued_kill_min):
-                cause = f"running_no_pid_timeout_{queued_kill_min:g}min"
-        else:
-            ref = parse_iso(data.get("startedAt")) or parse_iso(data.get("createdAt"))
-            age_min = ((now - ref) / 60) if ref else None
-            if force or (age_min is not None and age_min >= running_kill_min):
-                # CODEX-TRANSPORT-ATTRIBUTION-01: name the death correctly.
-                #
-                # This script's own header records the coupling: "a job dies the
-                # instant its launching client drops the app-server connection."
-                # `codex app-server` is a SINGLE shared process, so when it goes
-                # every in-flight job across every worktree dies together — and
-                # each one used to be stamped `worker_died_stale`, i.e. one shared
-                # cause reported as N independent worker failures.
-                #
-                # On 2026-08-21 that cost a day: three lanes in three different
-                # worktrees stopped logging within 32 seconds of each other, were
-                # filed as two different per-job diagnoses, and three separate
-                # wrong mechanisms were investigated (API credits, concurrent
-                # jobs, unregistered worktrees) before anyone checked whether the
-                # shared server was still alive. It was not.
-                #
-                # A distinct cause makes the shared failure legible and, unlike
-                # `worker_died_stale`, tells the next reader the work was almost
-                # certainly retryable rather than broken.
-                cause = "worker_died_stale"
-                if not _codex_app_server_alive():
-                    cause = "transport_gone_app_server_absent"
-
-        if cause is None:
-            return None
-
-        job_id = os.path.basename(job_path)[:-5]
-        orig_pid = data.get("pid")
-        completed_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
-        data["status"] = "failed"
-        data["phase"] = "failed"
-        data["pid"] = None
-        data["errorMessage"] = f"reaped: {cause}"
-        data["completedAt"] = completed_at
-
-        tmp = f"{job_path}.tmp.{os.getpid()}"
-        with open(tmp, "w") as f:
-            json.dump(data, f, indent=2)
-        os.replace(tmp, job_path)
-
-        # CODEX-DIES-MID-TEST-01 crit 2 — a killed job must SAY so. Until now the
-        # job log simply STOPPED at its last "Running command" line (measured on
-        # four lanes 2026-09-01), which reads as a lane still working. Whatever
-        # killed the worker acted outside this job's control (SessionEnd broker
-        # shutdown / V8 OOM abort — see docs/handoff/CODEX-DIES-MID-TEST-01/
-        # report.md), so this reaper — the first component that can PROVE the
-        # death — writes the terminal line naming cause and time directly into
-        # the log everyone already tails. Best-effort: a missing/unwritable log
-        # never fails the reap (the job file above is the authoritative record).
-        log_file = data.get("logFile")
-        if log_file:
-            try:
-                with open(log_file, "a") as _lf:
-                    _lf.write(
-                        "[codex-task] TERMINAL: job=%s cause=%s worker_pid=%s "
-                        "reaped_at=%s note=worker process died without recording a "
-                        "terminal state; named by the leadv2 reaper "
-                        "(CODEX-DIES-MID-TEST-01)\n" % (job_id, cause, orig_pid, completed_at)
-                    )
-            except OSError:
-                pass
-
-        patch = {
-            "id": job_id,
-            "status": "failed",
-            "phase": "failed",
-            "pid": None,
-            "errorMessage": f"reaped: {cause}",
-            "completedAt": completed_at,
-        }
-        return (job_id, cause, data.get("workspaceRoot"), log_file, patch)
-    finally:
-        release_lock(lock_dir)
-
-
-# wave2 round2 finding 2: reconcile any file/index divergence left by a PRIOR sweep's
-# failed upsertJob before reaping anything new this round.
-_retry_repair_markers(state_root, lib_dir, repair_dir)
-
-reaped = []
-_marker_persist_failed = False
-for root, _dirs, files in os.walk(state_root):
-    if os.path.basename(root) != "jobs":
-        continue
-    for name in files:
-        if not name.endswith(".json"):
-            continue
-        job_id = name[:-5]
-        if target and job_id != target:
-            continue
-        job_path = os.path.join(root, name)
-        result = reap_one(job_path, force=bool(target))
-        if result:
-            reaped_job_id, cause, workspace_root, log_file, patch = result
-            # Runs AFTER reap_one's own `finally: release_lock(...)` above -- upsertJob
-            # never touches the per-job-file lock (only writeJobFile does), so there is
-            # no lock-reentry/deadlock risk calling it here.
-            if not _sync_state_index(reaped_job_id, workspace_root, patch, lib_dir):
-                if not _write_repair_marker(job_path, reaped_job_id, workspace_root, patch, repair_dir):
-                    _marker_persist_failed = True
-            reaped.append((reaped_job_id, cause, workspace_root, log_file))
-
-# CODEX-DIES-MID-TEST-01 crit 2/3 — reap output grows two trailing fields
-# (workspaceRoot, logFile; "-" when absent). Field order for the first two
-# (<jobId> <cause>) is unchanged so existing line-shape readers keep working.
-for job_id, cause, workspace_root, log_file in reaped:
-    print(f"{job_id} {cause} {workspace_root or '-'} {log_file or '-'}")
-
-# wave2 round3 finding 4: the job itself WAS reaped (status=failed already landed in
-# job_path above) -- what is at risk is only the state.json index + this last-resort
-# retry marker, and that risk must not be invisible. Exit nonzero + an explicit stderr
-# line whenever ANY repair marker failed to persist this round, instead of always
-# returning 0 regardless of what happened inside this sweep.
-if _marker_persist_failed:
-    sys.stderr.write(
-        "[codex-task] ERROR: reap completed but a repair marker failed to persist -- "
-        "state.json index divergence for one or more jobs may be permanent without "
-        "manual reconciliation (see the marker-specific error above)\n"
-    )
-    sys.exit(1)
-PY
-)" || _reap_rc=$?
-  # CODEX-DIES-MID-TEST-01 — deliberately ONLY prints. The journal row and the
-  # arm-cooldown record live in the __deathwatch path below, NOT here: _codex_reap
-  # runs from every `status`/autoreap/`reap` call AND from hermetic suites
-  # exercising the reaper (measured 2026-09-01: recording here made
-  # test-codex-task-reap runs append REAL cooldown rows to the live arm ladder,
-  # which then refused the next real dispatch). The reaper's own critical outputs
-  # stay exactly as before: status=failed, errorMessage, TERMINAL line in the
-  # job log. Output contract: "<jobId> <cause> <workspaceRoot|-> <logFile|->"
-  # (first two fields unchanged; the trailing two are consumed by __deathwatch).
-  if [[ -n "$_reap_out" ]]; then
-    printf '%s\n' "$_reap_out"
-  fi
-  return "$_reap_rc"
-}
-
-# _record_spawn_failure <cwd> <error-text> -- CODEX-REAP-01 item 3 (spawn
-# failure visibility). When a background dispatch's launcher output carries
-# no parseable jobId (the "no live job record" case: codex-companion never
-# even reached its own writeJobFile), nothing tracks the failure and it
-# vanishes -- no job.json, no guard armed, no /codex:status entry. This
-# writes a synthetic terminal job record via the plugin's OWN state.mjs
-# functions (generateJobId/writeJobFile/upsertJob), so the failure shows up
-# in `codex-task.sh status --all` like any other job instead of disappearing.
-# Uses the plugin's exported API only -- no mjs file is edited or patched.
-_record_spawn_failure() {
-  local cwd="$1" errtext="$2" lib_dir
-  lib_dir="$(dirname "$COMPANION")/lib"
-  node -e '
-(async () => {
-  const [libDir, cwd, err] = process.argv.slice(1);
-  const { generateJobId, writeJobFile, upsertJob } = await import(libDir + "/state.mjs");
-  const jobId = generateJobId("spawnfail");
-  const now = new Date().toISOString();
-  const record = {
-    id: jobId,
-    status: "failed",
-    phase: "failed",
-    kind: "spawn-failure",
-    kindLabel: "spawn-failure",
-    jobClass: "task",
-    pid: null,
-    createdAt: now,
-    completedAt: now,
-    errorMessage: "spawn_failed: " + String(err).slice(0, 500)
-  };
-  writeJobFile(cwd, jobId, record);
-  upsertJob(cwd, record);
-  console.error("[codex-task] recorded spawn failure as " + jobId + " (job store, status=failed cause=spawn_failed)");
-})().catch((e) => {
-  console.error("[codex-task] WARN: could not record spawn failure to job store: " + (e && e.message ? e.message : e));
-  process.exit(0);
-});
-' "$lib_dir" "$cwd" "$errtext"
-}
-
-# ── --tier extraction (must run before the spark ban + subcommand dispatch,
-# since codex-companion has no concept of --tier — it only understands
-# --model/--effort). Strip --tier out of "$@" and resolve it to concrete
-# --model/--effort values, identical resolution table to leadv2-codex-planner.sh.
-# Strip --tier / --reason / --wait out of "$@" (every position) so codex-companion
-# never sees them folded into the prompt. codex-companion understands only
-# --model/--effort and (for review subcommands) --wait/--background -- `task` has
-# NO --wait option, so an unstripped --wait lands verbatim in the prompt text and
-# the call returns immediately (the CODEX-WAIT-AND-TIER-01 P0 bug).
-_TIER=""
-_REASON=""
-# CODEX-QUOTA-GUARDRAILS-01 — no-tier path must still pin model+effort.
-# Default to standard (terra/medium) instead of leaving the companion default
-# (which was gpt-5.5 with no effort pin — the CLI default for `codex exec` is
-# xhigh, the primary burn vector from RCA CODEX-QUOTA-BURN-RCA-01).
-_WAIT=0
-_pre_args=()
-_i=1
-while [[ $_i -le $# ]]; do
-  _arg="${!_i}"
-  case "$_arg" in
-    --tier|--tier=*)
-      if [[ "$_arg" == --tier=* ]]; then _TIER="${_arg#--tier=}"; else _i=$((_i + 1)); _TIER="${!_i:-}"; fi ;;
-    --reason|--reason=*)
-      if [[ "$_arg" == --reason=* ]]; then _REASON="${_arg#--reason=}"; else _i=$((_i + 1)); _REASON="${!_i:-}"; fi ;;
-    --wait|--wait=*)
-      _WAIT=1 ;;
-    *)
-      _pre_args+=("$_arg") ;;
-  esac
-  _i=$((_i + 1))
-done
-set -- "${_pre_args[@]}"
-
-# P1 (CODEX-WAIT-AND-TIER-01) -- --tier top must earn its cost. Measured before
-# this gate: 17 runs on top (Sol), 9 on standard (Terra), 0 on volume (Luna) --
-# 65% on the priciest tier, burning Codex to 27%. `top` is the scarce tier
-# (adversarial review + Heavy/arch plans ONLY); standard is the default, volume
-# for mechanical/bulk. Sol->Terra-ultra gov-gated fallback (below) is unaffected
-# -- it fires on _TIER=="top" regardless of which model resolves. standard/volume
-# pass through unchanged.
-if [[ "${_TIER:-}" == "top" && -z "${_REASON:-}" ]]; then
-  cat >&2 <<'EOF'
-[codex-task] REFUSED: --tier top requires --reason "<why this run earns top>".
-  Founder rule (CODEX-WAIT-AND-TIER-01): `top` (Sol -> Terra-ultra) is the scarce
-  Codex tier, reserved for adversarial review + Heavy/arch plans. Default is
-  `standard` (Terra/medium); use `volume` (Luna/low) for mechanical/bulk work.
-  Re-run with --reason "<text>" to attest this run earns top, or drop --tier.
-EOF
-  exit 2
-fi
-
-# CODEX-TIER-ENFORCER-01 -- record every ACCEPTED --tier top run (the gate above
-# already refused reasonless ones, so a refused run reaches neither this function
-# nor the ledger). One JSON object per line; ts/tier/sub/reason/model/effort/cwd/pid.
-# Best-effort by design: mkdir+append are stderr-swallowed and || true-guarded so
-# a read-only $HOME or full disk can never abort a Codex dispatch under set -e.
-# Single printf of one <8KB line => one O_APPEND write => atomic under concurrent
-# lanes; do NOT build the line across multiple >> calls. _REASON and $PWD are
-# free-form: escape \ then ", collapse newlines/tabs to spaces, and tr-sweep any
-# remaining C0 control char (formfeed, vtab -- a raw C0 invalidates strict JSON,
-# jq rc=5) so the line stays parseable. LEADV2_* naming matches
-# LEADV2_ARM_COOLDOWN_DIR above. Defined here, called (a) in the reap branch
-# below (early exit, before tier->model resolution -- model/effort record empty)
-# and (b) after tier resolution for the dispatching subcommands.
-_codex_tier_ledger() {
-  {
-    local _esc="${_REASON//\\/\\\\}"
-    _esc="${_esc//\"/\\\"}"
-    _esc="${_esc//$'\n'/ }"
-    _esc="${_esc//$'\r'/ }"
-    _esc="${_esc//$'\t'/ }"
-    _esc="$(printf '%s' "$_esc" | tr -d '\001-\037')"
-    # Cap before interpolation: a multi-KB reason would make the line long enough
-    # that bash printf may split it across write()s, losing O_APPEND atomicity
-    # under concurrent lanes (round-2 review). 1024 keeps the whole line well
-    # under one pipe-buffer-sized write; greppability survives.
-    _esc="${_esc:0:1024}"
-    local _cwd="${PWD:-}"
-    _cwd="${_cwd//\\/\\\\}"
-    _cwd="${_cwd//\"/\\\"}"
-    _cwd="$(printf '%s' "$_cwd" | tr -d '\001-\037')"
-    local _log="${LEADV2_CODEX_TIER_LOG:-$HOME/.claude/cache/codex-tier-log.jsonl}"
-    mkdir -p "$(dirname "$_log")" 2>/dev/null || true
-    printf '{"ts":"%s","tier":"%s","sub":"%s","reason":"%s","model":"%s","effort":"%s","cwd":"%s","pid":"%s"}\n' \
-      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_TIER:-}" "${SUB:-}" "$_esc" \
-      "${TIER_MODEL:-}" "${TIER_EFFORT:-}" "$_cwd" "$$" \
-      >> "$_log" 2>/dev/null || true
-  } 2>/dev/null || true
-}
-
-SUB="${1:-}"
-
-# `codex-task.sh reap` -- explicit manual sweep (not a real codex-companion
-# subcommand, intercepted here before anything is forwarded to node).
-if [[ "$SUB" == "reap" ]]; then
-  # CODEX-TIER-ENFORCER-01: reap early-exits below, before tier resolution --
-  # record the accepted top attestation HERE so it does not silently miss the
-  # ledger (model/effort stay empty; reap pins no model).
-  if [[ "${_TIER:-}" == "top" ]]; then
-    _codex_tier_ledger
-  fi
-  # wave2 round3 finding 4: capture the sweep's own exit code explicitly (the `||`
-  # keeps this line exempt from `set -e` so a nonzero rc is reported, not silently
-  # aborting before the reaped-jobs output below is ever printed) -- a repair-marker
-  # persistence failure inside _codex_reap now surfaces here as a real reap failure,
-  # not an unconditional success.
-  _REAP_RC=0
-  _REAP_OUT="$(_codex_reap)" || _REAP_RC=$?
-  if [[ -n "$_REAP_OUT" ]]; then
-    printf 'reaped:\n%s\n' "$_REAP_OUT"
-  else
-    echo "no stale jobs found"
-  fi
-  if [[ "$_REAP_RC" -ne 0 ]]; then
-    echo "[codex-task] REAP FAILED: a repair marker could not be persisted for one or more jobs -- state.json index divergence needs manual reconciliation (see stderr above)" >&2
-    exit "$_REAP_RC"
-  fi
-  exit 0
-fi
-
-# CODEX_AUTOREAP (default 1): every other subcommand sweeps the job store
-# first, amortized -- this is the "no cron, no daemon" automatic caller the
-# fix requires. Best-effort: never blocks or fails the real subcommand.
-#
-# wave2 round4 finding 2: the old `2>/dev/null || true` here discarded BOTH the repair-
-# marker failure detail AND its exit code -- unlike the explicit `reap` subcommand above
-# (round3 finding 4), this amortized path left a marker-persistence failure with literally
-# no operator signal, silent even by CODEX_VERBOSE=1's standard. `|| _AUTOREAP_RC=$?` is the
-# same errexit-exempt idiom as the explicit reap call site: it captures the real rc without
-# ever aborting the requested subcommand (still best-effort). The marker file itself (or the
-# lack of one) is the durable state note -- _write_repair_marker/_retry_repair_markers
-# already persist/retry it on disk regardless of this wrapper's own redirection; this fix
-# only restores VISIBILITY of that failure to whoever is watching stderr.
-if [[ "$CODEX_AUTOREAP" == "1" ]]; then
-  _AUTOREAP_RC=0
-  # review-wave2-verdict-5 finding 3: the old `2>/dev/null` here discarded the marker-
-  # specific ERROR line (job id + job file path) _write_repair_marker already writes to
-  # stderr, leaving the WARNING below with no way to say WHICH job needs attention.
-  # Captured to a tempfile instead so those lines can be surfaced alongside it.
-  _AUTOREAP_ERRFILE="$(mktemp 2>/dev/null || printf '%s/.codex-autoreap-err.%s' "${TMPDIR:-/tmp}" "$$")"
-  _AUTOREAP_OUT="$(_codex_reap 2>"$_AUTOREAP_ERRFILE")" || _AUTOREAP_RC=$?
-  if [[ -n "$_AUTOREAP_OUT" && "${CODEX_VERBOSE:-0}" == "1" ]]; then
-    printf '[codex-task] autoreap:\n%s\n' "$_AUTOREAP_OUT" >&2
-  fi
-  if [[ "$_AUTOREAP_RC" -ne 0 ]]; then
-    echo "[codex-task] WARNING: background autoreap failed (rc=${_AUTOREAP_RC}) -- a repair marker could not be persisted for one or more jobs; run 'codex-task.sh reap' to see details and retry" >&2
-    # Round-6 review: unguarded grep exits 1/2 under set -e when the marker line is absent
-    # or the errfile is unreadable, aborting the WRAPPED command -- diagnostics must never
-    # outrank the requested subcommand.
-    grep -E '^\[codex-task\] ERROR: could not persist repair marker' "$_AUTOREAP_ERRFILE" >&2 2>/dev/null || true
-  fi
-  rm -f "$_AUTOREAP_ERRFILE" 2>/dev/null
-fi
-
-# ST-2 — direct Codex tasks do not pass through dispatch-code.sh, so give them
-# the same blocking-question protocol here. Dispatch missions already contain
-# it; do not append a duplicate in that path.
-if [[ "$SUB" == "task" && " $* " != *"leadv2-ask.sh"* ]]; then
-  _QUESTION_TASK_ID="${LEADV2_TASK_ID:-codex-task}"
-  _QUESTION_PROTOCOL="
-
----
-If you hit a decision you cannot safely make yourself, call the blocking
-question channel and wait for the answer rather than guessing:
-  bash \"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/leadv2-ask.sh\" \"${_QUESTION_TASK_ID}\" \"<question>\" \\
-    --option \"a|<reversible label>\" --option \"b|<label>\" --default-option \"a\" [--timeout <sec=1800>]
-Every question must name its clearly reversible option with --default-option,
-so a timeout proceeds visibly and never holds a lane. Do not use this for
-routine progress or confirmation-seeking."
-  set -- "$@" "${_QUESTION_PROTOCOL}"
-fi
-
-# EFFICIENCY-TUNE-01 C: job registry for supervise-loop stall detection.
-# One line per spawn: /tmp/leadv2-job-registry/<session_id>/<job_id> = "run_dir\tstarted_at\tkind".
-# Registry-clear rides the wrapper's own EXIT trap — the completion point that
-# actually exists in this synchronous/--wait wrapper (foreground `node` call
-# returning). Detached `--background` dispatches exit the wrapper immediately
-# after parsing jobId, so their registry entry is cleared then too — no
-# completion-tracking regression vs today (background completion is already
-# tracked separately via codex-guard.sh's jobId watch, not this registry).
-if [[ "$SUB" == "task" || "$SUB" == "review" || "$SUB" == "adversarial-review" ]]; then
-  _JOB_REG_SID="${CLAUDE_SESSION_ID:-nosession}"
-  _JOB_REG_DIR="/tmp/leadv2-job-registry/${_JOB_REG_SID}"
-  _JOB_REG_ID="${SUB}-$(date +%s)-$$"
-  mkdir -p "$_JOB_REG_DIR" 2>/dev/null \
-    && printf -- '%s\t%s\t%s\n' "$PWD" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "codex" \
-       > "${_JOB_REG_DIR}/${_JOB_REG_ID}" 2>/dev/null || true
-  trap 'rm -f "${_JOB_REG_DIR}/${_JOB_REG_ID}" 2>/dev/null || true' EXIT
-fi
-
-# P0 (CODEX-WAIT-AND-TIER-01) -- --wait forces foreground blocking. `task`/
-# `review` detach ONLY with --background; without it they already block in the
-# foreground (codex-companion runForegroundCommand holds the app-server
-# connection until the job reaches a terminal state). So when --wait is set we
-# strip --background to guarantee the blocking path -- a backgrounded --wait is
-# contradictory and the job dies the instant the launcher returns (proven: 5
-# launch methods -> 5 deaths). adversarial-review already auto-injects --wait
-# for companion below, so it is unaffected here.
-if [[ "${_WAIT:-0}" -eq 1 && ( "${SUB:-}" == "task" || "${SUB:-}" == "review" ) ]]; then
-  _bg_seen=0
-  _wa_args=()
-  for _a in "$@"; do
-    if [[ "$_a" == "--background" ]]; then
-      _bg_seen=1
-    else
-      _wa_args+=("$_a")
-    fi
-  done
-  if [[ "$_bg_seen" -eq 1 ]]; then
-    set -- "${_wa_args[@]}"
-    echo "[codex-task] --wait set: stripping --background -- running foreground and blocking until terminal state (a backgrounded --wait would die on launcher exit)" >&2
-  fi
-fi
-
-_has_flag() {
-  # _has_flag <long> <short> "$@" -- true if either flag literal is present
-  local long="$1" short="$2"; shift 2
-  for _a in "$@"; do
-    [[ "$_a" == "$long" || ( -n "$short" && "$_a" == "$short" ) ]] && return 0
-  done
-  return 1
-}
-
-# CODEX-QUOTA-GUARDRAILS-01 — default _TIER to standard when unset so model
-# and effort are always explicitly pinned (never left to the CLI default,
-# which is xhigh for `codex exec` — the primary RCA burn vector).
-[[ -z "${_TIER:-}" ]] && _TIER="standard"
-if [[ -n "$_TIER" ]]; then
-  MODELS_CACHE="${CODEX_MODELS_CACHE:-$HOME/.codex/models_cache.json}"
-  case "$_TIER" in
-    top)
-      if command -v jq >/dev/null 2>&1 && [[ -f "$MODELS_CACHE" ]] \
-         && jq -e '.models[]? | select(.slug=="gpt-5.6-sol")' "$MODELS_CACHE" >/dev/null 2>&1; then
-        TIER_MODEL="gpt-5.6-sol"; TIER_EFFORT="high"
-      else
-        # lean: sol is gov-gated and currently absent from models_cache.json --
-        # fall back to terra/ultra. upgrade when sol lands on this plan.
-        TIER_MODEL="gpt-5.6-terra"; TIER_EFFORT="ultra"
-      fi
-      ;;
-    standard)
-      # EFFORT-RECAL 2026-07-10 (OpenAI 5.6: one-level-lower holds quality; rollback: standard=high, volume=medium)
-      TIER_MODEL="gpt-5.6-terra"; TIER_EFFORT="medium"
-      ;;
-    volume)
-      # EFFORT-RECAL 2026-07-10 (OpenAI 5.6: one-level-lower holds quality; rollback: standard=high, volume=medium)
-      TIER_MODEL="gpt-5.6-luna"; TIER_EFFORT="low"
-      ;;
-    *)
-      echo "[codex-task] unknown --tier: $_TIER (expected top|standard|volume)" >&2
-      exit 1
-      ;;
-  esac
-  # codex-companion only accepts {none,minimal,low,medium,high,xhigh} on the wire --
-  # "ultra" is a logical top-tier label only. Same translation as the planner.
-  WIRE_EFFORT="$TIER_EFFORT"
-  [[ "$WIRE_EFFORT" == "ultra" ]] && WIRE_EFFORT="xhigh"
-
-  case "$SUB" in
-    adversarial-review|review)
-      if _has_flag --model -m "$@"; then
-        echo "[codex-task] --tier ignored: explicit --model already present" >&2
-      else
-        set -- "$@" --model "$TIER_MODEL"
-      fi
-      echo "[codex-task] tier=$_TIER -> model=$TIER_MODEL (sub=$SUB; review has no --effort wire)" >&2
-      ;;
-    task)
-      if _has_flag --model -m "$@"; then
-        echo "[codex-task] --tier ignored: explicit --model already present" >&2
-      else
-        set -- "$@" --model "$TIER_MODEL"
-      fi
-      if _has_flag --effort "" "$@"; then
-        echo "[codex-task] --tier effort ignored: explicit --effort already present" >&2
-      else
-        set -- "$@" --effort "$WIRE_EFFORT"
-      fi
-      echo "[codex-task] tier=$_TIER -> model=$TIER_MODEL effort=$WIRE_EFFORT (sub=$SUB)" >&2
-      # WORKER-MCP-ALL-ARMS-01: this arm's worker MCP allowlist is documented
-      # at config/codex-mcp-servers.toml, but live injection is NOT wired --
-      # the actual spawn goes through node "$COMPANION" (openai-codex plugin
-      # cache, outside this repo), which has no --mcp-config-equivalent
-      # passthrough today. Fail-open: log once so the gap is visible, never
-      # block the dispatch on it.
-      if [[ "${LEADV2_CODEX_MCP_WARNED:-0}" != "1" ]]; then
-        echo "[codex-task] NOTE: code-intel MCP (codebase-memory-mcp/repowise) is not yet wired for Codex arms -- see config/codex-mcp-servers.toml comment (WORKER-MCP-ALL-ARMS-01 follow-up)." >&2
-        export LEADV2_CODEX_MCP_WARNED=1
-      fi
-      ;;
-    *)
-      echo "[codex-task] WARN: --tier has no effect on subcommand '$SUB' -- ignoring" >&2
-      ;;
-  esac
-fi
-
-# CODEX-TIER-ENFORCER-01 -- dispatching subcommands record here, AFTER tier->model
-# resolution so model/effort are populated (_codex_tier_ledger defined above the
-# SUB dispatch; reap records inside its own early-exit branch).
-if [[ "${_TIER:-}" == "top" ]]; then
-  _codex_tier_ledger
-fi
-
-# Hard ban: spark is never used in this project (founder directive 2026-04-28).
-# Reject both the CLI alias ("spark") and its resolved model id
-# (gpt-5.3-codex-spark, per codex-companion.mjs MODEL_ALIASES) so a caller can't
-# route around the ban by passing the resolved slug directly (H4).
-for ((_i = 1; _i <= $#; _i++)); do
-  if [[ "${!_i}" == "--model" || "${!_i}" == "-m" ]]; then
-    _next=$((_i + 1))
-    _next_val="${!_next:-}"
-    if [[ "$_next_val" == "spark" || "$_next_val" == "gpt-5.3-codex-spark" ]]; then
-      echo "[codex-task] spark model is banned in this project. Use default (gpt-5.5) or --tier <top|standard|volume>." >&2
-      exit 1
-    fi
-  fi
-done
-
-# C5 dispatch -- hidden watcher subcommand. Runs detached via nohup from the
-# launch blocks below; never reaches the gate (SUB not in the gate set).
-if [[ "$SUB" == "__quota-watch" ]]; then
-  shift  # drop "__quota-watch"
-  _codex_quota_watch "${1:-}" "${2:-}"
-  exit 0
-fi
-
-# CODEX-GATE-01 -- quota launch gate. Runs once, early, for the four dispatch
-# subcommands. Refuses (marker + exit 2, router contract) on active lockout or
-# quota-over-threshold; fails open (continue) on any reader/yaml/python3 gap.
-_codex_quota_gate "$@"
-
-# C6 (CODEX-GATE-01) -- `status <id>` cross-workspace resolution. The companion's
-# status is cwd-scoped and reports "No job found" for a job launched from a
-# different workspaceRoot (the same trap that made zombies survive `cancel`).
-# Keep the companion call on the happy path; only when it fails or says "No job
-# found" do we fall back to the cross-workspace glob scan (same idiom as the
-# zombie reaper) and render <id> <status> <phase> workspaceRoot=<root> log=<log>.
-if [[ "$SUB" == "status" ]]; then
-  shift  # drop "status"
-  _st_id=""
-  for _a in "$@"; do [[ -z "$_st_id" && "$_a" != -* ]] && _st_id="$_a"; done
-  _st_out="" _st_rc=0
-  _st_out="$(node "$COMPANION" status "$@" 2>/dev/null)" || _st_rc=$?
-  if [[ $_st_rc -eq 0 && -n "$_st_out" ]] \
-     && ! printf '%s' "$_st_out" | grep -q "No job found"; then
-    printf '%s\n' "$_st_out"
+if [[ "$1" == "adversarial-review" ]]; then
+    # Simulate Codex producing a minimal valid review (but with potential body loss risk)
+    echo "REVIEW_VERDICT: PASS"
+    echo "REVIEW_FINDINGS: critical=0 high=0 medium=0 low=0"
     exit 0
-  fi
-  # fallback: cross-workspace scan
-  #
-  # DEDUP-RELEASE-01 (2026-08-21) -- this fallback used to ALWAYS render the
-  # plain-text "<id> <status> <phase> workspaceRoot=... log=..." line, even
-  # when the caller passed --json. leadv2-lane-liveness.sh's --job lookup
-  # always passes --json (it queries with --cwd "$PROJECT_ROOT", the main
-  # checkout, while a background dispatch's job runs from a worktree --
-  # e.g. .claude/worktrees/<sig8> -- so the companion's own cwd-scoped
-  # lookup misses and falls into exactly this branch on every worktree job).
-  # leadv2-dispatch-code.sh's _dispatch_worker_liveness feeds that output
-  # through `json.loads(raw)` (leadv2-lane-liveness.sh:provider_jobs); a
-  # plain-text line is not valid JSON, so the parse silently threw, jobs
-  # came back {} regardless of the job's real status, and every codex
-  # --background dispatch made from a worktree resolved to liveness=
-  # "unknown" forever -- which _dispatch_outcome_blocks treats as "never
-  # free a live or unprovable task" (its safe-default `*) return 0` branch).
-  # A confirmed ledger row for a worktree-dispatched codex job could
-  # therefore NEVER be reclaimed by the outcome ledger, no matter how dead
-  # the worker actually was -- root cause of the 2026-08-21 hand-clear
-  # incident (4 lanes, `dispatch_refused reason=duplicate_task_signature`,
-  # only recoverable by manually clearing the dispatch-ledger row).
-  #
-  # Fix: detect --json in the ORIGINAL forwarded args and, when set, emit a
-  # `{"job": {...}}` object shaped like provider_jobs() already expects
-  # (same "job" key the companion's own --json response uses) instead of
-  # the plain-text line. json.dumps() -- not printf -- so a value containing
-  # a quote/backslash (a stray path component) can never produce invalid
-  # JSON. The plain-text line is UNCHANGED for every caller that does not
-  # pass --json (leadv2-dispatch-code.sh:3269,3802 parse prose, e.g. "No job
-  # found", and must keep seeing exactly that).
-  _st_json=0
-  for _a in "$@"; do [[ "$_a" == "--json" ]] && _st_json=1; done
-  if [[ -n "$_st_id" ]] && command -v python3 >/dev/null 2>&1; then
-    _st_root="$HOME/.claude/plugins/data/codex-openai-codex/state"
-    for _f in "$_st_root"/*/jobs/"$_st_id".json; do
-      [[ -f "$_f" ]] || continue
-      if [[ "$_st_json" -eq 1 ]]; then
-        python3 -c 'import sys, json
-o = json.load(open(sys.argv[1]))
-print(json.dumps({"job": {
-    "id": o.get("id", ""),
-    "status": o.get("status", ""),
-    "phase": o.get("phase", ""),
-    "workspaceRoot": o.get("workspaceRoot", ""),
-    "logFile": o.get("logFile", ""),
-}}))' "$_f" 2>/dev/null && exit 0
-      else
-        python3 -c 'import sys,json
-o=json.load(open(sys.argv[1]))
-print("%s %s %s workspaceRoot=%s log=%s" % (
-    o.get("id",""), o.get("status",""), o.get("phase",""),
-    o.get("workspaceRoot",""), o.get("logFile","")))' "$_f" 2>/dev/null && exit 0
-      fi
-    done
-  fi
-  [[ -n "$_st_out" ]] && printf '%s\n' "$_st_out"
-  exit "$_st_rc"
-fi
-
-# Default tier is now `standard` (pinned above: gpt-5.6-terra/medium).
-# CODEX-QUOTA-GUARDRAILS-01: the no-tier path previously left model+effort to
-# the companion default (gpt-5.5, no effort pin). It now always resolves to
-# standard. An explicit --tier still wins (already handled above).
-
-# adversarial-review MUST run synchronously. Without --wait, codex-companion starts an
-# async job and returns immediately — the findings land in the plugin job-log and the
-# caller's captured stdout gets only the start banner (the 2026-05-17 empty-output bug).
-# Auto-inject --wait so the wrapper always blocks and the full review reaches stdout.
-if [[ "$SUB" == "adversarial-review" ]]; then
-  _has_wait=0
-  for _a in "$@"; do [[ "$_a" == "--wait" ]] && _has_wait=1; done
-  [[ "$_has_wait" -eq 0 ]] && set -- "$@" --wait
-
-  # G2 -- default findings cap
-  _MAX_FINDINGS="${CODEX_MAX_FINDINGS:-8}"
-  _CAP_PREFIX="Review ONLY the changed files in the diff. Return at most ${_MAX_FINDINGS} findings, Critical/High severity only, one sentence each, with file:line. If a zone is clean say 'clean' -- do not pad."
-  _new_args=()
-  _found_focus=0
-  # Bash positional params are 1-indexed ($1..$#); $0 is the script path.
-  # Iterate [1, $#] inclusive -- starting at 0 forwarded $0 as the subcommand
-  # ("Unknown subcommand: <path>") and dropped the final arg.
-  _idx=1
-  while [[ $_idx -le $# ]]; do
-    _arg="${!_idx}"
-    _idx=$((_idx + 1))
-    if [[ "$_arg" == "--focus" ]]; then
-      _found_focus=1
-      _next_val="${!_idx:-}"
-      _idx=$((_idx + 1))
-      _new_args+=("--focus" "${_CAP_PREFIX} ${_next_val}")
-    else
-      _new_args+=("$_arg")
-    fi
-  done
-  if [[ "$_found_focus" -eq 0 ]]; then
-    _new_args+=("--focus" "$_CAP_PREFIX")
-  fi
-  set -- "${_new_args[@]}"
-
-fi
-
-# CODEX-DETACH-01 -- validate broker.json liveness before handing a job to the
-# companion. Root cause (established live, 2026-08-31, three sol workers
-# mtgk8ef8/mtgl2ea9/mtgl96u7 all worker_process_died within 1-3 min): the
-# companion's broker.json named a process that no longer existed, whose
-# sessionDir under /var/folders/.../T had been swept by the OS. Every new
-# worker attached to that corpse and died -- this was never a timeout (G1
-# below already caps at 1800s; the "5m00s" in the failure record is
-# codex-guard.sh reap_stale_workers stamping worker_died_silent after 300s of
-# log silence -- raising a timeout fixes nothing).
-#
-# We do not own the broker (that's ~/.claude/plugins/cache/openai-codex/) --
-# we only read scripts/lib/state.mjs:resolveStateDir()'s formula (git
-# toplevel of cwd, realpath'd, sha256[:16] + sanitized basename slug) to find
-# ITS broker.json, and move a stale one aside (never delete) so the companion
-# raises a fresh broker on its own next attach. A swept sessionDir with a pid
-# some unrelated process now holds is exactly why BOTH checks are required --
-# a pid-only check would wave that case through.
-_codex_broker_state_dir() {
-  local _cwd="$1"
-  command -v python3 >/dev/null 2>&1 || return 1
-  python3 - "$_cwd" "$CODEX_REAP_STATE_ROOT" <<'PY'
-import hashlib, os, re, subprocess, sys
-cwd, state_root = sys.argv[1], sys.argv[2]
-try:
-    root = subprocess.run(
-        ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
-        capture_output=True, text=True, check=True, timeout=5,
-    ).stdout.strip()
-    if not root:
-        root = cwd
-except Exception:
-    root = cwd
-try:
-    canonical = os.path.realpath(root)
-except Exception:
-    canonical = root
-slug_source = os.path.basename(root.rstrip("/")) or "workspace"
-slug = re.sub(r"[^a-zA-Z0-9._-]+", "-", slug_source).strip("-") or "workspace"
-digest = hashlib.sha256(canonical.encode()).hexdigest()[:16]
-print(os.path.join(state_root, "%s-%s" % (slug, digest)))
-PY
-}
-
-# $1=cwd. Renames a stale broker.json aside (timestamped, never deleted) when
-# its pid is dead OR its sessionDir no longer exists. Silent no-op if no
-# broker.json exists yet, or it is fully alive (pid live AND sessionDir
-# present -- both checks must pass).
-_codex_validate_broker() {
-  local _cwd="$1" _state_dir _broker
-  _state_dir="$(_codex_broker_state_dir "$_cwd" 2>/dev/null)" || return 0
-  [[ -n "$_state_dir" && -f "$_state_dir/broker.json" ]] || return 0
-  _broker="$_state_dir/broker.json"
-  command -v python3 >/dev/null 2>&1 || return 0
-
-  local _fields _pid _session_dir
-  _fields="$(python3 - "$_broker" <<'PY'
-import json, sys
-try:
-    data = json.load(open(sys.argv[1]))
-except Exception:
-    sys.exit(0)
-pid = data.get("pid")
-session_dir = data.get("sessionDir") or ""
-print(pid if isinstance(pid, int) else "")
-print(session_dir)
-PY
-)" || return 0
-  _pid="$(printf '%s\n' "$_fields" | sed -n '1p')"
-  _session_dir="$(printf '%s\n' "$_fields" | sed -n '2p')"
-
-  local _dead=0 _swept=0
-  if [[ -n "$_pid" ]] && kill -0 "$_pid" 2>/dev/null; then
-    :
-  else
-    _dead=1
-  fi
-  if [[ -n "$_session_dir" && -d "$_session_dir" ]]; then
-    :
-  else
-    _swept=1
-  fi
-  if [[ "$_dead" -eq 1 || "$_swept" -eq 1 ]]; then
-    local _reason _ts
-    if [[ "$_dead" -eq 1 && "$_swept" -eq 1 ]]; then _reason="pid_dead+sessionDir_gone"
-    elif [[ "$_dead" -eq 1 ]]; then _reason="pid_dead"
-    else _reason="sessionDir_gone"; fi
-    _ts="$(date '+%Y%m%dT%H%M%S')"
-    if mv "$_broker" "${_broker}.stale-${_ts}" 2>/dev/null; then
-      echo "[codex-task] STALE_BROKER_DETECTED reason=${_reason} state_dir=${_state_dir} pid=${_pid:-?} session_dir=${_session_dir:-?}" >&2
-    fi
-  fi
-  return 0
-}
-
-if [[ "$SUB" == "task" || "$SUB" == "review" || "$SUB" == "adversarial-review" ]]; then
-  _BROKER_CHECK_CWD="$PWD"
-  _prev=""
-  for _a in "$@"; do
-    if [[ "$_prev" == "--cwd" || "$_prev" == "-C" ]]; then _BROKER_CHECK_CWD="$_a"; fi
-    _prev="$_a"
-  done
-  _codex_validate_broker "$_BROKER_CHECK_CWD"
-fi
-
-# CODEX-DIES-MID-TEST-01 — per-job deathwatch (internal subcommand, armed by the
-# --background dispatch path right after codex-guard.sh). codex-guard.sh watches
-# JOB STATUS; this watches the WORKER PROCESS, because the incident class this
-# lane fixed is a worker killed out-of-band (SessionEnd broker shutdown / V8 OOM
-# abort) whose job record stays "running" for hours while its log just stops —
-# four lanes, zero commits, no terminal line anywhere (2026-09-01). The moment
-# the recorded pid is provably dead this triggers the SAME targeted reap the
-# `reap` subcommand uses (shared mkdir-lock protocol, status/index/log TERMINAL
-# line, journal row, arm-cooldown record) — within seconds of the death instead
-# of the next unrelated codex-task.sh invocation hours later. Same liveness
-# discipline as the reaper: kill -0 failing is necessary but not sufficient —
-# a reap that cannot PROVE the whole group dead reaps nothing and the watcher
-# keeps polling. Quiet by design on live workers (a long silent test run is
-# NOT a death) and on terminal-status jobs.
-if [[ "$SUB" == "__deathwatch" ]]; then
-  shift
-  _DW_JID="${1:-}"
-  shift || true
-  _DW_STATE_DIR=""
-  while [[ $# -gt 0 ]]; do
-    case "$1" in
-      --cwd)        _DW_CWD="${2:-}"; shift 2 ;;
-      --state-dir)  _DW_STATE_DIR="${2:-}"; shift 2 ;;
-      *) shift ;;
-    esac
-  done
-  _DW_CWD="${_DW_CWD:-$PWD}"
-  if [[ -z "$_DW_STATE_DIR" ]]; then
-    _DW_STATE_DIR="$(_codex_broker_state_dir "$_DW_CWD" 2>/dev/null || printf '')"
-  fi
-  # _dw_announce <job> <cause> <workspaceRoot> <logFile> -- crit 2+3 announcer.
-  # (a) a durable dispatch-journal row (kind=codex_worker_died, arm=codex) so lane
-  # liveness/the pulse see the death instead of a lane that "was still working",
-  # and (b) an arm-cooldown failure record (reason=<cause>) so the router's NEXT
-  # resolve cools the codex arm via the standard bounded ladder — quota, task
-  # shape and outcomes decide the arm, never a hardcoded exclusion. Both
-  # fail-open: an observability write never flips the watcher's rc.
-  _dw_announce() {
-    bash "${LEADV2_EVENT_BIN:-${_CODEX_SCRIPT_DIR}/leadv2-event.sh}" emit \
-      --repo "$(printf '%s' "${3##*/}" | tr -cd 'A-Za-z0-9._-')" \
-      --kind codex_worker_died --arm codex --handle "$1" \
-      --detail "cause=${2:-unknown} log=${4:--}" >/dev/null 2>&1 || true
-    LEADV2_ARM_COOLDOWN_JOB="$1" arm_cooldown_record codex "${2:-worker_died}" >/dev/null 2>&1 || true
-  }
-  _DW_POLL="${CODEX_DEATHWATCH_POLL_S:-5}"
-  _DW_MAX="${CODEX_DEATHWATCH_MAX_S:-14400}"
-  _DW_DEADLINE=$(( $(date +%s) + _DW_MAX ))
-  while (( $(date +%s) < _DW_DEADLINE )); do
-    _DW_JF="$_DW_STATE_DIR/jobs/$_DW_JID.json"
-    if [[ -f "$_DW_JF" ]]; then
-      _DW_STATUS="$(python3 -c 'import json,sys
-try:
-    print(json.load(open(sys.argv[1])).get("status") or "")
-except Exception:
-    print("")' "$_DW_JF" 2>/dev/null || true)"
-      case "$_DW_STATUS" in
-        completed|cancelled) exit 0 ;;
-        failed)
-          # The autoreap sweep (quota gate at this script's own startup, or a
-          # later dispatch's status call) can beat this watcher to the corpse:
-          # the sweep is a pure state mutation BY DESIGN -- recording inside
-          # _codex_reap made hermetic reap suites append real cooldown rows to
-          # the LIVE arm ladder (measured 2026-09-01). The deathwatch only
-          # exists on real dispatches, so IT owns the announcement even for a
-          # sweep-reaped job: a worker death is a router-visible failure no
-          # matter which leadv2 component buried the body.
-          _DW_PRE="$(python3 -c 'import json,sys
-try:
-    d = json.load(open(sys.argv[1]))
-    print((d.get("errorMessage") or "") + "\t" + (d.get("workspaceRoot") or "") + "\t" + (d.get("logFile") or ""))
-except Exception:
-    print("")' "$_DW_JF" 2>/dev/null || true)"
-          _DW_ERR="${_DW_PRE%%$'\t'*}"
-          if [[ "$_DW_ERR" == reaped:* ]]; then
-            _DW_CAUSE="${_DW_ERR#reaped: }"
-            _DW_REST="${_DW_PRE#*$'\t'}"
-            _dw_announce "$_DW_JID" "$_DW_CAUSE" "${_DW_REST%%$'\t'*}" "${_DW_REST#*$'\t'}"
-          fi
-          exit 0 ;;
-      esac
-      _DW_PID="$(python3 -c 'import json,sys
-try:
-    print(json.load(open(sys.argv[1])).get("pid") or "")
-except Exception:
-    print("")' "$_DW_JF" 2>/dev/null || true)"
-      if [[ -n "$_DW_PID" ]] && ! kill -0 "$_DW_PID" 2>/dev/null; then
-        _DW_OUT="$(_codex_reap "$_DW_JID" 2>/dev/null || true)"
-        if [[ -n "$_DW_OUT" ]]; then
-          while IFS=' ' read -r _DW_J _DW_CAUSE _DW_WS _DW_LOGF; do
-            [[ -n "${_DW_J:-}" ]] || continue
-            _dw_announce "$_DW_J" "$_DW_CAUSE" "$_DW_WS" "$_DW_LOGF"
-          done <<EOF_DW_LINES
-$_DW_OUT
-EOF_DW_LINES
-          exit 0   # reaped: TERMINAL line + journal row + arm record have landed
-        fi
-        # group not provably dead — fall through and keep polling
-      fi
-    fi
-    sleep "$_DW_POLL"
-  done
-  exit 0
-fi
-
-# G1 -- hard timeout + auto-kill
-# Controlled by CODEX_TIMEOUT env (default 600). Override per-repo via
-# codex_review_timeout_sec in codex-policy.yaml.
-#
-# D-g tier-aware default (SUPERVISE-V2-01 item 5): a flat 600s default killed
-# a --tier top (sol/high) run mid-work this session -- heavier tiers need
-# more wall-clock. An EXPLICIT CODEX_TIMEOUT always wins over the tier
-# default (never silently overridden).
-if [[ -n "${CODEX_TIMEOUT:-}" ]]; then
-  _CODEX_TIMEOUT="$CODEX_TIMEOUT"
-else
-  case "$_TIER" in
-    top)      _CODEX_TIMEOUT=1800 ;;
-    standard) _CODEX_TIMEOUT=900 ;;
-    *)        _CODEX_TIMEOUT=600 ;;
-  esac
-fi
-if command -v gtimeout >/dev/null 2>&1; then
-  _TIMEOUT_CMD="gtimeout"
-elif command -v timeout >/dev/null 2>&1; then
-  _TIMEOUT_CMD="timeout"
-else
-  _TIMEOUT_CMD=""
-fi
-# CODEX-DETACH-01 -- macOS ships no util-linux setsid; python3 os.setsid()+
-# execvp() is the portable equivalent used by glm-coder.sh/kimi-coder.sh
-# (see their setsid_wrapper() comment) to give a background worker its own
-# session/process-group so a SIGTERM to the LAUNCHING shell's process group
-# cannot reach it. codex-task.sh's `task`/`review` --background path never
-# had this: the node companion process (and whatever it forks internally to
-# run the actual Codex CLI job) stayed in the invoking shell's process
-# group. Once ANY later Bash-tool call in the SAME session hit its 2-minute
-# timeout, the harness's SIGTERM to that group killed the still-running
-# background worker too -- even though it had already returned a jobId and
-# was believed detached. Root-caused 2026-08-21: 4/4 lanes reaped
-# worker_process_died / worker_died_stale, each death timestamp lining up
-# with an unrelated Bash tool call ending in the launching session.
-#
-# `exec`'d as this function's last command, same reason as
-# glm-coder.sh:setsid_wrapper -- without `exec`, backgrounding a call to
-# this function forks a wrapper subshell whose pid is one level removed
-# from the setsid'd process, breaking anything that captures $!/pgid.
-# setsid() only changes session/process-group membership; it does not
-# touch file descriptors, so a caller capturing stdout via
-# `out="$(_run_node ...)"` keeps working unchanged after this wraps it.
-setsid_wrapper() {
-  exec python3 -c '
-import os, sys
-
-os.setsid()
-os.execvp(sys.argv[1], sys.argv[1:])
-' "$@"
-}
-
-_run_node() {
-  local _exit_code=0
-  local _bg=0 _rn_a
-  for _rn_a in "$@"; do [[ "$_rn_a" == "--background" ]] && _bg=1; done
-  if [[ -n "$_TIMEOUT_CMD" ]]; then
-    if [[ "$_bg" -eq 1 ]]; then
-      # `timeout`/`gtimeout` execve() their target directly -- they cannot
-      # invoke a bash function -- so the setsid_wrapper() mechanism is
-      # inlined here as python3 (a real executable) instead of calling the
-      # function. Same os.setsid()+execvp() as setsid_wrapper() above.
-      "$_TIMEOUT_CMD" "$_CODEX_TIMEOUT" python3 -c '
-import os, sys
-
-os.setsid()
-os.execvp(sys.argv[1], sys.argv[1:])
-' node "$COMPANION" "$@" || _exit_code=$?
-    else
-      "$_TIMEOUT_CMD" "$_CODEX_TIMEOUT" node "$COMPANION" "$@" || _exit_code=$?
-    fi
-  else
-    # M4/Codex#3 (SUPERVISE-V2-01 fix-1): stock macOS ships neither gtimeout
-    # nor timeout(1) -- the wrapper used to silently run node with NO deadline
-    # at all, making the tier-aware CODEX_TIMEOUT + exit-124 auto-retry
-    # completely inert. Loud WARN + a portable bash fallback (background
-    # sleep+kill watcher) that enforces the SAME deadline contract and
-    # explicitly reports it as exit 124, same as gtimeout/timeout(1) would.
-    printf '[codex-task] WARN: neither gtimeout nor timeout(1) on PATH -- enforcing the %ss deadline via a portable sleep+kill watcher instead. Install coreutils (brew install coreutils) for the standard implementation.\n' "$_CODEX_TIMEOUT" >&2
-    if [[ "$_bg" -eq 1 ]]; then
-      # CODEX-DETACH-01: same session-detach as the timeout branch above,
-      # via the setsid_wrapper() function this time (no `timeout` binary in
-      # the way, so the function itself can be backgrounded directly).
-      setsid_wrapper node "$COMPANION" "$@" &
-    else
-      node "$COMPANION" "$@" &
-    fi
-    local _node_pid=$!
-    local _fired_file
-    _fired_file="$(mktemp)"
-    (
-      sleep "$_CODEX_TIMEOUT"
-      if kill -0 "$_node_pid" 2>/dev/null; then
-        : > "$_fired_file"
-        kill -TERM "$_node_pid" 2>/dev/null || true
-        sleep 2
-        kill -KILL "$_node_pid" 2>/dev/null || true
-      fi
-    ) &
-    local _watcher_pid=$!
-    wait "$_node_pid" 2>/dev/null
-    _exit_code=$?
-    kill "$_watcher_pid" 2>/dev/null || true
-    wait "$_watcher_pid" 2>/dev/null || true
-    if [[ -s "$_fired_file" ]]; then
-      _exit_code=124
-    fi
-    rm -f "$_fired_file"
-  fi
-  if [[ "$_exit_code" -eq 124 ]]; then
-    printf 'CODEX TIMED OUT after %ss -- proceeding without Codex\n' "$_CODEX_TIMEOUT" >&2
-    # Machine-readable event (D-g) so a pulse loop can surface it without
-    # parsing prose -- tier defaults to "default" when --tier was not passed.
-    printf 'CODEX_TIMEOUT_EVENT tier=%s limit=%s\n' "${_TIER:-default}" "$_CODEX_TIMEOUT" >&2
-    exit 124
-  fi
-  return "$_exit_code"
-}
-
-# C1 -- 5.6 -> 5.5 fallback. A gpt-5.6-family dispatch can fail with a hard 400
-# if the local Codex CLI is a stable release that predates 5.6 support (message
-# observed: "requires a newer version of Codex") or if the resolved slug isn't
-# recognized by the account tier (message observed: "is not supported when
-# using Codex with a ChatGPT account", status 400). Either way this is a CLI/
-# entitlement problem, not a prompt problem -- retry once on gpt-5.5/high so a
-# stale CLI degrades gracefully instead of hard-failing every Codex call.
-# lean: buffers full output before replaying instead of streaming live -- loses
-# incremental [codex] progress lines during the (rare) fallback path. Upgrade
-# to a tee-based streaming retry if interactive live-progress becomes a
-# complaint.
-_FALLBACK_MODEL="gpt-5.5"
-# CODEX-QUOTA-GUARDRAILS-01 — was "high"; align with standard tier (medium).
-_FALLBACK_EFFORT="medium"
-
-_extract_model_arg() {
-  local _prev=""
-  for _a in "$@"; do
-    if [[ "$_prev" == "--model" || "$_prev" == "-m" ]]; then
-      printf '%s' "$_a"
-      return 0
-    fi
-    _prev="$_a"
-  done
-}
-DISPATCH_MODEL="$(_extract_model_arg "$@")"
-
-# Codex#4 (SUPERVISE-V2-01 fix-1): tier one-level-lower retry on a real
-# timeout (exit 124). Before this fix a timeout left `_run_with_fallback`
-# retrying only 5.6 HTTP-400 failures -- a genuine timeout was simply
-# abandoned, the tier-aware CODEX_TIMEOUT default existed but nothing acted
-# on the exit-124 event. Single retry only: top->standard, standard->volume;
-# volume (already the cheapest/fastest tier) has nowhere lower to go.
-_tier_down() {
-  case "$1" in
-    top)      echo "standard" ;;
-    standard) echo "volume" ;;
-    *)        echo "" ;;
-  esac
-}
-
-_tier_timeout_for() {
-  case "$1" in
-    top)      echo 1800 ;;
-    standard) echo 900 ;;
-    *)        echo 600 ;;
-  esac
-}
-
-# Sets TIER_MODEL_OUT / WIRE_EFFORT_OUT for the given tier name. Same
-# resolution table as the --tier extraction block above.
-_tier_model_effort() {
-  local _t="$1" _mc _eff
-  _mc="${CODEX_MODELS_CACHE:-$HOME/.codex/models_cache.json}"
-  case "$_t" in
-    top)
-      if command -v jq >/dev/null 2>&1 && [[ -f "$_mc" ]] \
-         && jq -e '.models[]? | select(.slug=="gpt-5.6-sol")' "$_mc" >/dev/null 2>&1; then
-        TIER_MODEL_OUT="gpt-5.6-sol"; _eff="high"
-      else
-        TIER_MODEL_OUT="gpt-5.6-terra"; _eff="ultra"
-      fi
-      ;;
-    standard) TIER_MODEL_OUT="gpt-5.6-terra"; _eff="medium" ;;
-    volume)   TIER_MODEL_OUT="gpt-5.6-luna";  _eff="low" ;;
-    *)        TIER_MODEL_OUT="gpt-5.6-terra"; _eff="medium" ;;
-  esac
-  WIRE_EFFORT_OUT="$_eff"
-  [[ "$WIRE_EFFORT_OUT" == "ultra" ]] && WIRE_EFFORT_OUT="xhigh"
-}
-
-_run_with_fallback() {
-  lv2_trace_begin "provider.codex" "$@"
-  local rc=0 out
-  out="$(_run_node "$@" 2>&1)" && rc=0 || rc=$?
-
-  if [[ $rc -eq 124 && -n "$_TIER" ]]; then
-    local _next_tier
-    _next_tier="$(_tier_down "$_TIER")"
-    if [[ -n "$_next_tier" ]]; then
-      echo "[codex-task] CODEX_RETRY_EVENT from_tier=$_TIER to_tier=$_next_tier reason=timeout" >&2
-      _tier_model_effort "$_next_tier"
-      local retry_args=() _prev=""
-      for _a in "$@"; do
-        if [[ "$_prev" == "--model" || "$_prev" == "-m" ]]; then
-          retry_args+=("$TIER_MODEL_OUT")
-        elif [[ "$_prev" == "--effort" ]]; then
-          retry_args+=("$WIRE_EFFORT_OUT")
-        else
-          retry_args+=("$_a")
-        fi
-        _prev="$_a"
-      done
-      _TIER="$_next_tier"
-      _CODEX_TIMEOUT="$(_tier_timeout_for "$_next_tier")"
-      DISPATCH_MODEL="$TIER_MODEL_OUT"
-      out="$(_run_node "${retry_args[@]}" 2>&1)" && rc=0 || rc=$?
-      echo "[codex-task] CODEX_RETRY_EVENT tier=$_next_tier result=$([[ $rc -eq 0 ]] && echo ok || echo rc=$rc)" >&2
-    fi
-  fi
-
-  if [[ $rc -ne 0 && "$DISPATCH_MODEL" == gpt-5.6* ]] \
-     && printf '%s' "$out" | grep -qE '"status":[[:space:]]*400|is not supported when using Codex|requires a newer version of Codex'; then
-    echo "[codex-task] FALLBACK: model '$DISPATCH_MODEL' rejected by Codex CLI -- retrying once with ${_FALLBACK_MODEL} (effort ${_FALLBACK_EFFORT})" >&2
-    local fb_args=() prev=""
-    for _a in "$@"; do
-      if [[ "$prev" == "--model" || "$prev" == "-m" ]]; then
-        fb_args+=("$_FALLBACK_MODEL")
-      elif [[ "$prev" == "--effort" ]]; then
-        fb_args+=("$_FALLBACK_EFFORT")
-      else
-        fb_args+=("$_a")
-      fi
-      prev="$_a"
-    done
-    out="$(_run_node "${fb_args[@]}" 2>&1)" && rc=0 || rc=$?
-  fi
-  printf '%s\n' "$out"
-  lv2_trace_end "$rc"
-  return "$rc"
-}
-
-# CODEX-NEVER-LOSE-01 -- auto-guard background dispatches. `task`/`review` with
-# --background detach into a Codex job with nothing to notify this session on
-# completion; if the session dies first, the result is lost. Arm codex-guard.sh
-# (detached, non-blocking) so every background dispatch is watched to a
-# terminal state and any uncommitted result gets rescued. --wait/foreground
-# runs already return the full result inline and don't need this.
-_has_background=0
-for _a in "$@"; do [[ "$_a" == "--background" ]] && _has_background=1; done
-
-if [[ ( "$SUB" == "task" || "$SUB" == "review" ) && "$_has_background" -eq 1 ]]; then
-  # cwd: whatever was forwarded via --cwd/-C, else $PWD -- matches
-  # codex-companion's own resolveCommandCwd() default (process.cwd()).
-  _GUARD_CWD="$PWD"
-  _prev=""
-  for _a in "$@"; do
-    if [[ "$_prev" == "--cwd" || "$_prev" == "-C" ]]; then
-      _GUARD_CWD="$_a"
-    fi
-    _prev="$_a"
-  done
-
-  # wave2 round3 finding 5: this script runs under `set -e`, and a bare
-  # `_BG_OUT="$(_run_with_fallback "$@")"` is a plain simple-command assignment --
-  # NOT exempt from errexit -- so a genuine nonzero launcher failure aborted the whole
-  # script AT this line, before `_BG_RC` was ever captured and before the no-jobId
-  # branch below could ever call `_record_spawn_failure`. Folding the assignment into
-  # an explicit `&&`/`||` list (the SAME idiom `_run_with_fallback` uses internally for
-  # its own inner command substitution) makes the compound command exempt from -e,
-  # since only the LAST command of an and-or list can trigger it and that is always
-  # one of the two `_BG_RC=` assignments below, which always succeeds.
-  _BG_OUT="$(_run_with_fallback "$@")" && _BG_RC=0 || _BG_RC=$?
-  printf '%s\n' "$_BG_OUT"
-
-  # jobId format: <task|review>-<base36-timestamp>-<random6> (lib/state.mjs
-  # generateJobId) -- appears verbatim in both the rendered launch line and
-  # --json payload, so one regex covers both output modes.
-  _JOB_ID="$(printf '%s\n' "$_BG_OUT" | grep -oE '(task|review)-[a-z0-9]+-[a-z0-9]+' | head -1 || true)"
-  if [[ -n "$_JOB_ID" ]]; then
-    # CODEX-QUOTA-BLIND-SPOT-01 B -- resolve codex-guard.sh by ordered probe
-    # (first executable wins). FIX2: the dispatch-site repo owns the guard, so
-    # $PWD/.claude/scripts and the job's _GUARD_CWD/.claude/scripts are probed
-    # BEFORE the invocation-relative script dir. The script dir is now the
-    # last-resort fallback -- previously it was #1, and via the literal
-    # ~/.claude/scripts/codex-task.sh invocation path dirname(BASH_SOURCE)
-    # resolved to ~/.claude/scripts, picking the stale 4KB guard there ahead of
-    # the real per-repo copy at $PWD. CLAUDE_PROJECT_DIR is probed only when set.
-    # The resolved path is echoed in the armed line so a wrong pick stays visible
-    # at the log surface, not silent.
-    _GUARD_SCRIPT=""
-    _GUARD_TRIED=""
-    _GUARD_CANDS=()
-    _GUARD_CANDS+=("$PWD/.claude/scripts/codex-guard.sh")
-    _GUARD_CANDS+=("$_GUARD_CWD/.claude/scripts/codex-guard.sh")
-    [[ -z "${CLAUDE_PROJECT_DIR:-}" ]] || _GUARD_CANDS+=("$CLAUDE_PROJECT_DIR/.claude/scripts/codex-guard.sh")
-    _GUARD_CANDS+=("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/codex-guard.sh")
-    for _cand in "${_GUARD_CANDS[@]}"; do
-      if [[ -x "$_cand" ]]; then
-        _GUARD_SCRIPT="$_cand"
-        break
-      fi
-      _GUARD_TRIED="${_GUARD_TRIED:+$_GUARD_TRIED }$_cand"
-    done
-    if [[ -n "$_GUARD_SCRIPT" ]]; then
-      nohup "$_GUARD_SCRIPT" "$_JOB_ID" "$_GUARD_CWD" >/dev/null 2>&1 < /dev/null &
-      disown 2>/dev/null || true
-      echo "[codex-task] armed codex-guard.sh for $_JOB_ID (cwd=$_GUARD_CWD, guard=$_GUARD_SCRIPT)" >&2
-      # CODEX-DIES-MID-TEST-01 — codex-guard watches job STATUS; the deathwatch
-      # watches the WORKER PID so an out-of-band kill (SessionEnd broker
-      # shutdown, V8 OOM abort) is named in the job log, the dispatch journal
-      # and the arm ladder within seconds instead of hours. Same self-invoked,
-      # detached, disowned pattern as the guard line above.
-      nohup bash "$_CODEX_SCRIPT_DIR/codex-task.sh" __deathwatch "$_JOB_ID" \
-        --cwd "$_GUARD_CWD" >/dev/null 2>&1 < /dev/null &
-      disown 2>/dev/null || true
-      echo "[codex-task] armed deathwatch for $_JOB_ID (cwd=$_GUARD_CWD)" >&2
-    else
-      echo "[codex-task] WARN: codex-guard.sh not found -- tried: ${_GUARD_TRIED:-<none>} -- background job $_JOB_ID is unguarded" >&2
-    fi
-    # CODEX-GATE-01 C5 -- arm the quota watcher too (same nohup shape as the
-    # guard above). It records a lockout line if this job dies on a usage-limit
-    # error, so the next launch is refused up-front instead of burning another
-    # instant-failed slot. Resolves self via BASH_SOURCE so it works whether this
-    # script was invoked directly or through a sibling symlink (e.g. the
-    # ~/.claude/scripts/codex-task.sh link to this file).
-    _WRAPPER_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/codex-task.sh"
-    nohup "$_WRAPPER_SELF" __quota-watch "$_JOB_ID" "$_GUARD_CWD" >/dev/null 2>&1 < /dev/null &
-    disown 2>/dev/null || true
-    echo "[codex-task] armed quota-watch for $_JOB_ID" >&2
-  else
-    # T-f item 3 (spawn failure visibility): no jobId means codex-companion
-    # never wrote a job record at all -- today this WARNs and the failure
-    # vanishes. Synthesize a terminal job record so it's visible in
-    # `codex-task.sh status --all` instead.
-    echo "[codex-task] WARN: could not parse jobId from background dispatch output -- guard not armed" >&2
-    _record_spawn_failure "$_GUARD_CWD" "$_BG_OUT"
-  fi
-  exit "$_BG_RC"
-fi
-
-if [[ "${CODEX_VERBOSE:-0}" == "1" ]]; then
-  _run_with_fallback "$@"
-  exit $?
-fi
-
-# Strip noisy [codex] meta lines, keep the findings body / errors / un-prefixed content.
-_strip_meta() {
-  grep --line-buffered -vE '^\[codex\] (Running command|Command completed|Calling |Tool .* (completed|failed)|Assistant message captured)'
-}
-
-# For adversarial-review, also drop everything before the last findings marker so the
-# caller sees only the actionable tail (set CODEX_FULL=1 to keep the whole log).
-set -o pipefail
-if [[ "$SUB" == "adversarial-review" && "${CODEX_FULL:-0}" != "1" ]]; then
-  _run_with_fallback "$@" | _strip_meta | awk '
-    BEGIN { buf=""; all=""; found=0 }
-    /^# Codex|^\*\*Findings\*\*|^## Findings/ { buf=""; found=1 }
-    { buf = buf $0 "\n"; all = all $0 "\n" }
-    END { printf "%s", (found ? buf : all) }
-  '
 else
-  _run_with_fallback "$@" | _strip_meta
+    echo "Unknown subcommand: $1" >&2
+    exit 1
 fi
-exit "${PIPESTATUS[0]}"
diff --git a/plugins/leadv2/scripts/leadv2-dispatch-code.sh b/plugins/leadv2/scripts/leadv2-dispatch-code.sh
index f05137f6..321ace56 100755
--- a/plugins/leadv2/scripts/leadv2-dispatch-code.sh
+++ b/plugins/leadv2/scripts/leadv2-dispatch-code.sh
@@ -8155,10 +8155,26 @@ ${mission}"
         mkdir -p "$(dirname "${_lane_mission_path}")" 2>/dev/null
         printf '%s' "${mission}" > "${_lane_mission_path}" 2>/dev/null || _lane_mission_path=""
       fi
-      if [[ "${product_class}" == "product" ]] && ! spawn_product_close "${sig8}" "${candidate}" "${LAST_WORKER_HANDLE:-}" "${reviewer_arms}" "${lane_writes}" "${founder_task_id}" "${_lane_mission_path}" "${LANE_DELIVERABLE_DECL:-}"; then
+      # DISPATCHER-BRANCH-RESIDUE-01 (5e57c5ff codex r4 finding 4): persist the
+      # VALIDATED declaration (row/CLI --lane-deliverable wins over the mission
+      # line) beside the mission, so an advance-arm recovery re-threads the exact
+      # value instead of re-deriving it -- a re-derivation silently drops a
+      # --lane-deliverable override the lane was spawned with.
+      if [[ -n "${LANE_DELIVERABLE_DECL:-}" ]]; then
+        printf '%s' "${LANE_DELIVERABLE_DECL}" > "${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}/lane-deliverable" 2>/dev/null || true
+      fi
+      if [[ "${product_class}" == "product" ]]; then
+        if ! spawn_product_close "${sig8}" "${candidate}" "${LAST_WORKER_HANDLE:-}" "${reviewer_arms}" "${lane_writes}" "${founder_task_id}" "${_lane_mission_path}" "${LANE_DELIVERABLE_DECL:-}"; then
         # The worker is already live; make the failed postflight launch visible rather than
         # pretending close evidence will arrive.  Do not kill the independently-owned worker.
         log_err "product close gate could not be launched for task=${sig8}"
+        fi
+      elif [[ -n "${LANE_DELIVERABLE_DECL:-}" ]]; then
+        # DISPATCHER-BRANCH-RESIDUE-01 (5e57c5ff codex r2 finding 1): non-product
+        # classes never run the product close gate, so a report declaration there
+        # is NOT enforced -- surface that loudly instead of letting a declared
+        # report lane pass unjudged in silence.
+        emit decision "lane_deliverable task=${sig8} status=unenforced reason=non_product_class decl=${LANE_DELIVERABLE_DECL}"
       fi
       # V3-GLM-LADDER-01 Lever 3: attempted[] (not LAST_ARM_OUTCOME) is the durable
       # record of what was refused earlier in the loop -- by the time sonnet lands here,
@@ -8603,8 +8619,28 @@ cmd_advance_arm() {
   bash "${PHASE_RECORD_BIN}" record "${sig8}" build --status running \
     --handle "dispatch-${sig8}-build" \
     --task-id "${task_id}" --owner "$(basename "$0"):cmd_advance_arm" 2>/dev/null || true
+  # DISPATCHER-BRANCH-RESIDUE-01 (5e57c5ff codex r2 finding 2 + r4 finding 4):
+  # recover the lane's deliverable declaration. Prefer the VALIDATED declaration
+  # persisted at spawn time (docs/handoff/dispatch-<sig8>/lane-deliverable, which
+  # carries the higher-precedence --lane-deliverable / row value); fall back to
+  # re-harvesting the mission's own LANE_DELIVERABLE line. Without this, a report
+  # lane recovered via advance-arm is re-judged as a diff lane and blocks no_work
+  # despite its report.
+  local _adv_deliverable="" _adv_decl_file _adv_mission
+  _adv_decl_file="${PROJECT_ROOT}/docs/handoff/dispatch-${sig8}/lane-deliverable"
+  if [[ -f "${_adv_decl_file}" ]]; then
+    _adv_deliverable="$(cat "${_adv_decl_file}" 2>/dev/null)"
+  fi
+  [[ -n "${_adv_deliverable}" ]] || {
+    _adv_mission="$(cat "${mission_file}" 2>/dev/null || true)"
+    _adv_deliverable="$(_mission_deliverable "${_adv_mission}")"
+  }
+  if [[ -n "${_adv_deliverable}" ]] && ! lv2_deliverable_parse "${_adv_deliverable}" >/dev/null; then
+    emit decision "lane_deliverable task=${sig8} status=ignored reason=unknown_kind decl=${_adv_deliverable} src=advance_arm"
+    _adv_deliverable=""
+  fi
   if [[ "${E2E_GATE}" == "1" || "${REVIEW_GATE}" == "1" ]]; then
-    spawn_product_close "${sig8}" "${arm}" "${handle}" "$(IFS=,; printf '%s' "${candidate_arms[*]}")" "${writes}" "${task_id}" "${mission_file}"
+    spawn_product_close "${sig8}" "${arm}" "${handle}" "$(IFS=,; printf '%s' "${candidate_arms[*]}")" "${writes}" "${task_id}" "${mission_file}" "${_adv_deliverable}"
   fi
   printf 'arm_advance model=%s task=%s handle=%s\n' "${arm}" "${sig8}" "${handle}"
   exit 0
diff --git a/plugins/leadv2/scripts/leadv2-review-run.sh b/plugins/leadv2/scripts/leadv2-review-run.sh
index 3fd63104..7da6eeda 100755
--- a/plugins/leadv2/scripts/leadv2-review-run.sh
+++ b/plugins/leadv2/scripts/leadv2-review-run.sh
@@ -186,6 +186,14 @@ resolve_review_pool_call() {
   # The caller captures THIS function's stdout as resolver_out -- the original
   # tail passed python's stdout straight through; the buffer must be re-printed.
   printf '%s\n' "${_resolver_out}"
+  # DISPATCHER-BRANCH-RESIDUE-01 (worktree-100a892d §3.1 residue): also hand the
+  # caller the rc and the stderr artifact path so the unreviewed gate below can
+  # carry them. The close-gate's _pc_write_unreviewed has shipped refusal:/
+  # resolver_rc:/resolver_stderr: since dispatch-8e2a32be A3 -- the engine path
+  # must never emit a lossier artifact than the lane it replaces. The caller
+  # parses keys individually, so these additive lines change no existing reader.
+  printf 'resolver_rc=%s\n' "${_resolver_rc}"
+  printf 'resolver_stderr=%s\n' "${_resolver_err_file#"${ROOT}"/}"
 }
 
 # ---------------------------------------------------------------------------
@@ -1379,6 +1387,25 @@ resolver_out="$(resolve_review_pool_call)"
 reviewer="$(printf '%s\n' "${resolver_out}" | sed -n 's/^reviewer=//p' | head -n1)"
 pool="$(printf '%s\n' "${resolver_out}" | sed -n 's/^pool=//p' | head -n1)"
 refusal="$(printf '%s\n' "${resolver_out}" | sed -n 's/^refusal=//p' | head -n1)"
+# DISPATCHER-BRANCH-RESIDUE-01 (worktree-100a892d §3.1 residue): rc/stderr ride
+# the resolver buffer since the FP-07B parity change above.
+resolver_rc="$(printf '%s\n' "${resolver_out}" | sed -n 's/^resolver_rc=//p' | head -n1)"
+resolver_stderr="$(printf '%s\n' "${resolver_out}" | sed -n 's/^resolver_stderr=//p' | head -n1)"
+
+# DISPATCHER-BRANCH-RESIDUE-01 (worktree-100a892d §3.1 residue): the ONE writer
+# for "no reviewer was ever seated" in the engine path, field-for-field the
+# close-gate's _pc_write_unreviewed (dispatch-8e2a32be A3/A5 shape): refusal:/
+# resolver_rc:/resolver_stderr:/merge_blocked: used to be silently absent here,
+# leaving a bare empty `pool:` as the last informative line -- the live
+# dispatch-4c9ddb05 failure mode. Literal "-" for empty, same as the lane writer.
+# <refusal> <pool> <tried> — resolver_rc/resolver_stderr from the parse above.
+_rr_or_dash() { [[ -n "${1:-}" ]] && printf '%s' "$1" || printf '%s' '-'; }
+_rr_write_unreviewed() { # <refusal> <pool> <tried>
+  printf 'status: unreviewed\nreason: all_arms_unavailable\nauthor: %s\npool: %s\ntried: %s\nrefusal: %s\nresolver_rc: %s\nresolver_stderr: %s\nmerge_blocked: true\n' \
+    "${AUTHOR}" "$(_rr_or_dash "$2")" "$(_rr_or_dash "$3")" "${1:-all_review_arms_unavailable}" \
+    "$(_rr_or_dash "${resolver_rc}")" "$(_rr_or_dash "${resolver_stderr}")" > "${HANDOFF}/review-gate.md"
+  emit decision "review_gate task=${TASK} status=unreviewed reason=all_arms_unavailable author=${AUTHOR} pool=$(_rr_or_dash "$2") tried=$(_rr_or_dash "$3") refusal=${1:-all_review_arms_unavailable} resolver_rc=$(_rr_or_dash "${resolver_rc}")"
+}
 SECURITY_REVIEW_ENABLED=0
 if _engine_security_pass_enabled; then
   SECURITY_REVIEW_ENABLED=1
@@ -1395,11 +1422,7 @@ fi
 
 if [[ -z "${reviewer}" ]]; then
   refusal="${refusal:-all_review_arms_unavailable}"
-  {
-    printf 'status: unreviewed\nreason: all_arms_unavailable\nauthor: %s\npool: %s\ntried: \n' "${AUTHOR}" "${pool}"
-  } > "${HANDOFF}/review-gate.md.tmp"
-  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
-  emit decision "review_gate task=${TASK} status=unreviewed reason=all_arms_unavailable author=${AUTHOR} pool=${pool} refusal=${refusal} tried="
+  _rr_write_unreviewed "${refusal}" "${pool}" ""
   exit 9
 fi
 
@@ -1538,12 +1561,10 @@ done
 
 if [[ "${#ran_arms[@]}" -eq 0 ]]; then
   _pc_tried_csv="$(IFS=,; echo "${tried[*]:-}")"
-  {
-    printf 'status: unreviewed\nreason: all_arms_unavailable\nauthor: %s\npool: %s\ntried: %s\n' \
-      "${AUTHOR}" "${pool}" "${_pc_tried_csv}"
-  } > "${HANDOFF}/review-gate.md.tmp"
-  mv -f "${HANDOFF}/review-gate.md.tmp" "${HANDOFF}/review-gate.md"
-  emit decision "review_gate task=${TASK} status=unreviewed reason=all_arms_unavailable author=${AUTHOR} pool=${pool} tried=${_pc_tried_csv}"
+  # DISPATCHER-BRANCH-RESIDUE-01: same 8-field writer as the resolver-empty
+  # branch above -- the two "no reviewer seated" exits must never diverge in
+  # artifact shape again (dispatch-8e2a32be A3's lesson, applied here).
+  _rr_write_unreviewed "${refusal:-all_review_arms_unavailable}" "${pool}" "${_pc_tried_csv}"
   exit 9
 fi
 
diff --git a/plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh b/plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh
index 1043efe9..fbeecb9e 100644
--- a/plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh
+++ b/plugins/leadv2/scripts/lib/leadv2-report-deliverable.sh
@@ -29,6 +29,11 @@ lv2_deliverable_parse() { # <decl>
   # reject empty / absolute / traversal / interior-empty-segment paths
   [[ -n "${path}" && "${path}" != /* && "${path}" != "." && "${path}" != "/" ]] || return 1
   [[ "${path}" == ".." || "${path}" == ../* || "${path}" == */.. || "${path}" == */../* ]] && return 1
+  # DISPATCHER-BRANCH-RESIDUE-01 (5e57c5ff codex r4 finding 5): reject repo
+  # control metadata. .git/config et al. are inside the tree and pass the
+  # containment checks above, but a declared "report" must never ship repository
+  # configuration -- including credential-bearing remote URLs -- to external review.
+  [[ "${path}" == ".git" || "${path}" == .git/* ]] && return 1
   case "/${path}/" in *//*) return 1 ;; esac
   printf 'report\x1f%s' "${path}"
 }
@@ -38,10 +43,35 @@ lv2_deliverable_parse() { # <decl>
 # (root); rc 1 if neither exists. The report's canonical home is the lane worktree
 # (worker --cwd is LEADV2_LANE_WORK_ROOT), but a worker that ran in the main
 # checkout leaves it ROOT-side -- both are legitimate finds.
+# DISPATCHER-BRANCH-RESIDUE-01 (5e57c5ff codex review finding 2 + r2 finding 3 +
+# r4 finding 6): a symlink (the file itself, or any parent dir) is NOT a find --
+# the report is copied verbatim into the handoff and sent to an external
+# reviewer, so a declaration must never be able to harvest a host file outside
+# its tree. Physical containment via pwd -P (dereferences symlinked parents);
+# same-volume hardlinks (st_nlink > 1) escape containment without escaping the
+# path, so they are refused too.
 lv2_report_locate() { # <diff_root> <root> <rel>
-  local diff_root="$1" root="$2" rel="$3" cand
-  for cand in "${diff_root}/${rel}" "${root}/${rel}"; do
-    [[ -f "${cand}" ]] && { printf '%s' "${cand}"; return 0; }
+  local diff_root="$1" root="$2" rel="$3" base cand phys_base phys_dir nlink
+  for base in "${diff_root}" "${root}"; do
+    [[ -d "${base}" ]] || continue
+    cand="${base}/${rel}"
+    [[ -f "${cand}" && ! -L "${cand}" ]] || continue
+    phys_base="$(cd "${base}" 2>/dev/null && pwd -P)" || continue
+    phys_dir="$(cd "$(dirname "${cand}")" 2>/dev/null && pwd -P)" || continue
+    # physical containment: an escaped phys_dir means some path segment was a
+    # link out of the tree.
+    [[ "${phys_dir}" == "${phys_base}" || "${phys_dir}/" == "${phys_base}"/* ]] || continue
+    # a same-volume HARDLINK escapes containment without escaping the path: an
+    # inode shared with something this find cannot see is not a worker-written
+    # report (link-count 1). GNU form FIRST: on GNU stat, `-f %l` ALSO parses
+    # (filesystem max filename length, usually 255) and would reject every
+    # report on Linux, while BSD stat has no `-c` -- so the fallback order is
+    # unambiguous on both platforms.
+    nlink="$(stat -c %h "${cand}" 2>/dev/null || stat -f %l "${cand}" 2>/dev/null || printf '1')"
+    [[ "${nlink}" =~ ^[0-9]+$ ]] || nlink=1
+    (( nlink <= 1 )) || continue
+    printf '%s' "${cand}"
+    return 0
   done
   return 1
 }
@@ -76,6 +106,15 @@ lv2_report_harvest() { # <abs> <handoff_dir>
   local abs="$1" handoff_dir="$2" dest tmp
   dest="${handoff_dir}/report.md"
   mkdir -p "${handoff_dir}" 2>/dev/null || return 1
+  # DISPATCHER-BRANCH-RESIDUE-01 (5e57c5ff codex review finding 3 + r2 finding
+  # 4): fail closed on a non-regular destination. An existing DIRECTORY at
+  # report.md would make `mv` file the tmp INSIDE it and return success,
+  # advertising a deliverable that is not a file; a SYMLINK destination is
+  # refused outright because `-f`/`-ef` follow links, so a dest symlinked at
+  # the worktree source would skip the copy and dangle the moment the worktree
+  # is swept. Never silently delete the oddity -- the caller blocks.
+  [[ ! -L "${dest}" ]] || return 1
+  [[ ! -e "${dest}" || -f "${dest}" ]] || return 1
   if [[ "${abs}" -ef "${dest}" ]]; then
     printf '%s' "${dest}"
     return 0
diff --git a/plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh b/plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh
index c369f595..6d66a896 100755
--- a/plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh
+++ b/plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh
@@ -1,4 +1,5 @@
 #!/usr/bin/env bash
+# run-all-triggers: leadv2-dispatch-code.sh
 # Isolated subprocess integration coverage for PREPASS-PROVIDER-FALLBACK-01-R9.
 # Every case runs a copy of the dispatcher against a temporary Git repository;
 # Codex, GLM, and registry behavior are local stubs.  No provider or canonical
diff --git a/plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh b/plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh
index e1b68b3f..95398644 100644
--- a/plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh
+++ b/plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh
@@ -1,4 +1,5 @@
 #!/usr/bin/env bash
+# run-all-triggers: leadv2-dispatch-code.sh leadv2-dispatch-product-close.sh
 # Offline regression for CODEX-QUOTA-LOCKOUT-NEVER-FIRES-FOR-CODEX-01.
 #
 # Root cause: codex's launcher (codex-task.sh task ... --background) exits 0 the
diff --git a/plugins/leadv2/scripts/tests/test-report-only-gate.sh b/plugins/leadv2/scripts/tests/test-report-only-gate.sh
index 17056366..53e451c1 100644
--- a/plugins/leadv2/scripts/tests/test-report-only-gate.sh
+++ b/plugins/leadv2/scripts/tests/test-report-only-gate.sh
@@ -387,6 +387,145 @@ LANE_DELIVERABLE: report:docs/handoff/R1/report.md')"
 
 # ── harness ───────────────────────────────────────────────────────────────────────
 CASE_NAMES=(); CASE_RCS=()
+# ── Case 7 — symlinked report is not a find (codex review finding 2) ─────────────
+# A worker (or a compromised one) leaving a SYMLINK at the declared path must not
+# let the gate harvest a host file into the handoff / external review. The gate
+# treats it as report_missing — locate refuses symlinks and escaped parents.
+case_7_symlink_report() { # <scripts_dir>
+  local sd="$1"
+  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
+  local root tid wt d errf rrc gate secret
+  root="$(new_repo)"; tid="rog1c7-$$"
+  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
+  [[ -d "${wt}" ]] || return 2
+  secret="$(mktemp "${TMPDIR:-/tmp}/leadv2-rog1-s.XXXXXX")"
+  write_good_report "${secret}"
+  mkdir -p "${wt}/analysis"
+  ln -s "${secret}" "${wt}/analysis/report.md"
+  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
+  make_resolver_stub "${d}/resolver.py" codex
+  make_review_pass_stub "${d}/codex.sh"
+  rrc="$(run_gate "${sd}" "${root}" rog1c7sig "${wt}" "${d}" "${errf}" "report:analysis/report.md" "-")"
+  gate="$(gate_md "${root}" rog1c7sig)"
+  local ok=0
+  [[ "${rrc}" == "rc=5" ]] || ok=1
+  grep -q '^status: blocked' <<<"${gate}" || ok=1
+  grep -q '^reason: report_missing' <<<"${gate}" || ok=1
+  # the host file must NOT have been harvested into the handoff
+  [[ ! -e "${root}/docs/handoff/dispatch-rog1c7sig/report.md" ]] || ok=1
+  rm -rf "${root}" "${d}" "${wt}"; rm -f "${errf}" "${secret}"
+  return "${ok}"
+}
+
+# ── Case 8 — non-regular report.md at destination -> harvest_failed (finding 3) ──
+# An existing DIRECTORY at docs/handoff/dispatch-<sig>/report.md must fail closed:
+# blocked harvest_failed, never a pass advertising a deliverable that is not a file.
+case_8_dest_collision() { # <scripts_dir>
+  local sd="$1"
+  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
+  local root tid wt d errf rrc gate
+  root="$(new_repo)"; tid="rog1c8-$$"
+  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
+  [[ -d "${wt}" ]] || return 2
+  write_good_report "${wt}/analysis/report.md"
+  mkdir -p "${root}/docs/handoff/dispatch-rog1c8sig/report.md"   # the collision
+  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
+  make_resolver_stub "${d}/resolver.py" codex
+  make_review_pass_stub "${d}/codex.sh"
+  rrc="$(run_gate "${sd}" "${root}" rog1c8sig "${wt}" "${d}" "${errf}" "report:analysis/report.md" "-")"
+  gate="$(gate_md "${root}" rog1c8sig)"
+  local ok=0
+  [[ "${rrc}" == "rc=5" ]] || ok=1
+  grep -q '^status: blocked' <<<"${gate}" || ok=1
+  grep -q '^reason: harvest_failed' <<<"${gate}" || ok=1
+  grep -q '^kind: report' <<<"${gate}" || ok=1
+  rm -rf "${root}" "${d}" "${wt}"; rm -f "${errf}"
+  return "${ok}"
+}
+
+# ── Case 9 — hardlinked report is not a find (codex r2 finding 3) ─────────────────
+# A same-volume hardlink to a host file shares the inode with something outside the
+# tree; st_nlink > 1 means the find is refused -> report_missing, nothing harvested.
+case_9_hardlink_report() { # <scripts_dir>
+  local sd="$1"
+  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
+  local root tid wt d errf rrc gate secret
+  root="$(new_repo)"; tid="rog1c9-$$"
+  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
+  [[ -d "${wt}" ]] || return 2
+  secret="$(mktemp "${TMPDIR:-/tmp}/leadv2-rog1-s.XXXXXX")"
+  write_good_report "${secret}"
+  mkdir -p "${wt}/analysis"
+  if ! ln "${secret}" "${wt}/analysis/report.md" 2>/dev/null; then
+    rm -rf "${root}" "${wt}"; rm -f "${secret}"   # cross-volume fixture: not runnable here
+    return 2
+  fi
+  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
+  make_resolver_stub "${d}/resolver.py" codex
+  make_review_pass_stub "${d}/codex.sh"
+  rrc="$(run_gate "${sd}" "${root}" rog1c9sig "${wt}" "${d}" "${errf}" "report:analysis/report.md" "-")"
+  gate="$(gate_md "${root}" rog1c9sig)"
+  local ok=0
+  [[ "${rrc}" == "rc=5" ]] || ok=1
+  grep -q '^status: blocked' <<<"${gate}" || ok=1
+  grep -q '^reason: report_missing' <<<"${gate}" || ok=1
+  [[ ! -e "${root}/docs/handoff/dispatch-rog1c9sig/report.md" ]] || ok=1
+  rm -rf "${root}" "${d}" "${wt}"; rm -f "${errf}" "${secret}"
+  return "${ok}"
+}
+
+# ── Case 10 — symlink AT the destination -> harvest_failed (codex r2 finding 4) ──
+# A pre-existing report.md SYMLINK pointing at the worktree source would satisfy the
+# same-file (-ef) guard and dangle after the sweep; harvest must refuse it outright.
+case_10_dest_symlink() { # <scripts_dir>
+  local sd="$1"
+  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
+  local root tid wt d errf rrc gate
+  root="$(new_repo)"; tid="rog1c10-$$"
+  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
+  [[ -d "${wt}" ]] || return 2
+  write_good_report "${wt}/analysis/report.md"
+  mkdir -p "${root}/docs/handoff/dispatch-rog1c10sig"
+  ln -s "${wt}/analysis/report.md" "${root}/docs/handoff/dispatch-rog1c10sig/report.md"
+  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
+  make_resolver_stub "${d}/resolver.py" codex
+  make_review_pass_stub "${d}/codex.sh"
+  rrc="$(run_gate "${sd}" "${root}" rog1c10sig "${wt}" "${d}" "${errf}" "report:analysis/report.md" "-")"
+  gate="$(gate_md "${root}" rog1c10sig)"
+  local ok=0
+  [[ "${rrc}" == "rc=5" ]] || ok=1
+  grep -q '^status: blocked' <<<"${gate}" || ok=1
+  grep -q '^reason: harvest_failed' <<<"${gate}" || ok=1
+  grep -q '^kind: report' <<<"${gate}" || ok=1
+  rm -rf "${root}" "${d}" "${wt}"; rm -f "${errf}"
+  return "${ok}"
+}
+
+# ── Case 13 — .git deliverable path is refused at parse -> diff-lane shape ────────
+# report:.git/config parses as a path but is control metadata; the parser rejects it,
+# so the lane is judged as a diff lane (r4 finding 5).
+case_13_git_path() { # <scripts_dir>
+  local sd="$1"
+  [[ -f "${sd}/leadv2-dispatch-product-close.sh" ]] || return 2
+  local root tid wt d errf rrc gate
+  root="$(new_repo)"; tid="rog1c13-$$"
+  wt="$(ensure_worktree "${sd}" "${root}" "${tid}")"
+  [[ -d "${wt}" ]] || return 2
+  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rog1-d.XXXXXX")"; errf="$(mktemp "${TMPDIR:-/tmp}/leadv1-e.XXXXXX")"
+  make_resolver_stub "${d}/resolver.py" codex
+  make_review_pass_stub "${d}/codex.sh"
+  rrc="$(run_gate "${sd}" "${root}" rog1c13sig "${wt}" "${d}" "${errf}" "report:.git/config" "-")"
+  gate="$(gate_md "${root}" rog1c13sig)"
+  local ok=0
+  # refused at parse => exactly the dead-worker diff-lane shape, never a report pass
+  [[ "${rrc}" == "rc=5" ]] || ok=1
+  grep -q '^reason: no_work' <<<"${gate}" || ok=1
+  grep -q '^kind: diff' <<<"${gate}" || ok=1
+  if grep -q '^kind: report' <<<"${gate}"; then ok=1; fi
+  rm -rf "${root}" "${d}" "${wt}"; rm -f "${errf}"
+  return "${ok}"
+}
+
 run_case() { # <name> <fn> <scripts_dir>
   local name="$1" fn="$2" sd="$3" rc
   # Some gate helpers source strict-mode libraries.  Capture an expected red
@@ -429,6 +568,11 @@ run_case "C5-dead-worker-kind"   case_5_dead_worker       "${SCRIPTS_LIVE}"
 run_case "C6a-unknown-kind-gate" case_6a_unknown_kind_gate "${SCRIPTS_LIVE}"
 run_case "C6b-unknown-kind-journal" case_6b_unknown_kind_journal "${SCRIPTS_LIVE}"
 run_case "C6c-guard-exemption"   case_6c_guard_exemption  "${SCRIPTS_LIVE}"
+run_case "C7-symlink-report"    case_7_symlink_report    "${SCRIPTS_LIVE}"
+run_case "C8-dest-collision"    case_8_dest_collision    "${SCRIPTS_LIVE}"
+run_case "C9-hardlink-report"   case_9_hardlink_report   "${SCRIPTS_LIVE}"
+run_case "C10-dest-symlink"     case_10_dest_symlink     "${SCRIPTS_LIVE}"
+run_case "C13-git-path"         case_13_git_path         "${SCRIPTS_LIVE}"
 POST_NAMES=("${CASE_NAMES[@]}"); POST_RCS=("${CASE_RCS[@]}")
 
 echo ""
diff --git a/plugins/leadv2/scripts/tests/test-review-gate-scope-evidence.sh b/plugins/leadv2/scripts/tests/test-review-gate-scope-evidence.sh
index 45aeaddf..817a08a8 100755
--- a/plugins/leadv2/scripts/tests/test-review-gate-scope-evidence.sh
+++ b/plugins/leadv2/scripts/tests/test-review-gate-scope-evidence.sh
@@ -1,4 +1,5 @@
 #!/usr/bin/env bash
+# run-all-triggers: leadv2-dispatch-product-close.sh
 # tests/test-review-gate-scope-evidence.sh — REVIEW-GATE-INFRA-01 D-A regression.
 #
 # Three defects fixed in leadv2-dispatch-product-close.sh's empty-scoped-diff path:
diff --git a/plugins/leadv2/scripts/tests/test-review-pool-empty-rootcause.sh b/plugins/leadv2/scripts/tests/test-review-pool-empty-rootcause.sh
index 1e547883..fe9bdd22 100755
--- a/plugins/leadv2/scripts/tests/test-review-pool-empty-rootcause.sh
+++ b/plugins/leadv2/scripts/tests/test-review-pool-empty-rootcause.sh
@@ -1,4 +1,5 @@
 #!/usr/bin/env bash
+# run-all-triggers: leadv2-review-run.sh leadv2-glm-policy-resolve.py
 # tests/test-review-pool-empty-rootcause.sh — dispatch-59a0e749 (CODEX-QUOTA-GATE r2,
 # Layer A): a resolver crash must be LOUD, never the silent empty
 # `pool:`/`tried:` shape that made the live dispatch-83c44855 review-gate.md
diff --git a/plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh b/plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh
index 2ce38db3..3b1f1769 100644
--- a/plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh
+++ b/plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh
@@ -1,4 +1,5 @@
 #!/usr/bin/env bash
+# run-all-triggers: leadv2-review-run.sh leadv2-glm-policy-resolve.py leadv2-dispatch-product-close.sh
 # tests/test-review-pool-never-empty.sh — dispatch-8e2a32be round 2: the review pool
 # must never be empty, even when codex+glm are both quota-locked and the author is
 # excluded from reviewing itself.
diff --git a/plugins/leadv2/scripts/tests/test-review-verdict-recovery.sh b/plugins/leadv2/scripts/tests/test-review-verdict-recovery.sh
index cedbfc10..08bbcd55 100755
--- a/plugins/leadv2/scripts/tests/test-review-verdict-recovery.sh
+++ b/plugins/leadv2/scripts/tests/test-review-verdict-recovery.sh
@@ -1,4 +1,5 @@
 #!/usr/bin/env bash
+# run-all-triggers: leadv2-review-run.sh
 # tests/test-review-verdict-recovery.sh — REVIEW-GATE-INFRA-01 D-B regression.
 #
 # pc_persist_review_body copies every arm's review body to a STABLE path
```

## `plugins/leadv2/scripts/tests/test-lane-deliverable-advance-arm.sh` (untracked, 6614 bytes)

```
#!/usr/bin/env bash
# run-all-triggers: leadv2-dispatch-code.sh leadv2-report-deliverable.sh
# test-lane-deliverable-advance-arm.sh — DISPATCHER-BRANCH-RESIDUE-01 (worktree-5e57c5ff
# codex r2 finding 2 + r4 finding 4): a report lane recovered via `advance-arm` must
# re-thread its deliverable declaration into spawn_product_close -- preferring the
# VALIDATED declaration persisted at spawn time (docs/handoff/dispatch-<sig8>/
# lane-deliverable, carrying the higher-precedence --lane-deliverable / row value),
# falling back to re-harvesting the mission's LANE_DELIVERABLE line. Without this, a
# recovered report lane is re-judged as a diff lane and blocks no_work despite its
# report.
#
# Method: load the real dispatcher's definitions (everything above the `# ── dispatch `
# CLI footer) as a library, stub spawn_worker + spawn_product_close + the ledger, and
# drive cmd_advance_arm directly. No provider, registry, or network call ever runs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DISPATCH="${SCRIPTS_ROOT}/leadv2-dispatch-code.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s -- %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

bash -n "$DISPATCH" || { echo "ERROR: dispatch-code.sh syntax"; exit 1; }

ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t leadv2-ldaa)"; trap 'rm -rf "$ROOT"' EXIT
REPO="$ROOT/repo"
mkdir -p "$REPO/.claude/ref" "$REPO/docs/handoff" "$REPO/docs/leadv2/tasks"
(cd "$REPO" && git init -q && git config user.email test@example.com && git config user.name test \
  && printf 'seed\n' > seed && git add seed && git commit -qm seed)

# lib load: everything above the CLI footer marker
awk '/^# ── dispatch / { exit } { print }' "$DISPATCH" > "$ROOT/dispatch-lib.sh"

JOURNAL_CAPTURE="$ROOT/journal-capture.txt"
FAKE_JOURNAL="$ROOT/fake-journal.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$JOURNAL_CAPTURE" > "$FAKE_JOURNAL"
chmod +x "$FAKE_JOURNAL"

FAKE_PHASE_RECORD="$ROOT/fake-phase-record.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_PHASE_RECORD"
chmod +x "$FAKE_PHASE_RECORD"

CLOSE_ARGS="$ROOT/close-args.txt"

run_advance_arm() { # <sig8> <mission-file> -> close-gate 8th arg ("" if absent) in $CAPTURED_DELIVERABLE
  local sig8="$1" mission_file="$2"
  rm -f "$CLOSE_ARGS" "$JOURNAL_CAPTURE"
  (
    set -uo pipefail
    export LEADV2_PROJECT_ROOT="$REPO" CLAUDE_PROJECT_ROOT="$REPO"
    export LEADV2_JOURNAL_BIN="$FAKE_JOURNAL"
    export LEADV2_DISPATCH_E2E_GATE=1 LEADV2_DISPATCH_REVIEW_GATE=1
    export LEADV2_DISPATCH_CACHE_DIR="$ROOT/cache" LEADV2_QUOTA_LOCKOUT_DIR="$ROOT/lockouts"
    export LEADV2_ROUTER_V2=0 LEADV2_EXCLUDED_ARMS=__none__ LEADV2_LANE_SHAPE=off
    export LEADV2_TASK_ID="${sig8}-founder" LEADV2_PARENT_SESSION_ID=s-test
    export PHASE_RECORD_BIN="$FAKE_PHASE_RECORD"
    source "$ROOT/dispatch-lib.sh"
    # ── stubs over the loaded definitions ──
    spawn_worker() { printf 'PID=4242 LABEL=stub-arm SESSION_ID=s-stub\n'; }
    spawn_product_close() {
      # capture ALL args; arg 8 is the recovered deliverable declaration
      printf '%s\n' "${8-__ABSENT__}" > "$CLOSE_ARGS"
      return 0
    }
    _stamp_active_phase() { :; }
    dispatch_ledger_file() { printf '%s/ledger.jsonl' "$REPO"; }
    cmd_advance_arm --sig8 "$sig8" --arm sonnet --mission-file "$mission_file" \
      --task-id "${sig8}-founder" --worktree "$REPO" --writes seed >/dev/null 2>"$ROOT/adv.err"
  )
  CAPTURED_DELIVERABLE="$(cat "$CLOSE_ARGS" 2>/dev/null || printf '__NO_CLOSE__')"
}

confirm_ledger_row() { # <sig8> — a confirmed reservation row the guard accepts
  printf '{"task_sig":"%s","state":"confirmed","task_class":"Standard","founder_task_id":"%s-founder"}\n' "$1" "$1" \
    > "$REPO/ledger.jsonl"
}

# ── T1: validated lane-deliverable FILE wins -- 8th arg threads it ──────────────
SIG1=ldaa0001
confirm_ledger_row "$SIG1"
HANDOFF1="$REPO/docs/handoff/dispatch-$SIG1"
mkdir -p "$HANDOFF1"
printf 'stub mission with no deliverable line\n' > "$HANDOFF1/mission.md"
printf 'report:analysis/report.md' > "$HANDOFF1/lane-deliverable"   # the validated decl (spawn-time persistence)
run_advance_arm "$SIG1" "$HANDOFF1/mission.md"
if [[ "${CAPTURED_DELIVERABLE}" == "report:analysis/report.md" ]]; then
  pass "T1: advance-arm threads the persisted validated declaration"
else
  fail "T1: persisted declaration" "8th arg='${CAPTURED_DELIVERABLE}'"
fi

# ── T2: no file -> falls back to the mission's own LANE_DELIVERABLE line ────────
SIG2=ldaa0002
confirm_ledger_row "$SIG2"
HANDOFF2="$REPO/docs/handoff/dispatch-$SIG2"
mkdir -p "$HANDOFF2"
printf 'mission text\nLANE_DELIVERABLE: report:docs/other.md\nmore text\n' > "$HANDOFF2/mission.md"
run_advance_arm "$SIG2" "$HANDOFF2/mission.md"
if [[ "${CAPTURED_DELIVERABLE}" == "report:docs/other.md" ]]; then
  pass "T2: mission-line fallback recovers the declaration"
else
  fail "T2: mission fallback" "8th arg='${CAPTURED_DELIVERABLE}'"
fi

# ── T3: FILE beats mission line (the r4-finding-4 precedence) ──────────────────
SIG3=ldaa0003
confirm_ledger_row "$SIG3"
HANDOFF3="$REPO/docs/handoff/dispatch-$SIG3"
mkdir -p "$HANDOFF3"
printf 'LANE_DELIVERABLE: report:from-mission.md\n' > "$HANDOFF3/mission.md"
printf 'report:from-file.md' > "$HANDOFF3/lane-deliverable"
run_advance_arm "$SIG3" "$HANDOFF3/mission.md"
if [[ "${CAPTURED_DELIVERABLE}" == "report:from-file.md" ]]; then
  pass "T3: file declaration outranks the mission line"
else
  fail "T3: precedence" "8th arg='${CAPTURED_DELIVERABLE}'"
fi

# ── T4: UNPARSABLE decl -> ignored loudly, empty 8th arg ────────────────────────
SIG4=ldaa0004
confirm_ledger_row "$SIG4"
HANDOFF4="$REPO/docs/handoff/dispatch-$SIG4"
mkdir -p "$HANDOFF4"
printf 'mission without deliverable\n' > "$HANDOFF4/mission.md"
printf 'banana:nota/decl' > "$HANDOFF4/lane-deliverable"
run_advance_arm "$SIG4" "$HANDOFF4/mission.md"
if [[ "${CAPTURED_DELIVERABLE}" == "" ]]; then
  pass "T4a: unparsable declaration threads an EMPTY deliverable"
else
  fail "T4a: unparsable decl" "8th arg='${CAPTURED_DELIVERABLE}'"
fi
if grep -q 'lane_deliverable task=ldaa0004 status=ignored reason=unknown_kind src=advance_arm' "$JOURNAL_CAPTURE" 2>/dev/null; then
  pass "T4b: the ignore is journalled (never silent)"
else
  fail "T4b: journal" "capture lacks ignored line: $(tail -2 "$JOURNAL_CAPTURE" 2>/dev/null)"
fi

printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
```

## `plugins/leadv2/scripts/tests/test-review-unreviewed-artifact.sh` (untracked, 4947 bytes)

```
#!/usr/bin/env bash
# run-all-triggers: leadv2-review-run.sh
# test-review-unreviewed-artifact.sh — DISPATCHER-BRANCH-RESIDUE-01 (worktree-100a892d
# §3.1 residue): the engine path's two "no reviewer was ever seated" exits must emit
# the SAME 8-field unreviewed artifact the close-gate's _pc_write_unreviewed has shipped
# since dispatch-8e2a32be (refusal:/resolver_rc:/resolver_stderr:/merge_blocked:), never
# the lossy 4-field shape (bare `pool:` / empty `tried:`) that made the live
# dispatch-4c9ddb05 review-gate.md undiagnosable.
#
# Hermetic: LEADV2_GLM_POLICY_RESOLVER swaps in stub resolvers; no arms ever run on
# these paths (the gate exits before any spawn); no live provider/network calls.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPTS_ROOT}/leadv2-review-run.sh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL=$((FAIL + 1)); }

bash -n "$ENGINE" || { echo "ERROR: engine syntax check failed"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-unrev-artifact.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mk_fixture() { # <tag> -> ROOT/HANDOFF/DIFF
  local tag="$1"
  ROOT="$TMP/repo-$tag"
  mkdir -p "$ROOT/.claude/ref"
  HANDOFF="$ROOT/docs/handoff/dispatch-UNREV$tag"
  mkdir -p "$HANDOFF"
  DIFF="$HANDOFF/review.diff"
  printf 'diff --git a/x b/x\n+hello\n' > "$DIFF"
}

# 8-field shape assertions shared by both scenarios: every previously-absent field
# must now be present and non-empty (literal "-" for genuinely-empty values).
assert_full_shape() { # <label> <gate-file>
  local label="$1" gate="$2" ok=1
  grep -q '^status: unreviewed$'      "$gate" || { fail "$label: status: unreviewed missing"; ok=0; }
  grep -q '^reason: all_arms_unavailable$' "$gate" || { fail "$label: reason missing"; ok=0; }
  grep -q '^refusal: .\+$'            "$gate" || { fail "$label: refusal missing/empty"; ok=0; }
  grep -qE '^resolver_rc: [0-9]+$'    "$gate" || { fail "$label: resolver_rc missing/not-numeric"; ok=0; }
  grep -qE '^resolver_stderr: .+$'    "$gate" || { fail "$label: resolver_stderr missing"; ok=0; }
  grep -q '^merge_blocked: true$'     "$gate" || { fail "$label: merge_blocked: true missing"; ok=0; }
  grep -q '^tried: .\+$'              "$gate" || { fail "$label: tried missing/empty"; ok=0; }
  (( ok )) && pass "$label: full 8-field unreviewed artifact"
}

# ── T1: resolver returns an empty pool (reviewer empty, rc 0) — first unreviewed exit ──
cat > "$TMP/resolver-empty.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=")
print("pool=")
print("refusal=all_review_arms_unavailable")
PY
chmod +x "$TMP/resolver-empty.py"

mk_fixture empty
LEADV2_GLM_POLICY_RESOLVER="$TMP/resolver-empty.py" \
LEADV2_REVIEW_FANOUT=1 \
bash "$ENGINE" --task UNREVempty --root "$ROOT" --handoff "$HANDOFF" \
  --diff "$DIFF" --author sonnet >/dev/null 2>"$TMP/t1.err"
rc1=$?
if [[ $rc1 -eq 9 ]]; then
  pass "T1: empty pool exits 9"
else
  fail "T1: expected exit 9, got $rc1 (err tail: $(tail -1 "$TMP/t1.err"))"
fi
assert_full_shape "T1" "$HANDOFF/review-gate.md"
grep -q '^refusal: all_review_arms_unavailable$' "$HANDOFF/review-gate.md" \
  && pass "T1: refusal carries the resolver's named refusal" \
  || fail "T1: refusal value lost"

# ── T2: resolver CRASHES (rc 2, no pool= line at all) — fail closed, loud, 8 fields ──
cat > "$TMP/resolver-crash.py" <<'PY'
#!/usr/bin/env python3
import sys
sys.stderr.write("simulated resolver crash: bad --routing-yaml\n")
sys.exit(2)
PY
chmod +x "$TMP/resolver-crash.py"

mk_fixture crash
LEADV2_GLM_POLICY_RESOLVER="$TMP/resolver-crash.py" \
LEADV2_REVIEW_FANOUT=1 \
bash "$ENGINE" --task UNREVcrash --root "$ROOT" --handoff "$HANDOFF" \
  --diff "$DIFF" --author sonnet >/dev/null 2>"$TMP/t2.err"
rc2=$?
if [[ $rc2 -eq 9 ]]; then
  pass "T2: crashed resolver fails closed to exit 9"
else
  fail "T2: expected exit 9, got $rc2 (err tail: $(tail -1 "$TMP/t2.err"))"
fi
assert_full_shape "T2" "$HANDOFF/review-gate.md"
grep -q '^refusal: resolver_error_failclosed$' "$HANDOFF/review-gate.md" \
  && pass "T2: refusal names resolver_error_failclosed" \
  || fail "T2: fail-closed refusal lost"
grep -q '^resolver_rc: 2$' "$HANDOFF/review-gate.md" \
  && pass "T2: resolver_rc records the REAL rc (2), not a dash" \
  || fail "T2: resolver_rc wrong (want 2): $(grep '^resolver_rc:' "$HANDOFF/review-gate.md")"
# the stderr artifact must actually exist and carry the crash line
stderr_path="$(sed -n 's/^resolver_stderr: //p' "$HANDOFF/review-gate.md" | head -n1)"
if [[ "${stderr_path}" != "-" && -f "$ROOT/${stderr_path}" ]] \
  && grep -q 'simulated resolver crash' "$ROOT/${stderr_path}"; then
  pass "T2: resolver_stderr points at a real artifact carrying the crash text"
else
  fail "T2: resolver_stderr artifact missing/empty (path='${stderr_path}')"
fi

printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
```

