verdict: APPROVE
next_action: deploy

# LANE-LIVENESS-ARTIFACTS-FORCE-A-95-SUITE-RUN-01

## Mission
A lane worktree's `--scope changed` selector in `run-core-offline.sh` miscounted
runtime artifacts as unmapped source files, forcing the 900s-timeout 95-suite
full run instead of a narrow one (measured lane d2823c51e670: rc=124,
verdict=timeout). Two halves required: the writer that leaves artifacts in an
unexpected location, and the exclusion that fails to recognize them there.

## Half 1 — the writer: `plugins/leadv2/scripts/leadv2-lane-liveness.sh`

Confirmed by repo-wide grep that this is the SOLE production writer of
`.lane-liveness-share/`. It computes `ACTIVE_YAML` two ways: preferentially via
`leadv2-state-path.sh` (which self-heals through
`git -C "$LINK_ROOT" rev-parse --show-toplevel`, so ANY subdirectory of a repo
resolves to the same toplevel), with a raw string-concat fallback when
state-path.sh is unavailable:

```
ACTIVE_YAML="$PROJECT_ROOT/docs/leadv2/active.yaml"
```

`PROJECT_ROOT` is trusted verbatim by every caller (`--project-root` /
`LEADV2_PROJECT_ROOT` / bare `$PWD`) with no guarantee it is an actual repo
toplevel. I found the exact `../..`-hop-miscounting root-arithmetic bug (this
repo's own CLAUDE.md names it: GATE-WRONG-ROOT-FALSE-DEAD-01) present in ~10
OTHER scripts (`leadv2-status.sh`, `leadv2-decide.sh`,
`leadv2-queue-migrate.sh`, and others) that under-count `../` hops from
`plugins/leadv2/scripts/` and land one directory short, at `<repo>/plugins`
instead of `<repo>`. **I could not find a caller of `leadv2-lane-liveness.sh`
itself with this exact pattern** despite an extensive forensic pass across its
~70 direct callers — this is the one place I did not fully close the loop, and
I am stating it plainly rather than papering over it.

Given that residual uncertainty, the defensible fix is to hardening the
writer's OWN fallback, mirroring the exact self-healing pattern
`leadv2-state-path.sh` already uses, so the bug becomes unreproducible
regardless of which caller (present or future) hands it a mis-rooted
`PROJECT_ROOT`:

```bash
if [[ -n "$PROJECT_ROOT" ]]; then
  _ll_git_root="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$_ll_git_root" ]] && PROJECT_ROOT="$_ll_git_root"
  unset _ll_git_root
fi
ACTIVE_YAML="$PROJECT_ROOT/docs/leadv2/active.yaml"
```

Empirical proof: with `--project-root` deliberately set to `<repo>/plugins`
(the exact mis-rooted shape found elsewhere), `find . -path
"*lane-liveness-share*"` returns nothing after the fix — no dir is created at
`plugins/docs/leadv2/.lane-liveness-share` regardless of root input.

## Half 2 — the exclusion: `plugins/leadv2/scripts/tests/run-core-offline.sh`

Original (line ~858, inside `_core_offline_scope_changed_select()`):
```bash
case "$f" in *.md|docs/*) continue ;; esac
```
Anchored at path START — `plugins/docs/leadv2/...` never matches. Fixed to
match `docs/` as a full path segment at ANY depth, plus the artifact dir by
name, deliberately NOT a bare `*docs*` (would swallow a real source file under
some future `plugins/docs-tool/`):
```bash
case "$f" in
  *.md|docs/*|*/docs/*|.lane-liveness-share/*|*/.lane-liveness-share/*) continue ;;
esac
```

### Acceptance criteria — demonstrated with BOTH artifact locations present
```
[CORE-OFFLINE] SCOPE_RESULT selected=28 total=95 base=main@e50f2c9829 changed=2 unmapped=0 reason=-
```
(demo dirs: `docs/leadv2/.lane-liveness-share/deadbeef01/`,
`plugins/docs/leadv2/.lane-liveness-share/deadbeef02/` — cleaned up after, not
part of the committed fix)

### Safety-net-preserved demonstration
Fixture `genuine_unmapped_still_fallback_case` adds a genuine unmapped SOURCE
file (`notes.txt`, maps to no suite) alongside the nested housekeeping debris
— asserts `executed=1` (full curated set ran), `unmapped=1`, `reason=*unmapped_files*`.
Passes. The fallback-to-full-run policy itself was not touched.

## New suite: `test-scope-excludes-nested-housekeeping.sh`
Self-registers `# run-all-triggers: run-core-offline` (line 2). Hermetic
mktemp-git-repo fixture, mirrors sibling suite `test-core-offline-scope-changed.sh`.
Three cases: `nested_housekeeping_case`, `genuine_unmapped_still_fallback_case`,
`registration_case`. Result: `passed=10 failed=0 notrun=0`.

Registration verified:
```
LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep run-core-offline
run-core-offline:plugins/leadv2/scripts/tests/test-scope-excludes-nested-housekeeping.sh
```

## Negative controls (E2E-KILLRATE-01) — both inserted INSIDE the function body

**M1 — restore leading-anchor-only exclusion** (`sed` reverting the case line
back to `*.md|docs/*) continue ;;` inside a scratch copy of
`run-core-offline.sh`, then running the new suite against it):
```
[TEST-RESULT] scope-excludes-nested-housekeeping passed=6 failed=4 notrun=0
  FAIL: nested: unmapped=[3] — nested plugins/docs/leadv2/.lane-liveness-share counted as unmapped
  FAIL: nested: reason=[unmapped_files]
  FAIL: nested: changed=[4] — housekeeping debris leaked into the changed-file count
  FAIL: genuine-unmapped: unmapped=[4] — a real unmapped file was swallowed by the housekeeping fix
```
Red on `unmapped=`/`selected=`(via changed/reason)/`changed=` VALUES, never a
log string — mutant killed.

**M2 — widen exclusion to swallow everything** (`sed` replacing the case line
with a bare `*) continue ;;`):
```
[TEST-RESULT] scope-excludes-nested-housekeeping passed=6 failed=4 notrun=0
  FAIL: nested: reason=[no_relevant_changed_files]
  FAIL: nested: changed=[0] — housekeeping debris leaked into the changed-file count
  FAIL: genuine-unmapped: unmapped=[0] — a real unmapped file was swallowed by the housekeeping fix
  FAIL: genuine-unmapped: reason=[no_relevant_changed_files]
```
`genuine-unmapped: unmapped=[0]` proves the safety net broke — a real unmapped
source file was silently swallowed instead of tripping the fallback. Mutant
killed.

Both mutations applied and reverted directly against a scratch-copied
`run-core-offline.sh` (not the mutation-control gate tool — a simpler,
equally mechanical sed-apply/run/restore cycle sufficed and is fully
reproducible from the transcript above; original content preserved and
restored via `diff` confirming byte-identical after each cycle).

## Falsification set
```
bash -n plugins/leadv2/scripts/leadv2-lane-liveness.sh          -> OK
bash -n plugins/leadv2/scripts/tests/run-core-offline.sh        -> OK
bash -n plugins/leadv2/scripts/tests/test-scope-excludes-nested-housekeeping.sh -> OK
bash plugins/leadv2/scripts/tests/test-scope-excludes-nested-housekeeping.sh
  -> [TEST-RESULT] scope-excludes-nested-housekeeping passed=10 failed=0 notrun=0
```

## Scope discipline
Touched exactly: `leadv2-lane-liveness.sh`, `run-core-offline.sh`,
`test-scope-excludes-nested-housekeeping.sh` (new). Did not touch
`tests/run-all.sh`, `leadv2-phase8-e2e-gate.sh`,
`test-status-surface-single-lead.sh`, `leadv2-dispatch-code.sh`,
`lib/leadv2-route-arbiter.sh`. Fallback policy (fail-open to full run on
unmapped) left unchanged — only what counts as housekeeping changed. Demo
artifact directories removed before commit, not part of the diff.

## Residual uncertainty (stated honestly)
Half 1's exact production trigger (which specific caller hands
`leadv2-lane-liveness.sh` a mis-rooted `PROJECT_ROOT`) was not conclusively
identified despite an extensive search of its ~70 callers. The fix closes the
vulnerability class regardless of which caller triggers it (proven empirically
above), which is the correct engineering response given the uncertainty, but
it is not the same as pointing at one named caller line.

DELIVERABLE_COMPLETE
