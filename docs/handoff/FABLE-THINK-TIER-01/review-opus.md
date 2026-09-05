LABEL=critic-dispatch-FABLE-THINK-TIER-01-review-1788309326 SESSION_ID=de750df6-25ff-415b-b4ee-f181b730ee10
--- body from: docs/handoff/dispatch-FABLE-THINK-TIER-01-review/critic.full.md ---
# critic — FABLE-THINK-TIER-01 round 3 (build-attempt-4.diff), exhaustive

REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=2 high=7 medium=8 low=3

FINDING: severity=Critical file=plugins/leadv2/skills/leadv2-judge/SKILL.md line=9 dimension=design desc=Hardcoded `fable` at 7 think-role spawn sites never consults the resolver, so the `unavailable: true` opus kill-switch — the change's only documented rollback — is unreachable; census regex matches only `opus`, so it can never detect this.
FINDING: severity=Critical file=plugins/leadv2/scripts/leadv2-repo-install.sh line=302 dimension=correctness desc=Writing LEADV2_MAIN_MODEL=fable makes leadv2-main-model-check.sh:60 return early, silently disabling opus_mode_guardrails and the daily budget check for every repo on next install/refresh, with no replacement and no test.
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-llm-judge.sh line=393 dimension=correctness desc=Router invoked one line before its own `[[ -f "$ROUTER_SCRIPT" ]]` check; under `set -euo pipefail` a missing router aborts the script, so the `model="${model:-fable}"` guard on the next line is unreachable on exactly the failure it guards.
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-session-route.sh line=193 dimension=correctness desc=Two unguarded resolver command substitutions (:63 and :193) with no `|| true` under `set -euo pipefail` — a nonzero resolver kills session routing outright instead of degrading; :63 is also dead (overwritten by :193) and config key `claude_heavy_model` (:104) is now silently inert.
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-ask.sh line=0 dimension=correctness desc=`_architect_decide()` resolves via `lib/leadv2-think-model.sh` with `2>/dev/null` and NO fallback and NO empty-guard, so a failing or empty resolver yields `model=""` and spawns with an empty model.
FINDING: severity=High file=plugins/leadv2/scripts/tests/test-fable-think-tier.sh line=1108 dimension=correctness desc=Tree-wide census greps scripts/workflows/skills/hooks but NOT config/ — the exact blind spot that let `config/session-routing.yaml:31` pin opus and produce the round-4 regression; a second config pin in any other consumer stays invisible.
FINDING: severity=High file=plugins/leadv2/scripts/tests/test-fable-think-tier.sh line=1072 dimension=design desc=The allowlist exempts a self-admitted LIVE think-role opus pin (`leadv2-causal-critique.js`, reason text says "PRE-EXISTING think-role pin … NOT fixed here"), so the census is green by exemption rather than by compliance.
FINDING: severity=High file=plugins/leadv2/workflows/leadv2-diverge.js line=1539 dimension=correctness desc=New opus fallback is a bare `await agent(...)` outside `synthAgent`'s try/catch, so a throw now aborts the workflow where it was previously swallowed and fell through to the haiku fallback; same shape in leadv2-po-feedback-loop.js.
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-code.sh line=485 dimension=design desc=Call-site fallbacks diverge across nine resolver sites (opus / fable / sonnet / none), directly contradicting the diff's own stated invariant that "that opus fallback lives in exactly ONE place — the router — never at a call site".

---

## Scope and method

Read: the full 1648-line diff (`build-attempt-4.diff`), plus targeted verification against the live
worktree for every claim I rated High or Critical. No `context.yaml` exists for this review task, so no
`decisions` / `off_limits` constrain the findings. I ran the suite myself.

