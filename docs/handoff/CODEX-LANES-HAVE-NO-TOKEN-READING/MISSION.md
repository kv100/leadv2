# CODEX-LANES-PRODUCE-NO-TOKEN-READING-01

## Why pricing has not happened, measured

The join key between an estimate and its actual landed on 2026-09-14 and works. It did not unblock
pricing, and waiting will not unblock it either, because there is almost nothing to join:

```text
cost_actual rows:  tokens=-  54      tokens=<number>  1
```

One real token reading in the entire corpus. The single exception is `f8880421`.

The mechanism is a perfect correlation across every dispatch directory on disk:

```text
sig       arm      docs/handoff/dispatch-<sig>/costs.yaml
238dd210  sonnet   YES
f8880421  sonnet   YES
0a148de1  codex    no
2380dda8  codex    no
2511fd31  codex    no
4e2676a0  codex    no
569642dd  codex    no
856ba7d5  codex    no
e33f2050  codex    no
f15a2c7f  codex    no
```

2 of 2 Claude-armed lanes have `costs.yaml`; 0 of 8 codex lanes do. `leadv2_lane_token_total`
reads that file (and the burn `turn_events` fallback), so a codex lane returns `-` every time.
The reason is upstream: `claude-subsession.sh` writes the `.cost-pending.yaml` marker that
`leadv2-cost-flush.sh` later turns into `costs.yaml`. The codex launcher has no equivalent seam.

Codex is the arm most of our work runs on. So the corpus grows in rows and stays at one usable
pair — pricing per provider cannot be derived for the provider we use most, ever, on this path.

## What to build

1. **A token reading for a codex lane.** Find where codex's own run records its usage — its rollout
   files under `~/.codex/sessions/<date>/rollout-*.jsonl` are the known artifact, and the dispatcher
   already resolves one per attempt (`arm_dead_instant_complete_ambiguous_rollout … picked=<path>`).
   Establish whether a usable input/output token count exists there. If it does, write the same
   `costs.yaml` the Claude path writes, so `leadv2_lane_token_total` needs no change.
   If it does NOT, say so with the probe and stop at that finding — do not synthesise a number.
2. **Make the gap visible instead of silent.** `tokens=-` currently covers both "this arm has no
   telemetry seam" and "the seam exists but found nothing". Split them, the way the judge's
   fallback reasons are being split in a sibling lane: record WHY the token total is unknown
   (`no_seam_for_arm` / `costs_yaml_absent` / `turn_events_empty` / `parse_failed`).
3. **Then report what pricing becomes possible.** With codex readings flowing, state how many
   joined pairs exist per provider and whether a per-provider fit is yet defensible. If it is not
   yet, give the number of pairs and the number needed — a date is not an answer, a threshold is.

## Method — binding

- The correlation above is 10 rows. Widen it before you build: count every `dispatch-*/costs.yaml`
  against the arm recorded in its journal, and report the real ratio. If a codex lane with a
  `costs.yaml` exists, the premise is wrong and the whole mission changes — look for that case first.
- Name the surface of every count (this whole thread of work exists because a count was taken from
  the wrong surface twice).
- Negative control by mutation inside the function body; strip comments when grepping.

## Acceptance

1. A codex lane produces a real token total — shown on a live lane, not a fixture.
2. `tokens=-` is replaced by a named reason wherever the total is genuinely unknown.
3. The joined-pair count per provider, with the threshold needed for a defensible fit.
4. Still green: `test-launcher-refusal-event.sh`, `test-arbiter-decision-record-inputs.sh`,
   `test-reset-urgency.sh`, `test-leadv2-task-judge.sh`, `test-arbiter-prices-by-provider.sh`.
5. New suites registered so `tests/run-all.sh --scope changed` SELECTS them; commit first, then
   show the selection output.

## Off limits

- `leadv2_lane_token_total`'s existing Claude path — it works; extend, do not rewrite.
- `reset_urgency`, `provider_cost`, decision-record schema v2, the launcher-refusal event — landed.
- `docs/tasks.yaml`, `docs/leadv2/open-threads.md` — lead-owned.
