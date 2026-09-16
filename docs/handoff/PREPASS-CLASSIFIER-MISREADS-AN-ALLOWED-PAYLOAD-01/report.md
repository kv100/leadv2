# PREPASS-CLASSIFIER-MISREADS-AN-ALLOWED-PAYLOAD-01 — lane report

Lane `7b160d2ff551`, branch `worktree-7b160d2ff551`, code commit `734fccff`
(2026-09-16), macOS Darwin 25.6.0, worktree
`~/Projects/leadv2/.claude/worktrees/7b160d2ff551`. All measurements below are
from this tree at that commit unless a row names another tree (baseline =
pre-patch dispatcher from `HEAD^`, i.e. `2dfaffc3`).

## What was fixed — three defects, one live incident

Live evidence for all three at once — dispatch `598ff1eb` (getmany-followup-bot,
2026-09-15T12:11:53Z, `~/.claude/leadv2-state/getmany-followup-bot/tasks/dispatch-598ff1eb/journal.md:16`):

```
architect_prepass task=598ff1eb status=failed reason=rate_limited rc=1 arm=claude
  detail={"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1789489800,
  "rateLimitType":"five_hour","overageStatus":"allowed",...}}
architect_prepass_fallback task=598ff1eb arm=glm outcome=failed rc=124 reason=rate_limited
architect_prepass_fallback task=598ff1eb arm=glm-flash outcome=skipped reason=no_architect_launcher
architect_prepass_fallback task=598ff1eb arm=codex outcome=skipped reason=same_provider
architect_prepass_fallback task=598ff1eb arm=sonnet outcome=skipped reason=no_architect_launcher
architect_prepass_fallback task=598ff1eb arm=freepool outcome=skipped reason=no_architect_launcher
architect_prepass_fallback task=598ff1eb arm=haiku outcome=skipped reason=no_architect_launcher
architect_prepass_fallback task=598ff1eb arm=opus outcome=skipped reason=no_architect_launcher
architect_prepass_fallback task=598ff1eb arm=fable outcome=skipped reason=no_architect_launcher
```

A provider that answered "allowed" was journalled as `rate_limited`, and 7 of 8
ladder arms never reached a launcher.

## Claim 1 — defect 2, `:5724`: the admission parse was quote-blind

- Reproduction: `bash docs/handoff/PREPASS-CLASSIFIER-MISREADS-AN-ALLOWED-PAYLOAD-01/probe.sh`
  (red on the pre-patch tree, measured from this lane before any fix-shaped read):
  ```
  json "status":"allowed"            -> expect allowed        got unknown
  json "status":"quota_refused"      -> expect quota_refused  got unknown
  bare status=allowed (control)      -> expect allowed        got allowed
  pass=1 fail=2
  probe rc=1
  ```
- Cause class: `real_regression` in the subject (both branches of
  `_architect_prepass_admission_status` fell through to `unknown` on JSON).
- Mechanism: `grep -qiE 'status[=:][[:space:]]*allowed'` — after the colon the
  JSON has `"`, which matches neither `[[:space:]]*` nor `a`.
