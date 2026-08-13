Product implementation task dispatch-83c44855. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# CODEX-QUOTA-LOCKOUT-NEVER-FIRES-FOR-CODEX-01 — implementation design

Architect prepass. Design only; no implementation in this deliverable.

## 1. Confirmed root cause (read from source, not assumed)

| Fact | Evidence |
|---|---|
| Lockouts are written from exactly one call site family | `_maybe_record_quota_lockout()` at `leadv2-dispatch-code.sh:1037`, called only at `:2167` (glm), `:2207` (kimi), `:2254` (sonnet), `:2314` (codex) — every one inside `if [[ ${rc} -ne 0 ]]` of the **launcher** invocation |
| Codex's launcher exits 0 on a quota-doomed job | `:2304` `codex-task.sh task … --background` enqueues and returns a jobId; the usage-limit text appears later in the job log. `refusal_reason()` (`:2102`) never sees it |
| A post-spawn verdict seam already exists, but is hardcoded to one arm | `:2472` `if [[ "${arm}" == "kimi" ]]` → `_wait_kimi_verdict` (`:2381`) → `return 7` |
| `return 7` from the spawn wrapper already means "spill to next arm, same process" | candidate loop `7)` branch at `:3303`, ends in `continue` — the ladder retries the next candidate immediately |
| Lockout duration is flat | `:1043` `date -u -v+${LEADV2_QUOTA_LOCKOUT_MINUTES:-30}M`; no parse of provider text |
| Precheck read side is correct and generic | `:3108–3122` `_provider_available` → `quota_precheck_skip … reason=provider_quota_locked` |
| Close gate already polls worker status and understands `failed` | `leadv2-dispatch-product-close.sh:685` (`status == complete || status == failed`) |
| Close gate already has an arm-advance mechanism | `_pc_arm_advance()` `:984`, one-shot marker, chain from `LEADV2_DISPATCH_CANDIDATE_ARMS`, calls `advance-arm` `:1021` — but is reachable **only** from `pc_silent_arm_probe` (`:1310`) |

So: D1 is a missing *branch*, not a missing *mechanism*; D3 is a missing *trigger*, not a missing *mechanism*. Both fixes are wiring into seams that already exist.

## 2. Design principle — adapters vs. policy

The hard constraint is "never hardcode an arm out of routing." The distinction this design holds:

- **Forbidden:** any per-arm eligibility/exclusion knowledge in the ladder. No `if arm == codex`, no exclusion list.
- **Permitted and unavoidable:** a **channel adapter** table — how to ask *this launcher* for job status and *this launcher* for a job's final text. Each launcher has a different CLI; that is a protocol fact, not a routing decision. The adapter table decides *how to observe*, never *whether to select*.

The existing `if [[ "${arm}" == "kimi" ]]` at `:2472` is a policy-shaped hardcode and gets **replaced** by the generic block below — the diff net-removes an arm name from the ladder.

## 3. Data flow (numbered)

1. `_spawn_worker_body` launches an arm; launcher returns 0 with a handle.
2. `dispatch_confirm` writes the confirmed ledger row (unchanged; must stay before the wait, same reason the kimi comment at `:2469` gives).
3. **NEW** `_wait_arm_early_verdict <arm> <handle> <sig8>` runs for a bounded window:
   a. `_arm_status_probe <arm> <handle>` → raw text from that launcher's own `status` verb (adapter).
   b. `_arm_status_state <arm> <raw>` → `running | complete | failed | unknown`.
   c. `unknown`/`running` → sleep, loop until window expires → return 0 (proceed as today).
   d. `complete` → return 0.
   e. `failed` → `_arm_final_output <arm> <handle>` → last N lines of the job's own log (adapter) → step 4.
4. `_quota_shaped "<text>"` → rc0 if the text carries a provider quota/usage-limit/rate-limit signal.
   - Not quota-shaped → return 0 (today's behaviour exactly: an ordinary failed job is the close gate's problem, no lockout). **This is D-test-4.**
   - Quota-shaped → step 5.
