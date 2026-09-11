# GUARDS-ARE-NOT-IN-THE-PLUGIN-01 — move the portable guards into the plugin, step 1 of 2

## The measured problem

The leadv2 plugin installs and runs correctly in every repo. Proven, not assumed: a
`getmany-followup-bot` session's SessionStart carried
`FORK-GUARD: 10 hook-installation(s) checked, 0 violation(s)`, and the canonical link
`~/.claude/plugins/local/leadv2/plugins/leadv2 -> ~/Projects/leadv2/plugins/leadv2` is
intact with `hooks/hooks.json` on the same inode. Plugin enablement is USER-level
(`leadv2@leadv2-local: true`), so it applies in every repo regardless of what a project's
`enabledPlugins` says.

What does NOT travel is the **project-level** hook registration, and the scripts behind it:

| | persona-engine | getmany-followup-bot |
|---|---|---|
| project-level hook scripts registered | **23** | **5** |
| of those, the file actually exists | 20 | **2** (`leadv2-phase8-gate.sh`, `plugin-scripts-drift-session-warn.sh`) |
| files in `.claude/hooks/` | 36 (30 real, 6 symlinks) | 5 (2 real, 3 symlinks) |

18 hook scripts are registered in persona-engine and not in getmany-followup-bot. Checked
each by name against the plugin tree: **16 of 17 real ones exist ONLY in persona-engine**
(the single exception is `leadv2-queue-archiver.sh`, which has a plugin twin). They are not
plugin content, so no install can deliver them — including the one that carries the guards
everybody relies on, `leadv2-bash-hook-dispatcher.sh` (foreground-dispatch block, heredoc
block, destructive-git block).

## Scope of THIS task — step 1 only

Move the portable guards into the plugin **as files**, and change nothing about when they
fire in persona-engine.

Classified by counting persona-engine-specific references
(`systems-map|personas/|agent/|persona-engine|voice-dna|lifecycle-data|publish_slots|feature-liveness`)
in each script:

**PORTABLE — 11 scripts, zero persona-engine references. These move.**

| script | lines | event |
|---|---|---|
| `leadv2-bash-hook-dispatcher.sh` | 159 | PreToolUse |
| `scheduled-decisions-inject.sh` | 156 | SessionStart |
| `anti-silence-pulse-detector.sh` | 174 | UserPromptSubmit |
| `mojibake-guard.sh` | 145 | Stop |
| `pending-questions-inject.sh` | 89 | UserPromptSubmit |
| `open-threads-anchor-inject.sh` | 87 | UserPromptSubmit |
| `session-start-safe-pull.sh` | 85 | SessionStart |
| `learn-trigger-inject.sh` | 59 | SessionStart |
| `lane-lesson-capture-hook.sh` | 58 | PostToolUse |
| `leadv2-phase-pulse-sync.sh` | 43 | PostToolUse |
| `docs-truth-inject.sh` | 33 | SessionStart |

**STAYS in persona-engine — 3 scripts, genuinely repo-specific:**
`lifecycle-close-sync.sh` (17 refs), `control-truth-reminder.sh` (7),
`feature-liveness-session-inject.sh` (6).

**BORDERLINE — 3 scripts, exactly one reference each, all of them the string
`feature-liveness`:** `anti-silence-pulse-arm-inject.sh`, `leadv2-queue-archiver.sh`,
`learnings-recent-inject.sh`. Read the single reference in each. If it is a soft read of an
optional file, make the path optional and move it; if it is load-bearing, leave it and say
so in the report. Do not guess.

## The work

1. Copy the 11 portable scripts to `plugins/leadv2/hooks/` in THIS repo (the plugin repo),
   byte-identical, and commit them.
2. In `~/Projects/persona-engine`, replace each `.claude/hooks/<name>.sh` with a **symlink**
   to the plugin copy. One inode, per the standing rule "never a real copy of a
   plugin-owned file inside a project". persona-engine's `settings.json` registration is
   NOT touched: it still names `${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.sh`, which now
   resolves through the symlink to the same bytes. **Behaviour in persona-engine must not
   change at all** — that is the acceptance property.
3. In `~/Projects/getmany-followup-bot/.claude/settings.json`, add registrations for the 11
   under their correct events, pointing at `${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh`. Copy the
   idiom from the entries already there. Leave its existing 5 alone — but note in the report
   that 3 of them (`anatomy-index.sh`, `auto-migration-risk.sh`, `check-careful.sh`) name
   files that do not exist in that repo, so they are dead registrations.

## What NOT to do

- **Do NOT add these to `plugins/leadv2/hooks/hooks.json`.** That file is the plugin's own
  registry (86 commands, all `${CLAUDE_PLUGIN_ROOT}`), and committing to plugin main IS the
  deploy for all four repos. Registering them there while persona-engine still registers
  them per-repo makes every one of them fire TWICE in persona-engine. Moving the
  registration is step 2, a separate deliberate change that must delete the per-repo
  entries in the same commit.
- Do not touch `~/.claude/settings.json` or any permission file.
- Do not touch the 3 persona-engine-specific scripts.

## Acceptance

Suite `plugins/leadv2/scripts/tests/test-portable-guards-are-plugin-owned.sh`, and it must
prove three things, each with a negative control:

1. For each of the 11: the file exists under `plugins/leadv2/hooks/`, and
   `persona-engine/.claude/hooks/<name>.sh` is a symlink resolving to it (`-L` and
   same `readlink -f`). Negative control: point one symlink at a scratch copy and the suite
   must go RED.
2. persona-engine's registration still resolves to a readable, executable file for all 23
   registered scripts it had before — i.e. nothing was broken by the move. Negative control:
   break one symlink target and the suite must go RED.
3. getmany-followup-bot's `settings.json` registers all 11 under
   `${CLAUDE_PLUGIN_ROOT}/hooks/`, and each named file exists. Negative control: register a
   name with no file and the suite must go RED.

A suite that only asserts the happy direction is the false-green shape and will be rejected.

## Evidence trail

Counts above were measured 2026-09-11 by the persona-engine lead; the getmany side was
confirmed independently by the session running in that repo (FORK-GUARD line, user-level
enablement, canonical inode identity, 266 of 282 script symlinks).
