verdict: APPROVE
next_action: deploy

# MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01 — developer deliverable

Note on context: `docs/handoff/dispatch-8f93e5a5/context.yaml` does not exist for this dispatch.
The authoritative spec is `docs/handoff/dispatch-8f93e5a5/lane-mission.md` (14.7KB — a much more
precise brief than the generic task text in the orchestrator prompt) plus
`docs/handoff/MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01/lead-addendum-census.md`, which the mission
itself says wins on disagreement. Both were read in full before continuing. Substantial prior work
already existed in this worktree from an earlier turn of this same session (staged generator +
test suite + run-all.sh row, and all 8 canonical repos already scaffolded) — this session continued
and completed it rather than restarting.

## The real question, answered

Lead addendum's FIRST question: what does the generator do with the 19 git **worktrees** under
`~/MythicalGames` (only 8 of 27 `.claude`-bearing dirs are standalone clones)?

**Answer: option (a) — resolve from the parent, via a symlink.** `<worktree>/.claude/leadv2-overrides`
is `ln -sfn`'d to `<parent-clone>/.claude/leadv2-overrides`. Rejected (b) (identical copy per
worktree) because it's the one the addendum names as rotting — two copies of stack.yaml/verify.sh
per repo family drift the moment one is hand-tuned and the other isn't, the same failure class as
the 2026-07-29 canonical/persona-engine gate defect this repo's CLAUDE.md was written to prevent.
Rejected (c) (pointer file) because it would require a `leadv2-helpers.sh` reader change (a pointer
needs interpretation) — out of scope per the mission's Files allowlist, and unnecessary: a symlinked
directory already resolves transparently to every existing `grep`/`source`/`python3 open()` reader,
zero reader code touched. This is also the same "one inode, many views" convention already used for
`~/.claude/leadv2-shared/` scripts, so it's consistent with how this codebase already solves
exactly this problem shape.

Detection: `git -C "$repo" rev-parse --git-common-dir` (relative paths resolved against `$repo`,
then `cd .. && pwd` for the parent clone root) — matches the addendum's suggested detection exactly.
Companion dirs with no `.git` at all (`m3-market`) are a *different* case and are still hard-skipped,
never symlinked — verified by a dedicated test.

## What changed

- **`plugins/leadv2/scripts/leadv2-mythicalgames-overrides-gen.sh`** (new, 323 lines): auto-discovers
  `~/MythicalGames/*/` (override via `LEADV2_MG_ROOT`), disambiguates canonical repo (`.git` dir) vs
  worktree (`.git` file) vs companion dir (no `.git`) vs `--repo <path>` single-shot. Emits
  `stack.yaml`/`state-paths.yaml`/`codex-policy.yaml`/`deploy.sh`/`verify.sh` for canonical repos
  (skip-if-exists by default, `--force` to overwrite, both logged). For worktrees: `process_worktree()`
  resolves the parent and symlinks instead of emitting files. Per-repo hand-tuning table
  (`_mg_repo_test_cmd`, `_mg_repo_proxy_cmd`) matches the mission's stack table exactly, including the
  4 repos with no CI-run test command (`environment-platform`, `mondia-portal`, `mythical-aii`,
  `pf3-local-dev`) — their `verify.sh` either runs a clearly-labeled read-only substitute proxy or
  prints an explicit `SKIP` reason, never a plausible-looking invented command (addendum's explicit
  "half the fleet has no test command" instruction).
- **`plugins/leadv2/scripts/tests/test-mythicalgames-overrides-gen.sh`** (new, 236 lines): 23 offline
  checks against `/tmp/leadv2-fixture-repos/` fixtures only (real `git init`), never touches
  `~/MythicalGames`. Covers every stack id, idempotency, `--force`, auto-discovery, the no-`.git`
  companion-dir skip, and — the worktree case added this session — a **real** `git worktree add`
  fixture (not a synthetic fake `gitdir:` file, which cannot be resolved by real `git rev-parse
  --git-common-dir`) proving the symlink lands and reads through to the parent's `stack.yaml`.
- **`tests/run-all.sh`**: one appended `EXTRA_SUITE_MAP` row (`leadv2-mythicalgames-overrides-gen.sh:plugins/leadv2/scripts/tests/test-mythicalgames-overrides-gen.sh`) — the test file's name doesn't
  follow the `test-<stem>.sh` convention for the production file's own stem, so a future change to
  the generator alone (test file untouched) needs this explicit row to still self-select.
- **Live, untracked-only, in 8 MythicalGames repos' `.git/info/exclude`**: appended one line,
  `.claude/leadv2-overrides` (no trailing slash), to `environment-platform`, `m3`, `mondia-portal`,
  `mp-frontend`, `mythical-aii`, `pf3-backend`, `pf3-local-dev`, `pf3-smart-contracts`. Reason below.
  `.git/info/exclude` is not a tracked file, so this is not a "commit to a MythicalGames repo" —
  it's the same kind of untracked local config write the mission's own Files-allowlist explicitly
  permits ("WRITE ... one appended block in `.git/info/exclude`").

