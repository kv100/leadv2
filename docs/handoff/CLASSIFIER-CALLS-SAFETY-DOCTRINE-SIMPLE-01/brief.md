# CLASSIFIER-CALLS-SAFETY-DOCTRINE-SIMPLE-01 — implementation brief

Repo: `~/Projects/leadv2`. Plan row: `docs/leadv2/PLAN.md:68` (Wave 3, row 3.4).
**The row is NOT stale.** The defect reproduces, and is worse than stated: one matcher fires on the
wrong tasks *and* stays silent on the right ones. Blueprint only — no code below.

## 1. Where the class verdict is produced

| what | where |
|---|---|
| **the risk matcher — the actual bug** | `plugins/leadv2/scripts/leadv2-task-judge.sh:112-119` (`SAFETY_KEYWORDS`, substring scan over the whole mission body) |
| the complexity ladder, computed independently of it | `leadv2-task-judge.sh:95-110` |
| enclosing estimator / **single emit choke point (all 5 exit paths)** | `leadv2-task-judge.sh:92-155` `_fallback_estimate()` / `:289-294` `_emit()` |
| the LLM path — same hole, no floor | `leadv2-task-judge.sh:200-252`; rubric `leadv2-task-judge-prompt.tmpl:8,11` |
| consumer: risk → class escalation + safety pin (read-only, off-limits) | `leadv2-dispatch-code.sh:3940` → `ADMISSION_RISK_CLASS`; `:3954`, `:3996`, `:6961-6963` |
| consumer: complexity → arbiter descriptor | `leadv2-dispatch-code.sh:6968-6970` (`DC_COMPLEXITY`), `:7611` |

One function feeds all four consumers. `estimate_source=fallback` in the judge output is the same
`source=fallback` printed on the live `task_class_override` line — that is the audit trail.

## 2. Reproduction — measured, both directions

`/tmp/lv2m/dispatch.log` verified present (2814 B, mtime 2026-09-03 20:02), **not rotated**. Line 4:

```
HEAVY-TIER-VS-SAFETY-OPUS-01 rc=0 route_resolved by=arbiter role=worker arm=sonnet model=sonnet
tier=standard task=d552b9ab reason=cheapest_capable arbiter_pick=sonnet util_glm=13
util_codex=unknown_capped util_claude=43 floor_mode=bulk_only floor_mode_source=yaml
complexity=simple duration_class=short
```

Estimator run directly on the two real lane missions on disk:

```
$ for t in 79a9c5b7 d552b9ab; do LEADV2_JUDGE_DISABLE=1 LEADV2_JUDGE_CACHE_DIR=/tmp/rc-$t \
    bash plugins/leadv2/scripts/leadv2-task-judge.sh \
    --mission-file docs/handoff/dispatch-$t/lane-mission.md; done

79a9c5b7 (CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01 — NOT a safety task)
  hits: 'payment'=0 'publish'=2 'safety gate'=0 'safety-gate'=0
  {"complexity":"standard","risk_class":"safety_publish_payments","estimate_source":"fallback",...}

d552b9ab (HEAVY-TIER-VS-SAFETY-OPUS-01 — IS a safety-routing task)
  hits: 'payment'=0 'publish'=0 'safety gate'=0 'safety-gate'=0
  {"complexity":"simple","risk_class":"none","estimate_source":"fallback",...}
```

**False positive — cause measured, and it is not what was hypothesised.** The two `publish` hits in
79a9c5b7 are not a quoted off-limits paragraph. They are ordinary English prose about quota
providers: line 24 `…when a provider does not publish a reset…`, line 65 `…a provider that already
publishes a reset…`. `publish` the English verb collided with `publish` the product action — a
**homograph** — and escalated an ordinary task to `Heavy` with a safety pin (`class_escalated …
from=Standard to=Heavy because=risk_class:safety_publish_payments`, `safety_pin_applied by=admission`).

**False negative — cause.** `HEAVY-TIER-VS-SAFETY-OPUS-01` contains the token `SAFETY`, but every
pattern in the repo requires it adjacent to `gate`: `leadv2-task-judge.sh:112` (`'safety gate'`,
`'safety-gate'`) and `leadv2-routing.yaml:337-343` (`*safety-gate*`, `*safety_gate*`, `*safety*gate*`).
**The bare token `safety` appears in no pattern in this repo.**

**Root cause, one sentence:** `protected_path_patterns` are *path globs*, and both the judge and the
admission layer substring-match them against *free prose*. Matching a path glob against a paragraph
is the category error that yields a homograph false-positive and a shape-blind false-negative from
the same scan.

