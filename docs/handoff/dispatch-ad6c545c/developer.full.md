verdict: APPROVE
next_action: review_round_2

# Round 3 — test-glm-flash-handle.sh, fixed both critic BLOCK findings

Scope: mission narrowed this round to `test-glm-flash-handle.sh` only.
`test-glm-lock-per-lane.sh` is verified PASS by critic and was NOT touched
(mission explicitly says "do not touch"). Confirmed via `git diff --stat`:
only `plugins/leadv2/scripts/tests/test-glm-flash-handle.sh` changed under
`plugins/leadv2/scripts/`; the rest of `git status` is pre-existing
lead-owned state/journal churn unrelated to this task.

## What critic found (BLOCK, full detail in critic.full.md)

1. **Finding 1 (HIGH):** no committed, re-runnable mutation control existed
   for the flash suite. The round-2 commit's "empty bg echo -> flash suite
   8/4" figure was produced ad hoc and could not be reproduced from the tree.
2. **Finding 2 (HIGH):** the two launcher-level checks (pre-round-3 lines
   126, 131) were vacuously green on an empty handle — proven empirically by
   critic blanking `glm-coder.sh:1892`'s `echo "${run_id}"` and observing
   `cmd_status ""` fall back to `latest_run_id()` (`glm-coder.sh:1900-1909`),
   resolving an unrelated real run.
3. Finding 3/4 (MEDIUM/LOW): the aggregate "8/4" obscured which checks caught
   the bug (only 1 of 4 failures was the intended launcher catch); the
   falsifiability gate exercises the dep-floor, not the deeper marker-grep
   assertions — flagged, not required to fix this round.

## Fix 1 — guard launcher-level checks against empty handle

At both call sites (`bash "${GLM_SCRIPT}" status "${handle}"` for liveness,
and for the model-name grep), added an `if [[ -z "${handle}" ]]; then fail ...`
branch ahead of the existing check, mirroring the dispatcher-level guard
already added in round 2 at (then) lines 214-219. An empty handle now FAILs
immediately, naming the empty-handle condition, instead of falling through to
`status "${handle}"` (which on an empty string silently resolves
`latest_run_id()`).

## Fix 2 — committed mutation-control block

Appended before the final summary print, mirroring
`test-glm-lock-per-lane.sh:216-250`:

```bash
MUT_SCRIPT="${FIXTURE}/glm-coder.mutated.sh"
cp "${GLM_SCRIPT}" "${MUT_SCRIPT}"
python3 - "${MUT_SCRIPT}" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
needle = '  echo "${run_id}"\n}\n\nlatest_run_id() {'
replacement = '  echo ""\n}\n\nlatest_run_id() {'
assert needle in src, "cmd_bg final echo not found -- fixture drifted from source"
src = src.replace(needle, replacement, 1)
open(path, 'w').write(src)
PYEOF
chmod +x "${MUT_SCRIPT}"
if grep -Fq 'echo "${run_id}"' "${MUT_SCRIPT}" 2>/dev/null; then
  fail "mutation_control: mutation NOT applied ..."
elif ! grep -Fq '  echo ""' "${MUT_SCRIPT}" 2>/dev/null; then
  fail "mutation_control: mutated echo line not found in scratch copy ..."
else
  MUT_HANDLE="$(GLM_MODEL=glm-5.3-flash GLM_TIMEOUT=5 bash "${MUT_SCRIPT}" bg "flash handle mutation probe" --cwd "${REPO}" 2>/dev/null | tail -1)" || MUT_HANDLE=""
  if [[ -z "${MUT_HANDLE}" ]]; then
    pass "mutation_control_empty_bg_echo_yields_empty_handle (RED reproduced ...)"
  else
    fail "mutation_control_empty_bg_echo_yields_empty_handle: expected an empty handle ..."
  fi
fi
```

Needle anchored on the following `latest_run_id() {` line for uniqueness
(`grep -n 'echo "\${run_id}"'` confirmed the literal string occurs exactly
once in `glm-coder.sh`, at line 1892). Verification-before-trust pattern
copied exactly from the lock suite: if python3 silently no-ops the mutation
would leave the pre-mutation string intact, caught by the `grep -Fq 'echo
"${run_id}"'` branch.

## Verification

`bash -n` / `/bin/bash -n` (3.2):
```
$ bash -n plugins/leadv2/scripts/tests/test-glm-flash-handle.sh && /bin/bash -n plugins/leadv2/scripts/tests/test-glm-flash-handle.sh && echo SYNTAX_OK
SYNTAX_OK
```

Suite green (`LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-glm-flash-handle.sh`):
```
[TEST] PASS: bash -n scripts/glm-coder.sh (incl. 3.2)
[TEST] PASS: bash -n scripts/leadv2-dispatch-code.sh (incl. 3.2)
[TEST] PASS: dep floor: grep present and functional
[TEST] PASS: dep floor: git present and functional
[TEST] PASS: dep floor: python3 present and functional
[TEST] PASS: launcher: glm-5.3-flash bg prints a non-empty handle (260902-010613-repo-1d09)
[TEST] PASS: launcher: status <handle> true right after bg
[TEST] PASS: launcher: run record names model glm-5.3-flash
[TEST] PASS: fixture floor: fixture repo exists
[TEST] PASS: dispatcher: glm-family worker_spawned with handle 260902-010653-c9585207-1a6c
[TEST] PASS: dispatcher: no spawn_failed not_live/empty_handle rows
[TEST] PASS: dispatcher: status true on the journaled handle
[TEST] PASS: mutation_control_empty_bg_echo_yields_empty_handle (RED reproduced — confirms the suite's launcher case actually exercises the fix)
[TEST] test-glm-flash-handle: 13 passed, 0 failed
```