## A real finding this session caught: the shared-exclude claim was half true

The addendum states linked worktrees "share the parent's `.git/info/exclude` via the common git
dir" — true as far as it goes (`git -C <worktree> rev-parse --git-common-dir` does resolve to the
parent's `.git`, confirmed live). But the *existing* exclude line from the original adoption sweep,
`.claude/leadv2-overrides/` (trailing slash), is a gitignore dir-only pattern — it does not match a
path that is a **symlink** to a directory, only a real directory. Once worktrees got a symlink
instead of a real directory, every one of them leaked `?? .claude/leadv2-overrides` into
`git status --porcelain`, despite genuinely sharing the same exclude file. Live proof:

```
$ git -C ~/MythicalGames/m3 check-ignore -v .claude/leadv2-overrides       # m3: real dir
.git/info/exclude:12:.claude/leadv2-overrides/	.claude/leadv2-overrides
$ git -C ~/MythicalGames/m3-promo status --porcelain                       # m3-promo: symlink, BEFORE fix
?? .claude/leadv2-overrides
```

Fixed by appending the non-slash form (matches files, symlinks, and dirs alike) to each of the 8
parents' exclude files. After the fix, swept all 27 MythicalGames dirs (8 clones + 19 worktrees):

```
CLEAN=16 DIRTY=11
```

The 11 "dirty" repos show pre-existing, unrelated dirt from other concurrent leadv2 lanes/tasks
already running against these repos (e.g. `pf3-matview-gate`'s `app/pf3/matview_dirty.go`, `m3`'s
`traitOfferCriteriaTitle.test.ts`, various `.claude/anatomy.md`/`.repowise/`/`docs/handoff/*` from
the wider adoption sweep and repowise indexing) — **not** `.claude/leadv2-overrides` in any of the
27, confirmed by grepping every dirty listing. This task's own footprint is fully clean everywhere.

Addendum's specific "tracked settings.json — three, not one" acceptance (zero `LEADV2_` keys leaked
into `m3`/`m3-promo`/`m3-trait`'s git-tracked `.claude/settings.json`, `git diff --stat` empty):
confirmed live, all three — `git diff --stat` empty, `grep -c LEADV2_` = 0 in all three.

## Acceptance evidence (mission §Acceptance, re-run per repo)

**#1 tree exists** — all 8 clones have `stack.yaml`; all 19 worktrees have the symlink (spot-checked
`m3-promo`, `m3-trait`, `mondia-portal-bbva`, `pf3-digest-enricher`, `wt-peng-59`, all resolve via
`pwd -P` to their parent's real `.claude/leadv2-overrides`).

**#2 reader parses clean** (`_lv2_load_paths`, `_lv2_codex_enabled`, `_lv2_stack_scalar lang`) — run
against `pf3-backend`, `m3` (canonical) and `wt-peng-59`, `m3-promo` (worktree-via-symlink),
`mythical-aii`, `environment-platform`:

```
== pf3-backend ==
paths OK: /Users/kostiantyn.vlasenko/MythicalGames/pf3-backend/docs/handoff
codex: disabled (expected)
lang: go
exit=0
== wt-peng-59 ==
paths OK: /Users/kostiantyn.vlasenko/MythicalGames/wt-peng-59/docs/handoff
codex: disabled (expected)
lang: go
exit=0
== m3 ==
paths OK: .../m3/docs/handoff  | codex: disabled (expected) | lang: typescript | exit=0
== m3-promo ==
paths OK: .../m3-promo/docs/handoff | codex: disabled (expected) | lang: typescript | exit=0
== mythical-aii ==
paths OK: .../mythical-aii/docs/handoff | codex: disabled (expected) | lang: shell | exit=0
== environment-platform ==
paths OK: .../environment-platform/docs/handoff | codex: disabled (expected) | lang: iac | exit=0
```
All exit 0, all three lines printed, no stderr, for both canonical and symlink-resolved cases.

**#3 nothing leaked** — see the exclude-fix section above; empty for the specific
`.claude/leadv2-overrides` path in all 27 repos post-fix.

**#4 verify command runs, exit code verbatim** (per-repo `verify.sh`, real run, not invented):

