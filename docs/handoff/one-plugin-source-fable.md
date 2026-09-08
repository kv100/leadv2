# One plugin source, no project copies — design, arm A (fable)

Report only. No behaviour changed. Measured 2026-09-08 on this machine from
`~/Projects/leadv2` at `b2cf62f2` (worktree `1PLUGIN-FABLE`, base `70801308`). Every count below
names the command that produced it (§A). Where a number could not be measured it is marked
UNVERIFIED with the command that would settle it.

## 0. Verdict in five lines

1. The founder's diagnosis is right and the founder's location is wrong. There **are** divergent
   copies of the plugin, but almost none of them are in the projects' `.claude/scripts`. They are
   in (a) the plugin repo's own gitignored `.claude/scripts` (562 shadow files, 338 drifted, **193
   newer than canonical by mtime**), (b) `~/.claude/leadv2-shared/scripts` (185 shadow, 113
   drifted, 173 real files with no canonical counterpart by relpath, of which the wired
   checker's narrower perimeter reports 22), (c) project `.claude/skills` (getmany: 20 plugin skill
   directories copied 2026-05-06, all 20 drifted), (d) project `.claude/agents` (getmany: the 3
   plugin agents as real files, 52–145 lines drifted each), and (e) project `.claude/hooks`
   (13/4/4 `leadv2-*` hooks that exist in no plugin directory; `leadv2-phase8-gate.sh` exists as
   three different files in three repos).
2. End state: **one canonical manifest, symlinks or nothing everywhere else, plus a declared
   per-project layer that a script can check.** Reading (c) of the mission's three, with
   the scripts half of it already true for the consumer repos today.
3. The 53 override files are **not** stale wholesale: 31 are read by the plugin at runtime and
   differ from every template that exists; 20 (all in persona-engine) have zero readers and
   have not changed since May–July 2026; 2 are runtime state that should not be in the tree.
4. The rule already failed as prose because the guard that enforces it,
   `plugins/leadv2/hooks/plugin-scripts-drift-guard.sh`, is **wired nowhere** (0 hits in
   `hooks.json`, 0 in all three project `settings.json`), and the only wired checker
   (`leadv2-one-copy-drift.sh`) covers the shared trees only and warns without blocking.
5. Order: guard first, shared trees second, plugin-repo shadow dir third (after direction
   triage of the 193 newer files), project hooks/skills/agents fourth, overrides last. Each
   step has a one-command rollback (§5).

## 1. Measured surface (verify, do not assume)

### 1.1 `.claude/scripts` in every tree the runtime can reach

Perimeter: recursive, excluding `*.pyc` and `node_modules/`. "Shadow" = a real file whose
relative path also exists under `plugins/leadv2/scripts/`. "Drift" = shadow whose bytes differ.
"Newer" = drifted file whose mtime is later than canonical's mtime. Command: §A.1.

| tree | symlinks | real files | shadow | drift | newer than canonical | dangling links |
|---|---|---|---|---|---|---|
| `persona-engine/.claude/scripts` | 616 | 68 | 0 | 0 | 0 | 16 |
| `getmany-followup-bot/.claude/scripts` | 318 | 20 | 0 | 0 | 0 | 1 |
| `respiro-ios/.claude/scripts` | 403 | 40 | 1 (`codex-guard.sh`) | 1 | 0 (Jul 16 vs canonical Sep 3) | 12 |
| `m3-market/.claude/scripts` (at `~/MythicalGames/`) | 420 | 60 | 0 | 0 | 0 | 7 |
| **`leadv2/.claude/scripts`** (gitignored) | 14 | **563** | **562** | **338** | **193** | 0 |
| **`~/.claude/leadv2-shared/scripts`** | 749 | 358 | 185 | 113 | 0 | 0 |

Corrections to the lead's table: the lead counted `persona-engine` real=48, `getmany`=13,
`respiro`=20, `leadv2`=386 with drift 265. Those are top-level-only counts (my top-level-only
figures for leadv2 are real=226, drift=96; §A.1 shows both). The recursive figure is the one
that matters because `tests/` and `lib/` are where the shadow lives (292 + 29 files). The
only "shadow" files in the consumer repos are `__pycache__/*.pyc` (9 / 2 / 4), which are
interpreter artefacts, not copies.

Also: **m3-market exists** at `~/MythicalGames/m3-market`, exactly where
`~/.claude/leadv2-shared/cross-repo-paths.yaml` says it is. The lead looked under
`~/Projects/`. It is a fourth consumer with 420 links, 11 overrides, 14 real hooks and 19 real
agents. It has no active lanes (`docs/leadv2/active.yaml`: 0 build/review/deploy/recovery
entries, 0 worktrees), so it is the safest tree to convert first and the one most likely to
be forgotten. The founder named it active; the leadv2 `.claude/CLAUDE.md` does **not** mention it
(`grep -n m3-market .claude/CLAUDE.md CLAUDE.md` → 0 hits); the line the mission refers to is
in the user-level `~/.claude-work/CLAUDE.md:23`, and it is not stale.

