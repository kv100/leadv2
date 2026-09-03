# SKILL-USAGE-IS-UNMEASURED-01 — BUILD MISSION (STEP 1 ONLY: measure)

Binding: `docs/handoff/WAVE4/shared-constraints.md` (repo = `~/Projects/leadv2`; negative control
inside the function body; macOS **and** linux exit codes; no assertion weakened; no commit to `main`).

## Goal
Ship an **invocation** record for skills — which skill fired, when, in which session/lane, how it
ended — plus a period rollup that prints three honest buckets. Today nothing counts invocations.
Step 1 delivers the number. Step 2 (acting on it) is out of scope.

## What the current tally actually counts — `plugins/leadv2/scripts/leadv2-skill-usage-tally.sh`
| Line | Code | What it really measures |
|---|---|---|
| L115 | `refs=$(grep -lE "\b${skill_name}\b\|leadv2:${skill_name}" ... \| wc -l)` | number of **files whose text contains the skill's name**. Prose mentions. `-l` = files, so 52 files mention `leadv2-review`. |
| L117 | `dispatch_hits=$(grep -hE "Skill\(skill=\"${skill_name}\"" ...)` | occurrences of the **literal source string** `Skill(skill="X")` in plugin `commands/*.md`, `docs/*.md`, `hooks/*`, `scripts/*`, other `SKILL.md`. |
| L124 | `AUTO_LIST="leadv2-plan leadv2-build …"` | a hand-kept list of 9 names asserted to auto-fire. Declared, never observed. |
| L136-148 | ladder DEFERRED > DISPATCH > WIRED > AUTO > DORMANT | status is a function of text, never of runtime. |
| L157 | `summary: total=… dispatch=…` | `dispatch=5` = 5 skills that appear as a hard-coded literal somewhere. |

**Why `leadv2-review` is `refs=52 dispatch=0`.** `dispatch` counts something real but static: whether
an author hard-coded the string `Skill(skill="leadv2-review")` into a file. Nobody did — the skill
fires by description-matching, which leaves **no source-text trace at all**. So `dispatch` is
counting the wrong thing for this purpose: it measures authoring style, not firing. A skill can fire
300 times a week and stay `dispatch=0` forever. Neither column can ever move on an invocation.

## Why the tally sees 40 of 89
- `L25 SKILLS_DIR="$PLUG_ROOT/skills"` and `L152 find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d` — the enumeration set is **only** `plugins/leadv2/skills/`, which holds **41** dirs.
- `L57 [[ -f "$skill_file" ]] || continue` drops `plugins/leadv2/skills/archive/` (no `SKILL.md`) → **40**.
- The other **48** live in `/Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/skills/`. `--consumer-root` (L15-16, L100-106) only widens the *ref grep*; it never widens the enumeration. 41 − 1 skipped = 40 counted, 48 never seen. 40 + 48 + 1 = 89.
- (`~/Projects/leadv2/.claude/skills/` does not exist — do not look for it there.)

## Available invocation signals — verified on disk 2026-09-03, not assumed
**S1 — session transcript JSONL. AUTHORITATIVE. Retroactive. Two shapes, both confirmed:**
- **S1a explicit tool call** — in `message.content[]` of an `assistant` line: `{"type":"tool_use","id":"call-fde5e4af-…","name":"Skill","input":{"skill":"leadv2-init"}}`; the line carries `timestamp`, `sessionId`, `cwd`, `uuid`. Small: **28 in 7d** (30d: `leadv2-init` 8, `leadv2` 4, `leadv2-founder-question-router` 3, …).
- **S1b description-matched injection — the DOMINANT path.** A `user` line, `isMeta:true`, whose text carries `<command-name>NAME</command-name>` **and** `<skill-format>true</skill-format>`. Keys: `agentId, cwd, entrypoint, gitBranch, isMeta, isSidechain, parentUuid, promptId, sessionId, timestamp, uuid, version`. 7d: `leadv2-subagent-protocol` **290**, `systematic-debugging` 138, `error-handling` 119, `bash-scripting` 119, `async-python` 29 …
- **Discriminator (verified both ways):** skills carry `<skill-format>true</skill-format>`; slash commands (`/leadv2`, `/model`, `/compact`, `/standup-sync`) carry `<command-name>` **without** it. The parser MUST gate on that tag or it counts slash commands as skills.
- Globs (both required): `~/.claude/projects/<mangled-cwd>/<session-id>.jsonl` and `~/.claude/projects/<mangled-cwd>/<session-id>/subagents/agent-*.jsonl`. Worktree lanes get their own mangled dir, e.g. `-Users-…-leadv2--claude-worktrees-ONE-LANE-WATCH-01-R2`.

