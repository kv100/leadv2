#!/usr/bin/env bash
# tests/test-review-round-exhaustive.sh — REVIEW-ROUND1-EXHAUSTIVE-01.
#
# Round 1 of a review (no prior real verdict) must be an exhaustive multi-lens
# pass; round 2+ (a prior FAIL/PASS verdict exists for a diff that has since
# changed) must be verification-only, embedding the prior findings and asking
# the reviewer to verify each by execution. Mirrors the stub-resolver/stub-arm
# harness of test-review-engine-fanout-multiprovider.sh (zero network) and the
# red-first baseline pattern of test-review-gate-scope-evidence.sh:229-242.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0; FAIL=0
log()  { printf '%s\n' "$*"; }
pass() { log "PASS: $*"; PASS=$((PASS + 1)); }
fail() { log "FAIL: $*"; FAIL=$((FAIL + 1)); }

bash -n "${SCRIPT_DIR}/test-review-round-exhaustive.sh" 2>/dev/null || { echo "ERROR: self syntax check failed"; exit 1; }
bash -n "${SCRIPTS_ROOT}/leadv2-review-run.sh" 2>/dev/null || fail "bash -n leadv2-review-run.sh"
/bin/bash -n "${SCRIPTS_ROOT}/leadv2-review-run.sh" 2>/dev/null || fail "/bin/bash -n leadv2-review-run.sh (bash 3.2 syntax)"
if command -v shellcheck >/dev/null 2>&1; then
  # SC1091/SC2034 are pre-existing on this file (unrelated source-not-found
  # infos and vars set for callers) and predate this lane's change — excluded
  # so this suite gates only on issues this lane could have introduced.
  # SC2094 (REVIEW-ROUNDCAP-01 fix-round-1): the state-lock flock pattern mirrors
  # atomic_review_check_and_record (leadv2-dispatch-code.sh:2556) -- passing the
  # same lockfile path as both the fd-9 redirect target and lv2_lock_wait's
  # argument is the documented, safe use of that primitive, not an actual
  # read/write race.
  if shellcheck -x -e SC1091,SC2034,SC2094 "${SCRIPTS_ROOT}/leadv2-review-run.sh" >/dev/null 2>&1; then
    pass "shellcheck clean: leadv2-review-run.sh"
  else
    fail "shellcheck: leadv2-review-run.sh"
  fi
fi
if shellcheck -x "${SCRIPT_DIR}/test-review-round-exhaustive.sh" >/dev/null 2>&1; then
  pass "shellcheck clean: test-review-round-exhaustive.sh"
else
  fail "shellcheck: test-review-round-exhaustive.sh (or shellcheck unavailable)"
fi

STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rre-stubs.XXXXXX")"
trap 'rm -rf "${STUB_DIR}"' EXIT

cat > "${STUB_DIR}/resolver.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=sonnet")
print("pool=sonnet:ok:,opus:ok:")
print("refusal=")
PY
chmod +x "${STUB_DIR}/resolver.py"

# claude-subsession.sh stub: hack-detect role emits nothing; critic role
# writes a clean PASS verdict straight to stdout (review_out), so the engine
# never needs a real critic.full.md artifact to materialize a body from.
cat > "${STUB_DIR}/architect.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "${role}" == "hack-detect" ]] && exit 0
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "${STUB_DIR}/architect.sh"

cat > "${STUB_DIR}/dispatch.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${STUB_DIR}/dispatch.sh"