### 1.2 What is a "repo-native" script, measured

The 68 / 20 / 40 / 60 real non-shadow files are not all repo-native. Filtering for plugin
shape (`leadv2-*`, `lv2-*`, `_lv2*`, `install-leadv2*`) with no canonical at the same path
(§A.2):

| repo | plugin-shaped orphans | of which the plugin itself names | notes |
|---|---|---|---|
| persona-engine | 26 | 6 (`leadv2-phase-backfill.sh`, `leadv2-learn-consume.sh`, `leadv2-tasks-render.sh`, `leadv2-causal-analyze.sh`, `leadv2-rollback.sh`, `leadv2-preflight.sh`) | `leadv2-learn-consume.sh` is a plugin **hook** name reappearing as a project **script** |
| getmany-followup-bot | 11 | 6 | 3 of the 11 are byte-identical canonical copies parked in `.claude/scripts/.drifted-copies-20260902/` (`leadv2-helpers.sh`, `leadv2-state-atomic-write.sh`, `leadv2-codex-planner.sh`) |
| respiro-ios | 18 | 2 | 10 are `*.20260512` backups, 1 is `leadv2-dispatch-code.sh.quarantine-20260801T140041Z` |
| leadv2 | 1 (`leadv2-wiki-index.sh`) | 0 | also a dangling link target in persona-engine |

So the machine rule "real file whose path is not in the canonical manifest" is **necessary but
not sufficient**. It classifies `leadv2-rollback.sh` (5 plugin skill files name it, exists in
no plugin directory) as repo-native. That is the class of file the founder is actually
complaining about: plugin machinery that exists only in one project. §2.2 gives the rule that
catches it.

### 1.3 Hooks, agents, skills, the trees nobody measured

| repo | `.claude/hooks` real / links | `leadv2-*` hooks with no plugin counterpart | `.claude/agents` real / links | project skill dirs that share a name with a plugin skill |
|---|---|---|---|---|
| persona-engine | 35 / 6 | 13 (all tracked in git, 2026-04-27 … 2026-09-03) | 7 / 3 | 1 (`leadv2-deploy`, 1 entry differs) |
| getmany-followup-bot | 4 / 1 | 4 | 8 / 0 (**`architect`, `critic`, `security-auditor` as real files**, 2026-05-06, 145 / 102 / 52 lines differ from plugin) | **20** (all differ, 1–6 entries each, copied 2026-05-06) |
| respiro-ios | 5 / 1 | 4 | 15 / 3 | 1 (`lead-reflect`, 3 entries differ) |
| m3-market | 14 / — | UNVERIFIED (count only) | 19 / — | 1 |

Hook triplication (`md5 -q`, §A.3): `leadv2-phase8-gate.sh` is 3 distinct files in 3 repos;
`leadv2-reflect-enforcer.sh` 3 distinct; `leadv2-immune-intake-inject.sh` identical in all 3;
`session-start-safe-pull.sh` 2 distinct in 2 repos. These are plugin behaviour (Phase-8 gate,
reflect enforcement) shipped per repo, and they have already diverged. Nothing in
`plugins/leadv2/hooks/` has the same name (0 basename matches, §A.3), so there is no
canonical to compare against; the three copies are the only three.

The skills case is the most likely origin of the founder's "different copies of the plugin"
experience. Observed in this session's own skill listing: both `leadv2` and `leadv2:leadv2`,
both `leadv2-output-style` and the plugin's, appear as separately invocable skills. A project
copy of `leadv2-plan` from 2026-05-06 is offered next to the live `leadv2:leadv2-plan`, and
which one a model picks is not deterministic. UNVERIFIED: which of the two a bare
`/leadv2-plan` resolves to; settle with one invocation in getmany and `git log -1` on the
SKILL.md that produced the observed text.

### 1.4 Which path the runtime actually loads

Measured in this session: `CLAUDE_PLUGIN_ROOT=/Users/kostiantyn.vlasenko/.claude/plugins/local/leadv2/plugins/leadv2`,
and `readlink ~/.claude/plugins/local/leadv2/plugins/leadv2` →
`/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2`. So `hooks.json`'s 91
`${CLAUDE_PLUGIN_ROOT}` references resolve into the git checkout. **Committing to main is
deploying**, confirmed on the live path, not by doctrine.

Two facts that contradict each other and must be reconciled by whoever owns the checker:
`~/.claude/plugins/installed_plugins.json` records
`installPath: ~/.claude/plugins/cache/leadv2-local/leadv2/0.5.7` (lastUpdated 2026-09-01), that
directory was modified today (11:26), and `diff -rq` against the plugin shows 741 differing or
one-sided entries (413 in `scripts/`). Yet the environment variable says the runtime uses the
symlink. `leadv2-drift-guard.sh` still lists the cache as copy (3) of five and compares against
`0.1.0`, not `0.5.7`. UNVERIFIED: whether anything ever executes from the cache. Settle with
`fs_usage -w -f filesys | grep plugins/cache/leadv2-local` across one SessionStart; until then
the cache stays in the checker as INFO, never as a drift verdict (the guard's own header records
that a wrong perimeter "manufactures false confidence").

