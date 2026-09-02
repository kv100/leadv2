# HOOKS-PARITY-ACROSS-REPOS-01 — drift record for `leadv2-immune-intake-inject.sh`

Measured 2026-09-03, lane HOOKS-PARITY-ACROSS-REPOS-01. This file records the
diffs BEFORE any consumer-repo file is deleted (lane constraint), and the
per-repo verdicts.

Canonical: `plugins/leadv2/hooks/leadv2-immune-intake-inject.sh` (124 lines) at
lane branch `worktree-HOOKS-PARITY-ACROSS-REPOS-01`, merge base `caa34ed5` (= main).

## Verdict up front

All four consumer copies are the SAME stale generation of the hook — the
pre-MEM-SEMANTIC-RECALL-01 version. `persona-engine` and `getmany-followup-bot`
copies are byte-identical to each other (`diff` → empty, rc=0). Canonical is
STRICTLY AHEAD of every fork: every hunk is canonical-gained content, none is
fork-local work. **Nothing needed porting up.**

## What canonical has that the forks lack (the whole drift)

1. **Durable REPO_ROOT** — canonical resolves
   `LEADV2_PROJECT_ROOT` → `git rev-parse --git-common-dir` (worktree-safe);
   forks use `dirname ${BASH_SOURCE[0]}/../..`, which points into the PLUGIN
   install dir once loaded via `${CLAUDE_PLUGIN_ROOT}` → wrong repo root.
2. **Canonical lookup-script preference** — canonical prefers
   `${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-immune-lookup.sh`, falling back to the
   repo copy; forks hardcode the repo copy (rsync-staleness class).
3. **Lookup-script existence check** — canonical skips when
   `leadv2-immune-lookup.sh` is missing; forks would run lookup unconditionally
   (respiro-ios's copy had its own private early-exit for this; canonical
   already covers it in the PATTERNS_FILE/LOOKUP_SCRIPT combined skip).
4. **C2 score-gate fix** — forks gate on a single `score > 0.4` across two
   incompatible scales; canonical gates `score > 0 OR sem_cosine >= 0.35` on
   each match's native scale. Real keyword matches (~0.09–0.36 observed) were
   discarded by the fork gate — i.e. **the forks have been silently injecting
   nothing for months**.
5. Semantic-match annotation in the context output (`cosine=…` tag).

## Fork-vs-canonical diffstat (measured)

| repo | drift vs canonical | notes |
|---|---|---|
| persona-engine | 58 diff lines | stale gen; == getmany copy byte-for-byte |
| getmany-followup-bot | 58 diff lines | same bytes as persona-engine |
| m3-market | 58 diff lines + path header | same body as respiro-ios copy |
| respiro-ios | 64 diff lines | same as m3-market plus old watched path |

Two residual textual deltas, neither fork-local work:

- **Watched intake path in the header comment**: forks say
  `docs/leadv2/tasks/*/intake.md`, canonical says `docs/handoff/*/intake.md` —
  canonical moved the watched path when handoff dirs replaced leadv2 task dirs;
  this is an OLD canonical value, not a repo customization. respiro-ios has no
  `docs/handoff/` yet (checked: dir absent) and will gain it with its first
  handoff-based task; canonical is the forward-correct value.
- respiro-ios/m3-market copy carries an extra
  `[[ ! -f "$LOOKUP_SCRIPT" ]] && exit 0` guard — subsumed by canonical's
  combined skip (item 3).

## Per-repo disposition

| repo | path | action |
|---|---|---|
| persona-engine | `.claude/hooks/leadv2-immune-intake-inject.sh` | real file (2864 B, tracked) → symlink to canonical |
| getmany-followup-bot | same | real file (2864 B, tracked) → symlink to canonical |
| respiro-ios | same | real file (2956 B, tracked) → symlink to canonical |
| m3-market | `~/MythicalGames/m3-market/.claude/hooks/leadv2-immune-intake-inject.sh` | real file (2864 B) → symlink to canonical |

Each consumer repo's own settings.json wiring is left untouched (outside lane
writes): the hook keeps firing through the symlink, now executing canonical
bytes. This matches the established convention in persona-engine, where
`leadv2-pulse-json.sh`, `leadv2-model-inherit-guard.sh` and
`leadv2-supervisor-mode-reinject.sh` are already absolute symlinks into
`~/Projects/leadv2/plugins/leadv2/hooks/`.

## The rule (deliverable 3)

Plugin-owned = anything whose filename exists in `plugins/leadv2/hooks/`:

1. The plugin manifest (`hooks/hooks.json`) wires plugin-owned hooks for every
   adopter; no consumer repo may hold a REAL file with a plugin hook's name.
   Sanctioned shapes: symlink into the canonical plugin tree, or absence.
2. Everything else under `.claude/hooks/` is repo-local: wired by that repo's
   own `settings.json`, owned by that repo, never named after a plugin hook.
3. The rule is checkable, not a list to maintain:
   `bash plugins/leadv2/scripts/leadv2-hook-fork-guard.sh` — exit 1 iff rule 1
   is violated anywhere under `$LEADV2_HOOK_FORK_SCAN_ROOTS` (default
   `$HOME/Projects:$HOME/MythicalGames`). Wired as a plugin SessionStart hook
   (same commit series), so it fires in every adopter without anyone remembering.

