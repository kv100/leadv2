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