### 1.5 Existing machinery (do not build a sixth checker)

| script | perimeter | mode | wired where | callers |
|---|---|---|---|---|
| `hooks/leadv2-link-tree-heal.sh` | `~/.claude/leadv2-shared/scripts` vs canonical | warn, never heals a real file | SessionStart (`hooks.json`) | 1 |
| `hooks/leadv2-one-copy-drift.sh` → `scripts/leadv2-one-copy-convert.sh --check` | shared trees + `~/.claude/agents-shared` only | warn, output-capped, always exit 0 | SessionStart + PostToolUse:Bash | 1 |
| `hooks/plugin-scripts-drift-session-warn.sh` | `<repo>/.claude/scripts` real plugin-owned files | warn | SessionStart | 1 |
| `hooks/plugin-scripts-drift-guard.sh` | staged files under `.claude/scripts` that exist in canonical | **block at commit** | **nowhere** (`hooks.json` 0, three `settings.json` 0) | 0 |
| `scripts/leadv2-drift-guard.sh` | 5 copies incl. leadv2 repo shadow dir, cache `0.1.0`, `cross-repo-paths.yaml` repos | report, per-entry direction (`CANONICAL_NEWER` / `VENDORED_NEWER`) | called by one-copy-drift PostToolUse path | 4 |
| `scripts/leadv2-overrides-drift.sh` | `<repo>/.claude/leadv2-overrides` vs readers (ORPHAN / STALE) | report | nowhere | 0 |
| `scripts/leadv2-scripts-symlink-plan.sh` | per-file `.claude/scripts` conversion, `--apply` / `--rollback <backup-dir>` | mutate with backup | manual | 0 |
| `scripts/leadv2-one-copy-convert.sh` | shared trees, `--apply` / `--revert`, backup at `~/.claude/leadv2-one-copy-backups` | mutate with backup; refuses while LIVENESS-SELF-DESTRUCT-01 open | manual | 1 |

Live output of the wired checker today (`--check` from `~/Projects/leadv2`, §A.4):
`linked=722 regression=62 badlink=0 expected_override=3 diverged=113 info=22`, exit 1. This
session's SessionStart printed a LINK-TREE-DRIFT line and a FORK-GUARD line but **no one-copy
line**, although the hook is wired and the check is red. UNVERIFIED why (the hook writes a
capped JSON `additionalContext`; the harness may have dropped it); settle by running the hook
by hand with the SessionStart stdin shape and reading its stdout.

Conclusion for §4: the pieces exist. What is missing is one perimeter, one manifest, and one
place where the check can say no.

## 2. End state

### 2.1 The choice

**Chosen: (c) a declared, small, machine-checkable per-project layer**, with the plugin-owned
part of every project tree being symlinks or absent.

Against (a) "every project file is a symlink into `plugins/leadv2/`": already true for 99.7 %
of plugin-owned scripts in the four consumer repos (§1.1), and it cannot describe the other
68 / 20 / 40 / 60 files, which are `deploy-latest.sh`, App-Store pollers, engine probes and
persona tooling that must never live in the plugin. (a) has no answer for hooks that the plugin
does not ship, or for project skills. It is a statement about one directory, not an end state.

Against (b) "projects hold nothing; the runtime resolves through `~/.claude/plugins/`": the
plugin runtime itself hard-codes `<repo>/.claude/scripts/<name>` at 24 non-test call sites
(`codex-task.sh` 9, `claude-subsession.sh` 4, `codex-guard.sh` 3, `ask-lead.sh` 3,
`glm-coder.sh` 2, `cx-tail.sh` 2, `multi-model.sh` 1; §A.5), the subagent protocol tells every
worker to call `.claude/scripts/ask-lead.sh`, `leadv2-fanout.sh:60` and
`leadv2-fanout-lane-launcher.sh:98` fall back to `~/.claude/leadv2-shared/scripts/leadv2-active-registry.sh`,
and every project's `settings.json` wires hooks through `.claude/hooks/` (38 / 7 / 13
commands, all `project-hooks`, 0 `plugin`; §A.6). (b) is the right asymptote and the wrong
next step: it requires rewriting the plugin's own path resolution while 24 build/review lanes
are live in leadv2 and 5 in persona-engine (§A.7). Each call-site rewrite is a separate,
testable change and can be scheduled after (c) has removed the copies.

### 2.2 The invariant, stated so a script can check it

Let `MANIFEST = git -C ~/Projects/leadv2 ls-files plugins/leadv2/{scripts,hooks,agents,skills}`,
relative to `plugins/leadv2/`. Let `TREES` = `~/Projects/leadv2/.claude`,
`~/.claude/leadv2-shared` (+ `~/.claude/agents-shared`), and `<repo>/.claude` for every
`path:` in `cross-repo-paths.yaml`.