# architect-ctrl.sh: like architect.sh, but its verdict is controlled by
# ARCH_CTRL_VERDICT (FAIL|PASS, default PASS) so T10 can drive a real
# fail->fix->verify->re-review->fix sequence through the actual engine
# instead of hand-seeding review-gate.md.
cat > "${STUB_DIR}/architect-ctrl.sh" <<'SH'
#!/usr/bin/env bash
role=""
while [[ $# -gt 0 ]]; do case "$1" in --role) role="$2"; shift 2 ;; *) shift ;; esac; done
[[ "${role}" == "hack-detect" ]] && exit 0
if [[ "${ARCH_CTRL_VERDICT:-PASS}" == "FAIL" ]]; then
  printf 'REVIEW_VERDICT: FAIL\nREVIEW_FINDINGS: critical=0 high=1 medium=0 low=0\nFINDING: severity=High file=a.sh line=10 dimension=correctness desc=%s\n' "${ARCH_CTRL_DESC:-off by one in loop bound}"
else
  printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
fi
SH
chmod +x "${STUB_DIR}/architect-ctrl.sh"

# codex-task.sh stub: records its --focus argument to a fixed path so T6 can
# inspect it. Only reached if a case's pool ever includes codex (none do here,
# but the stub is wired for completeness / future fanout>1 cases).
CODEX_FOCUS_CAPTURE="${STUB_DIR}/codex-focus-capture.txt"
cat > "${STUB_DIR}/codex.sh" <<SH
#!/usr/bin/env bash
focus=""
while [[ \$# -gt 0 ]]; do case "\$1" in --focus) focus="\$2"; shift 2 ;; *) shift ;; esac; done
printf '%s' "\${focus}" > "${CODEX_FOCUS_CAPTURE}"
printf 'REVIEW_VERDICT: PASS\nREVIEW_FINDINGS: critical=0 high=0 medium=0 low=0\n'
SH
chmod +x "${STUB_DIR}/codex.sh"

# run_review <scripts_dir> <handoff> <diff_file> <task> [fanout] [extra pool]
# ROOT is a plain dir (not git-initialized) — matches the fanout-multiprovider
# fixture; the engine's git calls all degrade gracefully with `|| true`.
run_review() {
  local scripts_dir="$1" handoff="$2" diff_file="$3" task="$4"
  local fanout="${5:-1}"
  local root="${handoff%/docs/handoff/*}"
  mkdir -p "${root}/.claude/ref"
  LEADV2_GLM_POLICY_RESOLVER="${STUB_DIR}/resolver.py" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${STUB_DIR}/architect.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${STUB_DIR}/codex.sh" \
  LEADV2_DISPATCH_BIN="${STUB_DIR}/dispatch.sh" \
  LEADV2_REVIEW_FANOUT="${fanout}" \
  bash "${scripts_dir}/leadv2-review-run.sh" --task "${task}" --root "${root}" --handoff "${handoff}" --diff "${diff_file}" --author glm >/dev/null 2>&1
}

# run_review_ex <scripts_dir> <handoff> <diff_file> <task> <fanout> <stderr_file> [NAME=VAL ...]
# Like run_review, but captures stderr to <stderr_file> (emit() is stderr-only,
# design §2 step 10) and accepts extra env assignments (e.g.
# LEADV2_REVIEW_ROUND=2, ARCH_CTRL_VERDICT=FAIL) for the escape-hatch and
# real-verdict-sequence tests.
run_review_ex() {
  local scripts_dir="$1" handoff="$2" diff_file="$3" task="$4" fanout="$5" errfile="$6"
  shift 6
  local root="${handoff%/docs/handoff/*}"
  mkdir -p "${root}/.claude/ref"
  env "$@" \
  LEADV2_GLM_POLICY_RESOLVER="${STUB_DIR}/resolver.py" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${STUB_DIR}/architect-ctrl.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${STUB_DIR}/codex.sh" \
  LEADV2_DISPATCH_BIN="${STUB_DIR}/dispatch.sh" \
  LEADV2_REVIEW_FANOUT="${fanout}" \
  bash "${scripts_dir}/leadv2-review-run.sh" --task "${task}" --root "${root}" --handoff "${handoff}" --diff "${diff_file}" --author glm >/dev/null 2>"${errfile}"
}

new_handoff() { # <task> -> stdout=handoff dir path
  local task="$1"
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rre.XXXXXX")"
  local h="${d}/repo/docs/handoff/dispatch-${task}"
  mkdir -p "${h}"
  printf '%s' "${h}"
}

seed_prior_round() { # <handoff>
  local h="$1"
  printf 'arms: sonnet\nverified: 0/2\nstatus: fail\ncritical: 0\nhigh: 2\nmedium: 0\nlow: 0\nFINDING: severity=High file=a.sh line=10 dimension=correctness desc=off by one in loop bound\nFINDING: severity=High file=b.sh line=22 dimension=correctness desc=unchecked null deref on parse\n' > "${h}/review-gate.md"
  printf '{"task":"seed","arms":["sonnet"],"fanout":1,"findings":[{"dimension":"correctness","severity":"High","file":"a.sh","line":10,"arm":"sonnet","verifier_arm":"opus","verifier_verdict":"upheld","desc":"off by one in loop bound"},{"dimension":"correctness","severity":"High","file":"b.sh","line":22,"arm":"sonnet","verifier_arm":"opus","verifier_verdict":"upheld","desc":"unchecked null deref on parse"}]}' > "${h}/review-findings.json"
}

# ── T1: round-1 content ──────────────────────────────────────────────────────
case_t1_round1() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T1ROUND1)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+hello\n' > "${diff}"
  run_review "${scripts_dir}" "${h}" "${diff}" T1ROUND1 1
  local mf="${h}/review-mission-sonnet.md"
  [[ -f "${mf}" ]] || return 1
  grep -q 'EXHAUSTIVE ROUND 1' "${mf}" || return 1
  grep -q 'Census rule:' "${mf}" || return 1
  grep -q 'tests-can-fail (falsification)' "${mf}" || return 1
  grep -q 'product-invariant/contract' "${mf}" || return 1
  grep -q 'census' "${mf}" || return 1
  grep -q 'if you find one instance of a defect shape, enumerate ALL same-shape instances in the touched files before returning' "${mf}" || return 1
  grep -q 'Report EVERYTHING you find in this one pass. Never stop at the first 1-3 findings.' "${mf}" || return 1
  grep -q '^REVIEW_VERDICT: <FAIL|PASS|PASS_WITH_NITS>$' "${mf}" || return 1
  grep -q '^REVIEW_FINDINGS: critical=<n> high=<n> medium=<n> low=<n>$' "${mf}" || return 1
  return 0
}

# ── T2: round-2 verification-only ────────────────────────────────────────────
case_t2_round2() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T2ROUND2)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+first version\n' > "${diff}"
  seed_prior_round "${h}"
  printf 'round=1\ndiff=deadbeef00\n' > "${h}/.review-round.state"
  # diff content differs from the sidecar's recorded hash -> "changed" branch.
  printf 'diff --git a/x b/x\n+second version, fixed\n' > "${diff}"
  run_review "${scripts_dir}" "${h}" "${diff}" T2ROUND2 1
  local mf="${h}/review-mission-sonnet.md"
  [[ -f "${mf}" ]] || return 1
  grep -q 'VERIFICATION-ONLY ROUND 2' "${mf}" || return 1
  grep -q 'off by one in loop bound' "${mf}" || return 1
  grep -q 'unchecked null deref on parse' "${mf}" || return 1
  grep -q 'verify by execution whether each prior finding below is fixed' "${mf}" || return 1
  grep -q 'Admit a NEW finding ONLY if the fixes introduced it.' "${mf}" || return 1
  grep -q 'EXHAUSTIVE ROUND 1' "${mf}" && return 1
  grep -q '^REVIEW_VERDICT: <FAIL|PASS|PASS_WITH_NITS>$' "${mf}" || return 1
  return 0
}