**S2 — PreToolUse hook, `matcher: "Skill"`. Real but PARTIAL.** Supported and already in use:
`~/.claude/settings.json:203` registers `~/.claude/hooks/codex-marker` on it.
`plugins/leadv2/hooks/hooks.json` PreToolUse matches `.*|Monitor|Bash|AskUserQuestion|Read|Agent|
Workflow|TaskOutput|Write|Edit|MultiEdit` — no `Skill` row. **A hook sees only S1a**: ~10× under-count,
and only from deploy day forward. Not the source of truth.

**Verdict: a reliable signal EXISTS today — the emitter does not have to be built.** Build a
**collector** (transcript scanner): it covers S1a+S1b, is retroactive over existing history, and
changes no dispatch path. **Emitter-site note (WAVE4):** the natural *live* emitter is that
PreToolUse `Skill` hook, which is **not** inside `leadv2-dispatch-code.sh` or
`leadv2-claude-profile-select.sh` — no collision; but it is insufficient and is deferred to step 2.
`~/.claude/settings.json` is user-level, outside the repo, and off-limits here.

## Telemetry design
**Store:** `docs/leadv2/skill-invocations.jsonl` — append-only, one JSON object per line, git-tracked.
**Record (exact keys; emit all, `null` when unknown — never omit a key):**
```json
{"event_id":"<sha1(session_id + '|' + uuid)>","ts":"2026-09-01T19:46:08.868Z",
 "skill":"leadv2-subagent-protocol","source":"skill_format_injection|skill_tool_use",
 "session_id":"6c3c6465-…","agent_id":"agent-a0dc…|null","is_sidechain":true,
 "cwd":"/Users/…/leadv2/.claude/worktrees/ONE-LANE-WATCH-01-R2","repo":"leadv2",
 "lane":"ONE-LANE-WATCH-01-R2|main","git_branch":"worktree-…|null",
 "phase":"<nearest preceding phase in the lane journal>|unknown",
 "outcome":"ok|error|n_a","collected_at":"<UTC>"}
```
- `repo` / `lane` derive from `cwd` (worktree basename, else `main`). `phase` is `unknown` unless a lane-journal row precedes the timestamp — **do not guess a phase.**
- `outcome`: S1a resolves the matching `tool_result` by `tool_use_id` → `ok` / `error`. S1b has **no** result record, so `outcome:"n_a"`. Never write `ok` for an S1b row.

**Writer:** `plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh` (to-create). Batch scanner over both transcript globs, `--since <Nd>` default 30d, idempotent, runnable by anyone at any time.

**Concurrent-session safety — four layers, in this order:**
1. **`event_id` dedup is what makes it safe.** Load existing `event_id`s into a set first; re-running the collector while three sessions run appends zero duplicates. Idempotency, not the lock, is the guarantee.
2. **One locked critical section for the whole append**, using the repo's own idiom — source `plugins/leadv2/scripts/leadv2-portable-lock.sh` and wrap: `( lv2_lock_wait "$lockf" 10 || exit 3 ; cat "$tmp" >> "$jsonl" ) 9>"$lockf"` with `lockf=docs/leadv2/.skill-invocations.lock`. macOS ships no `flock(1)` in the acceptance PATH; the shim covers it. Never `echo >>` per record outside the lock.
3. Build the batch in a `mktemp` file and append once — one `cat` inside the lock, not N writes.
4. **`.gitattributes` (to-create): `docs/leadv2/skill-invocations.jsonl merge=union`** so two lane branches that both appended merge without a conflict; dedup makes union safe.

