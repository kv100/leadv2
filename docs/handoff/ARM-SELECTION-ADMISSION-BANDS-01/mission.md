# ARM-SELECTION-ADMISSION-BANDS-01 — §4.1 of the founder's proposal, config only

Founder order 2026-09-16: apply `docs/reference/arm-selection-proposal-2026-09-16.md` immediately.
This lane implements **§4.1 Admission and pool membership** and nothing else. Read the whole
proposal first, plus `docs/reference/arm-selection-logic.md` §1-§5.

Your only write into live behaviour is `plugins/leadv2/config/leadv2-routing.yaml`.

## The mechanism you are changing, stated correctly

Do not repeat the lead's two retracted errors — both are corrected in `arm-selection-logic.md` §5
and the reasons are in the proposal's §2:

- The `+100` `complexity_penalty` is **dead code on the live path**.
  `leadv2-route-arbiter.sh:1720` sets `complexity_penalty_rules = []` whenever `FIT_MODE == 'on'`,
  and it is on (`:1697`, from `capability_fit.enabled`). Do not "fix" the penalty, do not remove the
  tags to escape it, do not cite it as a cause.
- `price_ratio` in the journals is **a loser label, not a refusal** (`:2099-2104` assigns it to every
  arm that survived every gate and merely did not win). Do not treat its count as an exclusion count.

What actually demotes glm-flash is the fit bucket: `ok.sort(key=_fit_key)` at `:2066`, where the
bucket is roughly `ceil(required_capability - capability - slack)`. `capability: 2` puts flash one
bucket down on standard work and two down on complex. That integer is the lever.

## What to change

1. **Provisional ordinary-engineering band 4** for glm-flash, alongside glm, sonnet and codex/terra.
   The proposal is explicit about what this is and is not: *"a policy correction to coarse
   eligibility, NOT a derived benchmark number or a statement of equal quality."* Say exactly that
   in the yaml comment you leave behind. Do not invent a benchmark citation.
2. **Leave codex/luna at 3 and haiku at 2.** The proposal forbids equating flash with
   untrusted/freepool behaviour, and equally forbids promoting luna/haiku on this lane's evidence.
3. **Preserve every founder-approved flash declaration**: `kinds`, `sizes`, `review`,
   `protected: true`, and the ladder entry `when: [all]` with no `untrusted:`. These came from
   `GLM-FLASH-DOES-ANY-WORK-01` (founder, 2026-09-10). Touching them is out of scope and would be a
   rollback of a founder decision.
4. **No name-based ban on complex work.** Do not add one, and do not preserve one by another name.
5. **Recon eligibility** for flash and luna where those transports genuinely support read-only
   execution. Today recon is freepool/haiku-only, which keeps the intended cheap candidates out of
   the very role they suit best. If a transport cannot do read-only execution, say so in the report
   and leave it out — do not grant eligibility you cannot justify.
6. **Routine review pools** may include sonnet, glm, terra and flash. **Do not weaken any existing
   stronger-review gate.** Where policy requires a stronger reviewer today, it still does after this
   lane. An economics change must not silently become a review-quality change; if you find yourself
   removing a constraint to make a pool work, stop and report it instead.
7. **Keep the opus build exclusion** (`kinds` without `code`). Removing it is a separate product
   decision and is not needed to promote flash.
8. **Model identity**: `:364` declares `model: opus`, which is an alias. Resolve it to the actual
   Opus 5 model id. If 4.8 is retained anywhere, it needs its own explicit versioned route and a
   recorded exception reason. A failed Opus 5 launch must never silently fall back to 4.8.
9. **Fix the lying comment at `:251`.** It states that glm-flash and freepool "remain
   `protected: false`" and are `untrusted: true` in the ladder. Both halves are false in the live
   file: the matrix row is `protected: true` and `untrusted:` was removed. The comment survived the
   change it describes. Correct it or delete it — do not leave it.

## Acceptance — against the frozen baseline

Lane `ARM-SELECTION-DECISION-FIXTURES-01` freezes the pre-change decisions and provides
`plugins/leadv2/scripts/tests/test-arm-selection-decision-fixtures-01.sh`. If it has not landed yet,
say so in the report and build your own minimal fixture rather than blocking — but reconcile against
it once it lands.

From the proposal's §6, the cases this lane owns:

1. A standard, concrete implementation task: flash is admitted and **can** win against glm under the
   documented cheaper-credit conditions. Show the fit buckets and the decisive comparator, not just
   the winner.
2. The same task with flash exhausted, cooling or reserved: an eligible alternative wins, with no
   loop and no forced quota bypass.
3. A complex, high-risk task: a suitable strong route still wins, and every mandatory risk/review
   gate is still intact.