# ── T3: stale-diff guard — sidecar hash matches current diff exactly (a
# re-review of the identical diff, no new fix) -> exhaustive AND the round is
# frozen at the prior round, not advanced. This is the one case the monotonic
# round in H1 must NOT bump: bumping here would mean simply re-running review
# against unchanged work grows the round forever (see T10, which exercises
# this same freeze mid-repro: round sequence 1,2,2,3 — the second "2" is this
# case).
case_t3_stale_diff() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T3STALE)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+unchanged content\n' > "${diff}"
  seed_prior_round "${h}"
  local hash8
  hash8="$(shasum -a 256 "${diff}" | awk '{print $1}' | cut -c1-8)"
  printf 'round=1\ndiff=%s\n' "${hash8}" > "${h}/.review-round.state"
  run_review "${scripts_dir}" "${h}" "${diff}" T3STALE 1
  local mf="${h}/review-mission-sonnet.md"
  [[ -f "${mf}" ]] || return 1
  grep -q 'EXHAUSTIVE ROUND 1' "${mf}" || return 1
  grep -q 'VERIFICATION-ONLY' "${mf}" && return 1
  return 0
}

# ── T4: no-sidecar / blocked-gate guard -> exhaustive ───────────────────────
case_t4_no_sidecar() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T4NOSIDE)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+content\n' > "${diff}"
  printf 'status: blocked\nreason: provider_error\n' > "${h}/review-gate.md"
  run_review "${scripts_dir}" "${h}" "${diff}" T4NOSIDE 1
  local mf="${h}/review-mission-sonnet.md"
  [[ -f "${mf}" ]] || return 1
  grep -q 'EXHAUSTIVE ROUND 1' "${mf}" || return 1
  grep -q 'VERIFICATION-ONLY' "${mf}" && return 1
  return 0
}