- **I1 (plugin-owned ⇒ link or absent).** For every `class/rel` in MANIFEST and every tree T,
  `T/class/rel` is absent, or is a symlink whose `_lv2_realpath` equals the canonical file.
  A real file at a manifest path is a REGRESSION regardless of content (identical copies drift
  next commit; the 62 identical shared-tree copies prove it). The 3 `agents-shared` files stay
  on the existing EXPECTED-OVERRIDE list until §5 step 4 decides them.
- **I2 (skills are namespaced, never copied).** For every `skills/<name>` in MANIFEST,
  `T/skills/<name>` is absent. The plugin already serves it as `leadv2:<name>`; a project copy
  is a second, older source with the same bare name.
- **I3 (plugin-shaped ⇒ declared).** Every real file under `T/{scripts,hooks}` whose basename
  matches `^(leadv2|lv2|_lv2|install-leadv2)` and is not in MANIFEST must be listed, one path
  per line, in `T/leadv2-overrides/native-plugin-shaped.txt`. The list is the reviewed
  exception: it says "this is ours, it only looks like the plugin's". An unlisted match is a
  PROMOTE-OR-DECLARE finding, never silently native. Today that list would need 26 / 11 / 18 /
  UNVERIFIED entries (§1.2) before the check goes green; that is the point, each is a decision.
- **I4 (overrides are contract paths).** Every file under `T/leadv2-overrides/` has a relpath
  (or lives under a directory) that the plugin greps for. The 28 contract paths are the ones
  `grep -rhoE 'leadv2-overrides/[A-Za-z0-9_./-]+' plugins/leadv2` returns (§A.8). Directory
  contracts: `rules/` (glob-loaded by `leadv2-rules-eval.sh:83` and `leadv2-rules-load.sh:50`),
  `golden/`, `scripts/`, `.state/` (state, gitignored). Anything else is ORPHAN, which
  `leadv2-overrides-drift.sh` already computes and nothing runs.
- **I5 (the plugin repo is consumer zero).** `~/Projects/leadv2/.claude/scripts` obeys I1 like
  every other tree. Because the directory is gitignored (`.gitignore:10`, since `6244403e`
  2026-06-10), its 563 files are invisible to every git-based check, which is how 193 of them
  came to be newer than the source of truth. After §5 step 3 the directory does not exist;
  `tests/run-all.sh:148-152` already prefers the plugin path and only falls through to
  `.claude/scripts/tests/run-core-offline.sh` when `plugins/leadv2/` is absent, so the P0
  (`GATE-RUNS-AN-UNTRACKED-HALF-SIZED-CORE-RUNNER-01`) and this end state agree: the fix for
  the P0 must not reintroduce a `.claude/scripts` dependency in this repo, and this design must
  not delete the fall-through, which consumer repos without `plugins/leadv2/` still need.
  Note for the P0 owner: at HEAD `b2cf62f2` the wrapper does **not** load the 496-line runner in
  this repo (`sed -n 148,152p tests/run-all.sh`); `run-core-offline.sh:650,667` does still scan
  `$REPO_ROOT/.claude/scripts/tests` for `# run-all-triggers:` rows, so the 292 stale test
  copies contribute scope-map rows today. Deleting the directory removes that input; the P0 fix
  should be verified against a tree where it is gone.

What legitimately stays per project, by construction: everything real that is not in MANIFEST
and either does not look plugin-shaped or is declared in `native-plugin-shaped.txt`; the
override files on the contract list; project hooks not shipped by the plugin, wired in the
project's `settings.json`; project skills whose name is not a plugin skill. The boundary is
decided by two string comparisons and one file, no human adjudication per file.

## 3. The 53 override files, one by one

Method (§A.9): for each file, count plugin files that name its basename, count readers in the
repo's own `.claude/scripts`, `.claude/hooks`, `settings.json`, diff against
`plugins/leadv2/examples/overrides/{generic,pe}/<basename>` where one exists, and take the
last git commit date. Verdicts: LIVE = read and differs from every template (or no template);
LIVE-GLOB = read through a directory glob, not by name; UNREAD = zero readers anywhere; STATE
= runtime state or archive.

### persona-engine (38)