## Wiring (deliverable 1) — where and why

**Chosen: plugin manifest SessionStart entry** (`plugins/leadv2/hooks/hooks.json`,
startup entry, appended as hook #13), wrapped in the standard degrade pattern:
rc=1 (violations) → the FAIL lines + a summary line go to stdout, which the
harness injects as session context, and the wrapper exits 0 (a parity drift
must not block session start); rc≥2 (fatal, e.g. missing scan root) → degrade
log + exit 0.

Rejected `leadv2-repo-install.sh` as the sole trigger: it fires only when a
human types `/leadv2`, which is not "without anyone remembering". Rejected CI:
the four consumer repos have no shared CI that runs plugin checks. SessionStart
fires in every adopter on every session — the guarantee the lane asked for.

**Deployed live**: `leadv2-plugin-cache-sync.sh` run from the lane root →
`synced=1064 cache=.../cache/leadv2-local/leadv2/0.5.7 repo_head=ed25d3d2`;
the cache's `hooks.json` now carries the wired entry (grep count 1) and the
guard body is in the cache `scripts/`. Sessions started after 2026-09-03
01:45 local load the hook; already-running sessions do not (inherent — hook
lists are read at session start). The guard's script BODY is live-from-repo
via the `CLAUDE_PLUGIN_ROOT` → `plugins/local` symlink pin, so body fixes need
no re-sync; only the hooks.json list did, and it got it.

## Proofs (2026-09-03, script: `/tmp/hook-parity-proof.sh`, 6 pass / 0 fail)

Case 1 — scratch consumer repo with a real copy, WIRED path (harness-emulated:
hooks.json command extracted, run with `CLAUDE_PLUGIN_ROOT` at the plugin):

```
FORK-GUARD FAIL: real copy of plugin-owned hook: /tmp/hook-parity-proof.wdxZG6/copy-repo/.claude/hooks/leadv2-immune-intake-inject.sh
FORK-GUARD: 2 hook-installation(s) checked, 1 violation(s)
HOOK-FORK-GUARD: real copies of plugin hooks detected in consumer repos (see FAIL lines above)
PROOF PASS: real copy detected through the wired SessionStart path
```

Case 2 — same repo with a symlink instead → silent:
```
FORK-GUARD: 1 hook-installation(s) checked, 0 violation(s)
PROOF PASS: symlink repo silent
```

Case 3 — repo-own hook with no canonical counterpart → silent (the
false-positive case that matters most):
```
FORK-GUARD: 0 hook-installation(s) checked, 0 violation(s)
PROOF PASS: repo-own hook silent — guard does not cry wolf
```

Case 4 — negative control: mktemp copy of the plugin with the fork-guard
entry unwired (baseline plugin wires 1 fork-guard command, mutant wires 0),
same real-copy fixture:
```
fork-guard commands wired in MUTANT: 0 (baseline plugin: 1)
(no fork-guard command wired — nothing to run)
PROOF PASS: mutant has zero fork-guard commands wired — real copy is NOT detected
PROOF PASS: mutant run silent on the same real copy
```
Detection is therefore attributable to the wiring, not to anything else.

Unit suite: `plugins/leadv2/scripts/tests/test-hook-fork-guard.sh`
→ 6 pass / 0 fail (4 original directions + 2 new: multi-root discovery,
legacy singular env).

## Census after cleanup

| repo | wired | real files | symlinks |
|---|---|---|---|
| persona-engine | 40 cmds | 32 (was 33) | 4 (was 3) |
| respiro-ios | 22 cmds | 4 (was 5) | 1 (was 0) |
| getmany-followup-bot | 7 cmds | 2 (was 3) | 1 (was 0) |
| m3-market | 30 cmds | 14 (was 15) | 1 (was 0) |

Guard on the live machine after cleanup:
```
FORK-GUARD: 6 hook-installation(s) checked, 0 violation(s)   (rc=0)
```
(was 5 checked / 3 violations before the multi-root fix — m3-market invisible;
6 checked / 4 violations with the fix before the swap.)

Repo-own hooks: untouched (each consumer repo's `.claude/hooks/` shows exactly
one change in git — the mode change to symlink of `leadv2-immune-intake-inject.sh`;
persona-engine's other 3 pre-existing symlinks predate this lane).

Known limit, stated honestly: stale real copies still exist inside OLD
persona-engine `.claude/worktrees/*/.claude/hooks/` snapshots. The guard
scans one level (`<root>/<repo>/.claude/hooks`) by design — worktrees are
ephemeral lane state that dies with its lane, and scanning them would flag
hundreds of stale checkout artifacts, i.e. crying wolf.

## Consumer-repo commits

- persona-engine `b831dd053`, respiro-ios `f13e1cb`, getmany-followup-bot
  `c2dfab0` — hook file → symlink. getmany's first commit accidentally swept
  three unrelated staged files (another session's migration+tests); it was
  soft-reset and re-committed pathspec-only; their staged files are back in
  the index untouched.
- m3-market: hook file was untracked in that repo → swap is a filesystem-only
  change, nothing to commit.
