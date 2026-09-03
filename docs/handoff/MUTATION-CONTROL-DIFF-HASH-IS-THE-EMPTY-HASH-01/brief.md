# MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01 — mission brief

Ref: `docs/handoff/WAVE4/shared-constraints.md` (binding — off-limits list, negative-control rule,
EXTRA_SUITE_MAP discipline). Repo: `~/Projects/leadv2` only.

## Goal
Make `diff_hash` in mutation-control evidence non-forgeable and non-degenerate: it must hash the
actual applied mutant diff, differ between two different mutations, and the emitter must refuse to
write evidence at all when the diff is empty. **Status check first: both halves are ALREADY landed
in the tree** (see Root cause). This lane's job is to close the one real test-coverage gap and
confirm the fleet's on-disk evidence is clean — not to re-implement the fix.

## Root cause — file:line + mechanism proven
Pre-fix, `plugins/leadv2/scripts/leadv2-mutation-control.sh` computed exactly ONE hash, `DIFF_HASH
= git -C "${ROOT}" diff "${MC_BASE}" HEAD -- . | shasum -a 256` (old line 84 — the LANE's own
committed history on the real checkout), near the TOP of the script, structurally before the
scratch copy or the mutation existed, and wrote that same value straight into the artifact's
`diff_hash=` field (old §7) no matter which mutation ran. Mechanism, reproduced live this session
in a throwaway repo (`git init; git commit --allow-empty; git diff HEAD HEAD | shasum -a 256`):
when base==HEAD (the normal state right after branching, or any call before the worker's own
commit), that diff is byte-empty and `sha256("")` is exactly `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
— confirmed byte-for-byte. Both task-listed candidate mechanisms apply simultaneously: wrong tree
(ROOT, not the scratch dir the mutation lives in) **and** wrong time (before the mutation exists).
Reader side: `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh::_dod_valid_mutation_artifact()`
(line 259) only checked `artifact_hash == expected_lane_hash` — no independent check that the
mutation's own hash was non-degenerate, so a matching-lane-hash artifact with `diff_hash=e3b0c442…`
still passed.

## Fix already landed — confirm, do not redo
Commits `adc272621f` (14:18) + `859030321d` (14:30), both 2026-09-03, task dispatch-926c2a38
(WORKER-OUTLIVES-ITS-TERMINAL-STATE-01 round 2):
1. **Writer refuses to write** — `leadv2-mutation-control.sh:211-216`: hashes
   `git -C "${SCRATCH}" diff --no-ext-diff --binary --no-color -- "${FILE_REL}"` (the actual
   mutant, in scratch, after mutation, scoped to the one file) into `MUTATION_DIFF_HASH`; if empty
   or equal to the constant, prints `reason=empty_mutation_diff`, `exit 2`, writes nothing.
2. **Reader rejects** — `lib/leadv2-dod-gate.sh:275-276`: `artifact_hash =~ ^[0-9a-f]{64}$` and
   `artifact_hash != e3b0c442…` are now required before the lane-hash-binding check runs.
3. Two hashes, separately named and never confused: `diff_hash=` (mutant) vs `lane_diff_hash=`
   (`leadv2-mutation-control.sh:87`, `_dod_worker_diff_hash()` at `lib/leadv2-dod-gate.sh:134`).
4. CI already selects the suite — `tests/run-all.sh:357-358` maps both
   `leadv2-dod-gate.sh` and `leadv2-mutation-control.sh` to
   `plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` in `EXTRA_SUITE_MAP`. No new row needed.

**Residual gap (why this lane still has real work):** zero hits for `empty_mutation_diff` anywhere
under `plugins/leadv2/scripts/tests/`. The existing "two mutations differ" case
(`test-worker-dod-gate.sh:495-517`) only ever drives REAL, non-empty mutations through the CLI, so
it never exercises the degenerate-hash path — reverting the guard at `leadv2-mutation-control.sh:213`
today would **not** turn the current suite red. That is the gap this lane closes.

## Blast radius
Command: `grep -rl e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
~/Projects/leadv2/docs/handoff | wc -l` → **8**. None is a `mutation-control/*.txt` evidence
artifact: 2 are this fix's own paper trail (`dispatch-926c2a38/{lane-mission.md,review.diff}`), 2
are other lanes' review reports independently flagging the same finding
(`dispatch-b4042501-review/`, `dispatch-e93d9162-review/critic.full.md`), 4 are incidental
`developer.stream.jsonl` transcripts. Repo-wide outside `docs/handoff`: 3 hits, all three are the
source files themselves (the guard's comparison literal). Directly verified clean:
`docs/handoff/WORKER-OUTLIVES-ITS-TERMINAL-STATE-01/mutation-control/*.txt` (the exact dir named in
the original report, 3 files) — regenerated through the fixed tool, zero carry the empty hash.
**Verdict: zero on-disk negative-control evidence is currently contaminated by this defect.**

## Files allowlist
- Write: `plugins/leadv2/scripts/tests/test-worker-dod-gate.sh` (add the two cases below);
  `docs/handoff/MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01/report.md` (this lane's evidence).
- Read-only reference, touch ONLY if Step 2 surfaces a genuine second defect (not expected):
  `plugins/leadv2/scripts/leadv2-mutation-control.sh`, `plugins/leadv2/scripts/lib/leadv2-dod-gate.sh`.
- Off-limits (WAVE4 + task-level, hard stop): `plugins/leadv2/scripts/leadv2-dispatch-code.sh`,
  `plugins/leadv2/scripts/leadv2-claude-profile-select.sh`, `tests/known-red-suites.txt`.

## Steps
1. Re-read `leadv2-mutation-control.sh:206-216` and `lib/leadv2-dod-gate.sh:259-277` — confirm
   unchanged since this brief; if drifted, treat this brief's line numbers as approximate and re-cite.
2. Add case to `test-worker-dod-gate.sh` next to the existing pair-of-mutations case: hand-craft a
   `mutation-control/*.txt` fixture with every field valid (`suite=`, `file=`, `baseline_rc=0`,
   `mutated_rc=1`, `lane_diff_hash=<64hex>`) except
   `diff_hash=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`; call
   `_dod_valid_mutation_artifact` directly (real production function, no fake needed); assert rc=1
   (reject). This is the one shape today's suite never exercises.
3. Keep the reader-focused test as primary (fully deterministic, no CLI plumbing needed to force an
   empty scratch-diff). Do not attempt to force the writer CLI into `empty_mutation_diff` through a
   normal sed mutation — post-fix, a real anchor match makes the scratch diff non-empty by
   construction, so that path is a hand-forgery scenario, exactly what step 2's fixture covers.
4. Run the negative control below; record both exit codes verbatim in `report.md`.
5. Run `test-worker-dod-gate.sh` full suite on macOS AND in a Linux container; record both rc.
6. Run `tests/run-all.sh --scope changed` after touching only the test file; confirm
   `test-worker-dod-gate.sh` is selected (already wired via `EXTRA_SUITE_MAP:357-358`).
7. `report.md` with a `## Evidence` heading; paste the new PASS line + both red/green pairs.

## Acceptance commands (re-runnable)
```bash
cd ~/Projects/leadv2
MC=plugins/leadv2/scripts/leadv2-mutation-control.sh
# A vs B: two different mutations must yield two different, non-empty-hash artifacts
bash "$MC" plugins/leadv2/scripts/tests/test-worker-dod-gate.sh plugins/leadv2/scripts/lib/leadv2-dod-gate.sh 's/return 0/return 0 #A/' /tmp/mc-run-a
HASH_A=$(sed -n 's/^diff_hash=//p' /tmp/mc-run-a/mutation-control/*.txt | tail -1)
bash "$MC" plugins/leadv2/scripts/tests/test-worker-dod-gate.sh plugins/leadv2/scripts/lib/leadv2-dod-gate.sh 's/return 1/return 1 #B/' /tmp/mc-run-b
HASH_B=$(sed -n 's/^diff_hash=//p' /tmp/mc-run-b/mutation-control/*.txt | tail -1)
EMPTY=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
[[ "$HASH_A" != "$HASH_B" && "$HASH_A" != "$EMPTY" && "$HASH_B" != "$EMPTY" ]] && echo PASS || echo FAIL
# C: no mutation applied (non-matching anchor) -> non-zero exit, no artifact written
rm -rf /tmp/mc-run-c
bash "$MC" plugins/leadv2/scripts/tests/test-worker-dod-gate.sh plugins/leadv2/scripts/lib/leadv2-dod-gate.sh 's/ZZZ_NO_SUCH_ANCHOR_ZZZ/ZZZ/' /tmp/mc-run-c
echo "rc=$?"  # must be 2, reason=anchor_count
[[ -d /tmp/mc-run-c/mutation-control ]] && echo FAIL || echo "PASS: wrote nothing"
```

## Negative control (WAVE4-mandatory, run for real, suite = `plugins/leadv2/scripts/tests/test-worker-dod-gate.sh`)
Mutation lands **inside** `_dod_valid_mutation_artifact`'s body — delete the empty-hash rejection
line, `lib/leadv2-dod-gate.sh:276`:
```bash
# before (current, correct):
[[ "${artifact_hash}" =~ ^[0-9a-f]{64}$ ]] || return 1
[[ "${artifact_hash}" != e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ]] || return 1
# mutate to (delete line 276 only):
[[ "${artifact_hash}" =~ ^[0-9a-f]{64}$ ]] || return 1
```
Run `bash plugins/leadv2/scripts/tests/test-worker-dod-gate.sh`: with the line deleted, Step 2's new
case MUST fail (the hand-forged empty-hash fixture is wrongly accepted) — suite exit ≠ 0. Restore
the line, re-run: suite exit = 0. Paste both exit codes verbatim in `report.md`.

## Out of scope
- Re-implementing the writer/reader fix — already landed, do not duplicate the hashing/rejection logic.
- The separate review-ledger `diff_hash` (`leadv2-dispatch-code.sh:3572`,
  `leadv2-dispatch-product-close.sh:3022`, `leadv2-review-run.sh`, `leadv2-builder-selfcheck.sh:537`)
  — hashes a review-diff FILE, unrelated concept, already discussed in `docs/handoff/WORKER-DOD-GATE-01/*`.
- Mass retro-invalidation sweep — blast radius is zero; nothing to invalidate (recommendation: no
  action needed beyond noting this in `report.md`, since the one directory the original report named
  is already regenerated and clean).
- Fixing the stale exit-code-2 reason list in `leadv2-mutation-control.sh:31-35` doc comment
  (omits `empty_mutation_diff`) — cosmetic, note it, do not block on it.
