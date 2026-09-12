# 429-METER-VERDICT-01 — evidence pack (lane bd7f811eb05c)

## What this lane found, and what it did

The brief described round 1 as "ran out of turns mid-edit, left the tree
regressed, both files reverted to HEAD". On arrival the tree was indeed clean —
but HEAD already contained the fix: commit **b7469eff** (`fix(profile-select):
a meter 429 is not a credential verdict; rank from last-known sidecar`), landed
2026-09-12 15:46 by the recovered lane. The mid-edit mess the brief describes
was a further edit on top of that commit, already reverted before dispatch.

So this lane's work became: **audit the landed fix against the brief, and
produce the evidence the fix's round never left behind** — the 1–4 chain
reproduction, before/after selector output, and a declared negative control per
half, actually run, RED. No code was changed by this lane; the diff is this
evidence pack only. `leadv2-quota-read.py` is untouched by b7469eff and by this
lane (verified: not in its stat, compiles clean).

Audit result — both halves are correctly implemented on HEAD:

- **Half one** (positive list): `leadv2-claude-profile-select.sh` classifies a
  completed probe as `ok` / `verdict` / `-`. `verdict` — the only outcome that
  writes a `probe-cooldown-until` marker — requires http 401/403 or an error
  naming expired/revoked/malformed/invalid/unauthorized/forbidden, minus the
  `account_state=unmetered` carve-out. A 429 and every unrecognized shape land
  on `-` (unmeasurable): no cooldown, the profile stays a live candidate.
- **Half two** (rank from last known): `write_last_ok` keeps the newest
  status=ok payload per identity in `anthropic-last-ok.json` (sidecar beside
  `anthropic.json`, same convention as `probe-cooldown-until.cred`). An
  unmeasurable read attaches it as picker columns 8/9; with NO record
  live-readable the picker re-ranks from those numbers as `source=stale
  reason=last_known` plus `stale_age_s=`, and the selector journals
  `degradation=stale_last_known age_s=N`. `leadv2-claude-profile-status.sh`
  surfaces a dedicated `stale:` line. Composition with 154b2cbe: a stale gap
  beyond `LEADV2_CLAUDE_DEMOTE_YIELD_MARGIN` yields (T33/T34), and a
  stale-but-known demoted slot vs a fresh nothing yields via
  `yield_reason=no_known_normal` (T35).

## The live 429 had cleared — fixtures, not assumption

At lane start both identity caches read `status:"ok", http:200`
(`fetched_at 2026-09-12T20:12:14Z/15Z`; personal max_20x seven_day 4%,
work Team/5x seven_day 81%). Per the brief, the reproduction below is
fixture-built: the exact payload shape the quota layer writes on a throttled
meter, driven through the **pre-fix binaries** (`git archive b7469eff^`) and
the **HEAD binaries**, hermetically (stub probe, fixture registry, no network,
no keychain). Script: `repro-429-chain.sh` beside this report.

## Reproduction of the measured chain, steps 1–4 (BEFORE = b7469eff^)

Step 1 — the meter 429s for both identities (payload on both labels):

```
{"provider":"anthropic","status":"unknown","accounts":[{..."http":429,..."status":"unknown",
 "account_state":"unknown","error":"429 rate_limited (reported as unknown, NEVER 0)",
 "five_hour":null,"seven_day":null,"binding_window":null}],...}
```

Step 2 — pre-fix treats it as a CONFIRMED live failure, cools BOTH 900s in the
same second (identical `until=`, shared cause):

```
WARN: profile label=personal live probe failed; cooling down 900s (reason=confirmed_live_failure cred=a22885580535 until=1789245756)
WARN: profile label=work live probe failed; cooling down 900s (reason=confirmed_live_failure cred=985b68e26038 until=1789245756)
cache/identity-max_personal_fixture_test/probe-cooldown-until=1789245756
cache/identity-team_work_fixture_test/probe-cooldown-until=1789245756
```

Step 3 — both cooled → every probe skipped → `completed==0` → the selector
refuses, and status reports DEGRADED:

```
stdout: profile=- reason=single_profile (rc=0)
live:    DEGRADED -- fell back (single_profile): profile=- reason=single_profile
```

Step 4 — cooldowns cleared by hand; the 429 recurs instantly (markers back at
:57), and with two candidates and no numbers the picker falls to
`rank_by=none` where self-slot demotion decides — picking the 81% account:

```
stdout: profile=work ... rank_by=none consumed_pct=- usable_now=- source=unknown
        reason=all_unknown candidates=2 ... demoted=personal
```

Exactly backwards, as measured live on 2026-09-12.

## AFTER (HEAD) — same fixtures, sidecars seeded by a healthy earlier round

```
stdout: profile=personal ... rank_by=usable_now_max consumed_pct=4 usable_now=0.630
        source=stale reason=last_known candidates=2 ... demoted=personal
        demote_yielded=personal margin=0.15 stale_age_s=3
WARN: profile label=personal live quota read unmeasurable; ranking from last-known payload (degradation=stale_last_known age_s=3)
WARN: profile label=work live quota read unmeasurable; ranking from last-known payload (degradation=stale_last_known age_s=3)
-- cooldown markers after the 429 round (must be none): (none)
stale:   last-known ranking in effect (age=3s) -- the winning account's numbers are NOT live; its meter read failed
```

