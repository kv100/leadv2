# LEAD ADDENDUM to mission.md — the census in the brief is short. Measured 2026-09-03.

Read this together with `brief.md`. Where the two disagree, this file wins.

The task row says "8 repos". The real number on disk is larger, and the shape matters more than
the count. Measured with `ls -d ~/MythicalGames/*/` plus a per-directory probe:

- **29 directories** under `~/MythicalGames`, of which **27 carry a `.claude/` directory**.
- **26 of those 27 have NO `leadv2-overrides`.** Exactly one does: `m3-market`.
- **19 of the 27 are git WORKTREES**, not standalone clones (detected by `.git` being a *file*,
  not a directory): every `wt-*`, every `pf3-digest-*`, plus `m3-promo`, `m3-trait` and others.

This changes the design question the brief must answer, and it is now the FIRST question:

**A worktree must not get its own hand-authored override tree.** A worktree of `pf3-backend` has
the same stack, the same test command and the same deploy posture as `pf3-backend`. Decide and
state plainly: does the generator (a) detect worktree-ness and resolve the override tree from the
parent repo, (b) emit an identical copy per worktree, or (c) emit a pointer file? Recommend one
and justify it in three lines. Option (b) is the one that rots — say so if you reject it.
Detection: `.git` is a file containing `gitdir: <path>` for a worktree; `git -C <dir> rev-parse
--git-common-dir` resolves the shared parent.

Also note `m3-market` ALREADY has an override tree. Read it first — it is the only worked example
in the fleet, and the generator should produce something consistent with it, or explain why not.

The 8 repos named in the brief's stack table are still the right FIRST batch (they are the
standalone clones). Keep that table. Add the worktree resolution rule on top of it, and make the
acceptance cover at least one worktree case, not only the 8 clones.

## Tracked settings.json — three, not one

`m3`, `m3-promo` and `m3-trait` each have a git-TRACKED `.claude/settings.json` (the latter two
are worktrees of `m3`). All three currently carry ZERO `LEADV2_` keys — nothing has leaked. The
override tree must not change that: after the generator runs, `git -C <repo> status --porcelain`
must be EMPTY in every one of them. That check is the acceptance, and it is not optional.

## Half the fleet has no test command — say so, do not invent one

The brief's own table shows 4 of 8 repos with no CI test command (`environment-platform`,
`mondia-portal`, `mythical-aii`, `pf3-local-dev`). Do NOT invent a plausible-looking command for
those. An override that declares a `verify` which was never run is exactly the lying-green
disease. For each such repo the `verify` entry must either be the honest read-only proxy the
brief names (`bash -n`, `docker compose config`) clearly labelled as a syntax/config check and
not a test run, or be explicitly empty with a one-line reason. State which of the two you chose
per repo.
