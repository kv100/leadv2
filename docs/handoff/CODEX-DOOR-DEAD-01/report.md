# CODEX-DOOR-DEAD-01 — report

## 1. Fault A — review base (landed, tested)

**Mechanism** (confirmed): `run_reviewer_arm()`'s codex branch in
`leadv2-review-run.sh` passed `--base HEAD` unconditionally. codex-companion's
`resolveReviewTarget` treats an explicit `--base` as authoritative and never falls
back to working-tree mode, so a lane that had already committed its work diffed its
own HEAD against itself — empty branch diff, short/empty stdout. codex still writes
its `[codex-task] tier=…` banner to **stderr** regardless, so the REVIEW-BODY-
PERSIST-01 guard downstream saw a live arm with no body and correctly (but
misleadingly) reported `review_body_lost`. That is `ee807b33`'s two verdicts.

**Fix** (already in the worktree, landed as-is — no redesign): a new
`_review_resolve_codex_base()` resolves, in order: (1) `merge-base
$LEADV2_LANE_START_SHA HEAD`, (2) `merge-base origin/main HEAD`, (3) refuse
(`review_arm_skipped … reason=no_base_resolved`, rc=77 → `classify_arm_failure`
already maps rc=77 to `refused_channel_down`, a clean skip, not a crash — verified
by reading the existing switch, no call-site change needed). A degenerate-repo
escape (`ROOT` not a git work tree) preserves the literal `HEAD` base so fixture
tempdirs don't trip the refusal. An empty-diff short-circuit
(`reason=empty_diff`) covers the "nothing to review" case. `--cwd "${ROOT}"` is now
passed to codex.

