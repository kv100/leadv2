# THE-KNOWN-RED-REGISTRY-ROTTED-AND-EVERY-LANE-PAYS-01

Founder, 2026-09-14: *«e2e давай все таки починим. это важно достаточно»*.

**The cause is already found. Do not spend a round re-deriving it — go straight to the decision.**

## What is actually broken

The tolerance mechanism **exists and works correctly**: `tests/known-red-suites.txt` makes
`run-core-offline.sh` SKIP the suites it lists. The list is a **snapshot taken 2026-09-02 with 14
entries**. Measured today on `~/Projects/leadv2` main:

```
[CORE-OFFLINE] suites passed=66 failed=27 missing=0 known_red_skipped=0
```

**27 red, 14 registered.** Thirteen suites went red after the snapshot and nobody added them. Among
the unregistered is `test-review-gate-shows-findings.sh`, which killed at least two lanes today and
had been red before they started.

The amplifier is documented in the registry's own header: *«`tests/run-all.sh --scope changed`
ALWAYS runs the full `run-core-offline.sh` set regardless of scope»*. So **one red suite anywhere
fails the e2e gate of EVERY lane**, including lanes that never touched it.

Proof on a real corpse — `docs/handoff/dispatch-ac05bfde/e2e-gate.md`:

```
status: fail
reason: e2e_regression
rc: 1
scope: whole_tree_fallback
failing_suites: plugins/leadv2/scripts/tests/run-core-offline.sh,
                plugins/leadv2/scripts/tests/test-review-gate-shows-findings.sh
run-all: 3 passed, 2 failed, scope=changed
```

**The price, measured 2026-09-14:** six lanes, six terminal states, **zero self-landed** —
`e2e_regression` x3, `e2e_timeout`, `dirty_lane`, `review_verdict_fail`. Every one of the six had a
green suite of its own. All six were verified and landed by hand by the lead.

## What to build — two halves, the second is not optional

1. **Bring the registry into agreement with fact.**
2. **Make it impossible for the registry to rot SILENTLY again.** A dated snapshot that diverges
   from reality without saying so is precisely the failure class this repo spent today hunting. A
   refresh that leaves the rot mechanism intact is not a fix — it just resets the clock.

## The danger — name it, do not walk into it

**Blindly appending thirteen lines HIDES whichever of them are genuine regressions introduced since
2026-09-02.** That would convert a noisy gate into a silent one, which is strictly worse.

Therefore: every entry you add carries a **date and a reason**, and the by-name list of reds stays
tracked in `docs/leadv2/scheduled-decisions.md` under `SD-MAIN-CORE-SUITE-RED-01` (the lead appended
today's full 27 names there). The registry suppresses noise; it must never become the place where
breakage goes to be forgotten.

## Measurement boundary — do not exceed it

The 27 were measured **on macOS**. A sibling row (`a54dcb736315`) establishes that twelve suites are
green on macOS and red on Linux. This row is about **lane deaths, which happen on macOS**, so Linux
is out of its perimeter — but do NOT carry the number "27" over to Linux, and do not claim anything
about CI from this measurement. Reproduce with:
`bash plugins/leadv2/scripts/tests/run-core-offline.sh | tail -1`

## Acceptance

1. A fresh `run-core-offline.sh` reports `known_red_skipped>0`, and `failed` equals the number of
   reds **not** in the registry. Show the summary line verbatim, before and after.
2. **Negative control, run it:** registering a suite that is actually GREEN must NOT silently
   suppress it — the run has to notice and refuse. Without this the registry is a mute button.
3. A suite proving **rot is detectable**: a registry entry naming a suite that no longer exists, or
   a snapshot that disagrees with the live result, produces a visible refusal rather than silence.
4. New suite registered so `tests/run-all.sh --scope changed` SELECTS it.

## Method — binding

- Report the summary line verbatim for every claim; name the surface of every count.
- Run the negative control. A tolerance mechanism you cannot demonstrate refusing is a mute button.

## Off limits

- **Do not repair the 27 suites themselves** — that is `SD-MAIN-CORE-SUITE-RED-01` and needs a Linux
  split first. You are fixing the gate's blast radius, not the suites.
- `capability` numbers · `router_v2.cost` · the think tiering · the reviewer-choice policy (all
  landed today).
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
