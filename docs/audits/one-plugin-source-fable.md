# One plugin source, no project copies — design, arm A (fable)

Date: 2026-09-08. Lane: dispatch-1f5e5544 / 1PLUGIN-FABLE-2. Report only; no behaviour changed.

Every count below carries the command that produced it. Commands were run from the lane
worktree with `plugins/leadv2` meaning `~/Projects/leadv2/plugins/leadv2` (same bytes at base
70801308). Where the worktree location itself distorted a number, that is called out.

## 0. Verdict in five lines

1. The founder's framing ("different copies of the plugin in the projects") is wrong about the
   projects and right about the system. The four project trees are 99.9% symlinks already; the
   copies live in the plugin repo's own `.claude/scripts`, in `~/.claude/leadv2-shared/scripts`,
   and in `~/.claude/scripts`. Those three are **rsync targets of the plugin's own sync script**,
   and any rsync target drifts between `--write` runs by construction.
2. End state (Q1): **one byte store, `plugins/leadv2/` in git; every other appearance of a
   plugin-owned file is a per-file symlink; a small declared per-project layer survives and is
   machine-checkable.** Not "projects hold nothing": 51 plugin scripts and every project's
   `settings.json` address `<repo>/.claude/...` paths, so that reading is a rewrite, not a cleanup.
3. Boundary (Q2): a file is plugin-owned **iff its relative path exists in canonical git**
   (`git -C ~/Projects/leadv2 ls-files plugins/leadv2/<kind>/<rel>`). Name prefixes cannot decide
   it (`ask-lead.sh`, `codex-task.sh`, `glm-coder.sh` are plugin-owned and unprefixed).
4. Overrides (Q3): the hypothesis is one-third right. 24 of 64 override files have zero readers in
   the plugin; 40 are read, and of those the yaml ones mostly carry real, repo-specific decisions
   with recoverable rationale. Delete the 24; keep and schema the rest.