**Author's central claim is TRUE.** `bash tests/test-fable-think-tier.sh` → `PASS=31 FAIL=0`, rc=0.
Round-3 fixes are real: the value-class `census_re` matches full model ids, uppercase shell vars,
`${X:-opus}` defaults, JSON keys and arm arrays (fixtures 2d, verified); mutation B (unguarded
`fallback`-labeled pin) is correctly rejected; the resolver's three-way behaviour (default fable /
env override / `unavailable: true` → opus) is pinned with a real negative control.

The findings below are what the green suite does not cover.

---

## Critical

### C1 — the opus kill-switch does not reach the think roles it is supposed to protect

The contract, stated in `lib/leadv2-think-model.sh` and in the suite header, is that *every* think-role
arm resolves through `think_model()`, whose sole purpose is to fall back to opus when
`model-capability.yaml` marks the fable row `unavailable: true`. Verified live, seven think-role sites
never call it and pin the literal `fable` instead:

```
skills/leadv2-judge/SKILL.md:9          model: fable          # frontmatter — cannot execute a resolver
skills/leadv2-recovery/EXAMPLES.md:25     model: fable,
skills/leadv2-plan/SKILL.md:346           model: fable,
workflows/leadv2-diverge.js:34          … || 'fable'
workflows/leadv2-diagnose.js:21         … || 'fable'
workflows/leadv2-learn.js:23            … || 'fable'
workflows/leadv2-po-feedback-loop.js:21 … || 'fable'
```

The four workflow constants read `a.model` and `process.env.LEADV2_THINK_MODEL`, then default to the
string `'fable'`. They never invoke the router. Set `unavailable: true` and the router returns `opus`,
but the judge skill, the plan critic, the recovery architect and all four workflows still spawn fable.
The documented retreat path is inert at the majority of the sites it exists for.

This is invisible to the gate by construction: `census_re` matches only `opus`, so a hardcoded `fable`
spawn pin is not a defect shape the census can express. The invariant is one-directional — the change
replaced "hardcoded opus" with "hardcoded fable" at these sites and pinned only the former.

Fix: give the workflows a resolver read (an arg the dispatcher fills from
`leadv2-router.sh think-model`, since the JS runtime has no `bash()`), and add a census pass that
treats a bare `fable` literal at a think-role spawn site as the same class of pin.

### C2 — main-model guardrails become a fleet-wide no-op

`leadv2-repo-install.sh` now writes `"LEADV2_MAIN_MODEL": os.environ.get("LV2_THINK_MODEL", "fable")`
into every repo's `settings.json`. Verified live:

```
leadv2-main-model-check.sh:6   # If main_model=opus: verify all opus_mode_guardrails …, check daily budget.
leadv2-main-model-check.sh:60  if [[ "$MAIN_MODEL" != "opus" ]]; then
```

With `main_model=fable` the checker returns early. `opus_mode_guardrails` and the daily budget check
stop running for every repo at its next install or refresh. `ref/leadv2-main-model.yaml` states this
outcome in its own comment ("returned as-is with no guardrail check needed") — but the guardrails were
not opus-specific *policy*, they were the only budget control on the lead's main model, and nothing in
the diff replaces them for fable. No test covers the post-change behaviour of `main-model-check.sh`.
`ref/leadv2-main-model.yaml` also carries the load-bearing claim *"only runs Opus guardrails when
`main_model=opus`"* with no inline evidence and no `UNVERIFIED` tag; it happens to be true (line 60
above), but it drives the decision to skip a replacement control, so it needed the citation.

---

## High

### H1 — `leadv2-llm-judge.sh`: use before existence check, and a guard that cannot fire

```
389 ROUTER_SCRIPT="${SCRIPT_DIR}/leadv2-router.sh"
393 model="$(bash "$ROUTER_SCRIPT" think-model 2>/dev/null)"
394 model="${model:-fable}"
396 if [[ -f "$ROUTER_SCRIPT" ]]; then
```