## Rollup design
**Command:** `bash plugins/leadv2/scripts/leadv2-skill-rollup.sh --since 7d [--repo <name>] [--skills-root <dir>]… [--format md|tsv]` (to-create).
**Output:** `docs/leadv2/skill-usage-rollup.md` (default), `--format tsv` to stdout for tests.
**Universe = the union of all skill roots, not just the plugin's** — default roots
`plugins/leadv2/skills` **and** `~/Projects/persona-engine/.claude/skills`; a dir without `SKILL.md`
is reported as `no-skill-md`, not silently dropped. This is the fix for 89-vs-40; the rollup must
print `universe=<N>`, and on today's disk that is 88 skills + 1 `no-skill-md`.
**Three buckets, decided by one function `bucket_for_skill()`** (the mutation target):
- `INVOKED` — ≥1 telemetry row inside the window.
- `NEVER_INVOKED` — 0 rows in the window **and** 0 rows in the whole file.
- `INVOKED_NO_LANE_SUCCESS` — ≥1 row in the window, and every row whose lane outcome **resolved** resolved to non-success. A skill whose rows are all `unresolved` may never land here.
**Columns:** `skill | root | invocations | sessions | lanes | last_seen | bucket | lane_success`.

## What "and did it help?" can honestly mean
Outcome attribution is **not possible in step 1** and the lane must not fake it. There is no
counterfactual: nothing records the same lane run *without* the skill, and S1b rows have no result
record at all. Do not invent a helpfulness metric.
What IS computable: for a row whose `lane` resolves to a task with a terminal state, the pair
(skill invoked, lane terminal). Aggregated per skill as `lane_success` = `landed / (landed + failed)`,
over resolved rows only. Rules:
- The rollup header MUST print, verbatim: `lane_success is CORRELATION, NOT PROOF of helpfulness.`
- Rows whose lane terminal cannot be resolved → `lane_outcome: unresolved`, in a separate column. A skill with **no** resolved rows prints `lane_success: n/a` — never `0%`.
- Forbidden in this lane: ranking skills by `lane_success`, any "score", any recommendation from it.

## Files allowlist
**Create:** `plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh` (to-create) ·
`plugins/leadv2/scripts/leadv2-skill-rollup.sh` (to-create) ·
`plugins/leadv2/scripts/tests/test-skill-telemetry.sh` (to-create) ·
`docs/leadv2/skill-invocations.jsonl` (to-create, generated) ·
`docs/leadv2/skill-usage-rollup.md` (to-create, generated) · `.gitattributes` (to-create) ·
`docs/handoff/SKILL-USAGE-IS-UNMEASURED-01/*.md`
**Edit:** `tests/run-all.sh` (EXTRA_SUITE_MAP rows only, near L134) ·
`plugins/leadv2/scripts/leadv2-skill-usage-tally.sh` — **header comment only** (state that
`refs`/`dispatch` are static-text counts and point at the rollup for invocation truth). No logic change.
**Off-limits:** `plugins/leadv2/scripts/leadv2-dispatch-code.sh` ·
`plugins/leadv2/scripts/leadv2-claude-profile-select.sh` · `~/.claude/settings.json` ·
`tests/known-red-suites.txt` · every `SKILL.md` (no edits, no deletions) · `.claude/worktrees/**` ·
anything under `~/Projects/persona-engine` (read-only source of the 48-skill universe).

## Steps
1. Collector: parse both transcript globs, both record shapes, gate S1b on `<skill-format>true</skill-format>`, emit the record above, dedup by `event_id`, locked single append.
2. `.gitattributes` row for `merge=union`.
3. Rollup: universe union across skill roots; `bucket_for_skill()`; the correlation header line.
4. Suite `test-skill-telemetry.sh`: real collector against a fixture transcript tree (fake only the transcript dir, never the collector), idempotent re-run, `skill-format` vs slash-command discrimination, universe count, all three buckets.
5. `EXTRA_SUITE_MAP` rows + prove selection with `--scope changed`.
6. Report: acceptance output, both negative-control exit codes, macOS + linux exit codes.