4. `FIT_MODE=on`: the legacy `+100` is absent from the decision, and `FIT_MODE=off` behaviour is
   stated explicitly. Report the winning fit bucket and the actual decisive comparator.
9. The `opus` route resolves to a real Opus 5; any 4.8 exception is recorded with its reason and its
   availability checked; no silent alias downgrade.

**Each case needs its negative control.** For case 1 in particular: show flash winning under the
cheap-credit condition AND show it correctly losing when the task genuinely needs more capability —
a change that makes flash win everything is not the requested change, it is a different bug.

## Explicitly NOT in scope

- `scripts/lib/leadv2-route-arbiter.sh` — a sibling lane owns it. Do not edit it.
- Price numbers and cost provenance (§4.2), quota semantics (§4.3), rotation (§4.4), telemetry
  vocabulary (§5). All belong to the sibling lane.
- Any orchestration training, bandit or automatic policy learning. The founder ruled these out.

## Write set — FILES, never directories

```
plugins/leadv2/config/leadv2-routing.yaml
plugins/leadv2/scripts/tests/test-arm-selection-admission-bands-01.sh
docs/handoff/ARM-SELECTION-ADMISSION-BANDS-01/report.md
```

## Before you finish

Run the suites that guard the FILE you changed, not only the ones your change targets:
`test-leadv2-routing-config.sh` and every suite whose name mentions routing, arbiter, balancer or
effort. Report each by name with its exit code. A suite that was red before your change must be
shown red before, not silently inherited.

## ROUND 2 (lead, 2026-09-16) — the critical is real, and item 8 of this mission was worded wrongly

The fable reviewer returned `critical=1 high=1 medium=2 low=1` and blocked. The critical stands, and
the lead reproduced it directly rather than trusting the verdict:

```
$ python3 lib/leadv2-launch-registry.py --check --arm opus --model claude-opus-5
refuse
$ python3 lib/leadv2-launch-registry.py --check --arm opus --model opus
ok
```

Reviewer's summary of the rest, which the lead accepts: **"glm-flash band-4 promotion and the new
suite are fine."** That is the heart of this lane and it survives. Do not touch it in this round.

### What went wrong, and whose fault it is

Item 8 of this mission said *"resolve it to the actual Opus 5 model id"*. **That instruction was
wrong, and the lane implemented it faithfully.** The registry header states the design in its own
words: it launches every Claude-family worker with the LITERAL short name (`--model sonnet`,
`--model opus`), and the Claude CLI resolves that alias to the current model itself. The allowed set
is `{"codex", "sonnet", "opus", "fable"}` — arm-shaped names, not published model ids. So
`model: opus` in `capability_matrix` is not an alias left lying around by accident; it is the argv
the launcher is required to emit. Renaming the cell made every arbiter-selected opus spawn refuse,
and dropped opus from the spawn gate's speakable pool.

The proposal's actual requirement (§2 correction 6) is about **effective identity, not naming**:
"Confirm actual launched Opus5; do not infer its version from the arm label. Historical 4.8 must be
an explicit separately recorded choice." That is a verification and telemetry job.

### What round 2 must deliver

1. **Revert the cell to `model: opus`.** Restore the exact prior value so
   `--check --arm opus --model opus` returns `ok` and the speakable pool contains opus again. Prove
   it with both registry invocations in the report.
2. **Satisfy the real requirement instead of the mis-worded one.** Record, at spawn time, which
   model the `opus` alias actually resolved to, so the answer comes from the running process rather
   than from the routing label. If the launcher already surfaces the resolved model, log it into the
   dispatch journal beside the arm; if it does not, say so plainly in the report and do not invent a
   value. `plugins/leadv2/scripts/lib/leadv2-launch-registry.py` is added to your write set for this
   and for nothing else.
3. **The 4.8 question.** Confirm by grep whether any opus-4.8 route exists anywhere. The round-1
   report claims none does. If that holds, state it as a measured fact with the command; if a route
   does exist, it needs an explicit versioned entry and a recorded exception reason, never a silent
   fallback from a failed 5.
4. **Address the high, the two mediums and the low** from `docs/handoff/dispatch-650ec59b-review/critic.full.md`.
   Take each on its merits: fix it, or decline it in the report with a reason. Do not fix a finding
   you disagree with just to clear the gate.

### Acceptance

- Both registry checks above, pasted with their real output.
- The lane's own suite `test-arm-selection-admission-bands-01.sh` green, and the parts the reviewer
  already blessed (glm-flash band 4, the suite itself) unchanged.
- `test-spawn-speakable-pool.sh` and `test-launch-registry-argv.sh` run and reported by name with
  exit codes — those two guard exactly what round 1 broke.
- The fixtures baseline suite reconciled: say which decisions moved and why. A band promotion is
  SUPPOSED to move decisions; an unexplained one is a defect.

### Still explicitly out of scope