5. Invariant (Q4): the check already exists in three pieces (`leadv2-one-copy-convert.sh --check`,
   `plugin-scripts-drift-guard.sh`, `leadv2-plugin-sync.sh`'s link classifier) but the pre-commit
   guard is **wired in zero repos** and the check's perimeter excludes the worst tree. Wire it,
   widen it, and retire the rsync targets so there is nothing left to drift.

## 1. Measured surface

### 1a. The six places a plugin script can be, today

The drift guard's own header names five copies (`plugins/leadv2/scripts/leadv2-drift-guard.sh:22-27`).
There is a sixth, `~/.claude/scripts/`, which `leadv2-plugin-sync.sh` syncs as target (e).

| # | location | mechanism today | symlinks | real files | real files shadowing a canonical path | of those, byte-different |
|---|---|---|---|---|---|---|
| 1 | `~/Projects/leadv2/plugins/leadv2/scripts` | git-tracked source | — | — | — | — |
| 2 | `~/Projects/leadv2/.claude/scripts` | rsync target (f), gitignored | 21 | 544 | 543 | 338 |
| 3 | `~/.claude/plugins/cache/leadv2-local/leadv2/<ver>/` | rsync target (a); inert (see below) | n/m | n/m | n/m | n/m |
| 4 | `~/.claude/leadv2-shared/scripts` | rsync target (b) + heal-linker | 749 | 351 | 178 | 113 |
| 5a | `~/Projects/persona-engine/.claude/scripts` | per-file links (c) | 610 | 68 | 0 | 0 |
| 5b | `~/Projects/getmany-followup-bot/.claude/scripts` | per-file links (c), repo NOT in cross-repo yaml | 318 | 20 | 0 | 0 |
| 5c | `~/Projects/respiro-ios/.claude/scripts` | per-file links (c) | 393 | 41 | 1 | 1 |
| 5d | `~/MythicalGames/m3-market/.claude/scripts` | per-file links (c) | 420 | 60 | 0 | 0 |
| 6 | `~/.claude/scripts/leadv2-*` | rsync target (e), additive | 119 | 101 | 101 | 13 |

Command for rows 2, 5a–5c (recursive, `__pycache__`/`.mypy_cache` excluded; "shadow" = same
relative path exists under canonical; "different" = `cmp -s` fails):

```
P=~/Projects; C=$P/leadv2/plugins/leadv2/scripts
for t in persona-engine getmany-followup-bot respiro-ios leadv2; do
  d="$P/$t/.claude/scripts"
  L=$(find "$d" -type l -not -path '*/__pycache__/*' -not -path '*/.mypy_cache/*' | wc -l)
  F=$(find "$d" -type f -not -path '*/__pycache__/*' -not -path '*/.mypy_cache/*' | wc -l)
  S=0; D=0
  while IFS= read -r f; do rel="${f#$d/}"; c="$C/$rel"
    if [ -f "$c" ]; then S=$((S+1)); cmp -s "$f" "$c" || D=$((D+1)); fi
  done < <(find "$d" -type f -not -path '*/__pycache__/*' -not -path '*/.mypy_cache/*')
  echo "$t: symlinks=$L real=$F shadow=$S drifted=$D"
done
# persona-engine: symlinks=610 real=68 shadow=0 drifted=0
# getmany-followup-bot: symlinks=318 real=20 shadow=0 drifted=0
# respiro-ios: symlinks=393 real=41 shadow=1 drifted=1
# leadv2: symlinks=21 real=544 shadow=543 drifted=338
```

Row 5d used the same loop against `~/MythicalGames/m3-market`. Row 4:

```
T=~/.claude/leadv2-shared/scripts; ... same loop ...
# real=351 shadow=178 drifted=113 non-plugin=173
```

Row 6: `for f in ~/.claude/scripts/leadv2-*; do ... done` → `real-shadow=101 drifted=13 symlinks=119`.

**Reconciliation with the lead's table.** The lead's persona-engine symlink count (616) reproduces
exactly with `find -type l` including `__pycache__` paths; mine excludes them (610). The lead's
leadv2 row (386 real / 265 drifted) does not reproduce under any perimeter I tried: recursive gives
544/338, top-level only gives 226/96, recursive-excluding-`tests/` gives 252/103. UNVERIFIED which
perimeter the lead used; the directory's newest file is dated Sep 7 12:09 so the tree may also have
changed between measurements. Nothing in the design depends on which figure is right: the row is
"hundreds of drifted real copies" under every perimeter.

**Row 2 is not an accident.** `.gitignore:9-10` reads "Plugin sync writes canonical scripts here —
not source, not committed", and `leadv2-plugin-sync.sh:996-1020` declares the tree as sync target
(f) with `rsync --recursive --delete`, with the recorded reason that the drift guard checked it and
nothing wrote it, so it "would drift forever". The fix chosen then was to make it another rsync
target; it has drifted anyway because nobody runs `--write` (newest file Sep 7, bulk Aug 28,
oldest Jun 10 — `ls -lt ~/Projects/leadv2/.claude/scripts/*.sh | head/tail`).

**Row 3 is inert.** `ls -ld ~/.claude/plugins/local/leadv2/plugins/leadv2` → symlink to
`~/Projects/leadv2/plugins/leadv2`. The runtime plugin root IS canonical; three cache versions
(0.1.0, 0.3.0, 0.5.7) exist under `~/.claude/plugins/cache/leadv2-local/leadv2/` and nothing on the
hook path references them (`hooks.json` commands all start `${CLAUDE_PLUGIN_ROOT}/...`, 30 of 30
listed via `python3 -c 'json.load(...)'`). This confirms the 2026-09-07 doctrine note in the user
CLAUDE.md.

**Row 4's "repo-owned files" are gone.** `leadv2-link-tree-heal.sh:15-18` says the shared tree
"legitimately holds ~196 REAL repo-owned files (glm-coder.sh and friends)". Today the 173 real files
with no canonical counterpart are: 171 under `node_modules/`, `leadv2-wiki-index.sh`, `.DS_Store`
(`find ... | sed 's|/.*||' | sort | uniq -c`). `glm-coder.sh` is canonical now. The comment that
justifies "never overwrite a real file in the shared tree" describes a state that no longer exists.

**Row 5b is unexplained.** `~/.claude/leadv2-shared/cross-repo-paths.yaml` lists persona-engine,
m3-market (at `~/MythicalGames/m3-market`) and respiro-ios; `grep getmany` over it returns nothing.
getmany's 318 links (oldest Aug 27, newest Sep 7) must have come from `--project-root` runs or a
hand loop. UNVERIFIED which; `grep -rn 'project-root' ~/Projects/getmany-followup-bot/.claude` or
the founder's shell history would settle it.

**Correction to the mission text.** `m3-market` does exist on this machine, at
`~/MythicalGames/m3-market` (`ls -d` succeeds), is the path the cross-repo yaml names, has 420
links / 60 real / 0 shadows and 11 override files, and is **not a git repository**
(`git -C ~/MythicalGames/m3-market log` → "fatal: not a git repository"). So it is a live sync
target that cannot carry a pre-commit guard. The `.claude/CLAUDE.md` in this repo has no
`m3-market` line at all (`grep -n m3-market .claude/CLAUDE.md` → empty); the stale line is in the
user-level `~/.claude-work/CLAUDE.md` ("Live repos: persona-engine, m3-market, respiro-ios"),
which omits getmany.

### 1b. Agents and hooks

Per repo, `maxdepth 1`, "shadow" = same basename exists under `plugins/leadv2/agents|hooks`:

| repo / dir | symlinks | shadow identical | shadow differs | native | hooks present but not in settings.json |
|---|---|---|---|---|---|
| persona-engine/agents | 3 (→ `~/.claude/agents-shared/*`) | 0 | 0 | 7 | — |
| persona-engine/hooks | 6 | 0 | 0 | 35 | 14 |
| getmany/agents | 0 | 0 | **3** (architect, critic, security-auditor: 162/121/71 diff lines vs plugin) | 5 | — |
| getmany/hooks | 1 | 0 | 0 | 4 | 3 |
| respiro-ios/agents | 3 (→ agents-shared) | 0 | 0 | 15 | — |
| respiro-ios/hooks | 1 | 0 | 0 | 5 | 1 |
| m3-market/agents | 3 (→ agents-shared) | 0 | 0 | 19 | — |
| m3-market/hooks | 1 | 0 | 0 | 14 | 0 |

`~/.claude/agents-shared/` itself holds **3 real files, 0 symlinks** (`ls -l | grep -c '^l'` → 0),
differing from `plugins/leadv2/agents/*` by 73/71/46 lines. They are the three entries in
`plugins/leadv2/ref/one-copy-exceptions.txt` (the whole non-comment content of that file). So the
shared agents are a declared fork of the plugin agents; three repos link to the fork, getmany
holds its own third variant.

The 14 unwired persona-engine hooks include `plugin-scripts-drift-guard.sh` (the pre-commit guard
this design needs) and `leadv2-phase8-gate.sh`. UNVERIFIED whether those are dead or invoked by a
dispatcher hook (`leadv2-bash-hook-dispatcher.sh` is in the same dir); a grep of that dispatcher
settles it and is a Stage-0 item below.

Project `settings.json` hooks are 100% project-local paths: pe 38/38, getmany 6/7, respiro 10/13,
m3 22/26 reference `.claude/hooks/...`; **zero** reference `CLAUDE_PLUGIN_ROOT` or the shared tree.

### 1c. Overrides: 64 files, not 53

38 + 7 + 8 + 11 (m3-market) = 64. Reader count = number of files under `plugins/leadv2/{scripts,hooks,skills,workflows,commands}` that mention `leadv2-overrides/<basename>`; the full table is in §4.

### 1d. Guards that exist and where they run

| guard | what it does | wired where |
|---|---|---|
| `hooks/leadv2-one-copy-drift.sh` (SessionStart) | wraps `leadv2-one-copy-convert.sh --check` over `~/.claude/leadv2-shared/scripts` and `~/.claude/agents-shared` only | plugin `hooks.json` — fires every session, reports, never blocks (this session: "149 real files ... NOT healed") |
| `hooks/plugin-scripts-drift-session-warn.sh` (SessionStart) | warns on real plugin-owned files in `<repo>/.claude/scripts` | plugin `hooks.json` |
| `hooks/plugin-scripts-drift-guard.sh` (pre-commit) | blocks committing a real copy of a plugin-owned file | **nowhere**: leadv2 has no pre-commit; pe's `pre-commit.d/` holds `000-legacy-pre-commit 010-board-guard.sh` only; getmany/respiro have none; m3 has no `.git` |
| `scripts/leadv2-drift-guard.sh` | 5-copy parity report, direction decided per file by mtime vs commit time | called from `leadv2-fanout.sh` preflight |
| `scripts/leadv2-plugin-sync.sh` | the only writer; `(c)` project trees via a LINK/CONVERT/DRIFT classifier (`_link_project_scripts`, line 318), `(a)(b)(e)(f)` via rsync | manual, dry-run by default |
| `hooks/leadv2-link-tree-heal.sh` (SessionStart) | adds missing links to the shared tree, never touches existing entries | plugin `hooks.json` |

Running `leadv2-one-copy-convert.sh --check` from this worktree reported `regression=62 badlink=721
expected_override=3 diverged=113`. The 721 "badlinks" are an artefact: the script derives
`CANONICAL_ROOT` from its own location (`"${SCRIPT_DIR}/../../.."`, line 24), so from a worktree it
believes the worktree is canonical and every link to `~/Projects/leadv2/...` looks wrong. That is the
"never count `../` hops" rule in this repo's own guidance biting its own guard, and it is a
Stage-0 fix.

## 2. Q1 — the end state, precisely

**Chosen: C′ — one byte store; per-file symlinks everywhere else; a declared, schema-checked
per-project layer.**

Invariants (each is machine-checkable; the check is in §5):

- I1. `~/Projects/leadv2/plugins/leadv2/` in git is the only place plugin-owned bytes exist.
- I2. For every location L in the perimeter (rows 2, 4, 5a–5d, 6 above; plus `.claude/agents`,
  `.claude/hooks` in each repo; plus `~/.claude/agents-shared`), every path `L/<rel>` whose `<rel>`
  is in canonical git is a symlink whose target realpath is `plugins/leadv2/<kind>/<rel>`, or is
  listed in `one-copy-exceptions.txt` with a rationale line.
- I3. Every real file under `<repo>/.claude/{scripts,agents,hooks}` is either not-in-canonical
  (repo-native) and tracked by that repo's git, or an exception. No third state.
- I4. The per-project layer is exactly `<repo>/.claude/leadv2-overrides/` and the repo-native files
  of I3. Every file under `leadv2-overrides/` is one of the filenames the plugin reads, or lives
  under `scripts/` or `rules/` (the two directories with generic readers, `leadv2-helpers.sh:138`
  and `leadv2-rules-load.sh:50`). Anything else there is dead and fails the check.
- I5. No rsync anywhere in `leadv2-plugin-sync.sh`. Targets (a), (e), (f) are retired; (b) and (c)
  use the link classifier.

Why not A ("every project file is a symlink into `plugins/leadv2/`"): each repo has 20–68 real
files in `.claude/scripts` that are not in canonical (pe 68, m3 60, respiro 41, getmany 20 — the
`real` column with `shadow=0`), 5–19 native agents and 4–35 native hooks. These are deploy scripts,
App-Store pollers, engine probes. A would either sweep them into the plugin (wrong owner) or leave
A false on day one. A is C′ with the per-project layer undeclared, which is how it rotted before.

Why not B ("projects hold nothing; runtime resolves through `~/.claude/plugins/`"): the reference
surface is `<repo>/.claude/...`. Measured: 51 plugin scripts embed `.claude/scripts/<name>`
(`grep -rl '\.claude/scripts' plugins/leadv2/scripts/*.sh | wc -l` → 51) against 16 that use
`CLAUDE_PLUGIN_ROOT`; the top embedded names are `codex-task.sh` (9), `leadv2-daemon.sh`,
`claude-subsession.sh`, `ask-lead.sh`, `codex-guard.sh` — all canonical files reached through the
project tree. Every project `settings.json` hook is a `.claude/hooks/...` path. `tests/run-all.sh`
falls back to `.claude/scripts/tests/run-core-offline.sh`. B needs all of that rewritten to a
resolver before a single copy can be removed, and `~/.claude/plugins/local/leadv2` is already a
symlink to canonical, so B buys no new single-source property that a per-file link farm does not.
A resolver (`_lv2_plugin_script <name>` → `${CLAUDE_PLUGIN_ROOT}/scripts/<name>`) is a good later
refactor; it is not the cleanup.

Directory links vs per-file links: a pure-plugin directory may be a single directory symlink
(persona-engine already has `.claude/leadv2 → plugins/leadv2`; the other three repos lack it,
`readlink` → empty). Mixed directories (`.claude/scripts`, `.claude/agents`, `.claude/hooks`) must
be per-file, because a directory link would hide the repo-native files. The classifier in
`_link_project_scripts` already does per-file.

What happens to row 2 (`~/Projects/leadv2/.claude/scripts`), which the P0 depends on: it becomes a
per-file link farm produced by the same (c) classifier with `--project-root ~/Projects/leadv2`,
and target (f)'s rsync block (lines 996–1021) is deleted. It stays gitignored (links to a path in
the same repo are not source). After that, both branches of `tests/run-all.sh:150-154` resolve to
the same inode, so the P0 fix (`GATE-RUNS-AN-UNTRACKED-HALF-SIZED-CORE-RUNNER-01`) and this end
state agree **iff the P0 fix deletes the fallback branch or leaves it, and does not re-rsync the
copy.** A P0 fix that runs `plugin-sync --write` to refresh the copy would restore the drift
generator. Note what I actually read at `tests/run-all.sh:150-154`: the tracked runner is
preferred and the `.claude/scripts` one is the `else` branch; the P0's claim that line 152 loads
the untracked runner is not what this checkout does unless `ROOT` resolves elsewhere. Not chased.