| file | lines | plugin readers | native readers | vs template | last change | verdict |
|---|---|---|---|---|---|---|
| state-paths.yaml | 47 | 34 | 2 | no template | 2026-08-01 | LIVE |
| deploy.sh | 68 | 25 | 1 | 79 lines vs generic | 2026-06-03 | LIVE |
| stack.yaml | 54 | 21 | 0 | 76 vs pe, 61 vs generic | 2026-07-27 | LIVE |
| verify.sh | 50 | 21 | 0 | 58 vs generic | 2026-05-12 | LIVE |
| codex-policy.yaml | 26 | 16 | 1 | 28 vs generic | 2026-07-24 | LIVE |
| outcome-watch.sh | 444 | 11 | 1 | 453 vs generic | 2026-06-12 | LIVE |
| extensions.md | 763 | 6 | 1 | 769 vs generic | 2026-09-05 | LIVE |
| active-limits.yaml | 32 | 6 | 0 | none | 2026-07-26 | LIVE |
| omp-task.sh | 158 | 4 | 1 | none | 2026-07-29 | LIVE |
| quality-engine.yaml | 72 | 4 | 0 | none | 2026-05-26 | LIVE |
| status-collector-facts.sh | 510 | 4 | 0 | none | 2026-08-29 | LIVE |
| toolsets.yaml | 21 | 3 | 0 | none | 2026-05-14 | LIVE |
| deploy-verify.sh | 121 | 2 | 0 | none | 2026-07-27 | LIVE |
| supervise-truth-probe.sh | 341 | 1 non-test (`leadv2-lanes-snapshot.sh`) | 0 | none | 2026-08-03 | LIVE, **suspect**: supervisor retired 2026-08-17 (SUPERVISOR-DELETE-01) |
| gate1.sh | 130 | 1 | 0 | none | 2026-05-27 | LIVE, single reader |
| backlog-pump.yaml | 3 | 1 | 0 | none | 2026-07-29 | LIVE |
| stability-policy.yaml | 57 | 0 | 1 (repo-native) | none | 2026-05-31 | LIVE (project-owned config, correctly per-project) |
| rules/R-001 … R-006 `.rule.md` (6) | 44–69 | 0 by name; dir glob-loaded | 0 | none | 2026-05-26 (R-006 2026-07-06) | LIVE-GLOB |
| gemini-policy.yaml | 51 | 0 | 0 | none | 2026-05-23 | **UNREAD** |
| golden/bandit-sample-seeded.json | 98 | 0 by name; `golden/` referenced once | 0 | none | 2026-06-11 | UNREAD (UNVERIFIED: the one `golden/` reference is `golden/eval_engine.py`, a different file) |
| tests/gate1-businesssignal-selftest.sh | 126 | 0 | 0 | none | 2026-05-29 | **UNREAD** |
| tests/test-canary-soak-probe.sh | 42 | 0 | 0 | none | 2026-05-27 | **UNREAD** |
| tests/rule-fixtures/*.txt (10) | 7–13 | 0 (`grep -rlF rule-fixtures plugins/leadv2/{scripts,hooks}` → 0) | 0 | none | 2026-05-26 | **UNREAD** |
| .state/trust-alarm.json | 0 | 0 | 0 | — | gitignored | STATE |

persona-engine tally: 17 LIVE by name, 6 LIVE-GLOB, **14 UNREAD**, 1 STATE.

### getmany-followup-bot (8)

| file | lines | plugin readers | vs template | last change | verdict |
|---|---|---|---|---|---|
| state-paths.yaml | 11 | 34 | none | 2026-05-19 | LIVE |
| deploy.sh | 226 | 25 | UNVERIFIED (not diffed) | 2026-09-07 | LIVE |
| stack.yaml | 14 | 21 | UNVERIFIED | 2026-05-19 | LIVE |
| verify.sh | 33 | 21 | UNVERIFIED | 2026-05-19 | LIVE |
| codex-policy.yaml | 12 | 16 | UNVERIFIED | 2026-05-19 | LIVE |
| outcome-watch.sh | 38 | 11 | UNVERIFIED | 2026-05-19 | LIVE |
| extensions.md | 171 | 6 | UNVERIFIED | 2026-05-22 | LIVE |
| archive/leadv2.md.fork-2026-08-12 | 492 | 0 | — | untracked | STATE |

### respiro-ios (7)

All 7 (`state-paths`, `deploy.sh`, `stack.yaml`, `verify.sh`, `codex-policy.yaml`,
`outcome-watch.sh`, `extensions.md`) are LIVE, 6–34 plugin readers each, all last changed
2026-08-21/25. `codex-policy.yaml` is 2 lines: worth reading before calling it a decision; it
may be the default written out (UNVERIFIED, settle with `cat` and compare to the plugin's
default when the file is absent).

### Hypothesis test

"All overrides are stale and unneeded" is **false for 31 of 53** (the six core contract files
in every repo are read by 6–34 plugin files each and none matches a template) and **true for
20**, all in persona-engine: `gemini-policy.yaml`, `golden/bandit-sample-seeded.json`, two
`tests/*.sh`, ten `tests/rule-fixtures/*.txt`, plus the 6 `rules/*.rule.md` **if and only if**
`quality-engine.yaml` no longer enables the rules engine (UNVERIFIED: `grep -n rules
quality-engine.yaml` and the `LV2_QE_*_RULES_DIR` export at `leadv2-helpers.sh:348`). The 2
STATE files should leave the tree regardless (I4). `supervise-truth-probe.sh` (341 lines) is
read by one script that snapshots a retired subsystem; recover the rationale from
`git -C persona-engine log --follow` before deleting, because a 341-line probe is a decision
someone made.

For the LIVE 31 the correct action is not deletion but **contract tightening**: an override that
the plugin reads is by definition the per-project layer the end state keeps. Whether its
*content* still differs from the default is a second question the plugin can answer itself
once `leadv2-overrides-drift.sh` STALE is run (it exists, 0 callers).

## 4. Enforcement

A rule that is prose fails; a rule that is a SessionStart warning also fails (the wired one is
red with 62 regressions and produced no visible line in this session). The check has to run at
the moment a copy is *created*, and it has to be able to say no.

- **Where a copy is born.** Three ways, all observed: `cp` in a shell (the 2026-07-29 defect),
  an editor "save as" into a symlink's place (the 2026-09-04 worktree defect is the inverse:
  edit landed where no link pointed), and a scaffold (`leadv2-init/SKILL.md:74`
  `cp "$EXAMPLE_SRC/$f" "$OVERRIDE_DIR/$f"` is correct, it targets overrides; the getmany 2026-05-06
  skills/agents copies came from an earlier install path that no longer exists in the plugin,
  UNVERIFIED which).
- **Check 1, commit-time, blocking.** Wire the existing `plugin-scripts-drift-guard.sh` into
  `hooks.json` as PreToolUse(Bash) matching `git (commit|add)`, perimeter widened from
  `.claude/scripts` to I1+I2 (`scripts`, `hooks`, `agents`, `skills`) and driven by MANIFEST,
  not by "exists in canonical" (`git ls-files` excludes the `.test-dispatch-ppf-r5-funcs.*.sh`
  scratch files that a directory listing would include). Cost per commit: one `git diff
  --cached --name-only` and one `comm` against a cached manifest; UNVERIFIED in ms, settle
  with `time` on a 20-file commit. It runs in whichever repo the session is in, because
  `hooks.json` ships with the plugin. This is the one change that "committing to main IS the
  deploy" makes cheap: one commit, four repos guarded.
- **Check 2, lane close, blocking.** The definition-of-done gate already refuses a lane whose
  diff touches runtime-state paths (item d). Add item (e): the lane's `git diff --name-only
  <base>..HEAD` intersected with MANIFEST paths under any `.claude/` prefix must be empty, and
  any new `.claude/leadv2-overrides/` path must be on the contract list. Cost: the diff is
  already computed for (d).
- **Check 3, SessionStart, warning, one perimeter.** Replace the three SessionStart checkers
  (`link-tree-heal`, `one-copy-drift`, `plugin-scripts-drift-session-warn`) with one invocation
  of `leadv2-one-copy-convert.sh --check` whose perimeter is TREES from §2.2 (today it is the
  shared trees only). One line of output: counts and a path to the detail log, which is what
  the output-cap fix already does. The cache stays INFO until §1.4 is settled.
- **Check 4, weekly, in the pulse.** `leadv2-overrides-drift.sh` (ORPHAN / STALE) and I3
  (`native-plugin-shaped.txt`) run once a week from the existing pulse, not per edit; a
  file-by-file override audit is not a per-commit cost.
- **The kill switch stays.** `LEADV2_ONE_COPY_DRIFT=0` already exists for the warn hook; the
  blocking hook gets the same env escape and nothing else, so a founder can commit through it
  in one step without editing a file, mirroring `LEADV2_ROUTE_ENFORCE=0`.
- **Test the failure path.** `test-plugin-scripts-drift-guard.sh` and `test-one-copy-drift.sh`
  exist; the widened perimeter needs three new red cases: a real file at
  `.claude/hooks/<manifest hook>`, a directory at `.claude/skills/<manifest skill>`, and a
  `leadv2-*.sh` under `.claude/scripts` not in `native-plugin-shaped.txt`. Each must be refused
  by check 1 and check 2 and must **not** fire on `deploy-latest.sh` or a declared file.

What this costs on a normal edit: nothing until `git commit`, then one diff-vs-manifest
comparison. What it costs at session start: one check instead of three. What it removes: the
possibility that a real file at a plugin path reaches main in any of five trees.

## 5. Order and reversibility

Live state at measurement (§A.7): leadv2 `active.yaml` 444 entries, 24 in
build/review/deploy/recovery, 190 worktrees registered, 76 of the registered worktree paths
exist on disk; persona-engine 27 entries, 5 live, 17 worktrees; getmany 0 / 7; respiro 0 / 1;
m3-market 0 / 0. A running lane reads canonical through symlinks and its own worktree; none
of the steps below rewrites a canonical file, so the only lane-visible change is a path that
was a real file becoming a link to identical or newer content. The steps still wait for
quiet where noted, because "identical" is a claim about the moment of conversion.

| # | step | must be quiet first | proof | rollback (one command) |
|---|---|---|---|---|
| 0 | Land MANIFEST + widened `--check` in report mode; run it in all six trees; commit the report of counts. No mutation. | nothing | `--check` exit code and tally per tree, pasted | `git -C ~/Projects/leadv2 revert <sha>` |
| 1 | Wire check 1 (commit guard) and check 2 (DoD item e) in **warn** mode for 7 days, then flip to block. | nothing; warn mode cannot break a lane | the warn log shows every would-be block for a week; zero unexplained entries before the flip | `git -C ~/Projects/leadv2 revert <sha>` (main is the deploy, so the revert is the undeploy) |
| 2 | Shared trees: `leadv2-one-copy-convert.sh --apply` on the 62 identical regressions; for the 113 diverged, `leadv2-drift-guard.sh --json` direction per entry (all 113 measured `CANONICAL_NEWER` by mtime, 0 vendored-newer, §A.1) then convert; for the 22 no-canonical, promote or delete by name. | no lane in `dispatch`/`fanout` for the ~1 min of the apply (`leadv2-fanout.sh:60` falls back to the shared registry path); precondition LIVENESS-SELF-DESTRUCT-01 closed, the script refuses otherwise | `--check` tally `regression=0 diverged=0`; `test-one-copy-drift.sh` green | `leadv2-one-copy-convert.sh --revert` (restores from `~/.claude/leadv2-one-copy-backups`) |
| 3 | Plugin repo shadow dir: (a) `leadv2-drift-guard.sh --json` on copy (2); triage the **193 vendored-newer** files: for each, `diff` against canonical, port anything that is a real fix into `plugins/leadv2/` as a normal committed change, record the rest as superseded; (b) `mv ~/Projects/leadv2/.claude/scripts ~/.claude/leadv2-quarantine/leadv2-dot-claude-scripts-<date>`; (c) run `tests/run-all.sh --scope all`. | no leadv2 lane in build/review (24 today); do it in a window with 0, or accept that a lane whose worktree reads `.claude/scripts/tests/*` via `$REPO_ROOT` would see the dir vanish mid-run | `run-all.sh --scope all` green on the tree without the directory; `run-core-offline.sh` scope map has no `.claude/scripts/tests` rows; P0 owner confirms their fix against this tree | `mv ~/.claude/leadv2-quarantine/leadv2-dot-claude-scripts-<date> ~/Projects/leadv2/.claude/scripts` |
| 4 | Consumer scripts: delete `__pycache__` shadows (regenerated), remove the 16 / 1 / 12 / 7 dangling links (all point at scripts retired 2026-08-17 or `dummy.sh`), convert respiro `codex-guard.sh` after diffing its 401 lines against canonical (canonical is 7 weeks newer), delete quarantine dirs older than 30 days (`.drifted-copies-20260902`, `*.20260512`, `*.quarantine-20260801*`). Start with m3-market (0 lanes). | per repo: no lane in build/review in that repo (persona-engine has 5) | `leadv2-scripts-symlink-plan.sh` dry-run shows 0 would-link; `--check` green | `leadv2-scripts-symlink-plan.sh --rollback <backup-dir>` |
| 5 | Hooks: for each of the 13 / 4 / 4 / UNVERIFIED `leadv2-*` project hooks, one decision: promote into `plugins/leadv2/hooks/` + `hooks.json` and delete the project file and its `settings.json` line, or add to `native-plugin-shaped.txt`. Triplicated ones (`phase8-gate`, `reflect-enforcer`) start from the newest by git and diff the other two before promotion. | the repo has no live lane, because UNVERIFIED whether a running session re-reads `hooks.json` (the user-level CLAUDE.md records this as the open question) | check 1 green in that repo; the hook fires in a fresh session (SessionStart line) | `git -C <repo> revert <sha>` plus `git -C ~/Projects/leadv2 revert <sha>`, two commands, one per side |
| 6 | Skills and agents: delete getmany's 20 plugin-skill directories and 3 agent copies (all older than the plugin, 2026-05-06); delete persona-engine `leadv2-deploy` and respiro `lead-reflect` skill copies; decide the 3 `agents-shared` EXPECTED-OVERRIDE files (promote the delta into the plugin agents or keep them declared). | no live lane in that repo | fresh session's skill list shows only `leadv2:<name>`; check 1 green | `git -C <repo> revert <sha>` |
| 7 | Overrides: delete the 14 UNREAD persona-engine files and 2 STATE files; run `leadv2-overrides-drift.sh` STALE on the 31 LIVE; recover rationale for `supervise-truth-probe.sh` and `gate1.sh` (single readers) before deciding; add `native-plugin-shaped.txt` per repo. | nothing (overrides are read at task start; a lane mid-flight has already read them) | `leadv2-overrides-drift.sh` ORPHAN=0 in all four repos | `git -C <repo> revert <sha>` |
| 8 | Retire the special cases: remove `leadv2-drift-guard.sh` copy (2) and the cache from the perimeter (after §1.4 is settled), delete `run-all.sh`'s `.claude/scripts` fall-through **only if** every consumer has `plugins/leadv2/` reachable, which none does today, so this stays. Update `tests/run-all.sh:146-148` comment (names m3-market as a repo without `plugins/leadv2/`, still true) and the drift-guard header (cache `0.1.0` → whatever §1.4 decides). | nothing | `--check` and drift-guard agree on tree count | `git revert` |

Steps 2, 4, 5, 6 are per tree and independent; step 3 is the one that touches the plugin
repo's own working tree and is the only one where a leadv2 lane could notice. Nothing in the
list pushes to origin, resets, cleans, stashes or prunes worktrees; the quarantine `mv` is the
only non-git mutation and is undone by the same `mv`.

## 6. What I deliberately left alone

- Did not touch the P0 gate defect; §2.2 I5 records the HEAD observation the P0 owner needs.
- Did not read the content of any override, hook, or skill copy beyond `diff | wc -l`; §3's
  per-file rationale recovery is the step-7 work, not this report's.
- Did not settle §1.4 (cache) or the skills-resolution question in §1.3; both are marked
  UNVERIFIED with the command that settles them.
- Did not measure m3-market hooks/agents beyond counts, or getmany's override templates diff.

## A. Measurement appendix (commands)

All run 2026-09-08 from `~/Projects/leadv2/.claude/worktrees/1PLUGIN-FABLE` with
`P=~/Projects/leadv2/plugins/leadv2`.

**A.1 scripts census (per tree `S`).**
```
find $S -type l | wc -l;  find $S -type f ! -name '*.pyc' ! -path '*/node_modules/*' | wc -l
# shadow / drift / newer:
while read f; do rel=${f#$S/}; c=$P/scripts/$rel; [ -f "$c" ] || continue; sh++;
  cmp -s "$f" "$c" || { dr++; [ "$f" -nt "$c" ] && nw++; }; done < <(find $S -type f ! -name '*.pyc' ! -path '*/node_modules/*')
find $S -type l ! -exec test -e {} \; -print | wc -l        # dangling
# top-level-only variant (matches the lead's perimeter): add -maxdepth 1
git -C ~/Projects/leadv2 ls-files | grep -c '^\.claude/scripts/'   # → 0
git -C ~/Projects/leadv2 check-ignore -v .claude/scripts/x         # → .gitignore:10
git -C ~/Projects/leadv2 log -S'.claude/scripts/' --format='%h %cs' -- .gitignore  # → 6244403e 2026-06-10
```
**A.2 plugin-shaped orphans.** Same walk, keep files with no `$P/scripts/$rel`, basename
matching `leadv2-*|lv2-*|_lv2*|install-leadv2*`; `grep -rlF "$b" $P/scripts $P/hooks $P/skills | grep -v /tests/`
for "plugin names it".
**A.3 hooks/agents/skills.** `find <repo>/.claude/hooks -type f|-type l | wc -l`;
`for f in <hook basenames>; do find $P/scripts $P/hooks -name "$f"; done` (2 hits: `leadv2-queue-archiver.sh`,
`leadv2-pulse-write.sh`, both plugin **scripts**, not hooks); `md5 -q <repo>/.claude/hooks/<b>` across repos;
`for d in <repo>/.claude/skills/*/; do [ -d $P/skills/$(basename $d) ] && diff -rq $d $P/skills/$(basename $d) | wc -l; done`;
`diff <repo>/.claude/agents/<a>.md $P/agents/<a>.md | grep -c '^[<>]'`.
**A.4 checkers.** `cd ~/Projects/leadv2 && bash $P/scripts/leadv2-one-copy-convert.sh --check | tail -1`;
`grep -c drift-guard $P/hooks/hooks.json` → 1 (that hit is `leadv2-blocker-drift-guard.sh`);
`grep -c drift-guard <repo>/.claude/settings.json` → 0, 0, 0.
**A.5 hard-coded project paths.** `grep -rhoE '\.claude/scripts/[A-Za-z_-]+\.(sh|py)' $P/scripts/*.sh $P/scripts/lib $P/hooks | sort | uniq -c | sort -rn`.
**A.6 hook wiring by origin.** `python3` over `<repo>/.claude/settings.json` classifying each
`hooks[*][*].hooks[*].command` by substring (`plugins/leadv2|CLAUDE_PLUGIN_ROOT` / `leadv2-shared` / `.claude/hooks`).
**A.7 live state.** `grep -cE 'phase:\s*(build|review|deploy|recovery)' <repo>/docs/leadv2/active.yaml`;
`git -C <repo> worktree list | wc -l`; worktree paths from `active.yaml` tested with `[ -d ]`.
**A.8 override contract.** `grep -rhoE 'leadv2-overrides/[A-Za-z0-9_.*/-]+' $P --include='*.sh' --include='*.md' --include='*.py' --include='*.json' --include='*.yaml' --include='*.mjs' | sort | uniq -c | sort -rn`
(106 plugin files reference overrides; 28 distinct paths after stripping trailing punctuation).
**A.9 override census.** Per file: `grep -rlF "$b" $P … | wc -l`; `grep -rlF "$b" <repo>/.claude/scripts <repo>/.claude/hooks <repo>/.claude/settings.json | grep -v leadv2-overrides | wc -l`;
`diff $f $P/examples/overrides/{generic,pe}/$b | grep -c '^[<>]'`; `git -C <repo> log -1 --format=%cs -- <path>`;
`grep -rnF 'leadv2-overrides/rules' $P` (3 non-test sites); `grep -rlF rule-fixtures $P/scripts $P/hooks` (0).
**A.10 runtime root.** `echo $CLAUDE_PLUGIN_ROOT`; `readlink ~/.claude/plugins/local/leadv2/plugins/leadv2`;
`sed -n 98,106p ~/.claude/plugins/installed_plugins.json`; `diff -rq ~/.claude/plugins/cache/leadv2-local/leadv2/0.5.7 $P | wc -l`.