```
environment-platform  exit=0   (labeled SKIP -- no automated verify command, needs human-authored check)
m3                     exit=124 (TIMEOUT at 240s -- `pnpm --filter=main exec eslint .` did not finish
                                  in this environment; not papered over, reported as-is)
mondia-portal          exit=1   (6 real eslint errors, 16 warnings -- pre-existing repo lint debt,
                                  not caused by this task; verify.sh correctly surfaces it)
mp-frontend            exit=0   (Jest: 26 suites / 202 tests passed)
mythical-aii           exit=0   (bash -n proxy over all .sh, labeled SUBSTITUTE PROXY)
pf3-backend            exit=2   (`make ci-unit-tests` -> gotestsum: command not found -- local
                                  environment gap, not installed on this machine; genuine finding)
pf3-local-dev          exit=0   (`docker compose config` -- valid compose file)
pf3-smart-contracts    exit=0   (forge test -vvv: 17 suites / 519 tests passed)
```
4 non-zero exits are real signal (timeout, pre-existing lint debt, missing local tool), reported
verbatim per the mission's explicit instruction not to paper over them, not a defect in the
generator or its emitted `verify.sh` wrapper.

## Falsification set (mission's mandatory self-check)

```
$ bash -n plugins/leadv2/scripts/leadv2-mythicalgames-overrides-gen.sh ; echo exit=$?
exit=0
$ bash -n plugins/leadv2/scripts/tests/test-mythicalgames-overrides-gen.sh ; echo exit=$?
exit=0
```
No Python files were added or changed by this lane — `python3 -m py_compile` step is N/A (verified:
`git status --porcelain` shows zero `*.py` entries in this diff).

Negative control (mission's required mutation, inside `detect_stack()`'s body — flipped the
pnpm-lockfile branch so it misreports `node-npm` even with `pnpm-lock.yaml` present):
```
RED  (mutated):  19 passed, 4 failed  -- exit=1
GREEN (reverted): 23 passed, 0 failed  -- exit=0
```
(4 failures under the mutation, not 1, because the mis-detected stack also breaks the unrelated
`--force` idempotency check further down the fixture, which reuses the same fixture dir — expected
knock-on, confirms the mutation actually changed generator behavior rather than being inert.)

Changed-scope suite runner:
```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-mythicalgames-overrides-gen.sh
[SELECT] .../tests/test-run-all-carrier-map.sh
run-all: 6 selected, scope=changed, select_only=1
```
`run-core-offline.sh` is a pre-existing suite in the selection (measured >10min per this repo's own
memory of prior lanes) — the full non-select-only run was started, observed still stuck inside
`run-core-offline.sh` after 5+ minutes via a background Monitor, and killed; the
`LEADV2_RUN_ALL_SELECT_ONLY=1` seam (built into `tests/run-all.sh` for exactly this purpose) was
used instead to prove selection without paying that suite's runtime. `test-run-all-carrier-map.sh`
(also selected, exercises the `EXTRA_SUITE_MAP` mechanism this lane's row was added to) run directly:
```
$ bash tests/test-run-all-carrier-map.sh ; echo exit=$?
PASS: dirty model-capability.yaml alone selects test-fable-think-tier.sh
PASS: dirty leadv2-glm-policy-resolve.py alone selects test-fable-think-tier.sh
PASS: dirty leadv2-diverge.js alone selects test-fable-think-tier.sh
PASS: dirty tests/run-all.sh alone selects tests/test-run-all-carrier-map.sh
PASS: negative control: unmapped scripts/*.sh change selects no think-tier suite
test-run-all-carrier-map: 5 passed, 0 failed
exit=0
```

**macOS**: `bash plugins/leadv2/scripts/tests/test-mythicalgames-overrides-gen.sh` — `23 passed, 0
failed`, exit=0.

**Linux container** (Alpine 3.19, `apk add bash git`, script copied in, run standalone — proves
portability beyond bash 3.2 macOS quirks, e.g. GNU vs BusyBox coreutils): identical `23 passed, 0
failed`, exit=0.

## Out of scope, left alone (per mission)

- `deploy-verify.sh` for all 8/27 — not emitted, matches "Out of scope."
- `environment-platform`'s real IaC verify command — flagged with an explicit `SKIP` reason in its
  `verify.sh`, not authored, needs a human to name the actual kustomize/kyverno overlay.
- `codex_enabled` stays `false` everywhere (explicit opt-out file per repo) — turning it on is a
  separate founder decision, per mission and per addendum.
- `m3`/`m3-promo`/`m3-trait`'s tracked `.claude/settings.json` — never touched, verified clean.
- `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`, `tests/known-red-suites.txt` — never
  opened.
- `m3-market`'s existing rich override tree (`extensions.md`, `mission-templates.md`, etc.) — read
  for schema-consistency only (this generator's minimal `stack.yaml` is a strict subset of
  `m3-market`'s keys, all of which are optional per `_lv2_stack_scalar`'s "no key required" reader
  contract — consistent, not divergent). Not split or copied anywhere; `m3-market` is not a git repo
  and was correctly skipped by the generator as a companion dir throughout.
- The `m3` `verify.sh` eslint timeout (exit=124) was not chased further (e.g. warming a cache,
  running with `--max-warnings`) — reported as measured, a environment/perf question for whoever
  owns m3 CI, not a defect in this task's scope.

DELIVERABLE_COMPLETE