## 3. Q2 — the boundary, and can a machine decide it

Rule: **plugin-owned ⇔ relative path present in canonical git.**

```
is_plugin_owned() { # <kind: scripts|agents|hooks> <rel>
  git -C ~/Projects/leadv2 ls-files --error-unmatch "plugins/leadv2/$1/$2" >/dev/null 2>&1
}
```

Decision table for a path `<repo>/.claude/<kind>/<rel>`:

| observed | plugin-owned? | verdict |
|---|---|---|
| symlink → `realpath` = canonical `<kind>/<rel>` | yes | OK |
| symlink → anything else | any | BADLINK (fix or exception) |
| real file | yes | REGRESSION unless in exceptions with rationale → the pre-commit guard blocks it, SessionStart reports it |
| real file, tracked in repo git | no | REPO-NATIVE, OK |
| real file, untracked | no | ORPHAN — report; usually a lane's scratch |
| missing, plugin-owned | yes | MISSING (heal by linking; today `link-tree-heal` does this for row 4 only) |

Why set membership and not a name rule: the plugin's own unprefixed names (`ask-lead.sh`,
`codex-task.sh`, `claude-subsession.sh`, `glm-coder.sh`, `lv2`, all confirmed present in canonical
by `[ -e $C/$b ]`) make any prefix rule wrong today, and `cx-tail.sh` / `multi-model.sh` are real
persona-engine files with plugin-shaped names that are **not** canonical. A human adjudicating
names is the rot path; `ls-files` is not.