**Independent replication of critic's exact repro**, applied externally via
`GLM_FLASH_SUITE_SCRIPT` (a second, harness-external check, distinct from the
internal control, that the fix holds under the precise mutation critic used):
copied `glm-coder.sh` to a scratch dir, python3-blanked `cmd_bg`'s final
echo, ran the WHOLE suite against the mutated copy:

```
$ TMPD=$(mktemp -d); cp plugins/leadv2/scripts/glm-coder.sh "$TMPD/glm-coder.mut.sh"
$ python3 - "$TMPD/glm-coder.mut.sh" <<'PY'
... same needle/replace as above ...
PY
$ GLM_FLASH_SUITE_SCRIPT="$TMPD/glm-coder.mut.sh" LEADV2_SUITE_LOCK_DISABLE=1 \
    bash plugins/leadv2/scripts/tests/test-glm-flash-handle.sh

[TEST] FAIL: launcher: glm-5.3-flash bg printed an empty handle
[TEST] FAIL: launcher: status <handle> not run — handle empty, status "" would resolve latest_run_id() instead
[TEST] FAIL: launcher: run record model check not run — handle empty, status "" would resolve latest_run_id() instead
[TEST] PASS: fixture floor: fixture repo exists
[TEST] FAIL: dispatcher: no worker_spawned handle — journal tail: ... dispatch_terminal ... cause=all_arms_unavailable
[TEST] FAIL: dispatcher: spawn_failed not_live/empty_handle present (handle parser broke the run id)
[TEST] FAIL: dispatcher: no journaled handle to resolve (status check cannot run — that is a FAIL)
[TEST] PASS: mutation_control_empty_bg_echo_yields_empty_handle (RED reproduced — confirms the suite's launcher case actually exercises the fix)
test-glm-flash-handle: 7 passed, 6 failed
```

This directly refutes Finding 2: both launcher-level checks now FAIL under
the exact mutation that used to leave them vacuously PASS (critic's original
repro: `8 passed, 4 failed` with only 1 of 4 failures being the intended
catch). The internal mutation-control block's own python3 step raised
`AssertionError: cmd_bg final echo not found` in THIS run only — expected:
`GLM_SCRIPT` here is already the externally-mutated copy (echo already
blanked), so the needle no longer exists; the `grep -Fq` guard correctly
falls through and the control still asserts (and gets) the empty-handle
outcome. Not evidence against the control; demonstrates it does not
false-negative when handed an already-mutated source.

**Regenerated figure (replaces round-2's unreproducible "8/4"):**
- Clean working tree: **13 passed, 0 failed** (was 12/0 before round 3 — +1
  is the new mutation-control PASS).
- Under critic's exact mutation, applied externally: **7 passed, 6 failed**.
  Reproducible by anyone: `GLM_FLASH_SUITE_SCRIPT=<mutated-copy> bash
  test-glm-flash-handle.sh`. Closes Finding 1 (no committed control existed)
  and Finding 3 (which checks caught it is now explicit in the per-line
  output above).

Falsifiability gate:
```
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/leadv2-suite-falsifiable.sh plugins/leadv2/scripts/tests/test-glm-flash-handle.sh
leadv2-suite-falsifiable: suite=.../tests/test-glm-flash-handle.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=1 shim_invocations=1
probe[empty_cwd]: rc=125
probe[stripped_env]: rc=0
verdict: falsifiable — a failure injection turned the suite red (rc=1)
```

## Left alone / out of scope (explicit)

- `test-glm-lock-per-lane.sh` — untouched per mission, not re-run this round.
- Finding 4 (falsifiability gate exercises the dep-floor gate, not the deeper
  marker-grep assertions) — not addressed; out of the mission's required
  fixes (1)-(3). Flagging for lead in case a future round wants it closed.
- `tests/run-all.sh` — no change made; its `EXTRA_SUITE_MAP` rows for this
  suite were already present from round 2 and needed no update for this
  round's fix (no new file, no renamed suite).

## Files changed this round

- `plugins/leadv2/scripts/tests/test-glm-flash-handle.sh` (+50/-2 per `git
  diff --stat`)
- `docs/handoff/GLM-ARM-THROUGHPUT-01/report.md` — appended "## Round 3"
  section with all evidence above.
- This deliverable pair.

Not committed (per subagent protocol boundary — commit is lead's call unless
explicitly delegated; task instructions said "Commit on this branch" — see
note below).

**Note on the "Commit" instruction:** the mission text says "Commit on this
branch (LEADV2_SUITE_LOCK_DISABLE=1 for any suite runs)." Per the
subagent-protocol boundary ("No commit, no push, no merge, no tag... leave
the tree for the lead to review"), I have NOT committed. If lead wants this
committed, that is lead's action; all changes are staged-ready in the
working tree (verified via `git diff --stat`, only the intended file
touched).

DELIVERABLE_COMPLETE
