# Do the leadv2 hooks and guards earn their keep? — measured 2026-09-02

Method: read BOTH wiring surfaces — `plugins/leadv2/hooks/hooks.json` (86 entries) and the
`MANIFEST` inside `leadv2-bash-pre-dispatch.sh` (12 sub-guards, Bash matcher only) — against the
93 `.sh` files on disk. Fire counts from a 10-day transcript window (2026-08-23 → 2026-09-02,
3,631 `.jsonl`, 1.4 GB, all repos), anchored on `"stderr":"[leadv2-<hook>]` at field start rather
than a substring grep, because several hooks contain their own bracketed tag as a literal, so any
transcript that merely READ the hook source would count as a fire.

## 1. Does it fire?

**True orphans (wired in neither surface): 12, not the 24 previously claimed.** The earlier census
counted the 12 MANIFEST-only sub-guards as unwired because it read only `hooks.json`.

Dead entrypoints, each superseded elsewhere:
`leadv2-block-codex.sh` (mirrored into `codex-first-nudge`), `leadv2-compact-trigger.sh`,
`leadv2-force-read-limit.sh` / `leadv2-read-dedup-hard.sh` / `leadv2-lead-read-guard.sh` (all three
inlined as SECTION 1/2/3 inside `leadv2-read-gate.sh:38,80,140`), `leadv2-hardbans-reinject.sh`,
`leadv2-hook-fork-budget.sh` (only caller is its own test), `leadv2-idle-guard-arm.sh` and
`leadv2-idle-lead-guard.sh` (explicitly retired by `lane-watch-v2.sh:24,287,394`),
`pre-compact-task-freeze.sh` (unwired, yet its header still claims to be the live fix for a
documented incident: 136/139 and 191/191 task ids lost across 27 compacts — that mission is not
running).

**Wired-but-missing-from-disk: 0**, not 1. `lane-watch-v2.sh` lives in `scripts/`, not `hooks/`.

**`leadv2-mode-isolation.sh` is NOT an orphan** — it is a shared library `source`d by five live
hooks. Sitting undistinguishable among 92 entrypoints in one flat directory is what produced two
separate false censuses, mine included.

Real fires, 10 days (higher than the earlier 11,920 / 9,302 because that was one session, this is
the whole corpus):

| hook | /10d | /day |
|---|---|---|
| lead-delegation-nudge | 38,724 | ~3,872 |
| loop-detect | 19,894 | ~1,989 |
| merged-worktree-sweep | 1,687 | ~169 |
| task-budget-tracker | 400 | 40 |
| taskoutput-ban | 304 | 30 |
| stale-pid-sweep | 281 | 28 |
| codex-first-nudge | 158 | 16 |
| skill-authoring-reminder | 11 | 1.1 |
| routing-guard | 9 | 0.9 |
| shared-script-warn | 5 | 0.5 |

Two hooks are 95% of all measured hook traffic.

**Silent by design, not dead:** the SessionStart injectors emit untagged `additionalContext` and
cannot be transcript-counted; without that distinction they read as dead.

**Log-backed, not tag-backed:** `promise-guard` keeps `~/.claude/leadv2-promise-guard.jsonl` —
2,097 rows Aug 1–Sep 2: 1,615 `suppressed_action` (correct and invisible), 482 `fired`, but
`block_decision=yes` only **4 times in the month**; enforcement defaulted ON one day ago
(2026-09-01). `continuation-guard`: 2,403 raw hits/10d, no log to cross-check — upper bound.

## 2. Does it help or hinder?

**One fully-traced case, and it is a hinder.** `leadv2-pulse-json.sh:103-107` resolves the lead's
task with an `awk … exit`-on-first-match over `docs/leadv2/active.yaml`, never checking `dead_at`
or `deregistered`. For ~40 minutes every Bash call rewrote `pulse.json` for a dead, twice-
deregistered task and the anchor injector fed the lead a false ACTIVE TASK every turn. Not a guard
blocking a bad action — a guard manufacturing a wrong belief the lead then acted on.

