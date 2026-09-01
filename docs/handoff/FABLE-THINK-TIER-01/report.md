# FABLE-THINK-TIER-01 — round 2 report

Fixes the two HIGH findings from round-1 review (reviewer glm):

1. **Invariant was false in-tree** — ≥8 think-role sites still spawned with a literal
   `opus`, and the suite's grep-gate covered only the 4 migrated workflows.
   → Round 2 ran its own census (below), migrated EVERY think-role site to the
   `think-model` resolver, and made the grep-gate tree-wide (the census command itself
   runs in `test-fable-think-tier.sh`, expecting zero unclassified `opus` literals).
2. **External-system claims drove code with no evidence** — round-2 PROBED the claims
   instead of asserting them. Result: the "same Claude Max bucket as Opus" claim is
   **WITHDRAWN** (probe could not confirm it; the live reader shows a separate
   Fable-scoped weekly window), `context_k: 1000` is **UNVERIFIED** and reverted, and
   Fable now carries its own bucket entry (`cost_class: fable-scoped-weekly`).

## Round 2 evidence

### Census (2026-09-01, this worktree)

Command (now also enforced tree-wide by the suite's grep-gate):

```
grep -rnE "model[=: ]+['\"]?opus|--model[ =]['\"]?opus" \
  plugins/leadv2/{scripts,workflows,skills,hooks}
grep -rnE "(subagent_type|agentType)[\"'= :]+[^,)]*(architect|critic|judge)" \
  plugins/leadv2/{scripts,workflows,skills,hooks}   # + opus on same line
```

Raw hits and classification (think-role → migrated / build-role+fallback → allowed /
telemetry / prose):

| Hit | Class | Action |
|---|---|---|
| `scripts/leadv2-llm-judge.sh:391` `model="opus"` (+ `:413 \|\| echo "opus"`) | think-role (judge default) | **migrated** → `think-model` resolver, fallback literal `fable` |
| `scripts/leadv2-fanout-classify.sh:126` `LEAD_MODEL="opus"` (Heavy/Strategic child lead) | think-role | **migrated** → resolver |
| `scripts/leadv2-fanout.sh:473` python `fallback_model = "opus" ...` + crash path `:516 "opus"` | think-role fallback | **migrated** → `think_model` var resolved once via resolver |
| `scripts/leadv2-fanout.sh:195` help text "opus for Heavy/Strategic" | prose (describes the pin above) | **updated** to describe resolver |
| `hooks/leadv2-routing-guard.sh:470,476` `Agent(%s, model=opus)` advisory | think-role (drives spawn advice) | **migrated** (resolver wording; see write-set note) |
| `skills/leadv2-judge/SKILL.md:7` frontmatter `model: opus` | think-role | **migrated** → `model: fable` + resolver note |
| `skills/leadv2-plan/SKILL.md:345` critic `model: opus,` | think-role | **migrated** → `model: fable` + resolver note |
| `skills/leadv2-po-feedback-loop/SKILL.md:42` architect `model="opus"` | think-role | **migrated** → resolver wording |
| `skills/leadv2-review/SKILL.md:223` `--model opus` (architect escape) | think-role | **migrated** → `--model "$(leadv2-router.sh think-model)"` |
| `skills/leadv2-diverge/PHASES.md:56` `model=<opus if Heavy/Strategic else sonnet>` | think-role | **migrated** (resolver wording; write-set note) |
| `skills/leadv2-recovery/EXAMPLES.md:24` architect `model: opus,` | think-role | **migrated** (write-set note) |
| `skills/leadv2-review/ref/manual-dispatch-cases.md:21,28` critic `model=opus` | think-role | **migrated** (write-set note) |
| `skills/leadv2-review/ref/architect-escape-mission.md:21` `--model opus` | think-role | **migrated** (write-set note) |
| `skills/leadv2-token-discipline/EXAMPLES.md:13` `model:'opus'` guidance | prose teaching a pin | **migrated** → resolver wording (write-set note) |
| `skills/leadv2-llm-judge/PROMPT.md:12` `model: <from router>` | think-role, already resolver-based | no change |
| `scripts/leadv2-dispatch-code.sh:7013-7015` `route_resolved ... model=opus` emit/log | route telemetry (describes a router decision; "requires_lead_judgment; not auto-dispatched") | allowed, kept |
| `skills/leadv2-plan/SKILL.md:268` architect `model: sonnet` | build-role per matrix (Standard architect cross-check: "architect(sonnet, never opus)") | allowed, kept |
| `workflows/leadv2-diverge.js:127`, `leadv2-po-feedback-loop.js:169` `model: 'opus'` on fallback-labelled retry arms | explicit fallback sites | allowed, kept |
| `hooks/leadv2-model-inherit-guard.sh:46` "opus is reserved for high-judgment agents" | guard prose (the hook ENFORCES tiering) | allowed, kept |
| comments: `leadv2-fanout-classify.sh:15`, `leadv2-main-model-check.sh:6`, `leadv2-router.sh:446`, `leadv2-ask.sh:505`, `claude-subsession.sh:842` | prose/comments | allowed |
| tests (`scripts/tests/*`) `opus` fixtures | test fixtures | excluded from gate by design |

**Write-set note:** the 12 migrated sites marked "(write-set note)" sit outside
LANE_WRITES (hooks/*.sh, skills/**/{PHASES,EXAMPLES}.md, skills/**/ref/*.md).
Expansion was requested via the async question channel (qid q-392fa4b8, default a =
expand, reversible via git revert of the lane commit) because the reviewer's HIGH
finding requires migrating EVERY think-role site; the suite's tree-wide gate is RED
on those sites until they are migrated, so "document the gap" (option b) would leave
a red suite — the reviewer explicitly demanded a green tree-wide gate.

### Quota-read probe (bucket claim) — 2026-09-01

**Before** — `python3 plugins/leadv2/scripts/leadv2-quota-read.py anthropic --no-cache`
`fetched_at: 2026-09-01T21:02:03Z` (active account `max_20x`, tier
`default_claude_max_20x`):

```
max_20x: five_hour_pct=31 seven_day_pct=6
  limits: session pct=31 active=true | weekly_all pct=6 active=false
          weekly_scoped pct=7 active=false scope={"model":{"display_name":"Fable"}}
max_5x:  five_hour_pct=29 seven_day_pct=2 (active=false, same Fable weekly_scoped window at 0)
```

**Probe** — `claude -p --model claude-fable-5-1 'say ok'` → rc=0 (Fable 5.1 accepted on
this plan; NOT refused).

**After** — same reader, `fetched_at: 2026-09-01T21:03:17Z`:

```
max_20x: five_hour_pct=31 seven_day_pct=6   (unchanged)
  weekly_scoped pct=7 scope={"model":{"display_name":"Fable"}}  (unchanged)
max_5x:  five_hour_pct=30 (inactive account)
```

**Verdict:** the five-hour window did NOT move across the probe, and the reader
exposes a model-scoped `weekly_scoped` window for Fable that is distinct from
`weekly_all` — the "same Claude Max bucket as Opus" claim is UNPROVEN. Per the round-2
directive: Fable gets its OWN bucket entry (`cost_class: fable-scoped-weekly` in
`model-capability.yaml`), `context_k` reverted to `unverified`, and
`glm-policy-resolve.py` keeps fable on the anthropic ACCOUNT reading only as the
conservative ceiling (its comment now says so; the same-bucket claim is gone).

**evidence: model ids** — Claude Code environment banner, verbatim: "Model IDs —
Fable 5.1: 'claude-fable-5-1', Opus 5: 'claude-opus-5', Sonnet 5:
'claude-sonnet-5', Haiku 4.5: 'claude-haiku-4-5-20251001'", cross-confirmed by the
probe above (`--model claude-fable-5-1` accepted).

### Mutation negative control (tree-wide gate)

Re-inserted a live think-role pin into `workflows/leadv2-learn.js` (a file NOT yet
touched this round):

```js
const MUTATION_OPUS_PIN = { model: 'opus' } // NEGATIVE-CONTROL mutation, do not keep
```

Gate output (red), mutation then reverted (file back to committed state, `git diff`
clean):

```
FAIL: tree-wide census: unclassified 'opus' literal(s): .../workflows/leadv2-learn.js:24:const MUTATION_OPUS_PIN = { model: 'opus' } // NEGATIVE-CONTROL mutation, do not keep
PASS=14 FAIL=1
```

### Suite green after all migrations

`LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-fable-think-tier.sh`:

```
PASS: resolver default = fable
PASS: resolver LEADV2_THINK_MODEL=opus override wins (negative control)
PASS: resolver falls back to opus when fable marked unavailable
PASS: tree-wide census: zero live think-role 'opus' spawn pins
PASS: leadv2-diverge: THINK_MODEL const present
PASS: leadv2-learn: THINK_MODEL const present
PASS: leadv2-diagnose: THINK_MODEL const present
PASS: leadv2-po-feedback-loop: THINK_MODEL const present
PASS: zero opus-4 literals under plugins/leadv2/{scripts,config,ref,workflows,hooks}
PASS: pool orders fable before opus (codex:blocked:98,glm:blocked:95,kimi:author:,fable:ok:30,opus:ok:30,sonnet:ok:30)
PASS: fable shares the anthropic reading (ok under the 95 ceiling)
PASS: reviewer=fable (first eligible arm after the author/probe exclusions)
PASS: author-exclusion intact: author=opus excluded, reviewer=fable
PASS: dispatch-code.sh: no hardcoded opus prepass default
PASS: dispatch-code.sh prepass default resolves via router think-model
PASS=15 FAIL=0
```

### Live resolver behaviour (fanout classifier)

```
$ leadv2-fanout-classify.sh --intent "routine bulk edit" --tags ""
launch_class=Standard ... lead_model=sonnet            (unchanged)
$ leadv2-fanout-classify.sh --intent "safety-gate deploy of auth flow" --tags "safety"
launch_class=Heavy risk_tags=auth,safety lead_model=fable   (was opus — now resolves)
```

### Self-check / falsification set

```
SYNTAX-OK: plugins/leadv2/scripts/leadv2-llm-judge.sh
SYNTAX-OK: plugins/leadv2/scripts/leadv2-fanout-classify.sh
SYNTAX-OK: plugins/leadv2/scripts/leadv2-fanout.sh
SYNTAX-OK: plugins/leadv2/hooks/leadv2-routing-guard.sh
SYNTAX-OK: plugins/leadv2/scripts/tests/test-fable-think-tier.sh
PY-OK: glm-policy-resolve.py          (python3 -m py_compile)
YAML-OK: model-capability.yaml        (yaml.safe_load)
```

Changed-scope repo runner (`LEADV2_SUITE_LOCK_DISABLE=1 bash tests/run-all.sh --scope
changed`):

```
[PASS] .../plugins/leadv2/scripts/tests/test-fable-think-tier.sh   (15/15, incl. tree-wide census)
run-all: 4 passed, 1 failed, scope=changed
  Failures (blocking):
    - plugins/leadv2/scripts/tests/run-core-offline.sh
```

run-core-offline.sh detail (full log captured at /tmp/core-offline-r2.log): the failing
tests inside it are `T13 slice2 (arbiter bench-fallback + abandon dedup)` — "CLI dispatch
table exposes an undocumented subcommand" — and `landed-at-spawn T-a` (dispatch exited 4,
reservation row unconfirmed). Both are in the PRE-EXISTING red baseline measured
2026-09-01 (commit 2192dab, memory `run-all-changed-preexisting-reds`: "t13-slice2,
landed-at-spawn 4/8"), BEFORE round 1 landed; none of the failing assertions touch files
this lane changed (they exercise dispatch exit codes, terminal/reservation ledgers, and
the arbiter CLI table). Remaining core-offline shards: 17+13+16+30 sub-checks green,
including all bash -n / shellcheck gates over the scripts this round edited.

### Async decision (write-set expansion)

qid q-392fa4b8 — status=timed_out, selected=a (expand), decided_by=architect
(timeout default; journaled, surfaces in open-threads). Reversible: revert of this
lane's commit restores the 6 out-of-write-set files.