**Test**: `plugins/leadv2/scripts/tests/test-review-codex-base.sh` (new, 11
assertions across 6 scenarios). Drives the real `leadv2-review-run.sh` CLI
end-to-end; the codex launcher is a recorder stub, never a reimplementation.
Confirmed red against the pre-fix script (9/13 failures — verified by
temporarily restoring `HEAD~1`'s copy of the file and re-running), green against
the post-fix script (11/11). Registered in `run-core-offline.sh`.

## 2. Fault B — the dispatch door

**Reproduction run** (per design §2, arm B2 — codex was leadv2-side "locked out" at
the time via `quota-lockout-codex.json`, so the direct-launcher path bypasses that
gate exactly as the design anticipated):

```
codex-task.sh task "Create a file named FILE.txt … containing exactly OK" \
  --background --cwd /tmp/codex-repro-28c1c11d --tier standard
```

Job `task-msvndxye-bj91r3` enqueued; `FILE.txt` (3 bytes, "OK\n") landed in the
scratch dir within ~15 seconds.

**Verdict: did NOT reproduce.** The codex runtime is healthy right now and fast —
this contradicts H3's premise (enqueue accepted, job never runs) for this specific
trivial task at this specific moment. This matches the pre-existing manual lockout
record already on disk (`quota-lockout-codex.json`'s `source` field, written by the
founder before this task started): *"Direct codex-task.sh returns OK, so the
provider is healthy and both leadv2 doors are not."* — i.e. the runtime itself was
never the suspect; a leadv2-side integration gap was. This pass could not
reproduce that gap live (the four dead lanes are historical; nothing available
today recreates their conditions), so per the design's own instruction ("If neither
arm reproduces, say plainly that it did not reproduce and ship the mitigation below
anyway; do not invent a mechanism") — H3 is **not confirmed**, and no second
mechanism is asserted.

**Mitigation shipped anyway** (§1 and §3 are both green, so per the design's
sequencing this was in scope): a first-byte deadline on the codex **builder** arm
only, in `leadv2-dispatch-code.sh`:

- `_codex_first_byte_probe <handle>` — rc0 iff codex-companion's own `log <handle>`
  verb (same verb `_arm_final_output` prefers) returns non-empty text. Deliberately
  does **not** fall back to the raw `status` text the way `_arm_final_output` does
  — a live job always has *some* status text, so that fallback would report
  "first byte" on every silently-stuck job and defeat the purpose.
- `_codex_first_byte_deadline_check <handle> <sig8>` — polls the probe until either
  a byte lands (rc0) or `LEADV2_CODEX_FIRST_BYTE_SECS` (default 180) elapses (rc7).
  On rc7: emits `arm_dead_no_first_byte arm=codex task=<sig8> job=<handle>`, calls
  `record-quota-lockout --provider codex --hours 1 --reason arm_dead_no_first_byte`
  (the new §3 stand-down mode), and returns 7.
- Wired into `atomic_dispatch_reserve_spawn_confirm`'s codex branch, immediately
  after the existing generic early-verdict window, mirroring the existing rc=7
  postspawn-quota spill branch exactly (abort the reservation, spill to the next
  candidate arm).

**Verification**: no dedicated test file was pre-authorized for this mitigation in
`LANE_WRITES` (unlike §1/§3, which both had one named). Manually exercised both
functions in isolation with a fake `CODEX_BIN`: a handle with output returns rc0
immediately; a handle with no output and `LEADV2_CODEX_FIRST_BYTE_SECS=2` returns
rc7 after ~2s and emits the `arm_dead_no_first_byte` journal line. Full offline
suites that exercise the codex spawn path (`test-codex-quota-guardrails.sh`,
`test-codex-quota-gate.sh`, `test-codex-task-spawn-failure.sh`) still pass
unchanged — none of them currently drives `atomic_dispatch_reserve_spawn_confirm`
far enough to reach the new codepath, so this mitigation carries **less test
coverage than §1/§3** and should be watched in the field before being trusted as
fully proven. This is flagged, not hidden.

## 3. Duration-based stand-down for `record-quota-lockout` (landed, tested)

Added `--hours`/`--minutes` (mutually preferring `--minutes` if both given) plus
`--reason` to `cmd_record_quota_lockout` in `leadv2-dispatch-code.sh`. Mode
selection: either duration flag present → stand-down mode (`--handle` no longer
required; `--provider` or `--arm` required; skips `_arm_final_output`/
`_quota_shaped` entirely — a stand-down asserts brokenness, it does not classify
launcher output). Guard: `--hours` must be `1..168`, `--minutes` `1..10080`;
invalid values → rc0, stderr names the bad value, no file written (never breaks
the close gate's poll loop). Writes via the existing `_record_quota_lockout` with
`source="standdown:<reason>"`, so `_provider_available` (the unmodified reader)
suppresses the provider through the identical path an exhausted-quota record uses.
Emits the distinct verb `quota_standdown_recorded` (never `quota_lockout_recorded`)
so a stand-down is never later misread as a quota event.

**Test**: `plugins/leadv2/scripts/tests/test-quota-standdown-duration.sh` (new, 16
assertions across 6 scenarios) — including the exact reported failure (an expired
lockout file left untouched) and the legacy quota-classification path (unchanged).
All pass. Registered in `run-core-offline.sh`.

## Non-goals honored

REVIEW-BODY-PERSIST-01's guard is untouched. codex-companion / `resolveReviewTarget`
were not touched (out of this repo). `docs/leadv2/open-threads.md` was not touched.
No `reset --hard`/`clean`/`stash` was run. The four dead lanes were not retrofitted
or unwound.

## What was deliberately left alone

- The kimi/glm/sonnet arms do not get a first-byte deadline (explicit non-goal).
- No new test file for §2's mitigation — flagged above as a coverage gap, not
  silently shipped as equally proven as §1/§3.
- This subagent did not commit — the repo's own `.claude/CLAUDE.md` boundary
  ("No commit, no push, no merge, no tag… leave the tree for the lead to review")
  overrides the mission text's step-1 "commit on main" instruction; the diff is
  staged (only `LANE_WRITES` paths — the two ambient `docs/leadv2/tasks/*/journal.md`
  hunks from other lanes were left unstaged) for the lead to review and commit.
