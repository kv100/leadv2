# CONTROL-PLANE-REVIEW-01 / M1 — the balancer and the quota layer

READ FIRST: `docs/handoff/CONTROL-PLANE-REVIEW-01/seed-facts.md`. Facts S1, S4,
S5 are yours. They are measured — cite them, do not re-measure them.

Repo: `leadv2`. **READ-ONLY review.** You write findings, not fixes. Your only
write target is `docs/handoff/CONTROL-PLANE-REVIEW-01/f1-balancer.md`.

## Subject

`plugins/leadv2/scripts/leadv2-claude-profile-select.sh`,
`plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py`,
`plugins/leadv2/scripts/leadv2-quota-read.py`,
`plugins/leadv2/scripts/leadv2-quota-daemon.py`,
`plugins/leadv2/scripts/lib/leadv2-quota-shape.py`,
`plugins/leadv2/scripts/leadv2-provider-quota-gate.sh`,
and `plugins/leadv2/config/model-capability.yaml` where it describes buckets.

## The question the founder is actually asking

He said: "fable тот же бакет что и все другие модели антропик + у него свой
бакет" — and then: "не верно у тебя тут, и в балансировщике тоже могут быть
ошибки". So: **does this layer's model of quota match what the API actually
returns?** Fact S1 shows one place it does not. Find the others, or prove there
are none.

Specifically, answer each with `file:line`:

1. **Two-bucket arithmetic.** An Anthropic account returns both `weekly_all`
   (shared) and `weekly_scoped` (per-model, e.g. Fable). Does the balancer's
   score treat a model-scoped limit as a constraint AT ALL, or does it only read
   the shared one? If a scoped bucket is exhausted while the shared one is free,
   what does the picker return — and is that right?

2. **Direction of the score.** S4: it printed `score=67` and chose the profile
   with the higher consumed percentage, demoting the one at 56. Trace the
   comparison. Is the ranking correct on `usable_now` grounds, and does the log
   line state which direction is better? A number whose direction a reader
   cannot infer is a defect even when the ranking is right.

3. **The unreadable bound account.** S5: `active_account` is the entry that
   returns 429 with every window `null`. What does the balancer do when the
   account it is actually bound to is the one it cannot read? Does `candidates=2`
   silently exclude it, and is exclusion the correct behaviour or a blind spot?

4. **Cache freshness.** S5: `fetched_at` was ~34 minutes old and served without
   the caller asking for cached data. Find the TTL, find whether any caller can
   demand fresh, and say whether a stale read can cause a wrong pick.

5. **Aggregate honesty.** Top-level `binding_window: null` while every account
   reports `seven_day`. Which consumer reads the top-level field, and what does
   it do with a null?

## Rules

- Every finding: `file:line`, the mechanism in one sentence, and a concrete
  failure scenario (inputs → wrong outcome). No "could be improved".
- A thing you checked and found SOUND is a finding too — say so explicitly with
  the line you read. A silent omission reads as "not checked".
- Do not propose a fix longer than two sentences. Fixes are a separate lane.
- `usable_now` already exists and already encodes reset-time weighting. Read it
  before claiming the picker ignores time.
- NEVER "fix" the 429-to-null refusal into a 0. That refusal is correct and was
  built deliberately (`"reported as unknown, NEVER 0"`).
- You may not write to `~/.claude/leadv2-state/` or to `~/.claude/settings.json`.