# ── T5: snapshot preservation across a round-2 run ──────────────────────────
case_t5_snapshot() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T5SNAP)"
  local diff="${h}/review.diff"
  seed_prior_round "${h}"
  printf 'round=1\ndiff=deadbeef00\n' > "${h}/.review-round.state"
  printf 'diff --git a/x b/x\n+fixed now\n' > "${diff}"
  run_review "${scripts_dir}" "${h}" "${diff}" T5SNAP 1
  local snap="${h}/review-gate.round1.md"
  [[ -f "${snap}" ]] || return 1
  grep -q 'off by one in loop bound' "${snap}" || return 1
  grep -q 'unchecked null deref on parse' "${snap}" || return 1
  grep -q '^status: fail$' "${snap}" || return 1
  return 0
}

# ── T6: codex focus flattening — single-line, carries the round marker ─────
case_t6_codex_flatten() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T6FLAT)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+content\n' > "${diff}"
  rm -f "${CODEX_FOCUS_CAPTURE}"
  cat > "${STUB_DIR}/resolver-codex.py" <<'PY'
#!/usr/bin/env python3
print("reviewer=codex")
print("pool=codex:ok:,sonnet:ok:")
print("refusal=")
PY
  chmod +x "${STUB_DIR}/resolver-codex.py"
  local root="${h%/docs/handoff/*}"
  mkdir -p "${root}/.claude/ref"
  local seed_sha=""
  ( cd "${root}" && git init -q -b main >/dev/null 2>&1 && git config user.email t@e.com && git config user.name t \
    && mkdir -p x && printf 'a\n' > x/f.txt && git add -A && git commit -qm seed >/dev/null 2>&1 \
    && printf 'b\n' > x/f.txt ) >/dev/null 2>&1
  seed_sha="$(git -C "${root}" rev-parse main 2>/dev/null)"
  LEADV2_GLM_POLICY_RESOLVER="${STUB_DIR}/resolver-codex.py" \
  LEADV2_DISPATCH_ARCHITECT_BIN="${STUB_DIR}/architect.sh" \
  LEADV2_DISPATCH_CODEX_BIN="${STUB_DIR}/codex.sh" \
  LEADV2_DISPATCH_BIN="${STUB_DIR}/dispatch.sh" \
  LEADV2_REVIEW_FANOUT=1 \
  LEADV2_LANE_START_SHA="${seed_sha}" \
  bash "${scripts_dir}/leadv2-review-run.sh" --task T6FLAT --root "${root}" --handoff "${h}" --diff "${diff}" --author glm >/dev/null 2>&1
  [[ -f "${CODEX_FOCUS_CAPTURE}" ]] || return 1
  local lines
  lines="$(wc -l < "${CODEX_FOCUS_CAPTURE}" | tr -d '[:space:]')"
  [[ "${lines}" -eq 0 ]] || return 1
  grep -q 'EXHAUSTIVE ROUND 1' "${CODEX_FOCUS_CAPTURE}" || return 1
  # `"`/backtick are forbidden only in the NEW round-mode text (R6/T6) — the
  # surrounding boilerplate ("Authoritative surfaces for this repo: `...`")
  # is pre-existing and untouched by this lane, and legitimately uses both.
  local round_text
  round_text="$(sed -nE 's/.*(EXHAUSTIVE ROUND 1.*FINDING: severity=<Critical\|High>[^ ]* file=<path> line=<n> dimension=<correctness\|security\|design\|perf> desc=<one line>).*/\1/p' "${CODEX_FOCUS_CAPTURE}")"
  [[ -n "${round_text}" ]] || return 1
  printf '%s' "${round_text}" | grep -q '"' && return 1
  printf '%s' "${round_text}" | grep -q '`' && return 1
  return 0
}

