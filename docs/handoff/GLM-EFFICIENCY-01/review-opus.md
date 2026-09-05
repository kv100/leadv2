LABEL=critic-dispatch-GLM-EFFICIENCY-01-review-1788309577 SESSION_ID=14d964a4-2e11-46a4-8800-e347a29c4cca
--- body from: docs/handoff/dispatch-GLM-EFFICIENCY-01-review/critic.full.md ---
# critic.full.md — GLM-EFFICIENCY-01, round 1 (exhaustive)

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=3 low=4

FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-code.sh line=5070 dimension=correctness desc=_glm_effort_for_class fallback can emit an effort outside glm-coder.sh's low|medium|high|max whitelist (e.g. routing's `standard`), so --effort is silently omitted while line 5134 journals effort_applied mechanism=flag — the exact falsehood EFFORT-IS-NOT-WIRED-01 exists to prevent

Reviewer: independent of author (glm). Scope: `docs/handoff/GLM-EFFICIENCY-01/build-attempt-1.diff` (784 lines, 7 files) plus the live tree in this worktree. No files modified.

---

## H1 — fallback effort can be out-of-vocabulary while the journal claims it applied

`plugins/leadv2/scripts/leadv2-dispatch-code.sh:5065-5072`

```bash
_glm_effort_for_class() { # <raw task class>
  case "${1:-standard}" in
    trivial|light|bulk) printf '%s' 'low' ;;
    standard)           printf '%s' 'high' ;;
    heavy|strategic)    printf '%s' 'max' ;;
    *)                  printf '%s' "${RESOLVED_EFFORT:-high}" ;;   # <-- 5070
  esac
}
```

The consumer side (`glm-coder.sh:389`, `:1213`) is a strict whitelist, fail-open:

```bash
case "${GLM_EFFORT:-}" in
  low|medium|high|max) spawn_args+=(--effort "${GLM_EFFORT}") ;;
esac
```

Three facts make the `*)` branch a live hazard, not dead code:

1. **`RESOLVED_EFFORT` is not confined to that whitelist.** `plugins/leadv2/config/leadv2-routing.yaml` carries `effort: standard` on the dispatch-ladder entries at lines 237, 251, 262, 268, 273, 305, 317 — `standard` is a first-class effort value in this system's own config, and it is not in `low|medium|high|max`.
2. **`--task-class` is unvalidated.** `leadv2-dispatch-code.sh:6558` checks arity only (`[[ $# -ge 2 ]]`), then `task_class="$2"`. Nothing constrains the value to the six documented classes, so a caller typo (`--task-class Standard`, `--task-class docs`) or a future class lands in `*)`.
3. **The emit is unconditional.** `leadv2-dispatch-code.sh:5134` journals `effort_applied … mechanism=flag effort=${_glm_effort}` regardless of whether glm-coder subsequently accepts the value.

Result on that path: `--effort` is dropped, the provider runs at its default `max`, and the journal asserts `effort_applied … mechanism=flag effort=standard`. That is precisely the state EFFORT-IS-NOT-WIRED-01 introduced `effort_dropped` to make visible — a silently-ignored effort recorded as applied. It also fails the ticket's own cost premise in the worst direction (unexpected `max`, not `low`).

Fix is one line: route the fallback through the same whitelist, e.g.
```bash
*) case "${RESOLVED_EFFORT:-}" in low|medium|high|max) printf '%s' "${RESOLVED_EFFORT}" ;; *) printf '%s' 'high' ;; esac ;;
```
Belt-and-braces: make the `effort_applied` emit conditional on the value being in-vocabulary, and emit `effort_dropped reason=effort_out_of_vocabulary` otherwise. The invariant worth defending is *the journal never claims an effort the launcher will drop*.

## M1 — self-contradicting cost documentation shipped inside the same diff (census: 2 instances)

The diff changes `leadv2-routing.yaml` glm-flash to `cost: 0.33`, then ships two artifacts that describe `0.4` as the current matrix value:

- `plugins/leadv2/config/model-capability.yaml:204` — "the routing matrix's cost 0.4 (legacy-plan figure) is …" (present tense, describes the pre-diff state).
- `plugins/leadv2/docs/model-effort-matrix.md:87` — "the matrix's `cost: 0.4` …".

`model-effort-matrix.md:111` gets it right in the same file ("the pre-lane 0.4 was a legacy-plan figure"), so the document contradicts itself. Census performed across both touched doc/config files; these are the only two instances. Mechanically harmless, but this is the reference pair a future audit reads before touching the cost figure — the same class of stale-reference error the ticket's own report says GLM-EFFICIENCY-AUDIT-01 committed.

## M2 — negative-control mutant is written into the live plugin scripts directory

`plugins/leadv2/scripts/tests/test-glm-effort-wiring.sh:260`

```bash
MUT_DISPATCH="$(mktemp "${DISPATCH%/*}/dispatch-nc-mutant.XXXXXX")"
```

`${DISPATCH%/*}` is `plugins/leadv2/scripts/`. The suite creates a mutated copy of the production dispatcher inside the real script directory, cleaned only by `trap … EXIT INT TERM` (line 49). SIGKILL, an outer `timeout -k` kill, or a hard crash leaves a runnable mutant dispatcher as an untracked file in a worktree whose lanes stage by path. Two concurrent suite runs also both write there. The fixture directory (`$FIXTURE`, already trapped) or `$TMPDIR` is the correct home; if the mutant must sit beside the original for path reasons, that dependency is not stated anywhere in the file.

## M3 — bg-path assertion does not discriminate (tests-can-fail)