- Fix (now `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, admission
  function): both branches tolerate the quote on both sides of the separator
  and anchor `status` against camelCase relatives:
  `'(^|[^[:alnum:]_])status["]?[[:space:]]*[=:][[:space:]]*["]?[[:space:]]*allowed'`
  (same shape for the `quota_refused|rate_limited|quota_exceeded` branch). The
  anchor is what keeps `"overageStatus":"allowed"` from satisfying admission
  (suite case A4).
- Probe after: `pass=3 fail=0`, rc=0 (all three lines `got` = `expect`).

## Claim 2 — defect 1, `:5672`: the rate-limit regex matched the event's own name

- Cause class: `real_regression` — informational telemetry was classified as a
  rate-limit refusal.
- Mechanism: `_ARCH_FAIL_RATE_RE='rate[ _-]?limit|…'` runs over the raw
  response text; `rate_limit_event` / `rate_limit_info` / `rateLimitType`
  contain the substring.
- Fix: prose-shaped pattern mirroring the in-repo quota classifier
  (`_QUOTA_SHAPED_RE`, `lib/leadv2-lockout-classify.py:43-46`, whose
  provenance is the live 429 incident):
  `'rate[ _-]limit(ed)?([^_[:alnum:]]|$)|rate_limit_error|HTTP 429|too many requests|overloaded_error'`
  — a real separator AND a non-identifier boundary; `rate_limit_error` kept as
  an explicit alternative because it is Anthropic's REFUSAL event type,
  distinct from the telemetry names (and `overloaded_error` was already an
  explicit identifier alternative).
- Both halves, measured (source-only seam, `_architect_failure_class` called
  directly), from this tree:
  ```
  {"type":"rate_limit_event","rate_limit_info":{"status":   -> failed_rc_1
  Error: rate limit exceeded, retry after 60s                -> rate_limited
  {"type":"error","error":{"type":"rate_limit_error","mess   -> rate_limited
  You are rate-limited, slow down                            -> rate_limited
  HTTP 429: too many requests                                -> rate_limited
  quota exceeded for this org                                -> quota_exceeded
  ```

## Claim 3 — defect 3, `:6036-6038`: the fallback ladder gate was a hardcoded name list

- Cause class: `real_regression` (a hand-kept list deciding arms, contrary to
  the standing rule that routing config decides).
- Mechanism: `case "${arm}" in codex|glm) : ;; *) …no_architect_launcher` —
  no tenant yaml could arm another launcher; at 598ff1eb seven arms were
  insta-skipped.
- Fix: launcher eligibility now comes from the ladder entry itself — a new
  `architect_launcher: codex|glm` field on `router.dispatch_ladder` entries,
  parsed by `_load_dispatch_ladder` into `_LADDER_ARCH_LAUNCHER` (invalid
  values coerce to empty), with built-in defaults for codex/glm so existing
  behavior is unchanged. `_architect_fallback_design` gates on the resolved
  style and launches by style (`case "${_afb_style}"`), so a tenant yaml arm
  with a declared style runs through the corresponding launcher in the same
  disposable-worktree isolation. Measured (fixture routing yaml through the
  REAL loader and REAL fallback walk, suite part C):
  ```
  arm=glm       provider=zai       launcher=[]
  arm=tssarm    provider=tssprov   launcher=[codex]
  arm=badstyle  provider=p3        launcher=[]      # invalid style -> none
  arm=barearm   provider=p4        launcher=[]
  ```

## Controls — one per claim (lane rules), plus the gate-tool artifacts

Suite: `plugins/leadv2/scripts/tests/test-prepass-admission-truth-01.sh`
(registered via `# run-all-triggers: leadv2-dispatch-code`; mutation hook
`LEADV2_PREPASS_TRUTH_SCRIPTS_DIR`). 19 cases: A1-A5 admission, B1-B7
classifier, C0-C6 fallback gate.

1. Baseline (pre-patch dispatcher from `HEAD^` in a full copied tree):
   `pass=10 fail=9` — reds exactly A1, A2, A5, B1, B7, C0, C1, C3, C4; the
   instrument controls (A3, A4, B2-B6, C2, C5, C6) pass on the old code too,
   so the suite has grip, not just appetite.
2. Live tree: `pass=19 fail=0`, wall time 1.97s (0.68s user), 19 of 19 at the
   120s ceiling.
3. Mutation m1 (rate RE reverted to the old pattern, in a copied tree):
   ```
   [TEST] FAIL: class B1 telemetry-name payload is NOT a rate limit: want failed_rc_1 got rate_limited
   [TEST] FAIL: class B7 camelCase rateLimitType is not a rate limit: want failed_rc_1 got rate_limited
   pass=17 fail=2
   ```
4. Mutation m2 (both admission greps reverted to quote-blind):
   ```
   [TEST] FAIL: admission A1 json status allowed: want allowed got unknown
   [TEST] FAIL: admission A2 json status quota_refused: want quota_refused got unknown
   [TEST] FAIL: admission A5 json status rate_limited: want quota_refused got unknown
   pass=16 fail=3
   ```
5. Mutation m3 (config read killed inside `_architect_fallback_design`:
   `_afb_style="${_LADDER_ARCH_LAUNCHER[${i}]:-}"` → `_afb_style=""`):
   ```
   [TEST] FAIL: C0 fallback run rc=1
   [TEST] FAIL: C1 arm=tssarm was not used (gate still a name list?)
   [TEST] FAIL: C3 design.md empty or missing
   [TEST] FAIL: C4 provider args missing --wait/--cwd or cwd is the fixture repo
   pass=15 fail=4
   ```
   Each mutation flips only its own claim's cases; reverting (the committed
   tree) is the `pass=19 fail=0` in item 2.
6. Gate-tool artifacts (WORKER mode, scratch copy, never the lane):
   `mutation-control/20260916T141016Z-13952.txt` (m1),
   `mutation-control/20260916T141029Z-24468.txt` (m2),
   `mutation-control/20260916T141042Z-27432.txt` (m3) — each
   `baseline_rc=0` → `mutated_rc=1`, `lane_diff_hash=792f071e…`. One honesty
   note: the m3 artifact's `red_line` field shows a PASS line — the tool's
   red-line picker grabbed the wrong line while `baseline_rc=0 mutated_rc=1`
   (the operative fields) are correct; the hand-run in item 5 shows m3's real
   red cases.

## The `arm=codex … reason=same_provider` thread — RESOLVED, mechanism established

The line is real and recurring (e.g. 598ff1eb at 12:18:54Z; also 97c86b41 on
2026-09-16, `d66a2033`, `140b745c`). The mechanism, measured end to end:

1. The prepass ALWAYS launches through the Claude subsession launcher
   (`ARCHITECT_BIN="${LEADV2_DISPATCH_ARCHITECT_BIN:-${SUBSESSION_BIN}}"`,
   dispatcher `:6572`), and the journal even says so (`arm=claude`, `:6436`).
2. But the FAILED PROVIDER is derived from the model STRING:
   `_pp_failed_prov="$(_architect_prepass_provider "${architect_model}")"`
   (`:6442`), where
   `architect_model="${LEADV2_DISPATCH_ARCHITECT_MODEL:-${LEADV2_THINK_MODEL:-fable}}"`
   (`:6206`). `_architect_prepass_provider` maps claude-family to "anthropic"
   and everything else through `_arm_provider`, and `_arm_provider` resolves
   `astra`/`sol`/`codex` arms to the shared "codex" bucket
   (`router_v2.capability_matrix`: `- { arm: astra, provider: codex }`,
   `- { arm: sol, provider: codex }`).
3. At 598ff1eb the lead session's think model WAS a codex-bucket name: the
   architect stream's own first lines carry
   `[claude-code:unrecognized_model] {"model":"codex","query_source":"sdk"}`
   (`docs/handoff/dispatch-598ff1eb-architect/architect.stream.jsonl:55` in the
   getmany-followup-bot repo) — a model string claude-code could not even
   recognize, inside a Claude session (session_id d561063c…, Anthropic-shaped
   `rate_limit_event` telemetry).
4. So `_pp_failed_prov` resolved to "codex" for a launch that ran on Claude
   infrastructure, and the genuinely-different codex arm was skipped as
   `same_provider` (`:6032-6034`) — while `glm`, whose provider is "glm", WAS
   tried. The skip is a MISCLASSIFICATION: the provider that failed was
   anthropic.

Not fixed here (report-only per the mission): the honest fix is to derive the
failed provider from the arm/launcher that actually ran (the prepass launch
arm), not from the model string — `_architect_prepass_provider(architect_model)`
conflates "model requested" with "provider that failed". This is Bundle
Defect 3 territory (`09714c4fc3a7`); a bundle lane must reconcile against this
finding. Related adjacent lie, also not fixed: `:6436` hardcodes `arm=claude`
in the journal line regardless of `architect_model`.

## Account-switch reporting (NOT fixed here, per mission)

Verified by grep in this tree: `_architect_fallback_design` contains ZERO
references to `profile-select`, `account-switch`, `profile-pick` or
`CLAUDE_CONFIG_DIR` (0 hits in the function body). File-wide there are exactly
two hits, both outside the fallback: `:5834` `config_dir="${CLAUDE_CONFIG_DIR:-…}"`
inside `_architect_selected_credential_exhausted()` — a read-side credential
window check, not a switch — and `:8865` a comment about
`leadv2-claude-profile-select.sh` in the worker-spawn land. So a Claude limit
triggers a cross-PROVIDER fallback only, never an account swap. Owned by the
account-selection rows.

## Falsification set (finish contract)

```
$ bash -n plugins/leadv2/scripts/leadv2-dispatch-code.sh   # name split in the
  bash -n dispatcher OK                                     # invoking command
$ bash -n plugins/leadv2/scripts/tests/test-prepass-admission-truth-01.sh
  bash -n suite OK
$ python3 -m py_compile …   # no Python files changed — nothing to compile
$ bash docs/handoff/PREPASS-CLASSIFIER-MISREADS-AN-ALLOWED-PAYLOAD-01/probe.sh
  pass=3 fail=0 (red pre-patch output in Claim 1)
```

Changed-scope runner (`tests/run-all.sh --scope changed`, from this worktree,
after the suite was committed so discovery admits it):

```
$ timeout 850 bash tests/run-all.sh --scope changed
...
[SUITE-TIMEOUT] plugins/leadv2/scripts/tests/run-core-offline.sh exceeded 600s ceiling
  (killed by run-all; counted as a blocking failure with a named cause)
[FAIL] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] .../tests/test-status-surface-bash32.sh
  <killed here by the outer 850s wrapper, rc=124 — never reached a final tally>
```

Does not measure a regression: `run-core-offline.sh` alone burns its own 600s
ceiling before run-all's next suite even starts, so no single-invocation
budget covers a `--scope changed` pass once core-offline is in the selection
(pre-existing runtime property, `run-all-changed-scope-runtime` in prior-lane
notes — core-offline is always-on in run-all and its own e2e budget already
exceeds what one changed-scope invocation can afford). This lane's two
targeted suites are the real signal instead, both green in this tree:
`test-prepass-admission-truth-01.sh` 19/19 PASS rc=0, and
`docs/handoff/.../probe.sh` pass=3 fail=0 rc=0 (both shown above/below).

## Adjacent suites

| Suite | Result | Boundary |
|---|---|---|
| `test-dispatch-prepass-provider-fallback.sh` | 18/18 PASS, rc=0 | this tree, ~90s |
| `test-prepass-outcome-is-named.sh` | PASS, rc=0 | this tree |
| `test-prepass-timeout-on-exhausted-credential-falls-back.sh` | rc=1 — PRE-EXISTING | identical failure on pre-patch baseline (`[FAIL] positive exhausted-credential case rc=1`, prepass times out rc=124) |
| `test-arm-ladder-vocabulary-drift.sh` | rc=1 — PRE-EXISTING | identical `PASS=6 FAIL=2` on a FULL pre-patch tree (case2/case5: canonical yaml ladder has `haiku`/`opus`/`fable` absent from `DISPATCHABLE_BUILD_ARMS`). Note: an earlier scripts-only baseline "passed" it vacuously (no `../config` in the copy → empty yaml list → enumeration over zero items); the full-tree baseline run is the honest one. Cause is config/resolver drift, outside this lane's write set. |

## Left red and why

- `test-prepass-timeout-on-exhausted-credential-falls-back.sh` — pre-existing
  (verified identical on pre-patch tree); not in this lane's write set.
- `test-arm-ladder-vocabulary-drift.sh` — pre-existing (verified identical on
  a full pre-patch tree); cause is the canonical routing yaml's ladder arms
  vs `DISPATCHABLE_BUILD_ARMS` in `lib/leadv2-glm-policy-resolve.py`; neither
  file is in this lane's write set.
- The `same_provider` misclassification and the hardcoded `arm=claude` journal
  field — established, reported above, deliberately not fixed (bundle row
  `09714c4fc3a7` owns the fix; mission says report).
- The `no account swap in fallback` gap — owned by the account-selection rows.