# ── T8: journal review_round line carries the REAL prior-findings count ────
# (H2: PRIOR_FINDINGS_COUNT used to be set inside a command-substitution
# subshell and never survived to the emit() call, so this line always showed
# prior_findings=0 regardless of how many prior findings actually existed.)
case_t8_journal_prior_findings() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T8JOURNAL)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+first version\n' > "${diff}"
  seed_prior_round "${h}"
  printf 'round=1\ndiff=deadbeef00\n' > "${h}/.review-round.state"
  printf 'diff --git a/x b/x\n+second version, fixed\n' > "${diff}"
  local errfile="${h}.err"
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T8JOURNAL 1 "${errfile}"
  grep -q 'review_round task=T8JOURNAL round=2 mode=verify_only prior_findings=2' "${errfile}" || return 1
  return 0
}

# ── T9: forced-mode hatch (LEADV2_REVIEW_ROUND) semantics post-fix ─────────
# T9a: =1 always forces exhaustive round 1.
case_t9a_forced_round1() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T9AFORCED)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+content\n' > "${diff}"
  local errfile="${h}.err"
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T9AFORCED 1 "${errfile}" LEADV2_REVIEW_ROUND=1
  local mf="${h}/review-mission-sonnet.md"
  [[ -f "${mf}" ]] || return 1
  grep -q 'EXHAUSTIVE ROUND 1' "${mf}" || return 1
  return 0
}

# T9b: =2 with no recorded prior findings (H3) -> exhaustive, NOT a
# verification-only page with an empty prior-findings list.
case_t9b_forced_round2_empty() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T9BFORCED)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+content\n' > "${diff}"
  local errfile="${h}.err"
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T9BFORCED 1 "${errfile}" LEADV2_REVIEW_ROUND=2
  local mf="${h}/review-mission-sonnet.md"
  [[ -f "${mf}" ]] || return 1
  grep -q 'EXHAUSTIVE ROUND 2' "${mf}" || return 1
  grep -q 'VERIFICATION-ONLY' "${mf}" && return 1
  return 0
}

# T9c: =2 with a real prior-findings body -> verify_only round 2.
case_t9c_forced_round2_body() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T9CFORCED)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+content\n' > "${diff}"
  seed_prior_round "${h}"
  printf 'round=1\ndiff=deadbeef00\n' > "${h}/.review-round.state"
  local errfile="${h}.err"
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T9CFORCED 1 "${errfile}" LEADV2_REVIEW_ROUND=2
  local mf="${h}/review-mission-sonnet.md"
  [[ -f "${mf}" ]] || return 1
  grep -q 'VERIFICATION-ONLY ROUND 2' "${mf}" || return 1
  grep -q 'off by one in loop bound' "${mf}" || return 1
  return 0
}