Name collision going forward: a repo-native file whose name later appears in canonical becomes a
REGRESSION on the next check. Policy: canonical owns the namespace; the repo renames (the
classifier already emits `typeclash`, `leadv2-plugin-sync.sh:321`). This has to be stated in the
doctrine so the collision is not "fixed" by copying.

Overrides boundary: the readable set is enumerable from the plugin —
`grep -rhoE 'leadv2-overrides/[A-Za-z0-9_./-]+' plugins/leadv2/{scripts,hooks,skills,workflows,commands} | sort -u`
gives 22 filenames (state-paths.yaml, stack.yaml, verify.sh, deploy.sh, codex-policy.yaml,
phases.yaml, active-limits.yaml, status-collector-facts.sh, extensions.md, deploy-verify.sh,
toolsets.yaml, session-routing.yaml, supervise-truth-probe.sh, quality-engine.yaml, omp-task.sh,
migrate.sh, frontend-paths.txt, e2e.yaml, direct-spawn-gate.yaml, backlog-pump.yaml,
po-audit-policy.yaml, outcome-watch.sh) plus the two generic dirs `scripts/` and `rules/`. That
list, regenerated by the check itself, is the schema. `leadv2-overrides-drift.sh` already computes
an ORPHAN category against `docs/OVERRIDES.md`; it should compute against this grep instead of a
hand-kept doc.

