verdict: APPROVE
next_action: review_round_2

# INSTALLER-REFUSAL-URGENT-01 — installer must refuse a tracked settings.json

## Branch / commit
- Branch: `wave4-installer-refusal` (created off `main` @ `cade1cf5`)
- Commit: `af202b4e` — "fix(install): refuse to write env block into a tracked settings.json"
- Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/INSTALLER-REFUSAL-URGENT-01`

## What changed
`plugins/leadv2/scripts/leadv2-repo-install.sh`, `env_py()` block (~line 342 onward):

1. New helper `_lv2_settings_is_tracked(repo)` — `git -C "$repo" ls-files --error-unmatch .claude/settings.json`, exit 0 = tracked.
2. New helper `_lv2_settings_target(repo)` — returns `.claude/settings.local.json` when tracked, else `.claude/settings.json` (unchanged behaviour when untracked/absent/non-repo).
3. `env_py()` computes `settings_target` via `_lv2_settings_target "$REPO"` and passes it to the embedded Python as `LV2_SETTINGS_PATH`; the Python side now opens `pathlib.Path(os.environ["LV2_SETTINGS_PATH"])` instead of hardcoding `.claude/settings.json`. Both `check` and `write` modes go through the same `env_py()` function, so both target the identical resolved path — satisfies the mission's point 4 (no more "MISSING forever after a correct write").
4. Merge logic is untouched — same `missing = [k for k in want if k not in env]` / `d.setdefault("env",{}).update(...)` as before, just against the new target path.
5. On write, if the repo's `.claude/settings.json` is tracked, the row line now reads `tracked — left untouched; added N key(s) to .claude/settings.local.json instead` (stdout), instead of the old `added N key(s)`.

Did NOT touch: `env_py()`'s `want{}` dict, `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`, or anything under `docs/leadv2/` (those paths show as dirty in `git status` from other concurrent lane/lead activity in this shared worktree — never staged or committed by this change; `git diff --stat main..HEAD` below shows only the 3 files touched).

## Diff stat
```
plugins/leadv2/scripts/leadv2-repo-install.sh      |  26 +++-
.../tests/test-repo-install-tracked-settings.sh    | 167 +++++++++++++++++++++
tests/run-all.sh                                   |   3 +-
3 files changed, 193 insertions(+), 3 deletions(-)
```
No file present on `main` is deleted by this branch (only these 3 files changed; 2 modified, 1 added).

## Scratch-repo acceptance (run, not described)
All under `mktemp -d`, with `LEADV2_STATE_BASE` pointed at a scratch dir so the real `~/.claude/leadv2-state` is never touched.

**Case 1 — tracked settings.json stays byte-identical, block lands in settings.local.json:**
```
SHA_BEFORE = 91adc84ca7ed6a3bf62b25711f7b067bba4b82463e1212ce74ca00c4dbb52d6e
SHA_AFTER  = 91adc84ca7ed6a3bf62b25711f7b067bba4b82463e1212ce74ca00c4dbb52d6e   (unchanged)
settings.local.json created, contains LEADV2_PROJECT_ROOT etc.
stdout: "  .claude/settings.json env       tracked — left untouched; added 17 key(s) to .claude/settings.local.json instead"
```
`--check` afterwards → rc=0 (targets settings.local.json, which is now complete — not "MISSING" forever).
Ran installer a 2nd time in this state: settings.local.json sha unchanged (idempotent, no duplicate keys), tracked settings.json still byte-identical.

**Case 2 — `git rm --cached .claude/settings.json` (still on disk, now untracked), run again:**
```
env block now lands directly in settings.json (contains LEADV2_PROJECT_ROOT)
2nd run: settings.json sha unchanged between run 1 and run 2 (idempotent)
```

Both cases run via the new suite `test-repo-install-tracked-settings.sh` (paste below is the actual run).

## Negative control — mandatory (mutation INSIDE the function body)
Mutation: `_lv2_settings_is_tracked() { git -C "$1" ls-files --error-unmatch .claude/settings.json >/dev/null 2>&1; }` body replaced with `_lv2_settings_is_tracked() { return 1; }` (always "untracked") — applied with `sed` directly inside the function body, not a top-level insert.

**RED (mutation applied to the real production `leadv2-repo-install.sh`, macOS):**
```
FAIL: scenario A: tracked settings.json CHANGED (91adc84c... -> cc530930...)
FAIL: scenario A: env block missing from settings.local.json
FAIL: scenario A: stdout missing tracked-file refusal message (...)
PASS: scenario A: --check reports ok against settings.local.json (rc=0)
PASS: scenario A: second run is idempotent (settings.local.json unchanged, no duplicate keys)
FAIL: scenario A: tracked settings.json drifted on second run
PASS: scenario B / non-repo / negative-control-mutated-copy cases still pass
----
PASS=6 FAIL=4
RED_EXIT=1
```

**GREEN (mutation reverted from `/tmp` backup, macOS):**
```
PASS=10 FAIL=0
GREEN_EXIT=0
```

**Linux container (docker `bash:5`, alpine + git + python3 installed):**
```
RED:   PASS=6 FAIL=4   RED_EXIT=1
GREEN: PASS=10 FAIL=0  GREEN_EXIT=0
```
(Alpine's `bash:5` image ships neither `shasum` nor a preinstalled `git`/`python3` — the suite's `sha()` helper falls back to `sha256sum` when `shasum` is absent; `git`/`python3` were `apk add`-ed into the ephemeral container. Both were reverted/discarded automatically — the container is `--rm` and the mutation applied through the bind mount was restored from a `/tmp` backup copy before the container exited, confirmed on host afterward: `git status --short` shows no diff beyond the intended fix.)

Committed production file is confirmed identical to the working, reverted, fixed version (`diff` against the pre-mutation backup showed no difference).

## `--scope changed` suite selection
The suite's own "changed" state file (`$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha`, worktree-scoped) had to be cleared for a clean demonstration — it had already recorded this commit's own SHA from an earlier probing run, which made the range empty (round-4 "already-checked" behavior working as designed, not a bug). After clearing it, using the built-in `LEADV2_RUN_ALL_SELECT_ONLY=1` non-executing seam (`tests/run-all.sh:557-559`) instead of a full run (avoids the >10min `run-core-offline.sh` always-on suite):
```
$ rm -f "$(git rev-parse --git-dir)/leadv2-run-all-last-checked-sha"
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-adoption-gate-passable.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-fable-think-tier.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-repo-install-tracked-settings.sh   <-- my suite selected
[SELECT] .../tests/test-run-all-carrier-map.sh
run-all: 8 selected, scope=changed, select_only=1
```

## EXTRA_SUITE_MAP edit
Exactly one row appended at the end of the existing block (`tests/run-all.sh`), no reordering/reflow of existing rows:
```
leadv2-repo-install.sh:plugins/leadv2/scripts/tests/test-repo-install-tracked-settings.sh
```

## Self-falsification (bash -n / py_compile / changed-scope runner)
```
$ bash -n plugins/leadv2/scripts/leadv2-repo-install.sh && echo OK
SYNTAX_OK: leadv2-repo-install.sh
$ bash -n plugins/leadv2/scripts/tests/test-repo-install-tracked-settings.sh && echo OK
SYNTAX_OK: test-repo-install-tracked-settings.sh
$ bash -n tests/run-all.sh && echo OK
SYNTAX_OK: run-all.sh
```
No Python files changed — `py_compile` step N/A (only bash + one YAML-shaped string block touched).

Full test suite run (macOS, final state, GREEN):
```
PASS: scenario A: tracked settings.json byte-identical (sha 91adc84ca7ed6a3bf62b25711f7b067bba4b82463e1212ce74ca00c4dbb52d6e)
PASS: scenario A: env block landed in settings.local.json
PASS: scenario A: stdout announces the tracked-file refusal
PASS: scenario A: --check reports ok against settings.local.json (rc=0)
PASS: scenario A: second run is idempotent (settings.local.json unchanged, no duplicate keys)
PASS: scenario A: tracked settings.json still byte-identical after second run
PASS: scenario B: now-untracked settings.json receives the env block
PASS: scenario B: second run is idempotent (no duplicate keys)
PASS: non-repo target: env block written straight to settings.json as before
PASS: negative control: mutation KILLED — tracked settings.json got overwritten as feared
----
PASS=10 FAIL=0
```

## Deliberately left alone
- `env_py()`'s `want{}` dict, key set, and merge semantics — unchanged.
- `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh` — untouched (off-scope per mission).
- Nothing already on disk in any real adopted repo (persona-engine, m3-market, m3-promo, m3-trait) was migrated or touched — that is explicitly out of scope for this lane (INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01 handles the rest, on its own lane).
- `docs/leadv2/*` dirty files visible in `git status` throughout this session belong to other concurrent lane/lead activity in this shared worktree — never staged, added, or committed by this change.

## Steps that could not be run
None — every acceptance item in the mission (scratch-repo assertions, negative control RED/GREEN, macOS + linux exit codes, `--scope changed` selection line) was executed and its real output pasted above, not summarized.

DELIVERABLE_COMPLETE