5. `_quota_return_time "<text>"` → ISO-8601 or empty (via `lib/leadv2-quota-error-parse.py`).
6. `_record_quota_lockout <provider> <iso> "postspawn_failure:<arm>"` — the same existing seam, unchanged.
7. `emit decision "quota_lockout_recorded provider=… arm=… reason=postspawn_quota source=provider_time|default_clamped|default until=<iso>"`.
8. Return 7 from `_wait_arm_early_verdict`'s caller after `dispatch_abort "${token}"` — identical to the kimi no-work path at `:2477–2482`. Candidate loop `continue`s → next arm. **This is D3, in-window.**
9. **Out-of-window** (job dies after the verdict window): `leadv2-dispatch-product-close.sh` observes `status == failed` in its poll (`:685` region) and calls the new subcommand `leadv2-dispatch-code.sh record-quota-lockout --arm <arm> --handle <h> --sig8 <t>`, then falls into `_pc_arm_advance` with `reason=arm_quota_failed`. **This is D3, out-of-window.**
10. Next dispatch: `_provider_available` returns 1 → `quota_precheck_skip … provider_quota_locked` → next arm. Unchanged code. **This is D-test-5.**

## 4. Interface contracts

| Symbol | Location | Signature | Contract |
|---|---|---|---|
| `_arm_status_probe` | dispatch-code.sh (new, near `:2381`) | `<arm> <handle>` → raw text on stdout, rc0; rc1 if no adapter for arm | Adapter. codex: `bash "$CODEX_BIN" status <h>`; kimi: `bash "$KIMI_BIN" status <h>`; glm: `bash "$GLM_BIN" status <h>`; sonnet/opus: **no adapter → rc1** (sonnet is a bare PID, no status verb) |
| `_arm_status_state` | dispatch-code.sh (new) | `<arm> <raw>` → one of `running\|complete\|failed\|unknown` | Parses `status:` line (kimi/glm shape) or codex's own status output. Anything unrecognised → `unknown`, never `failed` |
| `_arm_final_output` | dispatch-code.sh (new) | `<arm> <handle>` → ≤`LEADV2_ARM_TAIL_LINES` (default 60) lines | Adapter. Prefers the launcher's own log/output verb; falls back to the `status` raw text. Empty on failure — never fatal |
| `_quota_shaped` | dispatch-code.sh (new) | `<text>` → rc0 quota-shaped, rc1 otherwise | Case-insensitive match on a fixed pattern set (§5). Provider-agnostic; matches the *phenomenon*, not the vendor |
| `_quota_return_time` | dispatch-code.sh (new) | `<text>` → ISO-8601 Z on stdout, or empty | Thin wrapper over the python helper; empty on any error |
| `leadv2-quota-error-parse.py` | `plugins/leadv2/scripts/lib/` (to-create) | stdin=text, argv=`--floor-minutes N --max-minutes N` → prints ISO or nothing, always exit 0 | Pure; no I/O beyond stdin/stdout. Clamping lives here so the shell has one truth |
| `_wait_arm_early_verdict` | dispatch-code.sh (new, replaces `_wait_kimi_verdict`'s call site) | `<arm> <handle> <sig8>` → 0 proceed, 7 spill-quota, 78 spill-no-work | 78 preserves the kimi channel_no_work path verbatim |
| `record-quota-lockout` | dispatch-code.sh subcommand (new, dispatch at `:3478`) | `--arm --handle [--sig8] [--provider]` → rc0 always | Idempotent-safe: `_record_quota_lockout` overwrites atomically via tmp+mv (`:1029`). Callable by the close gate without sourcing |

## 5. `_quota_shaped` pattern set (the learning surface)

Matched case-insensitively against the job's final output. Deliberately narrow — every pattern names a *quota/rate* condition, none names a vendor:

```
usage limit
quota (exceeded|exhausted|reached)
rate limit(ed)?
out of (credits|tokens|quota)
insufficient (credits|quota|balance)
too many requests
(^|[^0-9])429([^0-9]|$)
you.?ve hit your (usage|rate) limit
resets? at
try again (at|in|after)
```

Anti-match guard (D-test-4): the last two lines are *supporting* patterns only — they alone must **not** trip the classifier. Implementation rule: require ≥1 match from the first seven ("primary") patterns; the last two only feed `_quota_return_time`. A test suite emitting `AssertionError … try again` therefore never produces a lockout.

## 6. Duration policy (D2)

`leadv2-quota-error-parse.py` handles, in order:
1. ISO-8601 (`2026-08-08T16:00Z`, `2026-08-08 16:00:00+00:00`).
2. Human absolute: `Aug 8th, 2026 8:49 AM` / `August 8, 2026 08:49` — ordinal suffixes stripped, `%b %d, %Y %I:%M %p`.
3. Relative: `in 3 hours`, `try again in 45 minutes`, `resets in 2h13m`.
4. Bare time-of-day (`8:49 AM`) → next occurrence of that time, UTC.

**Timezone:** an absolute time with no zone is interpreted as **local time** then converted to UTC — Codex prints wall-clock in the user's zone. If that assumption yields a time in the past, add 24h once; if still past, fall back to default. Record which interpretation was used in the emitted `source=` field so a wrong guess is one grep away.

**Clamps, applied after parse:**
- floor = `LEADV2_QUOTA_LOCKOUT_MINUTES` (default 30) — a parsed time nearer than the default is raised to the default. Satisfies "never shorter".
- ceiling = `LEADV2_QUOTA_LOCKOUT_MAX_MINUTES` (default 4320 = 72h) — satisfies "never absurd".
- unparsable/empty → default. `source=default`.
- parsed then clamped → `source=provider_time_clamped`.
- parsed within bounds → `source=provider_time`.

The existing `_maybe_record_quota_lockout` (launcher-refusal path) is refactored to route its duration through the same helper, passing the refusal text — so D2 improves the glm path too at zero extra cost. Its current behaviour (flat default) is preserved exactly when no time is parseable.

## 7. Latency tradeoff — explicit, and knobbed

`_wait_arm_early_verdict` costs up to `LEADV2_ARM_EARLY_VERDICT_S` (**default 20s**) of added dispatch latency on a *healthy* codex/glm spawn, because a running job never reaches a terminal state inside the window. Justification: the observed failure cost is 3+ minutes of a close gate polling a corpse plus a wasted lane. 20s is the smaller number, and the live reproduction died at t+3s so a 20s window catches it with 6× margin.

Knobs: `LEADV2_ARM_EARLY_VERDICT_S=0` disables the wait entirely (kill switch; kimi's own `LEADV2_KIMI_VERDICT_WAIT_S=60` remains honoured as an arm-specific override of the window only, preserving today's kimi timing).

## 8. Files touched

| File | Change | Size |
|---|---|---|
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | new `_arm_status_probe` / `_arm_status_state` / `_arm_final_output` / `_quota_shaped` / `_quota_return_time` / `_wait_arm_early_verdict`; `_wait_kimi_verdict` folded in as the arm=kimi branch of the state adapter; `:2472` `if arm == kimi` **removed**; `_maybe_record_quota_lockout` duration routed through the parser; new `record-quota-lockout` subcommand + dispatcher case at `:3478` | ~180 lines net |
| `plugins/leadv2/scripts/lib/leadv2-quota-error-parse.py` *(to-create)* | date/duration parser + clamps | ~90 lines |
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | in the worker-poll terminal branch (`:685` region): on `status == failed`, invoke `record-quota-lockout`; on rc0-with-lockout-written, enter `_pc_arm_advance` with `reason=arm_quota_failed` (relax its current silent-probe-only reachability) | ~35 lines |
| `plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh` *(to-create)* | the 5 mission tests + latency-knob test | ~320 lines |

**Existing files NOT touched:** `test-routing-enforcement-p1.sh` (its glm assertions must keep passing unchanged — that is the regression signal for the `_maybe_record_quota_lockout` refactor), `leadv2-router-v2.sh`, `routing.yaml`, all quota ceilings.

## 9. Test design — each must fail on HEAD

New suite `test-quota-lockout-postspawn.sh`, following `test-routing-enforcement-p1.sh`'s fake-launcher pattern (`make_refusing_glm` / `make_live_codex`). Every test exports `LEADV2_QUOTA_LOCKOUT_DIR="${TMP_ROOT}/…"` — the real `~/.claude/cache/dispatch-ledger/` is never touched.

New fixture `make_quota_dying_codex <path> <final_output_text>`: a fake `codex-task.sh` whose `task --background` exits 0 printing `task-fake-quota01 started in the background`, whose `status` prints `status: failed` after the first call, and whose log verb prints the supplied text.

| # | Test | Assertion | Why it fails on HEAD |
|---|---|---|---|
| T1 | codex job terminates `failed` with `You've hit your usage limit … try again at Aug 8th, 2026 8:49 AM.` | `${LOCKDIR}/quota-lockout-codex.json` exists; journal has `quota_lockout_recorded provider=codex … reason=postspawn_quota` | HEAD never enters a post-spawn branch for codex → no file |
| T2 | same fixture | `locked_until_epoch` is within ±90s of the parsed Aug 8 08:49 local→UTC instant, and is **> now+30min+1h** | HEAD would write now+30m if it wrote at all |
| T3 | fixture with `You've hit your usage limit.` and no time | `locked_until_epoch − now` ∈ [30min, 72h]; journal shows `source=default` | HEAD writes nothing |
| T4 | fixture with `FAILED tests/test_foo.py::test_bar — AssertionError; try again` | **no** `quota-lockout-codex.json`; no `quota_lockout_recorded` line | Vacuous-pass risk on HEAD → must also assert the job *was* observed terminal-failed (journal shows the probe ran) so the test proves the classifier said no, not that the branch is absent. Add sentinel `arm_postspawn_verdict arm=codex state=failed quota=no` |
| T5 | after T1's lockout file, run a 2nd dispatch with codex+sonnet in the chain | `quota_precheck_skip model=codex provider=codex … provider_quota_locked` **and** `worker_spawned by=router model=sonnet` | Depends on T1's write; HEAD produces no lockout so codex is re-picked |
| T6 (D3, extra) | T1's run, single-dispatch | journal shows `worker_spawned … model=sonnet` **in the same dispatch** after the codex verdict | HEAD has no post-spawn spill for codex |
| T7 (regression) | full `test-routing-enforcement-p1.sh` | unchanged pass count | guards the `_maybe_record_quota_lockout` refactor |

## 10. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **False lockout on a healthy provider** — classifier over-matches, arm is dead for 30min+ | Primary-pattern requirement (§5); T4 is the guard; `source=` in the journal makes every lockout auditable; floor is only 30min so a false positive self-heals |
| **Latency regression on every codex/glm dispatch** | §7 knob, default 20s, `=0` kill switch; documented in the emitted journal line |
| **Timezone misread inflates lockout to ~+1 day** | 72h ceiling caps blast radius; `source=provider_time` in the journal names the path; floor/ceiling both logged |
| **Adapter drift** — a launcher changes its `status` output shape | `_arm_status_state` returns `unknown` (never `failed`) for unrecognised text → degrades to today's behaviour, fails open |
| **`_arm_final_output` blocks** on a launcher that streams | Wrap every adapter call in `timeout 10` (or a bounded read); rc≠0 → empty text → no lockout |
| **Double-spill** — in-window spill AND close-gate advance both fire | The close gate's `_pc_arm_advance` one-shot marker `.arm-advanced-<AUTHOR>` (`:986`) already guards; the in-window path aborts the ledger token so no close gate was ever spawned for that arm. Verify no close gate is spawned before the verdict — **confirmed**: `spawn_product_close` runs at `:3121`, in `cmd_resolve`'s `0)` branch, strictly after `_spawn_worker_body` returns 0 |
| **Shared-tree edit** | Repo is the canonical plugin; founder authorized. No copy created in any consuming project |
| **Hardcoded arm re-introduction** | The diff must net-**remove** `arm == kimi` at `:2472`. Reviewer check: `grep -nE '(==|=~).*"(codex|glm|kimi|sonnet)"' ` on the diff — every survivor must be inside an adapter function, never inside ladder/eligibility code |

## 11. Sequencing (commit-incrementally)

1. `lib/leadv2-quota-error-parse.py` + its unit assertions. Standalone, no behaviour change.
2. Classifier + adapters + `_wait_arm_early_verdict`; replace the kimi hardcode. T1–T4, T6, T7 go green.
3. `_maybe_record_quota_lockout` duration routed through the parser. T7 re-run.
4. `record-quota-lockout` subcommand + close-gate out-of-window wiring. T5.

Phases 1–3 are self-contained; if phase 4 proves larger than budgeted, D1+D2+in-window-D3 still ship and out-of-window D3 is reported as scoped-out with this design as the follow-up spec. **It is not silently skipped either way.**

## 12. Out of scope (implementer: ignore)

- Any change to quota ceilings (glm 80/90, codex 90/95, claude 95).
- `leadv2-router-v2.sh`, `leadv2-task-judge.sh`, `leadv2-route-bandit.sh`.
- The live hand-written lockout at `~/.claude/cache/dispatch-ledger/quota-lockout-codex.json` — leave in place, never read or written by tests.
- Removing/refactoring the `codex_quota_blocked` filter at `:3090`.
- Reviewer-pool resolution, review gate, e2e gate.
- `.claude/scripts/tests/` stale-copy cleanup (separate open thread).

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >
      In the dispatch journal for a lane whose codex job died with a usage-limit
      message, a human reads a line naming provider codex, the reason
      postspawn_quota, and a lock-until timestamp of 2026-08-08 (the date the
      provider itself named) rather than half an hour from the dispatch time.
    authored_at: 2026-08-06T00:00:00Z
  - surface: file_artifact
    observable: >
      A file named quota-lockout-codex.json appears in the lockout directory
      after the failed codex job, containing the provider name, the return time
      the provider stated, and a source field saying the time came from the
      provider rather than from the flat default.
    authored_at: 2026-08-06T00:00:00Z
  - surface: log_line
    observable: >
      In the same dispatch (not a later one), after the codex verdict the
      journal shows a worker spawned on sonnet — the next arm in the chain — so
      a human reading the lane sees the work moved on instead of the lane
      sitting on a dead job.
    authored_at: 2026-08-06T00:00:00Z
  - surface: log_line
    observable: >
      For a codex job that failed on an ordinary test assertion, the journal
      shows the post-spawn verdict ran and concluded the failure was not
      quota-shaped, and no lockout-recorded line appears for codex.
    authored_at: 2026-08-06T00:00:00Z
  - surface: log_line
    observable: >
      On the next dispatch while the lockout is in effect, the journal shows
      codex being passed over for a quota lock and names the arm that was
      dispatched instead.
    authored_at: 2026-08-06T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/lib/leadv2-quota-error-parse.py, plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# CODEX-QUOTA-LOCKOUT-NEVER-FIRES-FOR-CODEX-01 — fix the quota gate

Plugin repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` — the single source. Founder ordered this
fix explicitly, so editing the plugin repo is authorized. **Never create a real copy of a
plugin-owned file inside a consuming project** — those are per-file symlinks and a copy drifts.

## What happened (live, 2026-08-06 15:17Z — this is the reproduction, not a hypothesis)

The router handed a lane to `codex` while codex had been out of quota since this morning and will
not return until Aug 8. The codex job died 3 seconds after spawn with its own message:

```
Codex error: You've hit your usage limit. ... try again at Aug 8th, 2026 8:49 AM.
```

Log: `~/.claude/plugins/data/codex-openai-codex/state/237f8026-*/jobs/task-mshnu2pl-peoman.log`.

## Three defects, all in `plugins/leadv2/scripts/leadv2-dispatch-code.sh`

### D1 (primary) — the lockout is only ever written from a *launcher refusal* branch

`_maybe_record_quota_lockout()` (`:1037`) is called only when a launcher refuses BEFORE spawning.
GLM's launcher refuses, so glm gets a lockout. **Codex's launcher accepts the job**, spawns it, and
the usage-limit error arrives later inside the codex job log — the refusal branch never runs, so
codex never gets a lockout from a real quota exhaustion. The arm ladder therefore keeps selecting
codex every single dispatch until something else writes a lockout.

Fix: detect a quota-shaped failure on the **post-spawn** path too — when a codex job reaches a
terminal `failed` state, read its final output/log, and if it is quota-shaped, record the lockout
through the same `_record_quota_lockout()` seam. Do not special-case codex textually if you can
avoid it: any provider whose failure arrives after spawn has this hole.

### D2 — the lockout duration ignores what the provider actually said

`LEADV2_QUOTA_LOCKOUT_MINUTES` (default 30) is applied flat. Codex's error names a real return time
("Aug 8th, 2026 8:49 AM"); a 30-minute lockout means the ladder re-picks a provider that will stay
dead for two more days, once every 30 minutes.

Fix: when the provider's error carries a return time, parse it and use it as `locked_until`. Fall
back to the flat default when no time can be parsed. Be conservative: an unparsable date must not
produce a lockout SHORTER than the default, and must never produce an absurd far-future lockout —
clamp to a sane maximum and log which path was taken.

### D3 — no fallback after a post-spawn provider failure

After the codex job reported `failed`, `leadv2-dispatch-product-close.sh` kept polling it for 3+
minutes rather than moving to the next arm. `candidate_chain` was `codex,sonnet` — sonnet was right
there and was never tried. Determine whether the ladder can fall back after spawn at all; if it
cannot, make it, and if that is too large for this task, say so explicitly in your return and cover
D1+D2 only. **Do not silently skip it.**

## Hard constraint on the shape of the fix

**Never hardcode an arm out of routing.** No hand-kept exclusion list, no `if arm == codex` guard.
Quota, task and complexity decide. The gate must LEARN from the provider's own error — that is the
whole point, and a hardcoded list is exactly the failure this task exists to remove.

## Tests — each must FAIL against current HEAD before your fix

1. A codex job that terminates `failed` with a quota-shaped final output ⇒ a lockout file exists
   for provider `codex` afterwards. (Fails today: no lockout is written.)
2. That lockout's `locked_until` reflects the return time named in the error, not now+30min.
3. An unparsable / absent return time ⇒ falls back to the default, never shorter, never absurd.
4. A non-quota failure (e.g. a real test failure) ⇒ NO lockout is written. Guard against the fix
   locking a healthy provider out on any ordinary error.
5. The next dispatch after a recorded lockout emits `quota_precheck_skip … provider_quota_locked`
   for that provider and resolves to the next arm.

The existing pattern to follow is in `plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh`
(around `:540`), which already asserts the glm lockout write side.

## Constraints

- Shared tree: never `git reset --hard`, `git clean`, or `git stash`.
- Do not change quota ceilings (glm 80/90, codex 90/95, claude 95).
- Commit incrementally.
- There is currently a hand-written lockout at
  `~/.claude/cache/dispatch-ledger/quota-lockout-codex.json` (until 2026-08-08T16:00Z, source
  `lead_manual:…`). Leave it in place — it is the live workaround. Your tests must use their own
  temp lockout dir (`LEADV2_QUOTA_LOCKOUT_DIR`), never the real one.

## Return

`PASS|FAIL|BLOCKED` + commit shas + all five tests shown failing-then-passing + what you did about
D3 (fixed, or scoped out with a reason) + confirmation that no arm is hardcoded in or out anywhere
in the diff.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-83c44855" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.