*Caveat:* `~/.claude/config/leadv2-quota-ceilings.sh` was absent until 20:04 today (three gates
failing open), so both `route_resolved` lines were produced with no ceilings in force. The judge runs
above are offline (`LEADV2_JUDGE_DISABLE=1`, no quota path) and are unaffected.

## 2b. Census - how much of this we are paying today

Corpus: **324 `docs/handoff/*/lane-mission.md` files** - that is literally the text
`_dispatch_complexity_estimate` hands the judge, so it is the faithful input surface (`brief.md` is
an author-time artifact the estimator never sees). Script `scratchpad/census.py`, run from the repo
root; it replicates `leadv2-task-judge.sh:112-119` exactly (lowercased substring scan).

**Q1 - `protected_path_patterns` entries that collide with ordinary prose: 6 of 6.**

| pattern | token | verdict | files matching in prose | files matching in a real path |
|---|---|---|---|---|
| `*safety-gate*` | safety-gate | collides-with-prose | 1 | 0 |
| `*safety_gate*` | safety_gate | collides-with-prose | 2 | 0 |
| `*safety*gate*` | safety*gate | collides-with-prose | 1 | 0 |
| `*publish*` | publish | collides-with-prose | **12** | **1** |
| `*payments*` | payments | collides-with-prose | 5 | 0 |
| `*payment*` | payment | collides-with-prose | 7 | 0 |

Judge's own list on disk: `SAFETY_KEYWORDS = ['payment','publish','safety gate','safety-gate']`.
**The path globs match prose 28x across the corpus and a real path once** - not one of the six is
path-only in practice.

**Q2 - false-positive rate of the current surface: 19 / 324 score `risk_class != none`; 17 are prose
homographs by the automated rule (5.2% of the corpus, 89.5% of all flags).** Manual check of the two
the rule called genuine found `dispatch-0f9e4d16` is also a homograph - it matched `published
benchmarks` in a `##` heading - so **18 of 19 flags (94.7%) are false**; `dispatch-e6b67151` is
unresolved. `dispatch-79a9c5b7` is in the homograph list, confirming section 2 mechanically.
**Not one of the 324 is a genuine safety task under today's matcher, while `d552b9ab` - the one task
that is - scores `none`.**

**Q3 - mirror figure, corrected surface: 6 / 324 flag, all via the id/title token `safety`, and
`d552b9ab` is among them.** The fix removes 18 false flags and adds the true one.

**Stated gaps, not guessed around.**
(a) **The declared-path arm is inert: `Reads:`/`Writes:`/`Touches:` lines appear in 0 of 324 lane
missions** - `grep -lEi '^[[:space:]]*(reads|writes|touches)[[:space:]]*:' docs/handoff/*/lane-mission.md
| wc -l` returns `0`. Every Q3 row matched on id/title alone, `paths=[]`. Section 3 is amended for it.
(b) The corpus is self-referential - leadv2's own missions discuss routing and safety vocabulary more
than a product repo would - so 5.2% is an **upper bound** for other tenants, not a fleet number.
(c) `~/Projects/persona-engine/docs/tasks.yaml` was not used: its rows carry titles and intents, not
mission text, so scoring it would measure a surface the estimator never reads.

## 3. The matcher — fix the surface, do not add a list

**Adding keywords makes both failure modes worse.** Reuse the existing list; apply it to the surface
it was designed for.

| layer | predicate | source of truth |
|---|---|---|
| **L1 — floor trigger** | `estimate.risk_class == "safety_publish_payments"` | the estimate itself |
| **L2 — what sets that field** | patterns evaluated against a **restricted structured surface**, never the free-text body | `leadv2-routing.yaml` `glm_policy.protected_path_patterns`, resolved tenant-first (`.claude/ref/leadv2-routing.yaml`, else plugin config) — the resolution `leadv2-router-v2.py:381-395` already performs |

**The structured surface — exactly three fields:**

1. **task id** (e.g. `HEAVY-TIER-VS-SAFETY-OPUS-01`) — case-insensitive word-boundary token match on
   `safety` / `publish` / `payment` / `payments` as whole hyphen-or-underscore-delimited tokens;
2. **mission title** (first `#` heading only) — same token match;
3. **the dispatcher's own resolved path signal** - `protected_path_patterns` applied as the
   **path globs they are**, against paths only. **Do NOT source these from `Reads:`/`Writes:`/
   `Touches:` mission lines: measured, 0 of 324 lane missions carry one (2b-a), so that arm would be
   decorative.** Take the paths from whatever the dispatcher already resolves for
   `_effective_protected`; if no such list is reachable from the judge, ship the id+title arm alone
   and say so - never ship an arm that cannot fire.

