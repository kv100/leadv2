# FABLE-IS-PRICED-FROM-A-WINDOW-IT-DOES-NOT-BURN-01 — row 0485ea90c9e0

Worker lane report · 2026-09-13 · commit `e90086e7` (code+suite), follow-up
commit (declaration fix + artifacts). Governing contract:
`docs/handoff/DECISION-LAYER-CONTRACT/decision.md` (QUOTA-WINDOWS).

## Defect (measured 2026-09-12, before any edit)

Live probe `/tmp/0485-live-anthropic.json` (raw endpoint output) and the
frozen pre-patch cache stubs (`/tmp/0485-before.9SfD/`, re-frozen
post-patch as liveA2/B2 through the real `leadv2-quota-live.sh --no-cache`):

- `limits[]` carries three kinds; nobody parsed `weekly_scoped`:
  `weekly_scoped_parsed=ABSENT` on every account pre-patch.
- Real mispricing direction on record: account `max_5x` — `weekly_all=81`,
  Fable `weekly_scoped=54`.
- Arbiter BEFORE (frozen live payloads, pre-patch binaries):
  - run A (session 8 / weekly_all 8 / scoped Fable 2): `util_claude=8` —
    the scoped meter invisible.
  - run B (session 7 / weekly_all 81 / scoped 54): `util_claude=81` +
    `headroom_priced=claude:0.227185` — fable penalised for the aggregate.
- Arbiter AFTER (same payloads, post-patch): run A2 `util_claude=8
  util_claude_fable=8` (session binds); run B2 `util_claude=81
  util_claude_fable=54` with its own gradient `claude/fable:0.265909` in
  `headroom_priced`.

## Implementation (3 files + suite, `git diff --stat` 276+/63- + new suite)

- `plugins/leadv2/scripts/leadv2-quota-read.py` — publisher half.
  `anthropic_scoped_windows()` parses `limits[]` into a `weekly_scoped` map
  keyed by lowercased scope display_name (id fallback); kind→window-name
  mapping declared once here (CONTRACT QUOTA-WINDOWS). `read_anthropic`
  publishes it; `normalize_payload` upgrades pre-parser caches in memory
  (both cache-hit and fresh-serve paths), so consumers see it regardless of
  cache age. `binding_window` stays the aggregate pair — the account
  balancer ranks ACCOUNTS, not arms (evidence: claude-subsession.sh:523-525
  passes no arm; profile-select.sh receives none).
- `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — consumer half.
  `util()`/`capped()`/`over_ceiling()`/`near_reset_wait()`/
  `headroom_weight()`/`ecost()`/forecast are arm-aware: a scoped arm's own
  window REPLACES `weekly_all` for that arm; the shared `five_hour` session
  window stays (worst window across window GROUPS). Scoped-ness is derived
  from the payload (normalized name join against the `weekly_scoped` map) —
  no hardcoded model list. `arm=None` paths are byte-identical to before.
- `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` —
  `live_anthropic_pct(bin, arm)` prices a scoped arm by
  max(five_hour, scoped); opus/sonnet keep the aggregate.
  `resolve_review_pool` accepts an injected `anthropic:<arm>` reading above
  the aggregate fallback.

## Contract divergence, stated (not hidden)

QUOTA-WINDOWS says "priced by max(aggregate, scoped)". Implemented
literally, acceptance case 1 could never pass — weekly_all 96 would still
penalise a scoped arm at 2. Implemented semantics: per window GROUP the
scoped window replaces the weekly aggregate for the scoped arm; ACROSS
groups worst wins — so max(session, scoped). This satisfies the clause's
goal (never priced by the aggregate alone; always by the meter the provider
enforces) and keeps the session window binding as the brief demands. The
clause's literal wording needs the same amendment in the contract doc.

## Acceptance suite

`plugins/leadv2/scripts/tests/test-fable-is-priced-from-its-own-window.sh`
— 10 cases, 10/0 green: P1/P2 publisher (parse + legacy-cache upgrade),
R-live/R1/R2/R3 resolver (scoped read; admitted/blocked/aggregate-fallback),
C1/C2/C3/C4 arbiter (not-penalised / withdrawn / session-binds /
aggregate-arms-untouched). Fixtures for the arbiter cases are built THROUGH
the real publisher parser (importlib), so the suite exercises the published
shape, not a suite-private idea of it.

Registration: self-select `# run-all-triggers:` header. Proven:
`LEADV2_RUN_ALL_LIST_TRIGGERS=1` shows the three stem rows; a one-line
ephemeral diff of quota-read.py alone selects the suite under
`LEADV2_RUN_ALL_SELECT_ONLY=1 ... --scope changed` (file restored
byte-identical after the probe). Token shapes: `leadv2-quota-read` (scripts
stems strip .py — a dotted token is a dead row), `leadv2-glm-policy-resolve.py`
(lib special case keeps it).