The file is *used* at 393 and *checked* at 396. Worse, `set -euo pipefail` is in force (line 26): a
missing router makes `bash` exit 127, the assignment inherits that status, and the script aborts at 393
— line 394's `:-fable` guard never executes. The guard is dead on precisely the failure mode it was
written for. Reorder the check above the call, or append `|| true`.

### H2 — `leadv2-session-route.sh`: unguarded substitutions, one dead assignment, one dead config key

```
63  CLAUDE_HEAVY_MODEL="$(bash "${SCRIPT_DIR}/lib/leadv2-think-model.sh" 2>/dev/null)"
104       claude_heavy_model) CLAUDE_HEAVY_MODEL="$_value" ;;
193 CLAUDE_HEAVY_MODEL="$(bash "${SCRIPT_DIR}/lib/leadv2-think-model.sh" 2>/dev/null)"
```

Three defects in one file. (a) Neither substitution carries `|| true` or a `:-` default, and
`set -euo pipefail` is on (line 7) — a nonzero resolver kills session routing outright rather than
degrading, which is strictly worse than the `opus` literal it replaced. Compare `leadv2-route-bandit.sh`
and `leadv2-dispatch-code.sh`, which both use `|| true`. (b) Line 63 is dead: line 193 overwrites it
unconditionally with an identical call, costing a second subprocess on every invocation. (c) Line 104's
`claude_heavy_model` config key is now inert. The comment calls the config pin "dead by design", which
is defensible for the `session-routing.yaml` override — but the same unconditional line also kills any
`LEADV2_CLAUDE_HEAVY_MODEL`-style override applied in the 183–192 block, and that is not stated.

### H3 — `leadv2-ask.sh`: no fallback at all

```bash
model="${LEADV2_ASK_ARCHITECT_MODEL:-$(bash "${SCRIPT_DIR}/lib/leadv2-think-model.sh" 2>/dev/null)}"
```

`2>/dev/null` and nothing else. A resolver that exits 0 with empty stdout (or is missing, under the
`set -euo pipefail` at line 68) yields `model=""`. Every other migrated site has *some* default; this
one has none. This is also the sole site using `lib/leadv2-think-model.sh` in the same idiom as
`session-route`/`route-bandit`/`repo-install`, while `dispatch-code`, `fanout-classify`, `fanout.sh`
and `llm-judge` call `leadv2-router.sh think-model` directly — two entry paths to one policy, which
the new lib file's own docstring says should be one.

### H4 — census does not scan `config/`

```
1108 census_raw="$(grep -rnE "$census_re" \
1109     "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/workflows" "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/hooks" …
```

Round 4's own discovery was that `config/session-routing.yaml:31` carried `heavy: model: opus` and beat
the script default. The fix forced the resolver *after* config application in one consumer — it did not
close the class. `config/` and `ref/` remain unscanned by the think-tier census (the separate `opus-4`
gate at 1226 *does* include them, which shows the omission is an oversight, not a decision). Any other
consumer reading a config-pinned model is still unprotected, and the suite would stay green.

### H5 — the census is green by exemption

```
1072 'leadv2-causal-critique.js::TASK_CLASS === .Heavy. \? .opus.::PRE-EXISTING think-role pin —
      workflow file OUTSIDE this lane LANE_WRITES; … NOT fixed here — flagged for a follow-up lane'
```

The allowlist entry states, in its own reason field, that this is a live think-role opus pin that the
census correctly caught and that was then exempted rather than fixed. The suite's headline assertion —
*"tree-wide census: zero live think-role 'opus' spawn pins"* — is therefore false as worded; it means
"zero unallowlisted pins". A lane-boundary constraint is a legitimate reason to defer the fix, but the
assertion text and the report should say the contract is not yet met. `leadv2-token-discipline/SKILL.md`
is allowlisted on the same basis ("stale doc prose … doc debt").

### H6 — the new opus fallbacks escape the error handling they were added beside