The mission body is not scanned. That is the whole fix at this layer. On the two measured cases:
79a9c5b7's `publishes a reset date` is body-only → stops firing; d552b9ab's id carries `SAFETY` →
starts firing. Both directions corrected by one change of surface, with **zero new patterns**.

*Verify, do not assume:* confirm the text `_dispatch_complexity_estimate` hands the judge
(`leadv2-dispatch-code.sh:6969`) actually carries the task id and the `Reads:`/`Writes:` lines. If it
does not, the estimate cannot see them — report that with evidence as an upstream row, do not guess
around it.

**No `LEADV2_*` bypass flag.** A kill-switch on a safety rule is the anti-pattern this task deletes.
On unreadable/absent yaml, fall back to the built-in tuple **plus the bare `safety` token** and
journal `safety_patterns=default`.

## 4. Where the override belongs, and what it overrides to

Apply the floor **inside `_emit()` (`leadv2-task-judge.sh:289`) as its first statement**, via a
helper `_apply_safety_floor` — before `printf`, before `_journal`. `_emit` is the only choke point
all five exit paths pass through:

```
1. LEADV2_JUDGE_DISABLE=1 (l.297) ─┐
2. --class Light          (l.302) ─┤
3. CACHE HIT              (l.305) ─┼─► _emit() ─► [FLOOR] ─► stdout ─► DC_COMPLEXITY ─► arbiter
4. judge output validated (l.238) ─┤                              └─► ADMISSION_RISK_CLASS
5. fallback               (l.327) ─┘
```

* Path 3 emits a **stored** estimate without re-running either producer — a producer-side floor is
  bypassed by every pre-fix cache entry. Flooring at emit self-heals `judge-cache/`, no migration.
* Path 4 is an LLM verdict; a prompt-rubric edit is guidance, not enforcement. Leave the `.tmpl`
  byte-identical (it carries the `test_t3_lexicon_grep` invariant).
* Leave the cache write (`l.234-237`) alone: raw in, floored on read-out, idempotent.

**The override:**

```
if risk_class == "safety_publish_payments" and complexity in {"trivial","simple"}:
        complexity = "standard"        # monotonic max — never a downgrade
```

* **Floor to `standard`, not `complex`** — the lowest rung that is not simple/trivial, which is what
  the row demands. `complex` would over-escalate duration/heavy-tier routing and inflate cost.
* `standard`/`complex` pass through untouched. **Touch only `complexity`** — not `duration_class`,
  `work_kind`, `subsystems_touched`; a safety fix can honestly be short.
* **Decides task shape, never an arm.** Names, prefers and excludes no arm; the arbiter still chooses.
  Never hardcode an arm into or out of routing.
* Journal `safety_floor=applied|none` on the existing `route_v2_estimate` line (`l.270-273`). A rule
  with no reader is not a rule.
* On any internal error: pass through unchanged, journal `safety_floor=error`. R2 (the judge never
  blocks a dispatch) still binds. This is a routing-quality fix, not the enforcement point —
  enforcement stays `glm_policy.sonnet_exceptions[safety_gate_publish_payments]`, untouched.

## 5. MANDATORY negative control

**Mutation — INSIDE the body of `_apply_safety_floor`, never at file top level.** In the python
heredoc, break the trigger so it can never match:

```
-if est.get('risk_class') == 'safety_publish_payments':
+if est.get('risk_class') == 'safety_publish_payments_NEVER':
```

**Suite that must catch it:** `plugins/leadv2/scripts/tests/test-leadv2-task-judge.sh`.
Expected: **T10, T11, T14 red; T12 and T15 stay green.**
**Second control (matcher layer):** inside `_fallback_estimate`, restore the body-wide substring
scan → **T15 red** (the homograph returns).
**Proof format:** the `baseline_rc` / `mutated_rc` pair plus the literal red suite line are the
primary proof. `diff_hash` may be cited normally alongside them — the empty-hash defect is fixed in
main and its blast radius was zero, so that restriction is lifted (2026-09-03).

## 6. Tests to add — same suite, after `test_t9_*`, wired into the runner list at `l.316-325`

