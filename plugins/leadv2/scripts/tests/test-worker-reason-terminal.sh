#!/usr/bin/env bash
# tests/test-worker-reason-terminal.sh — LANE-OBSERVABILITY-02 change 1.
#
# A no_work/dead terminal verdict is exactly the moment the founder most
# needs the worker's own last words ("census falsified by probe X", "codex
# refused: budget exhausted") — and exactly the moment every prior terminal
# line discarded them. This suite locks the three layers of change 1:
#
# A  LIB UNIT (lib/leadv2-worker-reason.sh, sourced):
#   A1  claude stream: last {"type":"result"} -> .result wins over older
#       assistant text; A2 assistant-text fallback when no result line.
#   A3  120-char clamp; A4 quote/backslash/newline sanitisation.
#   A5  codex rollout: newest cwd-filtered rollout's last task_complete
#       .last_agent_message; a sibling rollout with a DIFFERENT cwd must
#       never win.
#   A6  glm .out last non-blank line; A7 empty sources -> empty + rc 0;
#   A8  LEADV2_WORKER_REASON=0 kill switch.
# B  LEDGER UNIT (real leadv2-dispatch-ledger.sh):
#   B1  10th positional worker_reason -> JSON row carries the key, journal
#       decision line gains ` worker_reason="..."`;
#   B2  empty worker_reason -> JSON row STILL carries the (empty) key,
#       journal line gains NO worker_reason token (existing parsers
#       grep the bare shape and must keep working);
#   B3  `cause` readback returns the terminal cause.
# C  PRODUCT-CLOSE E2E (leadv2-dispatch-product-close.sh):
#   C1  forced no_work with a claude stream fixture -> terminal journal
#       line carries worker_reason="..." AND review-gate.md gains a
#       `worker_reason:` line;
#   C2  no stream source at all -> terminal journal line has NO
#       worker_reason token (empty degrades silently, never a bare
#       `worker_reason=""`).
#
# Hermetic: scratch repos, stubbed codex/journal/ledger bins, fixture
# CODEX_HOME, no network, no real dispatch.
# Run: bash scripts/tests/test-worker-reason-terminal.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
source "${SCRIPT_DIR}/leadv2-temp.sh"

source "${SCRIPT_DIR}/lib/leadv2-worker-reason.sh"
PC="${SCRIPT_DIR}/leadv2-dispatch-product-close.sh"
LEDGER="${SCRIPT_DIR}/leadv2-dispatch-ledger.sh"

export LEADV2_BURN_GOVERNOR=0