**The "prevented a mistake" side did not survive checking.** The one independent citation attempt
for `worktree-enforce` resolved to a grep artifact: line 89 of the hook's own source appearing
inside a Grep tool result, not a live block. Today's heredoc-guard matches concentrate in
`/private/tmp/leadv2-*-repo*` and `glm-effort-fixture-*` paths — the test suite exercising the
guard, not real blocks of founder work.

**Net:** on what could be verified this session the ratio cannot be certified favorable. A flagship
"it prevented a mistake" citation that fails a transcript check is exactly the bad-ratio case.

## 3. What does it cost?

- `lead-delegation-nudge`: ~3,872 fires/day × ~38 tokens ≈ **147K injected tokens/day** from one
  hook, re-entering context on every later turn.
- `loop-detect`: same order of magnitude.
- **Latency, measured by hand-invoking `leadv2-bash-pre-dispatch.sh`:** plain command (2 ALWAYS
  guards) ≈ **335 ms**; `git commit` (6 guards) ≈ **1.0 s**. Added to every Bash call, every
  session. Under the 30 s manifest ceiling, nowhere near free.

## 4. Every repo, every project type?

Hook scripts wired per repo's own `settings.json`: persona-engine 30, m3-market 20, respiro-ios 9,
getmany-followup-bot 4, **leadv2 0**. The zero is correct — leadv2's `settings.json` has no `hooks`
key and inherits the plugin baseline; it has no product surface to guard.

**The wiring divergence that caused today's incident.** Canonical `hooks.json` — byte-identical to
the live cache at `~/.claude/plugins/cache/leadv2-local/leadv2/0.5.7/hooks/hooks.json` — wires
`pulse-json.sh` to nothing. But `persona-engine/.claude/settings.json:336` wires a byte-identical
**real copy** at `persona-engine/.claude/hooks/leadv2-pulse-json.sh` to
`Bash|Edit|Write|MultiEdit|NotebookEdit|Agent|Workflow|Skill` — nearly every tool call — entirely
outside the plugin manifest. Only persona-engine does this, of four consumer repos. It is exactly
the "never create a real copy of a plugin-owned file" anti-pattern from this repo's own CLAUDE.md,
and it is the direct mechanism of §2.

**Genericity:** 69/93 need `python3` (fail-open per code comments, not independently confirmed).
33/93 hardcode `docs/leadv2/`, 25/93 `docs/handoff/` — the plugin's own convention, fine for an
adopter. 6/93 mention `persona-engine`, 5 of them in comments. One real defect:
`leadv2-shared-script-warn.sh:89` hardcodes `CONSUMERS="persona-engine, m3-market, respiro-ios"`,
missing getmany-followup-bot, a live consumer.

## 5. Verdict

**KEEP** — `leadv2-deny-floor.sh` (ALWAYS, exit-2, dynamic regex, correctly scoped hard floor);
`promise-guard` + `continuation-guard` (detection logic is log-backed and works — see FIX for
enforcement); `task-budget-tracker`, `taskoutput-ban`, `stale-pid-sweep` (narrow, checkable,
28–40/day).

**FIX** — `lead-delegation-nudge` and `loop-detect`: 95% of traffic, ~147K tok/day from one hook;
fire once per phase, not once per violation. `pulse-json`: check `dead_at`/`deregistered` and read
the live control plane `~/.claude/leadv2-state/leadv2/active.yaml`, not the repo-local file.
`shared-script-warn:89`: derive the consumer list from the symlink tree. `pre-compact-task-freeze`:
re-wire to PreCompact or delete it and fix the two files still citing it as live. Move
`mode-isolation.sh` into `hooks/lib/` — its flat location caused two false-orphan censuses.

**DELETE** — 8 confirmed-dead entrypoints: `block-codex`, `compact-trigger`, `force-read-limit`,
`read-dedup-hard`, `lead-read-guard`, `hardbans-reinject`, `idle-guard-arm`, `idle-lead-guard`;
plus `hook-fork-budget`, which exists only to make its own test pass. Each costs every future
reader the same file-by-file archaeology this audit had to do.
