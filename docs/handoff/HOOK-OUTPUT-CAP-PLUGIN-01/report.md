An ordinary session start's leadv2-one-copy-drift.sh output drops from 46256 B to 231 B measured
in the main checkout (~/Projects/leadv2); leadv2-truth-card-inject.sh is unaffected in that same
repo (145 B before and after, since leadv2 itself carries no persona_truth_card data — see below)
but its cap is proven correct via fixture (a >2048 B synthetic card is capped to 345 B, full card
written to disk).

## What changed and why

Two SessionStart hooks, both plugin-owned and shared across persona-engine/m3-market/respiro-ios
via symlink, injected their full detail into `additionalContext` — re-sent on every later turn of
every session that starts. Capped both at source: keep the fact + count/headline, write full
detail to disk, print a path.

### `plugins/leadv2/hooks/leadv2-one-copy-drift.sh`
Was: dumped every `[one-copy] REGRESSION`/`BADLINK`/`tally` line straight to stdout (582 lines /
46257 B measured against a real drifted tree). Now: always writes the full grep output to
`${TMPDIR:-/tmp}/leadv2-one-copy-drift-detail.log`, and stdout carries only the warning marker, a
count line (`N regression(s)/badlink(s). <tally line>`), and `Full list: <path>`. Applies on both
the SessionStart path and the PostToolUse:Bash post-sync path (same `report` variable, same
`printf '%b\n' "$report"` sink — one code path, not two).

Measured (main checkout, `~/Projects/leadv2`, SessionStart-shaped payload, `CLAUDE_PLUGIN_ROOT`
pointed at the real plugin cache so `resolve_canonical_root` falls back to the main checkout
exactly as the harness does):
- Before (pre-fix hook, same command): **46256 B**
- After (fixed hook script from this worktree, run against the SAME main-checkout drift state):
  **231 B**, full 46238 B detail on disk at `/tmp/leadv2-one-copy-drift-detail.log`.

### `plugins/leadv2/hooks/leadv2-truth-card-inject.sh`
Was: on a populated `persona_truth_card` row, printed the entire card (engine state, last
activity, pipeline health, working hours, verification rules) as one long `additionalContext`
string with no size bound. Now: the python heredoc assembles the same `full_text` as before, and
only if `len(full_text) > 2048` does it write `full_text` to
`<TMPDIR>/leadv2-truth-card-full-<slug>.txt` and emit a short summary (freshness header, RUN_MODE/
CONTROL_MODE, `Full card: <path>`) instead. Below the cap, behaviour is byte-for-byte unchanged
(verified — T4).

Measured (main checkout, `~/Projects/leadv2`): **145 B before and after**, unchanged — this repo
has no `.env` Supabase credentials and no `state-paths.yaml` persona_id (it's the orchestrator
repo, not a persona-engine checkout), so the hook takes the `[TRUTH CARD FAILED] ... not found in
.env` short-circuit both before and after the cap in either case; the cap branch is never reached
here. UNVERIFIED: the mission text's cited baseline of ~7758 B for this hook was, per its own
wording, "measured in a worktree" and called wrong; I could not reproduce a populated-card
measurement in the leadv2 main checkout either, for the reason above — a real 7758 B-class
measurement would need a persona-engine checkout with live Supabase creds, outside this lane's
worktree pin. The cap's correctness is instead proven with a controlled fixture (T3 below): a
synthetic row whose `working_hours_json` is padded to push the assembled card past 2048 B produces
a 3918 B `full_text`, capped to 345 B stdout with the full 3918 B card written to disk.

## Controls (RED before the cap existed, GREEN after) — `round1-red/`

Both controls mutate the **production hook file in place** (not a scratch copy), run the new
suite, capture RED, then restore the original file (`cp` from a pre-mutation snapshot, `diff`
confirmed clean) and capture GREEN.

- `round1-red/one-copy-drift-cap.RED-then-GREEN.log` — mutated the summary-assembly line to
  `report="$report"$'\n'"$(cat "$DETAIL_LOG")"` (dumps the full list back into stdout instead of
  the count). RED: T1 fails, stdout = 15112 B, full REGRESSION list back in `additionalContext`.
  GREEN after revert: 6/6 pass, T1 = 258 B.
- `round1-red/truth-card-inject-cap.RED-then-GREEN.log` — mutated `CAP = 2048` to
  `CAP = 999999999` inside the python heredoc. RED: T3 fails, stdout = 3975 B (full uncapped
  card). GREEN after revert: 6/6 pass, T3 = 345 B.

Both mutations matched exactly 1 line (confirmed via `grep -c` before running RED) — no zero-match
sed.

## New suite — `plugins/leadv2/scripts/tests/test-hook-output-cap.sh`