`leadv2-diverge.js:1539` and `leadv2-po-feedback-loop.js:1603` both add the fallback as a **bare**
`agent(...)`, outside `synthAgent`'s try/catch:

```js
if (judged === null && THINK_MODEL !== 'opus') {
  judged = await agent(…, { label: 'judge-opus-fallback', model: 'opus', … })   // no try/catch
}
if (judged === null) { /* haiku fallback */ }
```

Previously every judge failure funnelled through `synthAgent`, which swallowed throws and returned
`null`, reaching the haiku fallback. Now a throw from the opus attempt propagates and aborts the
workflow — the fallback made the failure path *less* robust. In `po-feedback-loop.js` the same bare
`agent()` sits inside a `parallel()` list, so the rejection takes the whole phase down. Additionally
both are redundant with `synthAgent`'s own chain (`[opts.model || THINK_MODEL, 'opus', 'sonnet']`),
so opus is now attempted twice per judge failure.

### H7 — call-site fallback values contradict the stated invariant

`lib/leadv2-think-model.sh` states: *"That opus fallback lives in exactly ONE place — the router —
never at a call site."* Census of all nine migrated sites:

| site | guard | fallback value |
|---|---|---|
| `leadv2-dispatch-code.sh:485` | `\|\| true` + `[[ -n ]]` | **`opus`** ← violates the invariant literally |
| `leadv2-fanout-classify.sh` | `\|\| echo fable` | `fable` |
| `leadv2-fanout.sh` (python) | try/except + `or "fable"` | `fable` |
| `leadv2-llm-judge.sh:394` | `${model:-fable}` (unreachable, H1) | `fable` |
| `leadv2-repo-install.sh` | `\|\| true` + `${…:-fable}` | `fable` |
| `leadv2-route-bandit.sh` | `\|\| true` + `${…:-sonnet}` | **`sonnet`** |
| `leadv2-session-route.sh` ×2 | none (H2) | — (abort) |
| `leadv2-ask.sh` | none (H3) | — (empty) |

Four different behaviours for one failure. `route-bandit` degrading a *think* tier to `sonnet` is the
most consequential: a Heavy/Strategic architect silently drops two tiers of capability on a transient
resolver failure. Also note the `|| echo …` / `|| true` idiom only fires on nonzero exit — a resolver
that exits 0 with empty stdout defeats it everywhere except the two sites that add `${…:-…}`.

---

## Medium

1. **`_lv2_classify_survivor` comment and code disagree on the exemption window.** The comment
   (`test-fable-think-tier.sh:1029`) says *"gated by a resolver check in the 2 preceding lines"*; the
   code uses `lineno - 25`. Because this diff inserts a `think-model resolver` explanatory comment
   above nearly every touched hunk, in the real tree those comments now satisfy the guard predicate for
   any `fallback`-labeled pin within the next 25 lines. Mutation B passes only because its fixture file
   contains no such comment — the positive control is not representative of the tree it guards.
2. **`_lv2_classify_survivor:1040` exempts any line merely *mentioning* `THINK_MODEL`.** A pin written
   `model: 'opus' // THINK_MODEL` is exempt with no guard at all.
3. **`leadv2-routing-guard.sh` advisory strings recommend a bare `leadv2-router.sh think-model`** — a
   non-PATH script name. This is the identical defect the report §1 claims to have fixed in
   `architect-escape-mission.md` by switching to `bash "${CLAUDE_PLUGIN_ROOT}/scripts/…"`. Census miss.
4. **`leadv2-model-inherit-guard.sh` received a comment-only edit.** Its allowlist is still
   `echo "$MODEL_LOWER" | grep -q "opus"` with no fable branch, so the *new default* think model is
   entirely outside the containment the hook exists to enforce.
5. **`model-capability.yaml`: `context_k` changed from integer `200` to the string `unverified`.** The
   honesty is right, the type change is a contract break — no consumer of `context_k` was checked in
   this diff.
