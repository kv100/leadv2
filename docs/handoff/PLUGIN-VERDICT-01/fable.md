# PLUGIN-VERDICT-01 — independent opinion (fable, systems angle)

Date: 2026-09-02. Repo measured: `/Users/kostiantyn.vlasenko/Projects/leadv2` (HEAD 2026-09-02, 1480 commits since 2026-05-15).
Not read: `CONTROL-PLANE-HAS-NO-OWNER-01/brief.md`, `architect.md`, `critic.md`, `codex.md`.
Every number below carries the command that produced it. Where a number is a proxy, the proxy is named. Ranges where unsure.

## 0. What kind of system this is

The plugin is a **control plane for non-deterministic workers, implemented as a distributed system whose only shared memory is the filesystem, with no process that owns that memory.**

- 152 distinct state-file basenames are referenced by scripts/hooks; 490 distinct state-path literals overall
  (`grep -ohE '(docs/leadv2|docs/handoff|\.claude/leadv2|…)[…]' scripts/*.sh lib/*.sh hooks/*.sh | sort -u | wc -l`).
- `docs/leadv2/active.yaml` is read by 87 scripts and written by 28 of them (`grep -l 'active.yaml'` → 87; write-shaped grep → 28).
- 870 distinct `LEADV2_*` knobs (`grep -ohE 'LEADV2_[A-Z0-9_]+' scripts hooks workflows | sort -u | wc -l`).
- Zero hooks write a fire-log (`grep -lE 'hook-fires|hooks\.log|…' hooks/*.sh | wc -l` → 0): the system has no record of what its own guards did.