6 cases: `bash -n` on both hooks, T1 (100-regression fixture capped + full detail on disk), T2
(clean tree stays silent, cap path not taken), T3 (oversized truth-card fixture capped + full card
on disk), T4 (small truth-card fixture emitted directly, cap path not taken, no disk file). All
green (see above). Fixtures use a scratch canonical root (`mk_one_copy_fixture`, same pattern as
the existing `test-one-copy-drift-hook-postsync.sh`) and a scratch CWD + stubbed `curl` on `PATH`
(`mk_truth_card_fixture`) — no network access, no real Supabase call.

## `tests/run-all.sh` — `--scope changed` selects the new suite

The existing changed-scope matcher only considered `plugins/leadv2/scripts/*.sh`; a change under
`plugins/leadv2/hooks/*.sh` never entered the stem-lookup loop, so `EXTRA_SUITE_MAP` could not have
selected anything for these two files no matter what it contained. Widened the `case` guard to
also match `plugins/leadv2/hooks/*.sh`, and added two `EXTRA_SUITE_MAP` rows:

```
leadv2-one-copy-drift.sh:plugins/leadv2/scripts/tests/test-hook-output-cap.sh
leadv2-truth-card-inject.sh:plugins/leadv2/scripts/tests/test-hook-output-cap.sh
```

Proof: `round1-red/scope-changed-selects-new-suite.log` — the SUITES-computation portion of
`tests/run-all.sh` (lines 1-160, before the execution loop) run standalone against the real
`git diff --name-only HEAD` for this branch; `test-hook-output-cap.sh` appears in the selected
list alongside the always-on suites. (Full `tests/run-all.sh --scope changed` execution was
abandoned after 5+ minutes — `ps aux` showed a dozen-plus other worktrees' `run-core-offline.sh` /
`run-all.sh --scope changed` processes stuck at ~0.01s CPU simultaneously, a system-wide resource
contention condition unrelated to this change. The individually-selected suites —
`test-hook-output-cap.sh`, `test-status-surface-bash32.sh`, `test-status-surface-single-lead.sh`,
`test-status-surface-fast-names.sh` — were each run directly with a 60s timeout and passed; see
`round1-red/` and the transcript.)

## Existing suite fixed for the new (intended) output format

`plugins/leadv2/scripts/tests/test-one-copy-drift-hook-postsync.sh` asserted the literal
`[one-copy] REGRESSION` line in stdout in three places (T1, T1b, T3) — stale after the cap
replaces that raw line with the `N regression(s)/badlink(s).` summary. Updated those three
assertions to the new literal; the suite's actual intent (three-leg SessionStart/PostToolUse/
kill-switch contract) is untouched. 7/7 pass.

## Hard constraints honored

- `hooks.json` untouched — `git diff --stat` confirms no changes to that file.
- `scheduled-decisions-inject.sh` untouched.
- No edits to `~/.claude/leadv2-shared/` or any shared tree.
- Both caps stay loud on real drift/data: the one-copy cap always states the count and never
  silences a real regression (T1); the truth-card cap always keeps the freshness header and
  RUN_MODE/CONTROL_MODE headline (T3) — never turns a real problem into silence.