No `single_profile`, no `rank_by=none`: the 429 accounts stay candidates, the
pick is the 4% account ranked from its last-known numbers, explicitly labeled
stale with an age, never mistaken for live.

Live path (real registry, real probes, 2026-09-12 ~23:30 local):

```
profile=personal ... rank_by=usable_now_max consumed_pct=4 usable_now=0.660 source=live
        reason=binding_window candidates=2 ... demoted=personal demote_yielded=personal margin=0.15
live: OK -- ... candidates=2
```

`leadv2-claude-profile-status.sh` live verdict still says DEGRADED — from the
RECENT axis only (`recent: DEGRADED -- 5/50`), whose newest offending record is
dated 2026-09-11T18:46Z, i.e. the incident's residue in dispatch history, not
a live regression.

## Negative controls — one per half, run, RED

Both via `plugins/leadv2/scripts/leadv2-mutation-control.sh` (worker mode:
scratch snapshot of HEAD + the two declared files, other lanes' 362 dirty files
excluded), `LEADV2_LANE_START_SHA=b7469eff^`, artifacts in
`mutation-control/` beside this report.

**Control A — half one.** Anchor asserted `count == 1` before replacing:
`if code in ("401", "403") or "http 401" in err` → grep -cF = 1.
Mutation: `("401", "403")` → `("401", "403", "429")` — a throttled meter
readmitted as a credential verdict. Artifact
`mutation-control/20260912T203041Z-59791.txt`: `baseline_rc=0`, **`mutated_rc=1`**.
Failing tests when the same mutant is applied to an identical scratch tree
(`git archive HEAD` + same sed), suite `test-claude-profile-select.sh`
152/0 → **144/8**: T29b/T29d/T29e (a 429 must not cool, must not skip a round,
must not write a marker) plus the cascade T33a/b/c, T34a, T35a (the cooldowns
destroy the stale round's fixtures).

**Control B — half two.** Anchor asserted `count == 1` before replacing:
`if _src == "live":` → grep -cF = 1. Mutation: → `if False:` — the picker never
re-ranks from the last-known sidecar. Artifact
`mutation-control/20260912T203310Z-94132.txt`: `baseline_rc=0`,
**`mutated_rc=1`**. Same-mutant scratch run, 152/0 → **149/3**: exactly
T33a/T34a/T35a — the stale-ranking trio — and nothing else (the selector-side
journal line T33b stays green because only the picker was mutated).

## Suites (all isolated foreground runs)

| Suite | Count | Note |
|---|---|---|
| test-claude-profile-select.sh | **152/0** | baseline in brief was 122/0; b7469eff added 30, all green |
| test-balancer-ranks-by-usable-now.sh | 18/0 | matches brief |
| test-profile-select-skips-exhausted.sh | all checks PASS, rc=0 | per-check format, no PASS= summary |
| test-claude-profile-requested.sh | "All checks passed", rc=0 | idem |
| test-account-switch.sh | 14/25 | pre-existing: identical at b7469eff^ and at HEAD; account-switch machinery, not the 429 path |
| test-balancer-every-arm.sh | 17/5 | pre-existing: identical at b7469eff^ and at HEAD; 5 failures are S6 spawn/reservation mechanics, not picker ranking |
| test-interactive-session-switch.sh | 34/26 | pre-existing: identical at b7469eff^ and at HEAD |
| test-claude-account-check.sh | 24/0 | green |
| test-quota-read-anthropic-liveness.sh | all green | quota-read.py 429 handling untouched, still correct |
| test-quota-identity-report.sh | 1 check red | pre-existing; asserts a byte-exact "no-opt-in first line" whose live numbers moved — unrelated to the 429 path |
| test-quota-weekly-total.sh | 13/0 | green |
| test-codex-quota-gate / -guardrails / test-provider-quota-gate / test-quota-daemon / -lockout-postspawn / -model-tier-granularity / -reset-arbiter / -standdown-duration | rc=0 each | non-PASS= summary formats, exit 0 |
| test-quota-glm-filter.sh | 8/0 isolated | printed 7/1 ONCE while running concurrently with another suite batch — reproducibly 8/0 in isolation at HEAD and at b7469eff (concurrency flake, not a regression) |

Attribution method for the pre-existing reds: `git archive` of b7469eff^
(pre-fix) and of HEAD, suites run in both, byte-identical counts → the 429 fix
did not cause them.

## Falsification set (this lane's own files + audited HEAD files)

```
bash -n: OK leadv2-claude-profile-select.sh, OK leadv2-claude-profile-status.sh, OK repro-429-chain.sh
python3 -m py_compile: OK lib/leadv2-claude-profile-pick.py, OK leadv2-quota-read.py
```

## Files changed by this lane

None in code. `docs/handoff/bd7f811eb05c/`: this report,
`repro-429-chain.sh`, `mutation-control/20260912T203041Z-59791.txt` (control A),
`mutation-control/20260912T203310Z-94132.txt` (control B).