# ── T10: H1 regression repro — fail -> fix -> verify -> re-review the
# unchanged diff -> fix. Sidecar rounds must read 1, 2, 2, 3 (non-decreasing;
# the re-review-unchanged step freezes at the prior round instead of growing
# it), and the final round-3 mission must carry round-2's findings, not
# round-1's (proves prior findings are read from the HIGHEST snapshot, not a
# stale one).
case_t10_h1_repro() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T10REPRO)"
  local diff="${h}/review.diff"
  local state="${h}/.review-round.state"
  local mf="${h}/review-mission-sonnet.md"

  # REVIEW-ROUNDCAP-01: this repro needs 3 REAL rounds to exercise round
  # monotonicity/freeze, an orthogonal H1 concern predating the round cap.
  # LEADV2_REVIEW_MAX_ROUNDS=0 is the documented kill-switch (byte-identical
  # to pre-cap behavior) so the cap doesn't fire mid-repro.
  printf 'diff --git a/x b/x\n+v1 broken\n' > "${diff}"
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T10REPRO 1 "${h}/err1" \
    LEADV2_REVIEW_MAX_ROUNDS=0 ARCH_CTRL_VERDICT=FAIL ARCH_CTRL_DESC="round1 unique finding marker"
  [[ -f "${state}" ]] || return 1
  grep -q '^round=1$' "${state}" || return 1

  printf 'diff --git a/x b/x\n+v2 partially fixed\n' > "${diff}"
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T10REPRO 1 "${h}/err2" \
    LEADV2_REVIEW_MAX_ROUNDS=0 ARCH_CTRL_VERDICT=FAIL ARCH_CTRL_DESC="round2 unique finding marker"
  grep -q '^round=2$' "${state}" || return 1
  grep -q 'VERIFICATION-ONLY ROUND 2' "${mf}" || return 1

  # Re-review the exact same (unchanged) diff — round must NOT advance.
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T10REPRO 1 "${h}/err3" \
    LEADV2_REVIEW_MAX_ROUNDS=0 ARCH_CTRL_VERDICT=FAIL ARCH_CTRL_DESC="round2 unique finding marker"
  grep -q '^round=2$' "${state}" || return 1
  grep -q 'EXHAUSTIVE ROUND 2' "${mf}" || return 1

  printf 'diff --git a/x b/x\n+v3 fully fixed\n' > "${diff}"
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T10REPRO 1 "${h}/err4" LEADV2_REVIEW_MAX_ROUNDS=0 ARCH_CTRL_VERDICT=PASS
  grep -q '^round=3$' "${state}" || return 1
  grep -qE 'EXHAUSTIVE ROUND 3|VERIFICATION-ONLY ROUND 3' "${mf}" || return 1
  grep -q '^count=' "${mf}" && return 1
  if grep -q 'VERIFICATION-ONLY ROUND 3' "${mf}"; then
    grep -q 'round2 unique finding marker' "${mf}" || return 1
    grep -q 'round1 unique finding marker' "${mf}" && return 1
  fi
  return 0
}

# ── T11: 40-finding cap + 300-char per-line cap + real count sentinel ──────
case_t11_finding_cap() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T11CAP)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+content\n' > "${diff}"
  printf 'status: fail\ncritical: 0\nhigh: 45\nmedium: 0\nlow: 0\n' > "${h}/review-gate.round1.md"
  python3 - "${h}/review-findings.round1.json" <<'PY'
import json, sys
findings = []
long_desc = "x" * 400
for i in range(45):
    desc = long_desc if i == 0 else ("finding number %d" % i)
    findings.append({"dimension": "correctness", "severity": "High", "file": "a.sh", "line": i, "desc": desc})
json.dump({"task": "seed", "findings": findings}, open(sys.argv[1], "w"))
PY
  printf 'status: fail\ncritical: 0\nhigh: 45\nmedium: 0\nlow: 0\n' > "${h}/review-gate.md"
  printf 'round=1\ndiff=deadbeef00\n' > "${h}/.review-round.state"
  local errfile="${h}.err"
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T11CAP 1 "${errfile}"
  grep -q 'prior_findings=45' "${errfile}" || return 1
  local mf="${h}/review-mission-sonnet.md"
  [[ -f "${mf}" ]] || return 1
  grep -q '^count=' "${mf}" && return 1
  local body_lines
  body_lines="$(sed -n '/^Prior findings:$/,/^$/p' "${mf}" | grep -c '^- ')"
  [[ "${body_lines}" -eq 40 ]] || return 1
  grep -q '(… capped, see docs/handoff/dispatch-T11CAP/review-gate.round1.md)' "${mf}" || return 1
  local first_line
  first_line="$(sed -n '/^Prior findings:$/{n;p;}' "${mf}")"
  [[ "${#first_line}" -le 300 ]] || return 1
  return 0
}

