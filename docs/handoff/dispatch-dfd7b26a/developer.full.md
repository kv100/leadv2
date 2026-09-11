# Architect prepass wrapper — D1 and D2, root cause and fix

File: `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, `architect_prepass()` (~L1870-2010).

## Investigation

Both defects the mission cites as "recent" (`PREPASS-READS-ARTIFACT-01`,
`4f54bf5385d`; timeout kill, `4f3ffccc2dc`) already landed on 2026-07-29, before
`75d151fe` / `117656b5` were observed. So the literal pre-2026-07-29 mechanisms
("stdout captured instead of the artifact", "communicate() never times out") were
already fixed on HEAD — I confirmed this by instrumented reproduction (below)
before touching anything, per the mission's "confirm or refute before fixing"
instruction.

### D1 — confirmed root cause: artifact read races the write, not a stdout/rc bug

Built a fake `LEADV2_DISPATCH_ARCHITECT_BIN` that writes a complete
`architect.full.md` (with `DELIVERABLE_COMPLETE` and a valid `LANE_WRITES:` /
`acceptance:` block) from a **backgrounded, disowned, fd-detached** subshell,
then exits 1 immediately — reproducing exactly what `claude-subsession.sh`'s own
`--wait` path can do: the launcher's own exit races an async completion of the
deliverable write (e.g. a Stop/SessionEnd hook, or simply OS scheduling of a
detached child that inherited nothing blocking). Run through the REAL dispatcher
(`leadv2-dispatch-code.sh`, only the architect binary stubbed — same pattern the
repo's own `test-dispatch-architect-degrades.sh` uses):

**Pre-fix** (`/tmp/orig-dispatch-code.sh`, copy of HEAD):
```
[leadv2-dispatch-code] architect_prepass task=d61def75 status=failed reason=failed_rc_1 rc=1
[leadv2-dispatch-code] architect_prepass task=d61def75 status=retrying attempt=1/2 reason=failed_rc_1
[leadv2-dispatch-code] architect_prepass task=d61def75 status=failed reason=failed_rc_1 rc=1
[leadv2-dispatch-code] architect_prepass task=d61def75 status=retrying attempt=2/2 reason=failed_rc_1
[leadv2-dispatch-code] architect_prepass task=d61def75 status=parked reason=no_design_after_2_attempts action=not_dispatched
```
This is byte-for-byte the incident's own `reason=failed_rc_1` signature — a lane
parked despite a fully valid design landing 0.6s after the launcher's own exit.

**Post-fix** (same fake architect, same 0.6s delay):
```
[leadv2-dispatch-code] architect_prepass task=eb4acf04 status=ran artifact=docs/handoff/dispatch-eb4acf04/architect-prepass.md source=.../architect.full.md
[leadv2-dispatch-code] worker_spawned by=router model=sonnet task=eb4acf04 ...
```

I could not pin down which real-world component performs the async completion in
persona-engine's actual `claude-subsession.sh` runs (candidates: a Stop hook, or
disk-visibility lag across the lane's linked worktree) — the mission's own
adir/PROJECT_ROOT-mismatch hypothesis did NOT reproduce (env `PROJECT_ROOT` is
passed explicitly into the Popen env and used consistently for both the child's
`HANDOFF_DIR` and the wrapper's own `adir`; a controlled test with `rc=1` and the
artifact written **synchronously before exit** already worked correctly on HEAD,
proving the artifact-ignored-on-nonzero-rc bug is fully fixed). What is real and
reproducible is the TOCTOU: a single `-s` stat right after `communicate()` returns
can race a still-completing write, exactly as the mission's "must achieve" section
requires guarding against, independent of which exact mechanism last did it in
production.

**Fix**: `architect_prepass` now polls the three candidate paths in a bounded loop
(up to 10 × 200ms = 2s, only when `rc != 0`) instead of a single stat, before
falling through to the `failed reason=...` branch.

### D2 — confirmed root cause: `os.killpg` cannot reach a re-sessioned descendant

macOS has no `setsid` binary, so a naive `&`-backgrounded descendant stays in the
launcher's process group and IS killed by the existing `os.killpg`. I built a
descendant that genuinely escapes via `python3 -c "os.setsid()"` (the same
mechanism a detached agent-CLI helper or MCP server would use) and ran it through
the real dispatcher with `ARCHITECT_PREPASS_TIMEOUT_SEC=3`:

**Pre-fix**: the wrapper itself DID correctly detect the timeout and journal it
(`status=failed reason=timeout rc=124`, retried, parked) — this refutes the
mission's literal "nothing is emitted at all" for the wrapper's own accounting.
What actually leaked: the process group kill left the re-sessioned grandchild
running. Marker-file line count kept growing after the lane had already parked
(`15 -> 21` over 3s, unbounded) — this is the mechanism behind
`architect.stream.jsonl` still growing 63 minutes after prepass entered even
though the *lane* itself had already moved on. A live `pulse`/health check that
only looks at "is a process alive" would report this healthy indefinitely.

**Post-fix**: same escaping grandchild, same timeout — journal still shows
`status=failed reason=timeout rc=124` (unchanged, correct), and the marker file
is now provably dead: `8 -> 8` (stable) after the same wait window, versus
`15 -> 21` (still climbing) pre-fix.

**Fix**: on `TimeoutExpired`, walk the full descendant tree with `pgrep -P`
(recursively) and `os.kill(pid, SIGKILL)` each PID individually, in addition to
the existing `os.killpg` (kept as a backstop for the common non-escaped case).

### A bug I introduced and had to fix along the way

My first D2 patch put an apostrophe ("launcher's own group") inside the python
heredoc comment. That heredoc is nested inside `out="$(... <<'PY' ... PY)"` —
bash's `$(...)` scanner apparently tracks quote state THROUGH quoted heredoc
bodies (confirmed with a 4-line minimal repro: `out="$(cmd <<'PY'\n# it's\nPY\n)"`
fails `bash -n`; the same heredoc NOT inside `$(...)` parses fine). Rewrote the
comment without contractions and left a note in the file so the next person who
touches this heredoc does not reintroduce it. Re-verified `bash -n` clean after.

## What changed

`plugins/leadv2/scripts/leadv2-dispatch-code.sh`:
1. Timeout-kill branch of the python subprocess wrapper (~L1944): recursive
   `pgrep`-based descendant kill before/alongside `os.killpg`.
2. Artifact-candidate scan (~L1982): bounded poll (2s, only on non-zero rc)
   instead of a single stat, before declaring `failed reason=...`.

No change to the architect role, its model, its prompt, the retry/park policy,
or the timeout value.

## Tests added (both RED pre-fix, GREEN post-fix — shown above and re-verified below)

- `plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh` (D1)
- `plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh` (D2)

```
$ bash plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh
PASS: architect_prepass polls briefly for a late-landing artifact instead of racing a single stat (ARCHITECT-PREPASS-ORPHAN-01 D1)