Every worker failure mode produces a new *observer* (hook/guard/watch/census) that infers truth from mtimes, pids and yaml rows. Observers disagree (false-zero, lying-green — the founder's own vocabulary), so new observers are added to adjudicate the old ones (`GUARD-CENSUS-IS-WRONG-01`, `CACHE-TRUTH-01`, `CAPABILITY-TRUTH-AUDIT-01`, `STALE-ROW-STARTING-GRACE-01`, all in the last 10 days of `git log`). That is the signature of a system compensating for unreliability by adding state, and state is exactly what it cannot keep consistent.

**Is the failure mode intrinsic?** Half. Orchestrating unreliable agents *does* intrinsically require liveness, verdicts, retries and a cap. It does **not** require 6 parallel stores for one lane's state ("re-dispatch needs 4 stores cleared" is a memory entry, i.e. a known invariant nobody can enforce), 870 knobs, or 70 hooks that infer state from a shell transcript. The intrinsic part fits in ~1 table and ~1 state machine. The rest is accidental.

## 1. Machinery growth vs failure removal — the two curves

Method:
- scripts added: `git log --diff-filter=A --name-only --format='%ad' --date=format:%Y-%m -- '*.sh' | awk …`
- scripts deleted: same with `--diff-filter=D`
- net LOC: `git log --numstat --format='COMMIT %ad' -- '*.sh' '*.js' ':!*/node_modules/*' | awk …`
- code-fix commits: commits touching `plugins/leadv2/{scripts/*.sh,scripts/lib,hooks}` whose subject matches `fix|guard|stale|false|drift|race|dedup|lying|broken|regress` (case-insensitive) — a keyword proxy, over-inclusive on "guard"/"gate", under-inclusive on unlabeled fixes.

| Month | .sh added | .sh deleted | net LOC (+) | code commits | code-fix commits | fix share | fixes per added KLOC |
|---|---|---|---|---|---|---|---|
| 2026-05 | 135 | 0 | +22.4K | 19 | 14 | 74% | 0.6 |
| 2026-06 | 67 | 7 | +13.1K | 54 | 37 | 69% | 2.8 |
| 2026-07 | 189 | 0 | +56.6K | 173 | 109 | 63% | 1.9 |
| 2026-08 | 343 | 21 | +106.7K | 486 | 334 | 69% | 3.1 |
| 2026-09 (2 days) | 78 | 1 | +13.1K | 73 | 27 | 37% | 2.1 |

Reading:
- May→Aug: machinery ×4.8 (LOC), fixes ×24 (code-fix commits). **Fixes per added KLOC rose 0.6 → 3.1 (5×).** Each kilo-line added now needs five times more fixing than it did in May. That is divergence, not convergence.
- Deletion is ~3.5% of addition (29 deleted vs 812 added). Nothing is retired; the surface is monotone.
- Fix share of code commits is flat at 63–74% for four months. Four months of "this time it stabilises" with a flat ratio is the measurement the founder is asking for: **the fixes are not converging on stability, they are the steady state.**
- The single file `leadv2-dispatch-code.sh`: 0 lines on 2026-07-01 → 2,237 on 08-01 → 8,405 now; 171 commits; 51 commits in ISO week 35 alone, 24–27 per week for the four weeks before (`git log --format='%ad' --date=format:%Y-%V --name-only | awk …`). A file that changes 51 times in a week has no contract; it *is* the failure curve.
- Fix-round depth: 12 task ids carry `fix-round-N` in subjects; 5 reached round ≥4, max round 8 (`FABLE-THINK-TIER-01`). A "round cap" that yields "judge FIX-ROUND after round cap" (verbatim subject) is a cap that isn't one.

Share of LOC that exists only to compensate for worker unreliability (filename proxy: `guard|watch|liveness|stale|recover|dedup|ledger|registry|gate|verdict|truth|census|audit|drift|orphan|freeze|receipt|reinject|lock|beat|pulse|status|budget|quota|cap|idle|dead|zombie|rescue|…`):
**31,421 of 111,988 LOC = 28% by file; 112 of 318 top-level scripts+hooks = 35% by count; inside dispatch-code.sh 49 of 160 functions = 31%.** Range 25–40% (the proxy misses guard code inside non-guard-named files and counts some legitimately-named status code).

## 2. The system designed once, today (≤400 words)

**One daemon, one store, thin edges.**

- `leadv2d` — one long-running Python process per machine (asyncio). It *launches* every worker (`claude -p`, `codex exec`, GLM) as a child process, so liveness is a process handle, never an mtime, a pid in yaml, or a symlink target. Backpressure = a semaphore per provider; cancellation = kill the child; WIP = an integer.
- One SQLite file (WAL). Tables: `tasks`, `lanes`, `attempts`, `events` (append-only), `verdicts`, `questions`. Every state the plugin has today (active.yaml, registry, receipt, lock, pid, session-id, journal, ledger, scorecard, watches, e2e-gate) becomes a row or an event. One writer. `SELECT` replaces 87 readers parsing yaml with sed.
- Review/close is a state machine in code: `dispatched → produced → reviewed(round n) → landed | blocked`, with a hard round cap enforced by the transition table, not by a hook that nudges.
- Policy is one declarative file with a JSON schema, validated at startup; ≤40 knobs. Routing/quota/ladder are data, not 870 env vars.
- Claude Code edges: one `/leadv2` command, one MCP (or CLI) `leadv2 status|dispatch|answer|close`, **≤5 hooks** (pre-Bash guard, pre-compact checkpoint, session-start inject, subagent-stop verify, worktree scope). Prompts = ~8 role templates rendered by the daemon into missions; no Skill tool dependency.
- Cross-repo: `pipx install leadv2`; each repo holds one `leadv2.toml`. No symlink farm, no plugin-cache copy, no "one inode is three views".
- Tests: pytest against the daemon with fake workers; the mutation catalog targets the state machine; CI selects by module.

Size: ~8–12K Python. Provider runners (`glm-coder.sh`, `codex-task.sh`, `freepool-coder.sh`, ~6K bash) stay as subprocesses behind a stdin/stdout JSON contract in phase 1.

**Distance from the current tree:** the current tree is ~112K LOC bash + 2K JS + 9.5K Python, 870 knobs, 152 state files, 94 hook files, 41 skills, replicated into 4 repos by ~250 symlinks each plus 14–56 real copies per repo (`find <repo>/.claude/scripts -maxdepth 1 -type l | wc -l`). Not bridgeable by in-place refactoring: every one of the 245 scripts assumes *files are the state*, so a refactor that keeps them running keeps the contract that produces the defects. It **is** bridgeable by strangling: the daemon takes over one store at a time (lanes first), scripts become clients (`leadv2 state get …`), and each script is deleted when its last reader moves.

## 3. Which skills and hooks have ever changed an outcome

Corpus: every `*.jsonl` under `~/.claude/projects/` for persona-engine, leadv2, getmany-followup-bot (1,200 files incl. subagent transcripts; oldest 2026-08-23 — a 10-day window, older transcripts are gone). respiro-ios / m3-market dirs absent locally.

**Hooks** (70 registered in `hooks.json`; 93 files on disk):
- Files on disk but **not registered**: 24 (26%) — `comm -23 <(ls hooks/*.sh) <(grep -oE '\S+\.sh' hooks.json)`. Dead by construction; they still cost reading and drift.
- Registered but **missing on disk**: 1 (`leadv2-lane-watch-v2.sh`) — a guard the config claims and the filesystem cannot run.
- Registered hooks with a visible outcome in 10 days (a `hook error: […/x.sh]` block or a `[leadv2-x]` tag in any transcript): **11 of 70** by strict name match; **≤20 of 70** allowing tag/filename mismatches (e.g. `[leadv2-loop-detect]` is emitted by `leadv2-loop-detect-hook.sh`). **Ratio: 16–29% ever seen acting; 71–84% never seen.** 59 registered hooks produced zero blocks and zero tags (`leadv2-active-cache … leadv2-worktree-enforce, post-compact-reground`). Caveat: silent SessionStart/additionalContext injectors leave no tag; some of the 59 are those. Discount them and the "never seen" set is still ≥40 of 70.
- The hooks that *do* fire, fire absurdly often: `[leadv2-lead-delegation-nudge]` 11,920 times, `[leadv2-loop-detect]` 9,302 times in 10 days (`grep -oE '\[leadv2-[a-z-]+\]' | sort | uniq -c`). ~2,100 injected hook messages per day. A nudge that fires 1,200 times a day is not changing behaviour; it is context tax. Real blockers with measured effect: `leadv2-verdict-format-guard` 562 blocks, `leadv2-bash-pre-dispatch` 440 (it blocked this author's own heredoc), `guard-worktree-scope` 170 (it blocked this author's first Write of this file), `open-threads-shrink-guard` 14.
- The plugin's own repo has no `.claude/hooks` (`ls leadv2/.claude/hooks | wc -l` → 0): the guards protect consumers, not the code that ships them.

**Skills** (41 on disk):
- Chosen via the Skill tool, ever, in the corpus: **15 invocations total**, of which leadv2 skills = `leadv2-judge` (5), `leadv2-founder-question-router` (2), `leadv2-plan` (1). Auto-injected at spawn: `leadv2-subagent-protocol` (311). **4 of 41 skills have any runtime presence (10%); 37 (90%) none.** Method: `find … -name '*.jsonl' -exec grep -ohE '"name":"Skill","input":\{"skill":"[^"]+"|<command-name>[^<]+</command-name>' {} +`.
- Static references (skill name mentioned in `commands/scripts/hooks/workflows`): 8 skills have 0 refs, 12 have ≤2. High static counts (`leadv2-review` 50, `leadv2-plan` 30) are scripts `cat`-ing SKILL.md into prompts — they are prompt fragments wearing a skill costume, not skills.
- Workflows: 8 JS files, 4 referenced from anywhere (`grep -rl 'workflows/' scripts hooks commands | wc -l`).

An unused mechanism is not neutral: 24 unregistered hooks + 59 silent hooks + 37 unchosen skills = ~120 artifacts that are read by agents, appear in censuses as "protected", and drift. `CAPABILITY-TRUTH-AUDIT-01` (commit subject: "guards are wired in 1 repo of 4") is what that drift looks like when someone finally measures it.

## 4. Explicit answers

### Q1. What drives the recurring-defect rate?

Method: 779 fix-shaped subjects (`git log --format='%s' | grep -iE 'fix|guard|stale|false|drift|race|dedup|lying|broken|regress'`), keyword buckets, **overlapping** (one subject can hit several), so percentages sum >100. Second-pass exclusive reading of the 25 most recent subjects by hand to sanity-check.

| Driver | Regex bucket | Hits / 779 | Share | Hand-read estimate |
|---|---|---|---|---|
| LANGUAGE (bash) | quoting, IFS, set -e/-u, subshell, heredoc, bash3/assoc, BSD vs GNU, `$$`, eval | 45 | 6% | 5–10% |
| ARCHITECTURE (state ownership / contracts) | stale, active.yaml, registry, lock, pid, receipt, marker, session-id, worktree, prune, ledger, journal, liveness, mtime, dedup, orphan, truth, lying, false-zero/green, drift | 267 | 34% | 35–45% |
| SURFACE SIZE / sync | sync, symlink, cache, plugin update, propagate, copy, missing file, per-repo, override | 142 | 18% | 15–20% |
| PROCESS (rounds, dispatch, review) | dispatch, round, review, gate, verdict, resume, respawn, retry, routing, quota, lane, fanout, supervise, close, phase, mission, budget | 590 | 76% (regex too broad — catches the task vocabulary itself) | 25–35% |

Bottom line: **architecture ≈ 40%, process ≈ 30%, surface/sync ≈ 18%, language ≈ 6–8%** (residual/unclear ~5%). Confirming evidence for "not language": the root of the plugin repo contains tracked junk `a.txt b.txt c.txt report.md M8-RESULT.md` and untracked files literally named `echo "=== WRITERS of .supervise-active`, `for f in test-fg-dispatch-guard.sh …`, `grep -nE 'DEPTH|…'` (`ls`) — agents mis-redirecting shell into filenames. That *is* a bash-language wound, and it is a rounding error next to the state-ownership wounds.

### Q2. Rewrite in Python?

**Yes — but as a kernel rewrite that changes state ownership, not a translation.** A line-for-line port of the same architecture would reproduce ~90% of the defects (language is ≤10%). The reason to rewrite is that the only way to give state one owner is to have one process, and one process in bash is not a thing this team can maintain (dispatch-code.sh is the attempt; it is 8,405 lines).

Migration surface, counted:

| Surface | Today | After | How counted |
|---|---|---|---|
| Kernel scripts (dispatch, close, status, helpers, registry, subsession, review-run, phase8-close) | ~25–30K LOC bash (`wc -l` top-8: 8405+3353+3291+2603+…) | 6–10K Python | rewrite |
| Provider runners (`glm-coder.sh`, `codex-task.sh`, `freepool-coder.sh`) | ~6.2K bash | keep, behind JSON stdin/stdout contract | phase 1 unchanged |
| State stores | 152 basenames, 490 path literals | 6 tables | schema, not migration — old files become read-only during strangle |
| Knobs | 870 `LEADV2_*` | ≤40 in one schema-validated file | deletion, with a `leadv2 config-diff` listing unread ones |
| Hooks | 94 files / 70 registered | ≤5 | deletion |
| Skills | 41 | ~8 prompt templates | deletion + move |
| Workflows (JS) | 8 (4 referenced) | 0 (daemon jobs) | deletion |
| Offline tests | 315 in `scripts/tests` (8 touch a real provider) | pytest on daemon + fake workers | **do not port** — they test bash internals that will not exist |
| Consumers | 4 repos × ~250 symlinks + 14–56 real copies | `pipx install` + one toml each | deletion |
| `docs/handoff` | 273 MB, 973 dirs, 2,104 tracked files (`du -sh; ls | wc -l; git ls-files | wc -l`) | out of git, into `events` + an archive dir | deletion |

Cost estimate (range): 3–5 weeks of lanes if scoped to the kernel with runners kept; 8–12 weeks if the runners and review engine are rewritten too. The first 2 weeks produce nothing visible — that is the founder decision to make explicitly, because the alternative ("these fixes will bring stability") has a four-month flat fix-share curve against it.

**If NO (fix in place) — build order:**
1. Freeze: no new hook, script, skill, or `LEADV2_*` knob for 30 days; every fix must delete ≥ as many lines as it adds (enforced by one pre-commit check on the plugin repo, which today has zero hooks).
2. One lane-state owner (see Q4).
3. Delete the unregistered/silent/unchosen set (§3) and `supervise`/`fanout` (retired by founder order 2026-08-17, still 29+30 commits of churn).
4. Fold the 4 consumer symlink farms into a single install step; delete real copies.
5. Only then: split dispatch-code.sh by state-machine phase.

### Q3. What must be DELETED — the largest thing

**`plugins/leadv2/scripts/leadv2-dispatch-code.sh` (8,405 lines).** Defence:
- 171 commits, 145 of them in August, 51 in one ISO week — the highest churn in the repo by 2.3× over #2 (`git log --name-only --format='' | sort | uniq -c | sort -rn | head`).
- 160 functions, 49 (31%) are guard/watch/retry/liveness/fallback; 123 distinct `LEADV2_*` knobs read by one file; 19 distinct `claude -p`/subsession invocation sites.
- It is queue + lock + liveness + routing + quota + review handoff + close in one process image that lives only as long as one bash invocation; every state it manages must therefore be re-read from files by the next invocation — which is the root defect class (34–45%).
- It cannot be tested except by the 315-file offline harness whose own runner (`run-core-offline.sh`) is #3 in churn (65 commits, 22 in one week). When the test runner churns like the code under test, the tests are measuring the runner.
Deleting it means replacing it with the daemon's `dispatch` state machine; until then, freezing it is the minimum.

Next in line, in order: 24 unregistered hook files; ~40–59 silent registered hooks (verify each against a fire-log for one week first — add the fire-log, it is 3 lines); 37 unchosen skills; `leadv2-supervise.sh` + `leadv2-fanout.sh` (retired); `docs/handoff` from git history going forward; the 4 workflows nobody references.

### Q4. Single highest defect-prevention per unit of work

**Give lane state one owner: a single `lanes` store (SQLite, one writer) behind one CLI `leadv2-state {get|set|claim|heartbeat|close} <task-id>`; make `active.yaml`, the registry, receipts, locks, pids and session-ids read-only views generated from it.**
- Targets the 34–45% bucket directly and structurally removes the "4 stores cleared" class, the "recovered row pins watcher pid" class, and the "pulse reports false zero when lanes live in another repo" class (all last-10-day subjects).
- Work: ~1 week — 87 readers become `leadv2-state get`, 28 writers become `leadv2-state set`; the 59 silent hooks that read these files can be pointed at the CLI or deleted.
- It is also step 1 of the strangle, so it is not wasted if the rewrite is approved.
Runner-up with lower work (1 day) and lower yield: a hook fire-log — it turns §3 from an estimate into a deletion list.

### Q5. What measurement would change the answer to Q1?

1. **A hand-read, exclusive-attribution sample.** Take 100 random code-fix commits (`git log --format=%H -- plugins/leadv2/scripts plugins/leadv2/hooks | <fix filter> | shuf -n 100`), read each diff, assign exactly one root cause. If LANGUAGE (quoting/word-splitting/`set -e`/bash-3 portability/BSD-vs-GNU) exceeds 25%, raise language to co-driver and a plain port becomes worth doing. My keyword proxy found 6%; hand reading could plausibly double it, not quadruple it.
2. **A controlled port.** Port the top-3 churn files to Python behind byte-identical file contracts (same yaml/lock/receipt semantics). If their code-fix rate drops >50% in the following month, language was the driver; if it stays within ±20%, architecture is confirmed. I expect the second.
3. **A hook fire-log for one week.** If the 59 "silent" hooks turn out to prevent incidents that never became commits, the deletion list in Q3 shrinks and the "surface size" share rises (the surface would be doing work, just invisibly).

## 5. Contradiction scan (self-check)

- Numbers derived twice where a false zero was possible: skill usage measured three ways (top-level-only pass → 2 chosen; `cat`-concatenation pass failed on `-`-prefixed filenames and reported 0 — discarded; `find -exec grep` pass → 15 chosen, 311 injected) — the last is the one reported.
- Hook "never seen" list is a lower bound on usefulness and an upper bound on deadness (silent injectors); stated as a range.
- Fix-shaped commit counts include `docs(handoff): … fix-round-N` commits (92 docs-only of 779); code-fix figures exclude them.
- Transcript window is 10 days; skill/hook ratios are per that window, not lifetime.
- No env vars, paths, or commands proposed here modify any repo; nothing was committed.

## Out of scope for implementers
Reading the other three opinions; touching runtime prompt files; any `ALTER` to consumer repos; provider-runner rewrite in phase 1.

DELIVERABLE_COMPLETE