The propagation mechanism is env inheritance of an already-exported variable. `glm-coder.sh:123` declares `readonly GLM_EFFORT="${GLM_EFFORT:-}"` **without `export`** — `readonly` does not add the export attribute; the value reaches `cmd_run_child` only because the dispatcher supplies it as a command-prefix assignment (`GLM_EFFORT="${_glm_effort}" bash "${GLM_BIN}" bg …`), which puts it in the process environment, and `setsid_wrapper "${SELF}" __run_child` (`glm-coder.sh:1587`) inherits exported env. **This is correct today** — identical shape to `GLM_MODEL:112`, which works in production; I am not reporting a live bug.

The test is the problem. Part B4 exports `GLM_EFFORT=low` into the parent shell and then asserts the child's argv contains `--effort low`. Because the child re-execs and re-derives from its own environment, that assertion passes under ambient inheritance whether or not the code intends the forwarding — it cannot falsify a broken seam. A refactor that sets `GLM_EFFORT` by plain internal assignment (no export) would break the bg path with the suite still green. Two cheap remedies: `export GLM_EFFORT` at line 123 alongside the `ANTHROPIC_*` exports, and/or have the test invoke `bg` through `env -u GLM_EFFORT` with the value passed only as a command prefix.

## L1 — `effort_dropped reason=no_effort_control` still emitted for other arms (census)

`leadv2-dispatch-code.sh:5198` and `:5248` retain the pre-existing emit for the non-GLM arms. Correct — those arms genuinely have no effort control. Flagged only because the suite's assertion name ("no effort_dropped remains") and the report's phrasing read as repo-wide when the check is scoped to a single GLM dispatch's journal. Census: exactly 2 remaining instances, both legitimate.

## L2 — `--effort` flag presence is assumed, never probed

Since `_glm_effort_for_class` never returns empty, every GLM spawn now passes `--effort`. The whitelist is fail-open against a bad *value*, but there is no guard against a Claude Code build that predates the *flag* — on such a build every GLM dispatch dies at argv parse, i.e. a total GLM-arm outage from a version skew.

Verified on this host (probe, 2026-09-02):
```
$ claude --version
2.1.258 (Claude Code)
$ claude -p --help | grep -i effort
  --effort <level>                      Effort level for the current session
```
So the flag is real and the diff's `--effort` claim is evidence-backed. The residual is durability, not correctness: no minimum-CC assertion exists in the suite or a preflight. Low because the repo pins its own CC.

## L3 — "unset omits the flag" assertion is non-hermetic

`_effort_run_v1 ""` uses `[[ -n "${1:-}" ]] && export GLM_EFFORT="$1"` and never `unset GLM_EFFORT`. An operator with `GLM_EFFORT` exported in their shell turns Part B2 into a spurious red. Fails safe (red, not green), but flaky. `unset GLM_EFFORT` in the empty-arg branch closes it.

## L4 — end-to-end class coverage is partial

Real dispatch is exercised for `trivial` and `light` only (`class_expect` returns `''` for the rest); `standard`/`heavy`/`strategic`/`bulk` are covered only by the `sed`-extracted unit check of `_glm_effort_for_class`. The extraction check is genuine (it re-evaluates the live function body), and the author discloses the gap in the report — noted for completeness, not as a defect.

---

## Lenses that came back clean

**Correctness (rest of diff).** The two `case` blocks in `glm-coder.sh` are byte-identical and placed before the `claude` invocation on both the v1 and bg paths. `bash -n` coverage under both `bash` and `/bin/bash` 3.2 is in the suite — appropriate given the repo's standing no-Bash-4 decision; the added code uses no Bash 4 constructs. The `review|verify|critic → high` override sits after the class map, so it wins, which matches the stated intent (reviewers never run cheap).

**Product invariant / contract.** The `effort_dropped → effort_applied` transition for the GLM arm is the contract change, and the suite asserts both halves (token present, old token absent) plus a mutation negative control. `glm-flash` keeps `protected: false` + `untrusted: true`; the diff does not touch chain-strip behaviour. `cost: 0.4 → 0.33` is a data-only edit consistent with founder ruling q-bba84179 option b as recorded in the report.

**Claims-without-evidence.** Satisfied for every decision-driving claim. `--effort` existence: `claude -p --help` output quoted (independently re-verified above). The Z.AI `output_config.effort` mapping and the `low|high|max`, default-`max`, medium→high ladder: live `curl -sL https://docs.z.ai/devpack/latest-model.md` with date. "The knob is real": the 130-vs-369 `output_tokens` A/B. The credit multipliers driving `cost: 0.33`: live `curl -sL https://docs.z.ai/devpack/teamplan.md`. Caching behaviour, thinking-token accounting, rate limits and live end-to-end provider acceptance are explicitly tagged UNVERIFIED in report §1d/§5 — tagged, so MEDIUM-capped by the rule, and none of them drives a code path here. One weakness worth naming rather than scoring: the probe script lives at `/tmp/glm-curl-probe.sh` and is not committed, so the numbers are not reproducible from the repo.

UNVERIFIED (reviewer): I did not execute the new suite, and I did not exercise a live GLM dispatch against Z.AI. All findings above are derived from the diff plus static reads of the live worktree, except the `claude --effort` probe, whose output is quoted verbatim in L2.

## Verdict

FAIL on H1 alone. H1 is a one-line fix and M2/M3 are small; M1 is a doc edit. Nothing here questions the design — the class→effort seam is the right shape and the negative control is real work. Re-review should confirm: fallback whitelisting (or a conditional emit), mutant relocated out of `plugins/leadv2/scripts/`, and the two `0.4` sentences corrected.

DELIVERABLE_COMPLETE