`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — the sibling lane owns it and is mid-round-2
there right now. Do not touch it.

## ROUND 3 (lead, 2026-09-16) — the merge landed a green-to-red suite. Two assertions, no behaviour change.

Round 2 is otherwise accepted. The critical is genuinely fixed and the lead verified it on main after
the merge, not from the report:

```
$ grep -n "arm: opus, provider: claude, model:" plugins/leadv2/config/leadv2-routing.yaml
421:    - { arm: opus, provider: claude, model: opus, ... }
$ python3 plugins/leadv2/scripts/lib/leadv2-launch-registry.py --check --arm opus --model opus
ok
```

`test-arm-selection-admission-bands-01.sh` is 32/0 on main. That part is done.

### What was missed, and it is the lead's finding not the reviewer's

`plugins/leadv2/scripts/tests/test-spawn-speakable-pool.sh` was **green before this merge and is red
after it**. Paired by the lead in a detached worktree at the pre-merge commit `c5d425a4`:

| | pre-merge `c5d425a4` | main after merge `9d496bdb` |
|---|---|---|
| `test-spawn-speakable-pool.sh` | rc=0, pass=26 fail=0 | rc=1, pass=24 fail=2 |

It is NOT in the lane's `pre_existing_red` list, and correctly so — it was not red before. The e2e
gate only ever names suites that were already red; a suite this lane turned red is invisible to it.
That is exactly the shape a lane must catch itself.

The two failures:

```
FAIL: D2 tokens missing: arm=refuse ... reason=pool_empty_all_excluded kind=recon ...
FAIL: H2 mutation did not reproduce the defect: arm=glm-flash kind=recon model=glm-5.3-flash
      tier=standard effort=low reason=cheapest_capable chain=glm-flash,co...
```

### Both have one cause, and the behaviour is CORRECT

The suite hardcodes the pre-change recon membership:

- `:99` — D2 asserts the exclusion list is exactly
  `arm_excluded=freepool:not_in_pool,haiku:not_in_pool`. Recon used to be freepool/haiku-only. Item 5
  of this mission deliberately added flash and luna, so the list legitimately grew.
- `:151` — H2 asserts that after the mutation strips the speakable filter, **freepool** answers the
  recon auction. Flash answers now instead, at `cost 0.33` against freepool's `1.0`, by
  `cheapest_capable`. The mutation still bites; only the name of the arm that bites changed.

The report at lines 38-40 says the bare-spawn gate's hardcoded pool
(`hooks/leadv2-spawn-arbiter-gate.sh:62`) is unchanged, and that is true. What it missed is that this
suite's D and H cases drive the **arbiter's** recon auction, not the hook's list, and that auction did
change by design.

So do **not** revert the recon eligibility. This round updates two assertions and nothing else.

### What round 3 must deliver

1. **D2** — assert the real post-change exclusion list. Produce it from an actual run rather than by
   editing the string by hand, and leave a one-line comment saying recon membership grew by founder
   proposal §4.1 item 5 on 2026-09-16, so the next reader does not "fix" it back.
2. **H2** — keep the negative control discriminating. Its point is that with the speakable filter
   stripped, an arm from OUTSIDE the speakable set `{sonnet, opus, haiku, fable}` answers. Assert
   that property, and additionally name the arm you currently expect, so a silent membership change
   still fails the case instead of passing on a weakened predicate. A control that now accepts any
   arm at all is worse than the red you are clearing.
3. **H0 must stay exactly as it is** — it asserts `arm=haiku` for the unmutated in-pool auction and it
   passes. If your change to H2 makes H0 pass for a new reason, you have broken the pair.
4. **Sweep for other green-to-red suites from this merge.** Pair every suite whose name mentions
   routing, arbiter, spawn, pool, recon or capability against the pre-merge commit `c5d425a4` the same
   way the lead did — a detached worktree, never a reset or a stash in this checkout, five sessions
   share the index. Report a table with both columns. If another one moved, say so; fix it only if it
   has the same suite-is-stale cause, and escalate rather than fix if it is a real behaviour defect.

### Acceptance

- `test-spawn-speakable-pool.sh` green, with the pre/post table in the report showing 26/0 before,
  red at 24/2 after the merge, and green again after this round with the case count stated.
- `test-arm-selection-admission-bands-01.sh` still 32/0 — untouched.
- The negative control proven, not asserted: restore the speakable filter and show H2 goes red again.
- The green-to-red sweep table, with the paired commit named.

### Out of scope

`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — the sibling lane `dacaf22f` is live in it right
now. Do not touch it. No config changes: `leadv2-routing.yaml` is correct as merged.

### Write set

```
plugins/leadv2/scripts/tests/test-spawn-speakable-pool.sh
docs/handoff/ARM-SELECTION-ADMISSION-BANDS-01/report.md
```
