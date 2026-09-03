# PULSE-HOOK-IS-A-FORKED-COPY-01 — persona-engine runs a five-week-old fork of a plugin hook

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will ever reach you. Never
  end a turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 900`.
- Nested agents allowed for bulk reads — **synchronously only**, never `isolation:"worktree"`.
- **Commit after every step.** Three workers died today with work uncommitted.
- The suite path is `tests/run-all.sh` at the **repo root**. `plugins/leadv2/scripts/tests/run-all.sh`
  does not exist; a round that reports running it has run nothing.

**Class:** Standard. **Repos touched:** persona-engine (the fork + its wiring) and the leadv2 plugin
(the resolver fix). Land the plugin half in the leadv2 lane worktree; the persona-engine half is a
separate small commit in that repo.

## The two facts, both verified 2026-09-02

**Fact 1 — the fork.** `persona-engine/.claude/hooks/leadv2-pulse-json.sh` is a **real copy** dated
Jul 28, wired at `persona-engine/.claude/settings.json:336` to
`Bash|Edit|Write|MultiEdit|NotebookEdit|Agent|Workflow|Skill` — nearly every tool call — entirely
outside the plugin manifest. Canonical `plugins/leadv2/hooks/hooks.json`, byte-identical to the live
cache at `~/.claude/plugins/cache/leadv2-local/leadv2/0.5.7/hooks/hooks.json`, wires `pulse-json.sh`
to **nothing**. Of four consumer repos only persona-engine does this. This is the anti-pattern named
in persona-engine's own CLAUDE.md: never a real copy of a plugin-owned file.

**Fact 2 — the resolver takes a dead row.** `plugins/leadv2/hooks/leadv2-pulse-json.sh:103-107`:

```bash
_active="$PROJ_ROOT/docs/leadv2/active.yaml"
tid="$(awk '/^[[:space:]]*-[[:space:]]+task_id[[:space:]]*:/{... print $3; exit}' "$_active")"
```

First match wins; `dead_at` and `deregistered` are never consulted. And `$PROJ_ROOT/docs/leadv2/`
is the repo-local registry while the live control plane is
`~/.claude/leadv2-state/leadv2/active.yaml`.

Live consequence, observed for ~40 minutes: persona-engine's `active.yaml` held two rows, both
`PHASE-PATH-REPRO-01`, both carrying `dead_at` and `event: deregistered`. Every Bash call the lead
made rewrote `docs/handoff/PHASE-PATH-REPRO-01/pulse.json` with the lead's own `session_id`, and the
anchor injector fed the lead `ACTIVE TASK: PHASE-PATH-REPRO-01` on every turn. The anti-silence
pulse printed `live=0` and named the lane twice in the same line — once per dead row. The lead
cleared the registry by hand at 14:55Z; that is not a fix, it returns on the next dispatcher exit.

Full write-up: `docs/handoff/PULSE-READS-THE-WRONG-REGISTRY-01/anchor-hijack-mechanism.md`.

## Deliver

1. **A dead row is never a candidate.** Skip any session entry carrying `dead_at` or a
   `deregistered` event. If no live entry remains, resolve to **no task id at all** — an absent
   anchor is strictly better than a false one, and the rest of the chain already handles empty.
2. **Read the live control plane.** `~/.claude/leadv2-state/leadv2/active.yaml` (honour
   `LEADV2_STATE_DIR` if the codebase already has such a knob — check before inventing one). The
   repo-local file may stay as a fallback only if you can show it is still written; if nothing
   writes it, say so and drop it.
3. **Kill the fork.** Decide and justify: either delete
   `persona-engine/.claude/hooks/leadv2-pulse-json.sh` and its `settings.json:336` wiring outright,
   or replace the copy with a symlink to canonical. Do NOT leave a real copy. State in the report
   which persona-engine actually needs — check whether anything reads the pulse file it writes
   before removing the writer.
4. **Report the diff between fork and canonical.** `diff` the Jul 28 copy against canonical and list
   what five weeks of drift changed. If the fork carries a fix canonical lacks, that fix goes UP into
   canonical in this round — do not delete a fix by deleting its only copy.

## Prove it

- **Regression case:** an `active.yaml` fixture holding only dead rows → the hook writes no task id.
  Paste the run and the resulting `pulse.json`.
- **Live case:** a fixture with one dead row followed by one live row → the live one is chosen.
- **Negative control:** restore the `exit`-on-first-match resolver in a mktemp FULL copy of the tree
  whose baseline is proven green → the first case must go red. Paste baseline and mutant runs.
  Insert the mutation INSIDE the function body; a top-level insert makes everything red for the
  wrong reason and reads as a pass.
- **No-fork check:** a command that fails while any real copy of a plugin-owned hook exists under
  `persona-engine/.claude/hooks/`. Paste it passing.
- `tests/run-all.sh --scope changed` from the LANE ROOT, FOREGROUND, `timeout 1800`. Paste the real
  tail. A placeholder token where run output belongs fails this round outright.

## Out of scope
The delegation-nudge volume (`NUDGE-TAX-01`), the dead-hook deletions (`DEAD-HOOKS-DELETE-01`), the
watcher leak (`WATCHER-LEAK-IS-FAKE-LIVENESS-01`). This round fixes one hook and removes one fork.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only. Tree clean, `main`
merged.

## Done when
Dead rows are provably skipped with pasted runs; the negative control is red against a green
baseline; no real copy of the hook remains in persona-engine and the report says which option was
chosen and why; the fork-vs-canonical diff is in the report with any fork-only fix carried up.