# ── T12: missing/unreadable diff file -> exhaustive, no sidecar write, and
# the failure is now visible on stderr instead of silent (M1).
case_t12_missing_diff() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T12MISSING)"
  local diff="${h}/does-not-exist.diff"
  local errfile="${h}.err"
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T12MISSING 1 "${errfile}"
  local mf="${h}/review-mission-sonnet.md"
  [[ -f "${mf}" ]] || return 1
  grep -q 'EXHAUSTIVE ROUND 1' "${mf}" || return 1
  [[ -f "${h}/.review-round.state" ]] && return 1
  [[ -s "${errfile}" ]] || return 1
  grep -qi 'diff file missing' "${errfile}" || return 1
  return 0
}

# ── T13: corrupt sidecar round (non-numeric) degrades to "absent", not a
# `set -u` abort (M2).
case_t13_corrupt_round() { # <scripts_dir> -> rc0=pass
  local scripts_dir="$1"
  local h; h="$(new_handoff T13CORRUPT)"
  local diff="${h}/review.diff"
  printf 'diff --git a/x b/x\n+content\n' > "${diff}"
  printf 'status: fail\ncritical: 0\nhigh: 1\nmedium: 0\nlow: 0\n' > "${h}/review-gate.md"
  printf 'round=abc\ndiff=deadbeef00\n' > "${h}/.review-round.state"
  local errfile="${h}.err"
  run_review_ex "${scripts_dir}" "${h}" "${diff}" T13CORRUPT 1 "${errfile}"
  local rc=$?
  [[ "${rc}" -eq 0 ]] || return 1
  grep -qi 'unbound variable' "${errfile}" && return 1
  local mf="${h}/review-mission-sonnet.md"
  [[ -f "${mf}" ]] || return 1
  grep -q 'EXHAUSTIVE ROUND 1' "${mf}" || return 1
  return 0
}

# ── inline (non-baseline) assertions ────────────────────────────────────────
if case_t1_round1 "${SCRIPTS_ROOT}"; then pass "T1 round-1 content"; else fail "T1 round-1 content"; fi
if case_t2_round2 "${SCRIPTS_ROOT}"; then pass "T2 round-2 verification-only"; else fail "T2 round-2 verification-only"; fi
if case_t3_stale_diff "${SCRIPTS_ROOT}"; then pass "T3 stale-diff guard"; else fail "T3 stale-diff guard"; fi
if case_t4_no_sidecar "${SCRIPTS_ROOT}"; then pass "T4 no-sidecar/blocked-gate guard"; else fail "T4 no-sidecar/blocked-gate guard"; fi
if case_t5_snapshot "${SCRIPTS_ROOT}"; then pass "T5 snapshot preservation"; else fail "T5 snapshot preservation"; fi
if case_t6_codex_flatten "${SCRIPTS_ROOT}"; then pass "T6 codex focus flattening"; else fail "T6 codex focus flattening"; fi
if case_t8_journal_prior_findings "${SCRIPTS_ROOT}"; then pass "T8 journal prior_findings count"; else fail "T8 journal prior_findings count"; fi
if case_t9a_forced_round1 "${SCRIPTS_ROOT}"; then pass "T9a forced round=1 -> exhaustive"; else fail "T9a forced round=1 -> exhaustive"; fi
if case_t9b_forced_round2_empty "${SCRIPTS_ROOT}"; then pass "T9b forced round=2, empty body -> exhaustive"; else fail "T9b forced round=2, empty body -> exhaustive"; fi
if case_t9c_forced_round2_body "${SCRIPTS_ROOT}"; then pass "T9c forced round=2, body -> verify_only"; else fail "T9c forced round=2, body -> verify_only"; fi
if case_t10_h1_repro "${SCRIPTS_ROOT}"; then pass "T10 H1 repro: rounds 1,2,2,3"; else fail "T10 H1 repro: rounds 1,2,2,3"; fi
if case_t11_finding_cap "${SCRIPTS_ROOT}"; then pass "T11 40-line/300-char cap + real count"; else fail "T11 40-line/300-char cap + real count"; fi
if case_t12_missing_diff "${SCRIPTS_ROOT}"; then pass "T12 missing diff file -> exhaustive, no sidecar, stderr"; else fail "T12 missing diff file -> exhaustive, no sidecar, stderr"; fi
if case_t13_corrupt_round "${SCRIPTS_ROOT}"; then pass "T13 corrupt sidecar round -> exhaustive round 1"; else fail "T13 corrupt sidecar round -> exhaustive round 1"; fi