## 4. Q3 — the 64 override files, one by one

Method: `readers` = count of plugin files mentioning `leadv2-overrides/<basename>`; for
zero-reader files a second grep on the bare basename over the same five plugin dirs (also zero
unless stated). Content judgement only where I read the file; otherwise UNVERIFIED.

### persona-engine (38)

| file | lines | mtime | readers | verdict |
|---|---|---|---|---|
| state-paths.yaml | 47 | 08-01 | 23 | DIFFERS — persona_id, dialogue/queue paths, two VPS host/repo pairs. Live per-repo decision. |
| stack.yaml | 54 | 07-28 | 12 | read via `leadv2-helpers.sh:411+`; content UNVERIFIED vs defaults |
| codex-policy.yaml | 26 | 07-28 | 9 | DIFFERS — full `codex_tier_routing` map, timeouts. Live. |
| deploy.sh, verify.sh, deploy-verify.sh, outcome-watch.sh, omp-task.sh, supervise-truth-probe.sh, status-collector-facts.sh | 68/50/121/444/158/341/510 | 07-28…08-29 | 9/7/2/1/2/1/3 | REPO-NATIVE — invoked, not compared |
| extensions.md | 763 | 09-04 | 4 | DIFFERS, actively edited |
| active-limits.yaml, toolsets.yaml, quality-engine.yaml | 32/21/72 | 07-28 | 5/3/2 | read; content UNVERIFIED vs defaults |
| backlog-pump.yaml | 3 | 07-29 | 1 | DIFFERS — `enabled: 1` with in-file rationale (ST-6 soak; env `LEADV2_BACKLOG_PUMP=0` is the rollback) |
| rules/R-001…R-006 (6 files) | 44–69 | 07-28 | generic | READ via `leadv2-rules-load.sh:50` / `leadv2-rules-eval.sh:83` (`RULES_DIR=.../leadv2-overrides/rules`) — live |
| gemini-policy.yaml | 51 | 07-29 | 0 | UNREAD (bare-name grep also 0) |
| stability-policy.yaml | 57 | 07-28 | 0 | UNREAD |
| gate1.sh | 130 | 07-28 | 0 at runtime | only `leadv2-overrides-drift.sh` and one test name it — UNREAD |
| tests/test-canary-soak-probe.sh, tests/gate1-businesssignal-selftest.sh | 42/126 | 07-28 | 0 | UNREAD |
| tests/rule-fixtures/*.txt (10 files) | 7–13 | 07-28 | 0 | UNREAD by the plugin; may be fixtures for the two unread tests above |
| golden/bandit-sample-seeded.json | 98 | 07-28 | 0 | UNREAD |
| .state/trust-alarm.json | 0 | **09-08** | 0 | runtime state being written into the overrides dir today — misplaced, not an override |

persona-engine tally: 18 read-and-live (incl. 6 rules), 20 unread (of which 1 is live state in
the wrong place).

### respiro-ios (7)

| file | lines | mtime | readers | verdict |
|---|---|---|---|---|
| state-paths.yaml | 9 | 05-12 | 23 | RESTATES — every key `null` (board_file, dialogue_file, queue_dir, leadv2_tasks_dir) |
| codex-policy.yaml | 2 | 05-12 | 9 | `codex_enabled: true` only; default when absent UNVERIFIED (reader is `_lv2_codex_enabled`, `leadv2-helpers.sh:245`) |
| stack.yaml | 55 | 05-12 | 12 | read; content UNVERIFIED |
| deploy.sh, verify.sh, outcome-watch.sh | 135/46/34 | 05-12 | 9/7/1 | REPO-NATIVE |
| extensions.md | 163 | 08-25 | 4 | DIFFERS |

### getmany-followup-bot (8)

| file | lines | mtime | readers | verdict |
|---|---|---|---|---|
| state-paths.yaml | 11 | 05-19 | 23 | RESTATES — comments only, no keys |
| codex-policy.yaml | 12 | 08-28 | 9 | DIFFERS — `codex_model: gpt-5.5`, `codex_review_rounds_max: 2`, `codex_planner_max_findings: 5` |
| stack.yaml | 14 | 05-19 | 12 | read; UNVERIFIED |
| deploy.sh, verify.sh, outcome-watch.sh | 226/33/38 | 09-07/05-19/05-19 | 9/7/1 | REPO-NATIVE (deploy.sh edited yesterday) |
| extensions.md | 171 | 09-03 | 4 | DIFFERS |
| archive/leadv2.md.fork-2026-08-12 | 492 | 08-12 | 0 | UNREAD |

### m3-market (11)

| file | lines | mtime | readers | verdict |
|---|---|---|---|---|
| state-paths.yaml | 9 | 05-30 | 23 | DIFFERS in one key: `leadv2_tasks_dir: .claude/leadv2-tasks`; rest null |
| codex-policy.yaml | 13 | 06-22 | 9 | DIFFERS with **recovered rationale**: `codex_enabled: true` overriding a prior ban; `leadv2-codex-planner.sh:5` still says "m3-market must set codex_enabled: false" — the plugin comment is the stale side |
| stack.yaml | 72 | 05-29 | 12 | read; UNVERIFIED |
| frontend-paths.txt | 4 | 05-21 | 2 | read |
| deploy.sh, verify.sh, outcome-watch.sh | 80/79/55 | 05-12…05-29 | 9/7/1 | REPO-NATIVE |
| extensions.md | 622 | 08-21 | 4 | DIFFERS |
| gemini-policy.yaml | 78 | 05-23 | 0 | UNREAD |
| mission-templates.md | 75 | 08-21 | 0 | UNREAD |
| archive/leadv2.md.fork-2026-08-17 | 347 | 08-17 | 0 | UNREAD |

### Cross-repo identity

`cmp` of every same-named override across the four repos: **no two are byte-identical**
(codex-policy, deploy.sh, extensions.md, outcome-watch.sh, stack.yaml, state-paths.yaml,
verify.sh: 0 identical, 3 differ each; gemini-policy 0/1). So none is a stale copy of another
repo's file; the yaml ones are genuinely per-repo.

### Verdict on the hypothesis

| | read & carries a decision | read but restates default | repo-native script | unread |
|---|---|---|---|---|
| count / 64 | ≥11 (state-paths pe/m3, codex-policy pe/getmany/m3, backlog-pump, 6 rules, 4 extensions.md) | 2 (state-paths respiro, getmany) | 19 | 24 |
| stack/active-limits/toolsets/quality-engine/frontend-paths | 8 files UNVERIFIED — need a reader-default diff each | | | |

24/64 are dead weight and can go after one `git log` each for rationale (pe: gemini-policy,
stability-policy, gate1.sh, 2 tests, 10 fixtures, golden, `.state/`; m3: gemini-policy,
mission-templates, archive; getmany: archive). The founder's "all stale" is false for the core
set: `deploy.sh`/`verify.sh` are the deploy contract, `extensions.md` is edited weekly,
`codex-policy.yaml` in m3 records a founder decision the plugin comment has not caught up with.
The right move is to shrink the layer to the 22-name schema and make the check reject anything
outside it, not to delete the layer.

## 5. Q4 — how the invariant holds afterwards

Prose failed because the three checks that exist each cover a different perimeter and the only
blocking one is unwired. The design makes one perimeter, one classifier, three run points.

**One perimeter file.** `plugins/leadv2/ref/one-copy-perimeter.txt`: rows 2, 4, 5a–5d, 6 of §1a
plus `<repo>/.claude/{agents,hooks}` and `~/.claude/agents-shared`, one root per line as
`<kind>|<root>`. Repos come from `cross-repo-paths.yaml` **plus getmany, which must be added**
(shared-tree edit; founder authorization required per the user CLAUDE.md, so it is a listed
LEAD_ACTION, not something a lane does).

**One classifier.** `_link_project_scripts` in `leadv2-plugin-sync.sh` already emits
LINK/CONVERT/OK/DRIFT/BADLINK/DANGLING/TYPECLASH/EXCEPTION per file with an exceptions file shared
with `leadv2-one-copy-convert.sh` (D3, line 134). Extend it to take `<kind>` (scripts/agents/hooks)
and use `git ls-files` for ownership instead of "exists under `${PLUGIN_ROOT}/<kind>`" (a working
tree can hold an uncommitted file; git membership is the invariant). Fix `CANONICAL_ROOT`
derivation in both scripts to `git -C "$SCRIPT_DIR" rev-parse --show-toplevel` with the worktree
case handled (`git rev-parse --git-common-dir` → main checkout), so a worktree run does not
manufacture 721 badlinks.

**Three run points.**

| where | mode | blocks? | cost |
|---|---|---|---|
| pre-commit in leadv2, persona-engine, getmany, respiro (m3 has no git; SessionStart only) | `plugin-scripts-drift-guard.sh` over staged paths | yes — a staged real file whose path is plugin-owned refuses the commit with the `ln -sf` remedy | one `git diff --cached --name-only` + one `ls-files` per staged `.claude/*` path; milliseconds on a normal edit, zero on edits outside `.claude/` |
| SessionStart (already in `hooks.json`) | `--check` over the whole perimeter, fail-loud line per REGRESSION/BADLINK/ORPHAN, plus heal MISSING by linking (what `link-tree-heal` does for row 4 today) | no (SessionStart must not gate) | a `readlink`/`ls-files` loop over ~2,500 entries; UNVERIFIED wall time — measure with `time leadv2-one-copy-convert.sh --check`; if over ~1s, cache by directory mtime |
| `tests/` in this repo | `test-one-copy-drift.sh` (fixture-based, exists) extended with the project-tree kinds and an ownership-by-git case | yes, in the gate | one suite |

**Cost on a normal edit** is zero by construction: editing `plugins/leadv2/scripts/x.sh` changes
the inode every link points at; there is no sync step, so there is no step to forget. The cost
moves to the moment somebody tries to create a copy, which is exactly the moment a check is worth
paying for.

**Remove the drift generators, do not just detect them.** Delete targets (a), (e), (f) from
`leadv2-plugin-sync.sh`; convert (b) to the link classifier; retire `leadv2-link-tree-heal.sh`
into the SessionStart check (it becomes the MISSING-heal branch). After that the drift guard's
"five copies" become "one store + N link farms", and the mtime-based `decide_direction()` logic —
which exists only because copies can be newer than canonical — has nothing to decide.

**Doctrine text to change** (prose, but now backed by the check): the user CLAUDE.md "Shared
trees" section should name the perimeter file, add getmany, drop "m3-market does not exist",
and state the name-collision policy from §3.

## 6. Q5 — order, quiet conditions, one-command rollback

Quiet condition Q for a root R: no live lane has R as its repo (`leadv2-active-registry.sh` for
that repo shows no active entries) and no `claude`/SwiftBar process has a cwd under R
(`lsof +D R -Fn | grep -c cwd` → 0). Every conversion below makes a pre-image first:
`tar czf ~/.claude/leadv2-one-copy-backups/<stage>-$(date +%s).tgz -C <root> .` — one command,
and its inverse (`tar xzf ... -C <root>`) is the rollback for every stage that touches files.
`leadv2-one-copy-convert.sh` already keeps a manifest-based `--revert`; the tar is the belt to its
braces.

Right now: 199 lane worktrees are registered in leadv2 (`git worktree list | grep -c worktrees/`),
17 in persona-engine, 7 in getmany, 1 in respiro. Registered is not live; the registry decides.

| stage | change | precondition | proof | rollback |
|---|---|---|---|---|
| 0 | Code only, no tree touched: fix `CANONICAL_ROOT` derivation (both scripts); add `<kind>` + `ls-files` ownership to the classifier; add perimeter file; extend `test-one-copy-drift.sh`; wire `--check` as report-only over the full perimeter; grep pe's `leadv2-bash-hook-dispatcher.sh` to settle the 14 "unwired" hooks | none | suite green; SessionStart report lists the numbers in §1a from inside the check | `git revert <sha>` |
| 1 | Row 2: `~/Projects/leadv2/.claude/scripts` → per-file links via `leadv2-plugin-sync.sh --write --project-root ~/Projects/leadv2` (classifier mode), then delete the (f) rsync block | Q(leadv2). Also settle UNVERIFIED: how a lane worktree resolves `.claude/scripts` (this worktree's own `.claude/scripts` holds 1 real file, 0 links, and is gitignored) — probe: from a worktree run `bash -x plugins/leadv2/scripts/leadv2-ask.sh --help 2>&1 \| grep claude/scripts` | `find ~/Projects/leadv2/.claude/scripts -type f -not -path '*/__pycache__/*'` lists only `leadv2-wiki-index.sh`; `tests/run-all.sh` both branches `realpath` to the same file | `tar xzf` pre-image, or `rsync -a plugins/leadv2/scripts/ .claude/scripts/` (content was canonical-derived anyway) |
| 2 | Row 4: `~/.claude/leadv2-shared/scripts` via `leadv2-one-copy-convert.sh --apply` (exists, has `--revert`). First move `node_modules/` (171 files) and `leadv2-wiki-index.sh` out or declare them; delete the stale "196 repo-owned files" comment in `link-tree-heal` | `precondition_ok` (LIVENESS-SELF-DESTRUCT-01 closed — the script refuses otherwise; status UNVERIFIED, the script's own exit code settles it); Q for every repo, since all repos' `.claude/leadv2` may resolve here | `--check` → `regression=0 diverged=0` | `leadv2-one-copy-convert.sh --revert` |
| 3 | Row 6 `~/.claude/scripts/leadv2-*` (101 real, 13 drifted) → links; delete target (e). `~/.claude/agents-shared` (3 real) → **decision needed**: fold the 73/71/46-line diffs into `plugins/leadv2/agents/*` and link, or keep as declared exception with a rationale line. Recover rationale with `git -C ~/Projects/leadv2 log -S<distinctive line> -- plugins/leadv2/agents/critic.md` and a diff read | Q(all) | `--check` clean for both roots | tar pre-image |
| 4 | respiro tracked shadow `.claude/scripts/codex-guard.sh` (401 diff lines; respiro commits 2026-07-14 and 07-21 "sync vendored scripts") → diff against canonical, upstream anything newer, replace with link, commit in respiro. getmany's 3 real agent files → same treatment as stage 3's decision | Q(respiro), Q(getmany) | respiro/getmany `shadow=0` in the §1a loop | `git -C ~/Projects/respiro-ios revert <sha>` |
| 5 | Overrides: delete the 24 UNREAD files after one `git log -1 --format=%s -- <file>` each in the owning repo; move `.state/trust-alarm.json`'s writer to `docs/leadv2/` or `.claude/cache/` (find the writer: `grep -rl trust-alarm plugins/leadv2` — UNVERIFIED, 0 hits in the plugin dirs, so the writer is a repo-local hook); resolve the 8 UNVERIFIED yaml files by diffing each against its reader's default; extend `leadv2-overrides-drift.sh` to compute ORPHAN against the 22-name grep | none (files nobody reads) | `leadv2-overrides-drift.sh` → 0 ORPHAN in all four repos | `git -C <repo> revert <sha>` |
| 6 | Wire `plugin-scripts-drift-guard.sh` as pre-commit in leadv2, pe (`pre-commit.d/020-plugin-scripts-drift-guard`), getmany, respiro; add getmany to `cross-repo-paths.yaml` (LEAD_ACTION: shared-tree edit, founder authorization) | stage 0 landed | `git commit` of a deliberately copied plugin file is refused in each repo, then the copy is removed | delete the hook file |
| 7 | Retire `leadv2-drift-guard.sh`'s 5-copy model and `decide_direction()`; delete plugin cache dirs under `~/.claude/plugins/cache/leadv2-local/` (inert — but confirm with `lsof` first, and UNVERIFIED whether Claude Code re-creates them on plugin reload) | stages 1–3 done | fanout preflight uses the `--check`; suite green | `git revert`; cache dirs are regenerable |
| 8 | Doctrine: user CLAUDE.md shared-trees section (perimeter file, getmany, m3 path, collision policy); plugin comment at `leadv2-codex-planner.sh:5` about m3 | none | text | revert |

Stages 1–4 each leave the tree strictly more link-shaped and are individually revertible; none
changes bytes that any running lane reads, because the link target is the file the copy was a
stale version of. The one behavioural risk is a lane that was relying on a **drifted** copy (338
in row 2, 113 in row 4) being newer than canonical — `leadv2-drift-guard.sh` measured that
direction as real on 2026-07-27 ("4/5 copies were 1–10 days NEWER than canonical"). So before
stages 1 and 2, run `leadv2-drift-guard.sh` and promote every `VENDORED_NEWER` entry into
canonical first; converting a newer copy into a link to an older canonical is the only way this
plan can lose work, and the guard already names those files.

## 7. What I deliberately left alone

- The P0 gate defect: referenced in §2; not fixed, not re-measured beyond reading
  `tests/run-all.sh:25-36,86,150-154`.
- No file outside this report was created, modified, linked or deleted. `--check` was run
  (read-only) once; `--apply` never.
- `~/.claude/leadv2-shared/`, `~/.claude/agents-shared/`, `cross-repo-paths.yaml`: read only.
- The other design arm: not read, not reasoned about.

## 8. UNVERIFIED items and what settles each

1. Lead's leadv2 row (386/265): perimeter unknown — re-run the §1a loop on the lead's side.
2. How getmany's 318 links were created (not in cross-repo yaml) — shell history or a
   `--project-root` mention in getmany's docs.
3. Default for `codex_enabled` when `codex-policy.yaml` is absent — read `_lv2_codex_enabled` in
   `leadv2-helpers.sh` around line 245.
4. Whether the 8 read yaml overrides (stack ×4, active-limits, toolsets, quality-engine,
   frontend-paths) restate their reader defaults — one reader-default diff each.
5. Whether pe's 14 hooks absent from `settings.json` are invoked through
   `leadv2-bash-hook-dispatcher.sh` — grep that file.
6. How a lane worktree resolves `<repo>/.claude/scripts/<name>` when its own `.claude/scripts` is
   near-empty — `bash -x` one script from a worktree.
7. Wall time of a full-perimeter `--check` — `time` it after stage 0.
8. LIVENESS-SELF-DESTRUCT-01 status — `leadv2-one-copy-convert.sh --apply` exits 1 with
   "REFUSING" if still open.
9. Writer of `persona-engine/.claude/leadv2-overrides/.state/trust-alarm.json` — 0 hits in plugin
   dirs; grep persona-engine's own hooks.
10. Whether Claude Code regenerates `~/.claude/plugins/cache/leadv2-local/` on reload.