6. **`leadv2-route-bandit.sh`: `two_arms` `["sonnet","opus"]` → `["sonnet","fable"]`.** Persisted bandit
   statistics keyed on `opus` are orphaned and `fable` starts cold; no migration or reset is mentioned.
   Opus is now unreachable by exploration under any conditions.
7. **`report.md` contradicts the suite it ships with.** The lead-appended Round 4 section (after the
   file's own `DELIVERABLE_COMPLETE` marker) states *"Mutation negative controls (brief step 4): NOT run
   by the worker in this round — unverified"*, yet §2c/2d of the suite contain those controls and pass.
   One of the two artifacts is stale; a reader cannot tell which.
8. **`leadv2-router.sh:800` `readonly MODEL_CAPABILITY_YAML`** at file scope makes the router
   non-idempotent under `source`, and unlike every other var it cannot be re-pointed after load.

## Low

1. `test-fable-think-tier.sh:1320` — the alternation `'leadv2-router.sh"; think-model\|router.sh" think-model'`
   has a nonsensical first branch (stray `;`); the assertion passes on the second branch only.
2. `leadv2-fanout.sh` help text has an unbalanced closing parenthesis after the rewording.
3. `leadv2-diverge.js` passes `model: THINK_MODEL` explicitly while `leadv2-diagnose.js` /
   `leadv2-learn.js` drop the key and rely on `synthAgent`'s default. Same result, three spellings.

## Falsification notes (tests-can-fail lens)

- The workflow assertion at :1217–1223 is `grep -n "const THINK_MODEL"` — presence only. It passes if
  the const is `'opus'`, `''`, or anything else. It cannot fail for the reason it exists (feeds C1).
- §4b (session-route stub config) is a genuine falsifying probe and is the strongest test in the suite.
- §1/§1b/§1c (resolver three-way) and §2c/§2d (mutation red/green fixtures) are genuinely falsifying.
- §3 (review pool) uses a stubbed quota reader with an explicit lockout-dir isolation — hermetic, good.
- Nothing in the suite exercises the *failure* path of any resolver call site — which is why H1/H2/H3
  all survive a 31/31 green run.

## Claims-without-evidence census

| claim | location | status |
|---|---|---|
| fable/opus share one quota bucket | glm-policy-resolve.py, model-capability.yaml | round-1 claim **withdrawn**, replaced with a quota-read delta probe. Correct handling. |
| `context_k` for fable | model-capability.yaml | tagged `unverified`. Acceptable (Medium 5 is the type break, not the honesty). |
| `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` nulls `opts.model` in CC 2.1.257 | model-effort-matrix.md | carries a `strings` disassembly excerpt. Evidenced. |
| `config/session-routing.yaml:31` carries a live `heavy: model: opus` | session-route.sh comment | cites file:line. Evidenced. |
| main-model-check only guards when `main_model=opus` | ref/leadv2-main-model.yaml | **untagged, evidence-free, and drives C2's decision to add no replacement control.** True (verified at :60), but the diff did not show it. |
| suite is `PASS=31 FAIL=0` at 587bb1f | report.md | **verified by me**: `PASS=31 FAIL=0`, rc=0. |
| mutation controls not run this round | report.md Round 4 | contradicted by the shipped suite (Medium 7). |

## What would flip this to PASS

C1 and C2 are the blockers. C1: route the four workflows and the three skill-frontmatter sites through
the resolver (or accept fable as terminal and delete the `unavailable`/opus-fallback story, which is the
worse option), and extend the census to treat a bare `fable` think-role pin as the same shape. C2: keep
the guardrails alive for a non-opus main model, or state explicitly and test that they are retired.
H1–H3 are one-line each. H4 is one path added to a `grep -r`. H5 is a wording change plus a follow-up
lane id. H6 needs the two bare `agent()` calls wrapped. H7 needs one agreed fallback value.

DELIVERABLE_COMPLETE