# ── T7: red-first baseline ───────────────────────────────────────────────────
# merge-base self-nullifies once the fix lands on origin/main; content-probe
# for _review_round_context in the extracted baseline tree and fall back to
# the pinned pre-fix floor if the probe finds the fix already present
# (same convention as test-review-gate-scope-evidence.sh:229-242 /
# run-core-offline.sh's 9e03dc0 floor).
PREFIX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-rre-baseline.XXXXXX")"
LEADV2_REPO="$(cd "${SCRIPT_DIR}" && git rev-parse --show-toplevel 2>/dev/null)"
LEADV2_TEST_BASELINE_REF="${LEADV2_TEST_BASELINE_REF:-}"
if [[ -z "${LEADV2_TEST_BASELINE_REF}" ]]; then
  LEADV2_TEST_BASELINE_REF="$(git -C "${LEADV2_REPO}" merge-base origin/main HEAD 2>/dev/null || true)"
  if [[ -n "${LEADV2_TEST_BASELINE_REF}" ]] && git -C "${LEADV2_REPO}" grep -q _review_round_context "${LEADV2_TEST_BASELINE_REF}" -- plugins/leadv2/scripts/leadv2-review-run.sh 2>/dev/null; then
    LEADV2_TEST_BASELINE_REF="85ae886"
  fi
fi
[[ -n "${LEADV2_TEST_BASELINE_REF}" ]] || LEADV2_TEST_BASELINE_REF="85ae886"
git -C "${LEADV2_REPO}" archive "${LEADV2_TEST_BASELINE_REF}" plugins/leadv2/scripts 2>/dev/null | tar -x -C "${PREFIX_DIR}" 2>/dev/null
PREFIX_SCRIPTS="${PREFIX_DIR}/plugins/leadv2/scripts"

if [[ ! -f "${PREFIX_SCRIPTS}/leadv2-review-run.sh" ]]; then
  fail "T7 red-first: git archive ${LEADV2_TEST_BASELINE_REF} extraction failed"
else
  if case_t1_round1 "${PREFIX_SCRIPTS}"; then
    fail "T7 red-first: T1 unexpectedly passed against baseline ${LEADV2_TEST_BASELINE_REF}"
  else
    pass "T7 red-first: T1 fails against baseline ${LEADV2_TEST_BASELINE_REF}"
  fi
  if case_t2_round2 "${PREFIX_SCRIPTS}"; then
    fail "T7 red-first: T2 unexpectedly passed against baseline ${LEADV2_TEST_BASELINE_REF}"
  else
    pass "T7 red-first: T2 fails against baseline ${LEADV2_TEST_BASELINE_REF}"
  fi
  for _t7case in case_t8_journal_prior_findings case_t9b_forced_round2_empty case_t10_h1_repro case_t11_finding_cap case_t12_missing_diff case_t13_corrupt_round; do
    if "${_t7case}" "${PREFIX_SCRIPTS}"; then
      fail "T7 red-first: ${_t7case} unexpectedly passed against baseline ${LEADV2_TEST_BASELINE_REF}"
    else
      pass "T7 red-first: ${_t7case} fails against baseline ${LEADV2_TEST_BASELINE_REF}"
    fi
  done
fi
rm -rf "${PREFIX_DIR}"

log ""
log "================================================"
log "  review-round-exhaustive: PASS=$PASS FAIL=$FAIL"
log "================================================"
[[ "$FAIL" -eq 0 ]]