| id | input | must assert |
|---|---|---|
| T10 | safety mission, run twice: no `--class`, then `--class Light` | `risk_class == safety_publish_payments` **and** `complexity` ∈ {`standard`,`complex`} in **both** |
| T11 | cache pre-seeded under the mission's `sig8` with `{"complexity":"trivial","risk_class":"safety_publish_payments",…}` | emitted `complexity == standard` — proves the floor is at the choke point |
| **T12** | README-typo mission, zero safety tokens | `complexity == "trivial"` **exactly** and `risk_class == "none"` — the no-over-trigger control; never weaken to "not simple" |
| T13 | safety mission with `--class Heavy` | `complexity == "complex"` — the floor never downgrades |
| **T14** | mission whose id is `HEAVY-TIER-VS-SAFETY-OPUS-01`, nothing else safety-shaped | `risk_class == safety_publish_payments`, `complexity != simple` — the d552b9ab regression |
| **T15** | body contains `a provider that already publishes a reset date`; id and paths safety-free | `risk_class == "none"` — the 79a9c5b7 homograph regression |

T14 and T15 are the same bug from opposite ends; a fix that greens one and reds the other is not the fix.

**CI selection:** `tests/run-all.sh:82` maps a changed file to `test-<stem>.sh` by stem, so touching
`leadv2-task-judge.sh` selects this suite with no new `EXTRA_SUITE_MAP` row. **Prove it** — paste
`bash tests/run-all.sh --scope changed` showing the suite in the selected list.

## 7. Adjacent, observed — NOT in scope, do not fix here

1. **The safety pin may not bind the arm.** On 79a9c5b7 class escalated to `Heavy` with
   `safety_pin_applied`, yet the arm still resolved `sonnet … reason=cheapest_capable`.
   `leadv2-dispatch-code.sh:7611` puts `"safety"` into the arbiter descriptor and `:7659` takes
   `arm="${candidate_arms[0]}"` from the arbiter pick — but **UNVERIFIED:** I did not locate
   `route_arbiter`'s handling of `descriptor.safety` (no `leadv2-route-arbiter.sh` at the referenced
   path). If the pin does not survive into arm selection, fixing classification alone fixes nothing.
   Own row, this evidence attached.
2. **`floor_mode=bulk_only floor_mode_source=yaml`** — all four lanes routed sonnet
   `reason=cheapest_capable` at `util_glm=13` vs `util_claude=43`. GLM appears admitted to bulk only,
   so it is never a candidate at `tier=standard` — a yaml line silently overriding GLM-FIRST-01.
   Own row (measured pre-20:04, ceilings failing open — re-measure).
3. **`util_codex=unknown_capped`** — unknown Codex utilisation is replaced by a ceiling, so Codex
   loses to any arm with a known number regardless of real load. Own row.
4. **`agent/safety/` matches nothing** in `protected_path_patterns`; a mission naming
   `agent/safety/pre-execute.sh` with no prose keyword scores `risk_class: none` (reproduced). That
   list also drives GLM dispatch routing, so widening it changes arm selection fleet-wide — file
   `SAFETY-PATH-PATTERNS-MISS-AGENT-SAFETY-01`.
5. Row 3.5 `HEAVY-TIER-VS-SAFETY-OPUS-01` — adjacent lane.

## 8. Hard constraints

* MUST NOT touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (another lane owns it) — read-only.
* MUST NOT weaken any existing assertion; MUST NOT add to `tests/known-red-suites.txt` (it may only
  shrink — `tests/known-red-guard.sh` fails the build on growth).
* MUST NOT print or log any credential value; the journal line carries verdict fields only.
* MUST run on **macOS bash 3.2** and in a linux container: no `${var,,}`, no `declare -A`, no
  `mapfile`, no GNU-only `sed -i`/`date -d`. Matching goes in the existing `python3` block.
* No new env var. Convention is `LEADV2_*` (verified against every flag in this script); §4 forbids a
  bypass flag regardless.
* Concurrency: the floor adds no writer. `route-estimates.jsonl` stays `flock`-guarded (`l.277-283`);
  the cache write stays tmp+`mv -f` atomic (`l.234-237`); the floor is per-read and idempotent.
* The `claude -p` call at `l.219-221` already carries `--max-turns 3 --permission-mode
  bypassPermissions --output-format json` — verified, unchanged.

## 9. Acceptance

1. Re-run §2's loop on both real lane missions: 79a9c5b7 → `risk_class: none`; d552b9ab →
   `risk_class: safety_publish_payments` with `complexity: standard`. Paste both.
2. T10–T15 green; suite name shown in `run-all.sh --scope changed` output.
3. §5 mutation applied inside the function body → `baseline_rc`/`mutated_rc` pair plus the literal
   red suite line pasted; mutation reverted.
4. `git diff --stat` shows only `leadv2-task-judge.sh` + `test-leadv2-task-judge.sh`.

DELIVERABLE_COMPLETE
