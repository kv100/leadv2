# HOOKS-PARITY-ACROSS-REPOS-01 — one plugin hook is a drifted copy in all four consumer repos

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.**
- Suite path is `tests/run-all.sh` at the repo **ROOT**. Do NOT open with a full suite run.

**Class:** Standard. **Repo:** leadv2 plugin (plus the four consumer repos for the cleanup step).

## The measurement, 2026-09-03

Census of `.claude/hooks/*.sh` across every repo on this machine:

| repo | wired in settings.json | real files | symlinks |
|---|---|---|---|
| persona-engine | 9 | 33 | 3 |
| m3-market | 10 | 15 | 0 |
| respiro-ios | 3 | 5 | 0 |
| getmany-followup-bot | 1 | 3 | 0 |
| leadv2 (the plugin repo) | 0 | 0 | 0 |

Classified against canonical `plugins/leadv2/hooks/`:

- **52 of those files are the repos' own hooks** — not plugin-owned, and they belong where they are.
  Do not touch them.
- **One is plugin-owned and copied into all four**: `leadv2-immune-intake-inject.sh`, drifted
  **58 lines** from canonical in persona-engine, m3-market and getmany-followup-bot, and **64 lines**
  in respiro-ios. Four independent forks of one file, none of them canonical.
- leadv2's own 0 is correct — it inherits the plugin baseline and has no product surface to guard.

This is exactly the shape that produced today's other incident: a plugin-owned hook copied into a
repo, wired locally, quietly diverging. That one (`leadv2-pulse-json.sh`) had been a five-week-old
copy wired to nearly every tool call.

## The tool for this already exists and is not wired anywhere

`plugins/leadv2/scripts/leadv2-hook-fork-guard.sh` (merged today, `b950cc95`) detects precisely
"a real, non-symlink copy of a plugin-owned hook inside a consumer repo", with a suite that proves
all four directions. **Nothing runs it.** That is the gap.

## Deliver

1. **Wire the guard so it runs by itself.** Pick where and justify it: `leadv2-repo-install.sh`
   (which runs on every `/leadv2` in every repo and currently barely mentions hooks — one match in
   the whole file), a SessionStart hook, CI, or some combination. It must fire without anyone
   remembering to run it.
2. **Resolve `leadv2-immune-intake-inject.sh` — carefully, this is the part that can lose work.**
   Four copies drifted independently. Diff each against canonical and against each other, and say
   what each fork actually changed. If a fork carries a fix canonical never got, **port it up
   before removing anything**. Only then replace the copies with symlinks (or delete them if the
   plugin manifest already wires the hook). Report per repo what you found and what you did.
3. **Say what "the right hooks everywhere" should mean.** Right now four repos wire 9/10/3/1 hooks
   by hand and nobody can say which set is correct. State the rule: which hooks come from the
   plugin manifest for every adopter, and which are legitimately repo-local. A rule someone can
   check beats a list someone maintains.
4. **Do NOT touch the 52 repo-own hooks.** They are not plugin-owned. Naming them as violations
   would be a false positive, and a guard that cries wolf gets switched off within a day.

## Prove it
- Create a scratch consumer repo with a real copy of a plugin hook → the wired guard fires. Paste it.
- Same repo with a symlink instead → silent. Paste it.
- A repo-own hook that has no canonical counterpart → silent. Paste it (this is the false-positive
  case that matters most).
- After the cleanup: the census command above, re-run, showing zero drifted plugin-owned copies.
- **Negative control:** unwire the guard in a mktemp copy whose baseline is proven green → the
  real-copy case stops being detected. Paste baseline and mutant runs.
- `tests/run-all.sh --scope changed` from the LANE ROOT at the END, FOREGROUND, `timeout 1800`.

## Constraints
LANE_WRITES: `plugins/leadv2/scripts/`, `plugins/leadv2/hooks/`, `tests/`, this task's handoff dir,
plus the four consumer repos' `.claude/hooks/leadv2-immune-intake-inject.sh` for step 2.
Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, `critic.*`.
**Never delete a consumer repo's file before its diff is recorded in the report.**

## Done when
The guard runs without anyone invoking it; the four drifted copies are resolved with a per-repo
record of what each contained; repo-own hooks are provably untouched; the census shows zero drifted
plugin-owned copies; the negative control stops detecting against a green baseline.