- Bash 3.2 compatible: no `read -N`, no bash-4 array idioms; the one C-style `for ((i=1;...))`
  loop in the new test fixture is bash 3.2-compatible (verified via `bash -n`, and the fixture
  itself already ran under the system's default `/bin/bash` in every test invocation above).

## Round 2 (this pass) — three reviewer findings

### [Critical] hook was silent about a crash-shaped failure — FIXED

`leadv2-one-copy-drift.sh`: when `leadv2-one-copy-convert.sh --check` exits non-zero with stderr
that matches none of `REGRESSION`/`BADLINK`/`tally` (a traceback, a missing-dependency error), the
old code still ran `grep -E '^\[one-copy\] ...'` over it, got zero matches, and reported
`0 regression(s)/badlink(s).` against a 0-byte detail log — silencing a real failure as if the tree
were clean. Fixed: after the grep, if `DETAIL_LOG` is empty (`[[ ! -s "$DETAIL_LOG" ]]`), write the
raw `$output` to it instead and report `⚠ one-copy drift check FAILED` +
`... exited <status> with no recognizable REGRESSION/BADLINK/tally output` + `Full output: <path>`.
The normal-drift branch (non-empty detail log) is unchanged.

Control (mutation-proven, this session):
- Added `mk_one_copy_fixture_crash` + test T5 to `test-hook-output-cap.sh`: a stub checker that
  writes a 3-line traceback to stderr and `exit 2`s.
- GREEN (fix in place): 7/7 pass, T5 passes — stdout contains `FAILED`/`exited 2`, detail log is
  non-empty and contains `RuntimeError: fixture-induced crash`.
- RED (mutated `leadv2-one-copy-drift.sh` in place, reverting the crash-branch back to the old
  unconditional-grep code — exact match, single block, confirmed present before mutating): 6/7 —
  T5 fails with `rc=0 detail=0 stdout=⚠ one-copy drift / 0 regression(s)/badlink(s). / Full list:
  <path>` — i.e. reproduces the reviewer's exact repro verbatim.
- Reverted mutation (re-applied the fix), re-ran: 7/7 GREEN again.

### [High] `--scope changed` didn't select the suite post-commit with unrelated dirt — FIXED

`tests/run-all.sh` only fell back to `git diff --name-only HEAD~1..HEAD` when the uncommitted
`git diff --name-only HEAD` was *empty*. In this repo, concurrent lanes routinely leave
`docs/leadv2/*` coordination files dirty, so `changed` was never empty and the committed-lane-file
fallback never fired. Fixed: `changed` is now the **union** of both diffs (unconditionally appends
`HEAD~1..HEAD` whenever `HEAD~1` exists), not an either/or.

Proof, at the actual current committed HEAD (`41256ac`) with the 9 unrelated `docs/leadv2/*` files
dirty (`git status --short` — confirmed non-lane, pre-existing coordination files):
- Extracted lines 49-165 of `tests/run-all.sh` (the SUITES-selection block only, to avoid running
  the full multi-minute `run-core-offline.sh` always-on suite) into a standalone script with
  `ROOT`/`SCOPE` pinned to this worktree, appended `printf "%s\n" "${SUITES[@]}"`.
  Result: `test-hook-output-cap.sh` IS in the selected list, alongside the three always-on
  `test-status-surface-*` suites.
- RED control: same extraction, with the union logic mutated back to the original either/or
  (`if [[ -z "${changed}" ]] && ...`). Result: `test-hook-output-cap.sh` drops out of the selected
  list entirely (only the always-on suites remain) — reproduces the reviewer's exact failure mode.
- GREEN: re-ran the unmutated (i.e. actual committed) selection block — `test-hook-output-cap.sh`
  selected again.
- `bash tests/run-all.sh --scope changed` full execution (not just the selection block) was not
  run to completion: `run-core-offline.sh` (the always-on first suite, 111 files) alone exceeded a
  2-minute timeout in this session, consistent with the round-1 note about multi-lane resource
  contention on this machine. The selection-block extraction above is the falsification evidence
  for the fix itself; `test-hook-output-cap.sh` was additionally run standalone (7/7 pass, see
  above) to prove the suite it now selects is itself green.

### [Medium] persona-engine cache still pays the old bill — recorded, not fixed (lane cannot touch cache)

Per CLAUDE.md, hooks are the one exception to single-inode sharing: `~/.claude/plugins/local/
leadv2/plugins/leadv2/hooks/*.sh` is a separate copy, not a symlink, and `claude plugin update`
no-ops when content changed but the plugin version didn't.

Confirmed stale in this session:
- `~/.claude/plugins/local/leadv2/plugins/leadv2/hooks/leadv2-one-copy-drift.sh`: **4327 B**
  (source), `diff` against this worktree's fixed `plugins/leadv2/hooks/leadv2-one-copy-drift.sh`
  shows they differ — the cache predates even the round-1 fix.
- `~/.claude/plugins/local/leadv2/plugins/leadv2/hooks/leadv2-truth-card-inject.sh`: **8888 B**
  (source), same — differs from this worktree's fixed version.
- Runtime output byte counts (46256 B → 231 B for one-copy-drift; the reviewer's independently
  measured 45,705 B → 277 B and, in persona-engine, 7,758 B → 287 B for truth-card-inject) are
  UNVERIFIED by me for the persona-engine repo specifically — I did not have Supabase creds or a
  persona-engine checkout in scope for this worktree-pinned lane; those numbers are the reviewer's
  own reproduction, reported in the mission text, not independently reproduced here.

What's needed (not performed — out of this lane's writable scope, "do not attempt the refresh from
inside the lane"): the plugin cache directory must be refreshed from `~/Projects/leadv2` (the
canonical repo, once this lane's fix lands there) and any persona-engine / m3-market / respiro-ios
session must be **restarted** — a running session's hook is already loaded into its process
environment and a cache-file update alone does not reload it mid-session.

## Left alone

- Did not touch the other ~5 SessionStart hooks in `hooks.json`; out of this lane's declared
  scope (`leadv2-one-copy-drift.sh` and `leadv2-truth-card-inject.sh` only).
- Did not attempt to reproduce the mission's cited 7758 B truth-card baseline — see UNVERIFIED
  note above; the cap's correctness against an oversized card is proven by fixture instead.
- `run-core-offline.sh` (the always-on suite) was not run to completion in this session due to
  observed system-wide multi-lane contention (see above) — `bash -n` and the individually-run
  changed-scope suites are the falsification evidence provided.