## Negative controls (all run RED via leadv2-mutation-control.sh, worker mode)

| half | mutation (anchor count==1) | red line |
|---|---|---|
| publisher | `!= "weekly_scoped"` → `!= "weekly_scoped_x"` | `FAIL: P1 ... keys=[]` |
| arbiter | `windows.pop('seven_day', None)` → `'seven_day_x'` | `FAIL: C1 ... util_claude_fable=96 ... fable:capped` — the original defect reproduced |
| resolver | `if scoped_pct is not None:` → `is None` | `FAIL: R-live readings: bad (96, 7, 7)` — scoped leaks to aggregate arms |

Artifacts: `mutation-control/20260912T214420Z-22163.txt` (publisher),
`...214452Z-34073.txt` (arbiter), `...214517Z-43883.txt` (resolver);
`lane_diff_hash=327121156f...` identical in all three.

## Guarding suites (mine vs pristine-HEAD discrimination)

Pre-existing reds on main (identical with and without this lane's diff —
proven by re-running every failing suite against a pristine `git archive
HEAD` tree at /tmp/0485-pristine): test-route-arbiter.sh 28/4 (case g ×3,
arbiter-lib-absent fallback), test-arbiter-seam-plugin-kind.sh 7/7,
test-balancer-every-arm.sh 17/5, test-provider-quota-gate.sh (ceiling-source
drift), test-quota-reset-arbiter.sh 8/1, test-think-through-arbiter.sh 14/1,
test-quota-lockout-postspawn.sh (env: backlog row premise refused),
nc-claude-profile-select.sh (NC2-SETUP-FAIL).

Green with this lane: test-balancer-ranks-by-usable-now.sh 18/0,
test-claude-profile-select.sh **152/0** (baseline held),
test-claude-profile-requested.sh, test-codex-quota-gate.sh 10/0,
test-quota-daemon.sh, test-quota-glm-filter.sh, test-quota-identity-report.sh,
test-quota-model-tier-granularity.sh, test-quota-read-anthropic-liveness.sh,
test-quota-standdown-duration.sh 16/0, test-quota-weekly-live.sh,
test-quota-weekly-total.sh, test-route-arbiter-failure-memory.sh 14/0,
test-route-arbiter-loud-refusal.sh 4/0, test-route-arbiter-spend-forecast.sh
9/0, test-route-arbiter-symlink-install.sh 3/0, test-spawn-arbiter-gate.sh
28/0, test-think-model-arbiter-wins.sh 10/0,
nc-arbiter-observed-cost.sh / nc-quota-reset-*.sh / nc-think-model-arbiter-wins.sh
all NC-PASS.

test-codex-quota-guardrails.sh: red in BOTH trees with different,
environment-dependent shapes (mine 28/1 f3; pristine 26/3 f1-f3 — lane
adoption / lead-identity resolver availability inside its temp repos). No
failure names scoped-window code; this lane does not touch codex paths.

## Falsification

`bash -n` green on route-arbiter.sh + the new suite; `python3 -m py_compile`
green on quota-read.py + glm-policy-resolve.py. Changed-scope runner
proven to select the suite (selection seams above). No runtime-state paths
touched (docs/leadv2/, dispatch-nw* untouched); no stash/reset/clean/prune;
no push.