## Acceptance commands (re-runnable, exact)
```bash
cd ~/Projects/leadv2
# A. controlled invocation -> a new row with the right fields
claude -p "Use the Skill tool to load the skill named leadv2-verify, then reply DONE." \
  --max-turns 3 --permission-mode bypassPermissions --output-format json > /tmp/skill-probe.json
SID=$(python3 -c "import json;print(json.load(open('/tmp/skill-probe.json'))['session_id'])")
bash plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh --since 1d
grep -c "\"session_id\":\"$SID\"" docs/leadv2/skill-invocations.jsonl   # expect >= 1
grep "\"session_id\":\"$SID\"" docs/leadv2/skill-invocations.jsonl | head -1 | python3 -m json.tool
# ^ must show skill/ts/session_id/cwd/repo/lane/source=skill_tool_use/outcome
# B. idempotency under concurrent sessions
wc -l < docs/leadv2/skill-invocations.jsonl > /tmp/n1
bash plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh --since 1d
wc -l < docs/leadv2/skill-invocations.jsonl > /tmp/n2; diff /tmp/n1 /tmp/n2   # expect identical
# C. the dominant path is captured retroactively (no spawn needed)
bash plugins/leadv2/scripts/leadv2-skill-telemetry-collect.sh --since 7d
grep -c '"skill":"leadv2-subagent-protocol"' docs/leadv2/skill-invocations.jsonl  # expect >= 200
# D. three buckets + universe
bash plugins/leadv2/scripts/leadv2-skill-rollup.sh --since 7d --format tsv | tee /tmp/rollup.tsv
grep -c NEVER_INVOKED /tmp/rollup.tsv; grep -c INVOKED_NO_LANE_SUCCESS /tmp/rollup.tsv
grep -q 'CORRELATION, NOT PROOF' docs/leadv2/skill-usage-rollup.md && echo HEADER_OK
grep -q 'universe=89' docs/leadv2/skill-usage-rollup.md && echo UNIVERSE_OK
# E. a never-invoked skill really lands in NEVER_INVOKED (pick it dynamically, never hard-code)
S=$(awk -F'\t' '$0 ~ /NEVER_INVOKED/ {print $1; exit}' /tmp/rollup.tsv); echo "$S"
grep -c "\"skill\":\"$S\"" docs/leadv2/skill-invocations.jsonl   # expect 0
# F. CI selects the suite
bash tests/run-all.sh --scope changed --dry-run 2>&1 | grep test-skill-telemetry.sh
```

## Negative control (run for real, both directions)
Suite: `plugins/leadv2/scripts/tests/test-skill-telemetry.sh`.
`EXTRA_SUITE_MAP` rows to add near `tests/run-all.sh:134`:
```
leadv2-skill-telemetry-collect.sh:plugins/leadv2/scripts/tests/test-skill-telemetry.sh
leadv2-skill-rollup.sh:plugins/leadv2/scripts/tests/test-skill-telemetry.sh
```
- **M1 (bucketing).** In a scratch worktree, insert **inside the body of `bucket_for_skill()`** in `leadv2-skill-rollup.sh`, after the local-var declarations and before the count comparison: `count=1` → every skill classifies as invoked. Assertion E must go RED.
- **M2 (collector).** Insert **inside the body of the per-transcript collect function**, immediately after `event_id` is computed: `event_id="${event_id}-$RANDOM"` → idempotency breaks. Assertion B must go RED.
Anchor both `sed` inserts on the function's opening line with a body-scoped range. A top-level insert
reddens everything for the wrong reason and reads as a pass — that exact mistake invalidated a
measurement on 2026-08-25. Record RED and GREEN exit codes verbatim for M1 and M2 separately.

## Out of scope
- **Step 2 — acting on the measurement.** No consolidation, no rewiring, no inlining, no promotion of a skill, no change to the tally's classification logic, no PreToolUse `Skill` hook. Step 1 produces the number; a later lane decides what to do with it.
- **HARD PROHIBITION — binding on this lane:** *do not delete and do not "inline" a single skill before invocation measurement exists. Today DORMANT means only "the docs do not mention it", and nothing may be deleted on that basis.*
- `ARBITER-ESTIMATES-BLIND-AND-NEVER-LEARNS-01` — related, not in scope.
- Editing skill content, or any change under `~/Projects/persona-engine`.
