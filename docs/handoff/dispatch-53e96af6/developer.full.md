# dispatch-53e96af6 — developer deliverable

Role: developer (report-only design task). Worktree: `.claude/worktrees/1PLUGIN-FABLE`.

## Outcome

The design is in `docs/handoff/one-plugin-source-fable.md` (the mission's named output). This
file records what was done, what was verified, and what was left alone.

## What changed

- Added `docs/handoff/one-plugin-source-fable.md` — the design (end state, per-project
  boundary, 53-file override census, enforcement, ordered and reversible steps, measurement
  appendix with every command).
- Added this deliverable pair under `docs/handoff/dispatch-53e96af6/`.
- No shell, Python, config, symlink, or deletion changes. `git diff --stat` shows only the
  three Markdown files above.

## Key findings (detail in the design)

1. Consumer repos' `.claude/scripts` are clean: 0 shadow files in persona-engine, getmany and
   m3-market; 1 in respiro (`codex-guard.sh`, canonical is newer). The only "shadows" are
   `__pycache__/*.pyc`.
2. The plugin repo's own gitignored `.claude/scripts` holds 563 real files, 562 of them shadows,
   338 drifted, **193 newer than canonical by mtime** — these must be direction-triaged before
   deletion, not just removed.
3. `~/.claude/leadv2-shared/scripts`: 358 real files, 113 drifted, all 113 older than canonical.
4. getmany holds 20 plugin skill directories and the 3 plugin agents as real files from
   2026-05-06, all drifted; `leadv2-phase8-gate.sh` and `leadv2-reflect-enforcer.sh` exist as
   three distinct files across the three repos with no plugin counterpart.
5. Override hypothesis: 31/53 live and read by the plugin (6–34 readers each), 20/53 unread (all
   persona-engine: gemini-policy, golden sample, two tests, ten rule fixtures, six rules if the
   rules engine is off — UNVERIFIED), 2/53 runtime state.
6. `plugin-scripts-drift-guard.sh` (the blocking commit guard) is wired nowhere; the wired
   SessionStart checker is red (`regression=62 diverged=113`) yet printed nothing in this session
   (cause UNVERIFIED).
7. Two corrections to the mission's inputs: m3-market exists at `~/MythicalGames/m3-market`
   (420 links, 0 shadow, 0 lanes); and at HEAD `tests/run-all.sh:148-152` prefers the plugin
   runner and only falls through to `.claude/scripts/tests/run-core-offline.sh` when
   `plugins/leadv2/` is absent — the P0 owner should re-check against HEAD.

## Falsification set (raw output)

No shell or Python files were changed, so `bash -n` and `py_compile` have no targets:

```
$ git diff --name-only HEAD -- | grep -E '\.(sh|py)$' | wc -l
0
```

Changed-scope runner output is pasted in the "Self-check" section below (appended after the run).

## Deliberately left alone

- The P0 gate defect (`GATE-RUNS-AN-UNTRACKED-HALF-SIZED-CORE-RUNNER-01`): referenced, not fixed.
- Content of any override/hook/skill copy beyond `diff | wc -l`.
- `~/.claude/leadv2-shared/`, `~/.claude/agents-shared/`, `~/.claude/settings.json`, all
  project trees: read only.
- Nested agent spawns: the route arbiter assigned both recon spawns to the `freepool` arm,
  which the Agent tool cannot target, so the censuses were run directly as bounded shell
  loops instead.

## Self-check

Run from the worktree, foreground, `timeout 500`:

```
$ git status --short
?? docs/handoff/dispatch-53e96af6/
?? docs/handoff/one-plugin-source-fable.md
$ bash tests/run-all.sh --scope changed 2>&1 | tail -25
test-status-surface-single-lead: 24 passed, 0 failed
[PASS] .../tests/test-status-surface-single-lead.sh
[RUN] .../tests/test-status-surface-fast-names.sh
== T1: resolve_lane_label fallback chain ==
  ok   - ledger lane_label hit
  ok   - active.yaml worktree fallback
  ok   - mission heading fallback (MISSION-HEADING-TASK — implementation de)
  ok   - miss -> sig8 unchanged
  ok   - lane_label pipe stripped (got 'AB')
== T2: cold cache ==
  ok   - cold cache shows «нет кэша», no spinner
  ok   - cold render <1s (wall 0s)
  ok   - cold render kicked a refresh (lock held)
== T3: warm cache ==
  ok   - warm cache: label in title+row, no sig8 sub-row
  ok   - warm render <1s (wall 0s)
== T4: stale cache ==
  ok   - stale cache -> «⚠️ кэш устарел»
== T5: rename hygiene (SELF_PATH) ==
  ok   - copy-reply bash= path is the .5s.sh and exists (.../plugins/leadv2/scripts/leadv2-status-surface.5s.sh)
test-status-surface-fast-names: 12 passed, 0 failed
[PASS] .../tests/test-status-surface-fast-names.sh
run-all: 4 passed, 0 failed, scope=changed
```

There was no red-then-green cycle because no executable file was changed; the always-on suites
(4) are the only ones a docs-only diff selects, and they passed on the first run.

DELIVERABLE_COMPLETE