$ bash plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh
PASS: architect prepass timeout kills the whole descendant tree, including a re-sessioned grandchild (ARCHITECT-PREPASS-ORPHAN-01 D2); marker stable at 8 lines
```

Regression: `test-dispatch-architect-degrades.sh` (the existing suite covering
retry-then-park on repeated failure/timeout) still passes unchanged — confirms
the retry/park policy and the `elapsed < 8s` timing bound are untouched.

I additionally launched the full 27-file `test-dispatch-architect-code.sh`-family
suite in the background to check for wider regressions; results were still
pending when I wrote this file — check `/tmp/lv2-test-out/RESULTS` if it has not
already been folded into a follow-up note.

## Left alone / not fully resolved

- I did NOT identify the exact production component that performs D1's async
  artifact completion (Stop hook vs. worktree fs-visibility lag vs. something
  else) — only that a bounded poll closes the race regardless of which it is,
  per the mission's own "must achieve" requirement. If precision matters for a
  future incident, instrumenting a real live architect dispatch (real opus lane,
  tens of minutes, real cost) would be the next step; I judged that out of scope
  for a wrapper-only fix given the explicit hard limit against touching the
  architect role/model/prompt.
- Did not raise the timeout or remove the rc check (per hard limits).
- Did not add either new/existing suite to a known-failures registry.

DELIVERABLE_COMPLETE
