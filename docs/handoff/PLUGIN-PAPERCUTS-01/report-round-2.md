# PLUGIN-PAPERCUTS-01 round 2 — P1 asserted a contract main deliberately retired

## §1 Contract decision: MAIN IS RIGHT — reader errors never stop the beat loop

The round-1 P1 asserted: a beat loop must stop itself after
`LEADV2_SINGLE_LEAD_BEAT_LOOP_UNKNOWN_MAX` consecutive UNKNOWN (reader-error)
passes. Main removed that stop on purpose (fix-round 3 H-2, stated in the
script's own header and pass body):

- A reader error (heartbeat bin missing, unparseable output, error object)
  means the monitor is BLIND — precisely when the founder still needs the
  beat. Stopping the beat there re-creates the founder-blindness silence the
  loop exists to prevent. Main's body: "an UNKNOWN pass is a READER error …
  Keep beating … do NOT count it toward any stop condition (the old
  UNKNOWN_MAX stop died here)" (`leadv2-single-lead-beat-loop.sh`, unknown
  branch).
- The leak the round-1 lane feared (an unbounded loop) is bounded by
  WATCHER-LIFECYCLE-LEAK-01 instead, which merged with strictly more capable
  machinery: a trapped TERM kills the in-flight child and exits (interruptible
  background waits, measured 0.015s vs the 29.5s deferred-handler death), a
  race-safe singleton claim, owner-gone self-reap, and a hard lifetime cap
  `LEADV2_SINGLE_LEAD_BEAT_LOOP_MAX_S` (default 86400s) so a wedged heartbeat
  can never make the loop immortal.

Counting reader errors toward a stop is therefore the wrong mechanism: it
bounds blindness by manufacturing silence. The lane did NOT tune the test to
pass; it replaced the assertion with one that states main's actual rule on
both sides.

## What P1 now asserts (test-plugin-papercuts.sh)

- **P1a** — with the retired `UNKNOWN_MAX=2` knob explicitly set (proving it
  is inert), a detached loop whose heartbeat reader errors on every pass
  keeps beating (≥3 beats over ~5 passes), stays alive, and holds its
  pidfile claim.
- **P1b** — with `ZERO_MAX=2` and a heartbeat that returns a readable empty
  registry (`[]` = REAL zero), the loop beats, then stops itself after
  ZERO_MAX consecutive real zeros and removes its pidfile.

Vacuous-run guards kept from round 1: each loop must be alive ~1s after
launch and must have actually beaten before any stop/survive assertion.

## Mutation proofs (mutations INSIDE the production body, real call path)

- **Mutation A** — `(( _zero_streak >= ZERO_MAX ))` →
  `(( _zero_streak >= ZERO_MAX + 1000 ))`: suite RED (rc=1):
  `FAIL: P1b: beat loop kept beating on a genuinely empty board (pid 32990
  still alive)`; P1a stayed green. Reverted → GREEN rc=0, 14/0.
- **Mutation B** — unknown branch `_unknown_streak=$(( _unknown_streak + 1 ))`
  → `… ; (( _unknown_streak >= 2 )) && exit 0` (reintroduces the retired
  stop): suite RED (rc=1): `FAIL: P1a: loop silenced/stopped on reader errors
  (beats=1, alive=n, claim=)`; P1b stayed green. Reverted → GREEN rc=0, 14/0.
  Production script verified byte-identical to HEAD after both reverts.

## Owner tag (§2)

`LEADV2_BEAT_OWNER_TAG` untouched; P8 (argv carries `--owner=<repo>:<lane>`)
and P8b (explicit override) green in every run, including inside run-all.

## Changed-scope selection

`tests/run-all.sh --scope changed` selects `test-plugin-papercuts.sh` on this
change (suite map lines: `leadv2-single-lead-beat-loop.sh:…test-plugin-papercuts.sh`,
`leadv2-pulse-beat.sh:…`); it ran and passed 14/0 inside the runner.

## Re-verification (2026-09-01, post-sync session — the report above was found gitignored/uncommitted)

Branch re-synced onto main (merge of 4 commits; lane diff is still only the
test rewrite + these reports). Production `leadv2-single-lead-beat-loop.sh`
and `leadv2-pulse-beat.sh` are byte-identical to main
(md5 `1b8aba14362ffd2d06010cebd72ff6b4` before mutation = after revert).

- Suite GREEN against synced main: `test-plugin-papercuts: 14 passed, 0 failed`,
  `GREEN_SUITE_RC=0`.
- Mutation B re-proven LIVE on the synced tree: retired stop reintroduced after
  `_unknown_streak` line 237 (`(( _unknown_streak >= 2 )) && exit 0`) →
  `RED_SUITE_RC=1`, `FAIL: P1a: loop silenced/stopped on reader errors
  (beats=1, alive=n, claim=)`, 13 passed / 1 failed; reverted via
  `git checkout --`, md5 byte-identical, suite GREEN again.
- Scope selection rows confirmed live on main: `tests/run-all.sh:132`
  (`leadv2-single-lead-beat-loop.sh` → `test-plugin-papercuts.sh`) and `:133`
  (`leadv2-pulse-beat.sh` → same suite), on top of the stubbed-executor
  end-to-end proof documented above.

## Flake found and fixed on re-verification: P1b vacuous guard raced under load

The immediate second green run came back `13 passed, 1 failed` —
`FAIL: P1b: fixture loop never beat — assertions would be vacuous`. Not a
production defect: the P1b guard did a fixed `sleep 1` and then required a
beat already on disk, but under load (three back-to-back suite runs plus
concurrent live lanes) the loop's first pass can exceed any fixed window.
Fix in the test only: a bounded `wait_beats <min> <deadline>` poll (0.3s
steps) replaces both fixed sleeps — P1a waits ≤15s for ≥3 beats, P1b waits
≤15s for the first beat (then `wait_gone 20` for the ZERO_MAX stop). No
assertion weakened; the vacuous guard got STRICTER (a loop that never beats
still fails, but a healthy slow loop no longer does). Two consecutive green
runs after the fix: `14 passed, 0 failed`, `GREEN3_RC=0`, `GREEN4_RC=0`,
zero `/tmp/leadv2-plugin-papercuts-*` leftovers from these runs.
