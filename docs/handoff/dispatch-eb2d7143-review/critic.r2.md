# critic.r2 — V3-GLM-LADDER-01 round-2 adversarial review

- Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/eb2d7143`
- Range reviewed: `389820a..269e59f` (checkpoint `4077109` + final `269e59f`)
- Diff hash: `a3dffcc6ffd2640cb33b810f8440d85dc6c67183c1292ccb3dd69a18236903e1`
- Method: execution, not reading. Every r1 finding was re-probed by running the code and, where
  the fix claimed to remove a leak, by re-injecting the leak to confirm the old code failed and
  the new code does not.

## Verdict: PASS_WITH_NITS

All eight r1 findings (C1, C2, C3, H1, H2, H3, M1–M5) are genuinely fixed and verified by
execution. One new High is opened (H4) against the *claim* attached to the routing-enforcement
fix, not against the ladder feature itself.

## Per-finding status

| r1 finding | status | evidence |
|---|---|---|
| C1 lockout benches glm, count freezes at 1 | **fixed** | suite case (e), see below |
| C2 `--retry-all` can never retry | **fixed** | suite case (f), real new dispatch observed |
| C3 no retry coverage | **fixed** | 5 new legs: (f)(g)(h)(i) + (e2) |
| H1 `.gitignore` uncommitted | **fixed** | committed in `269e59f`, rules verified effective |
| H2 4 bare `flock 8` on macOS | **fixed** | 0 bare `flock 8`; 8 `lv2_lock_wait` sites |
| H3 mark-retried without rc check | **fixed** | mark only inside `rc -eq 0` branch |
| M1 dead `_glm_deferred_is_retried` | **fixed** | 0 references repo-wide |
| M2 hardcoded `"glm quota"` reason | **fixed** | case (d) asserts the real variant |
| M3 park gate too wide (`glm_refused_*`) | **fixed** | narrowed to the two quota reasons |
| M4 `glm_deferred_count` counts rows | **fixed (untested)** | see M6 below |
| M5 new SC2034 | **fixed** | 0 SC2034 across all 5 changed files |

## 1. C1 — shared cache dir, two refusals, count=2

`test-glm-deferred-ladder.sh` case (e) now runs both dispatches through a **single**
`CACHE_E="${TMP_ROOT}/e-cache"`. `run_e` no longer mints a fresh cache dir per run — only the
sonnet stub and its snapshot file are per-run. Run 1 refuses live
(`glm_refused_quota_gate`), run 2 is benched by the quota-precheck loop
(`glm_refused_quota_precheck`) off the lockout run 1 wrote into that shared cache. The harness
asserts `count=2` **and** that both distinct sig8s are recorded **and** that run 2's park row
carries `reason=glm_refused_quota_precheck`. This is the exact shape r1 said the old harness hid.

Source-side fix is real, not harness-only: `_arm_exception_bump` now takes a sig8, dedups on
`sig8=` lines, and derives `count` from `grep -c '^sig8='` rather than trusting the stored
`count=`. The precheck bench site (`leadv2-dispatch-code.sh:4258`) parks + counts identically to
the live-refusal site. `mission` is in scope there (assembled at 3692–4019), so the parked
mission content is real.

Case (e2) additionally proves idempotence: a repeat bump for a sig8 already present leaves
`count=1`.

## 2. C2/C3/H3 — `--retry-all` actually retries

Case (f): a parked row with real mission content at `glm-deferred.d/ffffffff.md`, a fixture glm
launcher that touches a marker file, ledger stub returning non-terminal. Result:

```
retried ffffffff as=27aa4766
```

Marker file created (a real new dispatch ran), old sig8 gone from `--list`. The new sig8 is
correctly extracted, so both r1 blockers (empty `mission_path`, `already_terminal`) are gone.
D5's four other rows are each covered: (g) reaped when the ledger says terminal, (h)
`skipped_no_mission` leaves the row pending, (i) failed dispatch leaves the row pending.

H3 is satisfied — `_leadv2_glm_deferred_mark_retried` is called only inside the `rc -eq 0`
branch, and (i) proves a failed retry does not mark.

## 3. H2 — portable locking

`grep -c 'flock 8'` → **0**. Eight `lv2_lock_wait "<lock>" 10 || exit 3` sites. The fd move from
8 to 9 is required, not incidental: `lv2_lock_wait` delegates to `flock -w N -x 9`, so the
`9>"$lockf"` redirect is the primitive's contract. No ledger subprocess runs inside any of these
critical sections, so the documented fd-9 collision with `leadv2-dispatch-ledger.sh` cannot occur.

## 4. H1 — gitignore

Committed. `git check-ignore -v` confirms `docs/leadv2/glm-deferred.jsonl.lock` matches
`docs/leadv2/*.lock:22` and `glm-deferred.d/` matches line 19. The L5 leak dirs
(`plugins/leadv2/scripts/tests/docs/`, `.claude/`) are ignored and currently untracked (0 files).

## 5. The two previously-red core-offline suites

Both green in the worktree: `test-routing-enforcement-p1.sh` 19/0,
`test-plan-followups-01.sh` 21/0. `test-lane-placement-pin.sh` 24/0. But the two suites were red
for **two different reasons**, and only one of them was actually fixed.

### 5a. The state leak is real and the fix is genuine (not a weakened assertion)

`DISPATCH_LEDGER_DIR` is not covered by the `LEADV2_*`/`CLAUDE_*` prefix scrub in either the
suite preamble or `run-core-offline.sh`, so an ambient export overrode per-case
`LEADV2_DISPATCH_CACHE_DIR` sandboxing through the old `${DISPATCH_LEDGER_DIR:-...}` default.
Proved by injection:

- pre-ladder code (`b9959aa`), no poison → 3 failures
- pre-ladder code, `DISPATCH_LEDGER_DIR=/tmp/poison-ledger` → **10 failures**
- r3 code, same poison exported → **0 failures**

The fix is at the source (`DISPATCH_LEDGER_DIR` derived unconditionally from the already-sandboxed
`CACHE_BASE`), with the suite `unset` as defence in depth. This is a real isolation fix.

### 5b. H4 (new, High) — 3 of the 4 red cases were NOT the state leak, and the fix pins away the production default

`test-routing-enforcement-p1.sh` also gained `LEADV2_ROUTER_V2_ON_QUOTA_GATE=0` at four call
sites, with no comment. It is load-bearing: removing those four lines turns three cases red again
(`quota refusal advances chain`, `codex dead-arm no_first_byte spill`, `quota lockout write side`,
all rc=4).

Those three reds reproduce **identically on pre-ladder main** (`b9959aa`, same rc, same task
sigs), so this diff did not cause them. But their root cause is not state isolation. Full output
of the failing leg under the production default:

```
arm_refused by=router model=glm reason=glm_refused_quota_gate
route_headroom_chosen arm=sonnet after=glm_quota_gate ordered=sonnet
  headroom={"codex": 0.0, "sonnet": 0.445} credits={"codex": {"has_credits": false}}
spawn_failed by=router model=sonnet rc=99 reason=launcher_nonzero_exit
  POISON: real provider spawn attempted
dispatch_rolled_back reason=all_arms_unavailable
```

Commit `c5f60ee` ("choose quota-gate fallback by live headroom") deliberately superseded the
strict-ladder GLM→Codex advance: with codex at zero credits its headroom is 0.0, so sonnet wins
and hits the suite's poison fence. The assertions encode pre-`c5f60ee` semantics and have been
stale-red since.

Consequences, and why this is a High rather than a nit:

1. **The close claim is wrong.** `269e59f`'s message says both reds were "root-caused
   (routing-enforcement-p1 state leak, plan-followups harness isolation)". For three of the four
   cases the real cause is a superseded ladder invariant, not a leak. A close message that
   misattributes a root cause is exactly the lying-green failure mode this repo's rules target.
2. **The production default now has zero coverage in this suite.** `ON_QUOTA_GATE=0` is an
   undocumented kill-switch referenced at exactly one site
   (`leadv2-dispatch-code.sh:4518`) and nowhere else in the repo — no config, no doc, no other
   test. The suite reports green on "routing enforcement" while the headroom-based quota-gate
   fallback that actually ships is untested, so a regression there is invisible.

I did **not** score this as assertion-weakening in the falsification sense: the assertion text is
unchanged and `ON_QUOTA_GATE=0` is a real supported code path, so the test still tests something
true. The defect is the missing coverage of the default path plus the inaccurate attribution.

**Required remedy (cheap):** comment the four sites with why the flag is set; add one case under
the default that asserts `route_headroom_chosen ... arm=sonnet after=glm_quota_gate` with a
non-poison sonnet stub; correct the close claim to name the two distinct causes.

## 6. M6 (new, Minor) — M4's dedup is untested

`leadv2-broad-status.sh` now dedups `glm_deferred_count` by sig8 set. No suite asserts it. Given
the diff's own C1 case makes double-parking of one sig8 reachable (precheck bench + live refusal),
one assertion is warranted on a founder-visible counter.

## 7. L-level notes

- **L1** Case (f) greps `retried ${SIG_F} as=` — `as=unknown` would also pass. The mechanism is
  verified working by direct probe (`as=27aa4766`), so this is an assertion gap only.
- **L2** `_leadv2_glm_deferred_mark_retried`'s header claims the marker is appended "under the
  SAME lock as the read that decided to retire it". It is not: `_rp_json` is read unlocked at the
  top of `retry-all`, and the mark takes a fresh lock later. Two concurrent `--retry-all` runs can
  still both dispatch. The comment overstates the guarantee; either fix the comment or hold one
  lock across read-and-mark.
- **L3** `_codex_credits_watch` at the precheck site is fed via `--chain glm` while the credits it
  reads are codex's. Works (case (c) passes) but reads as a copy-paste of the arm variable.
- **L4** Case (e2) `sed`-extracts `_arm_exception_bump` out of the real script. Better than
  reimplementing it, but it will silently stop testing the real function if the `}` at column 0
  convention changes.
- **L5** `docs/leadv2/*.lock` does not untrack the already-tracked `.bus.lock`, `.merge.lock`,
  `active.yaml.lock`. Pre-existing, outside this diff's scope; the new glm-deferred lock is
  correctly covered.

## Mechanical checks

- `bash -n`: OK on all 5 changed shell files.
- `shellcheck -S warning -x`: only pre-existing warnings (lines 365, 387, 1735, 1741, 2799, 2808,
  3921, 3974, 4050 — all outside the changed hunks). **0 SC2034** on every changed file.
- Off-limits: `leadv2-dispatch-product-close.sh` and `supervise*` are untouched by the range.
- Suites: glm-deferred-ladder FAIL=0 (16 legs) · routing-enforcement-p1 19/0 ·
  plan-followups-01 21/0 · lane-placement-pin 24/0.