PASS=0; FAIL=0
ok()  { printf '[TEST] PASS: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '[TEST] FAIL: %s\n' "$1"; FAIL=$((FAIL+1)); }
assert_eq() { if [[ "$1" == "$2" ]]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

# ── shared fixtures ────────────────────────────────────────────────────────

claude_stream() {  # <handoff> <result_text|-> [assistant_text]
  mkdir -p "$1"
  {
    [[ -n "${3:-}" ]] && printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$3"
    [[ "$2" != "-" ]] && printf '{"type":"result","result":"%s"}\n' "$2"
    :  # always terminate with newline above
  } > "$1/developer.stream.jsonl"
}

wr() { lv2_worker_reason "$@"; }

TMP="$(lv2_mktemp_dir worker-reason)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ── A: lib unit ────────────────────────────────────────────────────────────

h1="$TMP/h-claude"; claude_stream "$h1" "DELIVERABLE_BLOCKED: census falsified by probe P42" "mid-flight thought"
r="$(wr "$h1" sonnet abcd0001)"
assert_eq "$r" "DELIVERABLE_BLOCKED: census falsified by probe P42" "A1: last result line wins over older assistant text"

h2="$TMP/h-assistant"; claude_stream "$h2" - "assistant fallback text"
r="$(wr "$h2" claude abcd0002)"
assert_eq "$r" "assistant fallback text" "A2: assistant-text fallback when no result line"

long="$(printf 'L%.0s' $(seq 1 300))"
h3="$TMP/h-clamp"; claude_stream "$h3" "$long" ""
r="$(wr "$h3" sonnet abcd0003)"
assert_eq "${#r}" "120" "A3: 120-char clamp"

messy='He said "no" and fell\n\path C:\\x\\y'
python3 -c 'import json,sys; print(json.dumps({"type":"result","result":sys.argv[1]}))' "$messy" > "$TMP/h-messy.tmp"
h4="$TMP/h-messy"; mkdir -p "$h4"; mv "$TMP/h-messy.tmp" "$h4/developer.stream.jsonl"
r="$(wr "$h4" sonnet abcd0004)"
if printf '%s' "$r" | grep -q '"'; then bad "A4: double quote survived sanitisation: $r"
elif printf '%s' "$r" | grep -q '\\'; then bad "A4: backslash survived sanitisation: $r"
elif [[ "$r" == *$'\n'* ]]; then bad "A4: newline survived sanitisation: $r"
else ok "A4: quote/backslash/newline sanitised (got: $r)"; fi

# A5 codex: two rollouts — the sibling (newer mtime, WRONG cwd) must lose.
rootA="$TMP/repo-a"; mkdir -p "$rootA"
codexhome="$TMP/codex-home"
mk_rollout() {  # <path> <cwd> <message>
  mkdir -p "$(dirname "$1")"
  printf '{"type":"session_meta","payload":{"cwd":"%s"}}\n' "$2" > "$1"
  printf '{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"%s"}}\n' "$3" >> "$1"
  sleep 0.05  # guarantee distinct mtimes, sibling written LAST (newest)
}
mk_rollout "$codexhome/sessions/2026/08/25/rollout-own.jsonl" "$rootA" "CODEX STOP: refusal enum exhausted"
mk_rollout "$codexhome/sessions/2026/08/25/rollout-sibling.jsonl" "$TMP/repo-sibling" "SIBLING MUST NOT WIN"
r="$(LEADV2_WORKER_REASON_CODEX_HOME="$codexhome" LEADV2_LANE_WORK_ROOT="$rootA" \
      wr "$TMP/h-empty-handoff" codex abcd0005)"
assert_eq "$r" "CODEX STOP: refusal enum exhausted" "A5: codex rollout cwd filter — sibling rollout never wins"

h6="$TMP/h-glm"; mkdir -p "$h6"; printf 'noise\n\nlast glm line\n\n' > "$h6/developer.glm.out"
r="$(wr "$h6" glm abcd0006)"
assert_eq "$r" "last glm line" "A6: glm .out last non-blank line"

h7="$TMP/h-nothing"; mkdir -p "$h7"
r="$(wr "$h7" sonnet abcd0007)"; rc=$?
assert_eq "$r" "" "A7: empty sources -> empty string"
assert_eq "$rc" "0" "A7: empty sources -> rc 0"

r="$(LEADV2_WORKER_REASON=0 wr "$h1" sonnet abcd0008)"
assert_eq "$r" "" "A8: LEADV2_WORKER_REASON=0 kill switch"

# ── B: ledger unit (real ledger, sandboxed) ────────────────────────────────

led_dir="$TMP/ledger"; mkdir -p "$led_dir"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/journal.log"\n' "$led_dir" > "$led_dir/journal.sh"
chmod +x "$led_dir/journal.sh"
ledger_env() {
  env LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$led_dir/rows.jsonl" \
      LEADV2_JOURNAL_BIN="$led_dir/journal.sh" \
      LEADV2_PROJECT_ROOT="$TMP" \
      bash "$LEDGER" "$@"
}

ledger_env write-terminal wrsig001 "founder-wr" dead no_reason_found "stream absent" 1 "disp" "" "" "worker said BOOM and stopped"
row="$(tail -n 1 "$led_dir/rows.jsonl" 2>/dev/null)"
if [[ "$(printf '%s' "$row" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("worker_reason","<MISSING>"))')" == "worker said BOOM and stopped" ]]; then
  ok "B1a: JSON row carries worker_reason"
else bad "B1a: JSON row worker_reason wrong: $row"; fi
if grep -q 'dispatch_terminal task=.* worker_reason="worker said BOOM and stopped"' "$led_dir/journal.log"; then
  ok "B1b: journal line gains worker_reason token"
else bad "B1b: journal line missing worker_reason: $(tail -n 1 "$led_dir/journal.log")"; fi

ledger_env write-terminal wrsig002 "founder-wr" no_work empty_diff "no diff" 1 "disp" "" "" ""
row="$(tail -n 1 "$led_dir/rows.jsonl")"
if [[ "$(printf '%s' "$row" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print("PRESENT" if "worker_reason" in d else "MISSING")')" == "PRESENT" ]]; then
  ok "B2a: empty worker_reason still an always-present JSON key"
else bad "B2a: JSON row lost worker_reason key: $row"; fi
if tail -n 1 "$led_dir/journal.log" | grep -q 'worker_reason'; then
  bad "B2b: empty worker_reason must NOT appear in the journal line"
else ok "B2b: journal line has no worker_reason token when empty"; fi

r="$(ledger_env cause wrsig001)"
assert_eq "$r" "no_reason_found" "B3: cause readback"

# ── C: product-close e2e (forced no_work, case-1 shape from
#      test-no-work-terminal.sh) ────────────────────────────────────────────

make_stubs() {  # <dir>
  cat > "${1}/resolver.py" <<'PY'
print("reviewer=codex"); print("pool=codex"); print("refusal=")
PY
  cat > "${1}/codex.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p "$2"; printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n' > "$1"
SH
  chmod +x "${1}/codex.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/journal.log"\n' "${1}" > "${1}/journal.sh"
  chmod +x "${1}/journal.sh"
}

new_repo() {
  mkdir -p "${1}/agent"
  ( cd "${1}" && git init -q -b main && git config user.email t@e.com && git config user.name t \
    && printf 'seed\n' > agent/seed.py && git add agent/seed.py && git commit -qm seed ) >/dev/null 2>&1
}

pc_no_work() {  # <sandbox>
  local d="$1" root="${1}/repo"
  mkdir -p "$root"; new_repo "$root"; make_stubs "$d"
  CLAUDE_PROJECT_ROOT="$root" LEADV2_DISPATCH_CACHE_DIR="$d/cache" \
    LEADV2_LANE_WORK_ROOT="$root" \
    LEADV2_DISPATCH_LANE_WRITES="agent/seed.py" \
    LEADV2_JOURNAL_BIN="$d/journal.sh" \
    LEADV2_DISPATCH_TERMINAL_LEDGER_FILE="$d/terminal-ledger.jsonl" \
    LEADV2_GLM_POLICY_RESOLVER="$d/resolver.py" LEADV2_DISPATCH_CODEX_BIN="$d/codex.sh" \
    bash "$PC" "$root" nw1sig001 sonnet "" 1 1 "founder-wr" >/dev/null 2>&1
  return $?
}

d1="$TMP/pc-with-stream"; pc_no_work "$d1" || true
handoff1="$TMP/pc-with-stream/repo/docs/handoff/dispatch-nw1sig001"
claude_stream "$handoff1" "CENSUS FALSIFIED: probe P42 disproved assumption 3" ""
pc_no_work "$d1" || true
if grep -q 'terminal=no_work.*worker_reason="CENSUS FALSIFIED: probe P42 disproved assumption 3"' "$d1/journal.log"; then
  ok "C1a: no_work terminal journal line carries worker_reason"
else bad "C1a: journal line missing worker_reason: $(grep dispatch_terminal "$d1/journal.log" | tail -1)"; fi
if [[ -f "$handoff1/review-gate.md" ]] && grep -q '^worker_reason: CENSUS FALSIFIED' "$handoff1/review-gate.md"; then
  ok "C1b: review-gate.md gains worker_reason line"
else bad "C1b: review-gate.md worker_reason line missing: $(cat "$handoff1/review-gate.md" 2>/dev/null | head -5)"; fi

d2="$TMP/pc-no-stream"; pc_no_work "$d2" || true
if grep 'dispatch_terminal task=' "$d2/journal.log" | tail -1 | grep -q 'worker_reason'; then
  bad "C2: empty source must omit worker_reason from the journal line entirely"
else ok "C2: no stream source -> no worker_reason token"; fi

# ── summary ────────────────────────────────────────────────────────────────
printf '\n[worker-reason-terminal] PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
