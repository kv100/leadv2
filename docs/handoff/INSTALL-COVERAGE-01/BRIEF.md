# INSTALL-COVERAGE-01 — a fresh install is not the plugin the founder knows

Two backlog rows, one file (`plugins/leadv2/scripts/leadv2-repo-install.sh`), one lane so
they cannot collide:

- `FRESH-INSTALL-LANDS-AT-ONE-HOOK-NOT-TWENTY-EIGHT-01`
- `LEAD-MODEL-KNOB-IS-DEAD-01`

Founder, 2026-09-11: **«я вот допустим начну работу над новым репо, загружу туда плагин и
он не будет работать как тут»**. He is right, and this brief carries the number.

## Defect 1 — the installer registers zero hooks

`leadv2-repo-install.sh` writes a `settings.json` containing **env vars only**. A grep of
the installer for hook event names (`PreToolUse|PostToolUse|SessionStart|UserPromptSubmit|
Stop|SessionEnd|PreCompact|Notification`) returns **0**. Its writer block at :360-385 emits
`ENABLE_TOOL_SEARCH`, `LEADV2_PULSE_MODE`, `LEADV2_MAIN_MODEL`, `LEADV2_THINK_MODEL`,
`LEADV2_FORCE_OPUS_LEAD`, `LEADV2_WORKFLOW_ENABLED`, `LEADV2_WIKI_INJECT`, the loop and
correction detectors, and `LEADV2_SCORECARD_ON_CLOSE`.

Registration counts measured across every installed repo on 2026-09-11:

    persona-engine         28
    m3-market              27      (~/MythicalGames/, a non-git umbrella workspace)
    getmany-followup-bot   17      (8 until earlier the same day)
    respiro-ios            13
    m3 / m3-promo / m3-trait  1 / 1 / 1

**The three at 1 are what the bare install produces.** Every high count was reached by
hand, repo by repo, over months. The 87 entries in `plugins/leadv2/hooks/hooks.json` do
reach every repo automatically — the plugin path is a symlink to this repo — so the gap is
exactly the per-repo registration layer, and it is invisible because the install reports
success.

Verify all of this yourself before changing anything; if a count has moved, report the new
one rather than working from this list.

**Two candidate shapes. Pick one with evidence, and say why in the commit message:**

1. The installer writes the expected registration set **and** the
   `.claude/hooks-manifest.json` that `plugins/leadv2/hooks/leadv2-hook-registration-guard.sh`
   compares against, so a fresh repo is covered from minute one and any later drift is
   reported by the guard that already exists.
2. Every hook that needs per-repo registration moves into the plugin's own `hooks.json`,
   after which registration is not something a repo can get wrong at all.

Shape 2 is stronger if it is achievable — a guarantee beats a guard. It may not be:
some registrations may be genuinely repo-specific. Determine that by reading what the
28 in persona-engine actually are, and split them into "belongs to every repo" and
"belongs to this repo only". That split IS the deliverable; whichever shape follows from
it is fine.

**Do not close this by hand-editing one more repo's `settings.json`.** That is the
mechanism that produced the spread.

## Defect 2 — the lead-model knob changes nothing

`LEADV2_MAIN_MODEL` and `LEADV2_FORCE_OPUS_LEAD` are presented by `CLAUDE.md` and by this
same installer as the control that sets the lead's model. They do not.

- `plugins/leadv2/scripts/leadv2-main-model-check.sh` reads them and merely **prints** a
  model name to stdout. It appears **zero** times in `plugins/leadv2/hooks/hooks.json`;
  its only callers are `docs/phases.md`, `ref/leadv2-main-model.yaml` and its own two test
  suites. Nothing on the live path invokes it.
- `hooks/leadv2-model-inherit-guard.sh:26` uses the value purely as a display label:
  `SESSION_MODEL="${LEADV2_MAIN_MODEL:-the session model}"`.
- `leadv2-repo-install.sh:370/378` **writes both into every newly installed repo** with
  defaults `opus` / `0`, propagating a knob nothing reads.

A session's model is chosen at launch and no env var can change a running session
afterwards. Founder: **«я же сессию сам запускаю и выбираю модель лида»**.

**Change, per the CONTROL-TRUTH rule — either make it real or delete it:**

- Real: a SessionStart check that actually compares the running model against the declared
  `main_model` and warns (never blocks) when they differ. If you take this branch, it must
  be registered in the plugin's `hooks.json`, not in a repo's `settings.json`.
- Delete: remove the variables, the installer lines that propagate them, and the `CLAUDE.md`
  sentence that claims the control exists.

Pick one and justify it. Do not leave a control rendering that changes nothing.

## Suites

`scripts/tests/test-fresh-install-covers-the-hook-set.sh` — install into a **scratch repo
in the suite's own temp dir**, then assert:

1. The installed `settings.json` (or the plugin `hooks.json`, depending on the shape you
   chose) covers every hook the split above marks "belongs to every repo".
2. A hook the split marks repo-specific is NOT force-installed into an unrelated repo.
3. Installing twice changes nothing the second time (idempotent).
4. If shape 1: the installed `.claude/hooks-manifest.json` is exactly the expected set, and
   deleting one registration afterwards makes the existing registration guard report it.

`scripts/tests/test-lead-model-knob-is-real-or-gone.sh` — one suite that passes under either
resolution: either the check is registered in `hooks.json` AND fires on a model mismatch, or
`LEADV2_MAIN_MODEL` / `LEADV2_FORCE_OPUS_LEAD` appear nowhere in the installer, in
`leadv2-main-model-check.sh`, or in `CLAUDE.md`. Assert the chosen branch, not both.

## Negative control

`scripts/tests/nc-install-coverage.sh` — mutate the real installer into a scratch copy,
point the suite at the mutant, assert RED **on the named case**:

- (a) drop one hook from the installed set → case 1 must go red.
- (b) make the install non-idempotent → case 3 must go red.

If a mutation pattern is not found, **exit non-zero loudly**.

## Hard constraints

- **Never install into a real repo.** The scratch repo lives in the suite's temp dir. Do
  not touch `~/Projects/*/.claude/settings.json` or `~/MythicalGames/*/.claude/` at all.
- Note for context, do not act on it: row `a86804b99af9` claimed `~/Projects/m3-market` has
  no `.claude` — that path does not exist; the m3 repos live in `~/MythicalGames/`, and
  m3-market there is well covered. The row is closed as a false premise.
- Suites must never write to `~/.claude/leadv2-state/`.
- Refuse to write a mock onto a tracked file (`git ls-files --error-unmatch`).
- Never `git stash`, `git reset --hard`, `git clean`, or `git worktree prune`.
- Do not touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` or the markdown-backlog
  tests — other lanes are editing both.
- Commit in `~/Projects/leadv2` with `git commit -- <your paths>`; do not push.

## Report back

Under 300 words: commit sha, the every-repo vs repo-specific split with counts, which shape
you chose and why, the before/after registration count for a freshly installed scratch
repo, which resolution you took for the lead-model knob, suite counts, and the NC output
for both mutations.
