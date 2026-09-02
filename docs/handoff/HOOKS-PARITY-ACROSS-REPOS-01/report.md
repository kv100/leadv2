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
