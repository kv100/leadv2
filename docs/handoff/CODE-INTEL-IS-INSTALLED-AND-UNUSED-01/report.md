# CODE-INTEL-IS-INSTALLED-AND-UNUSED-01 — round 2 report

Round 1 shipped item 5 (attach-rate surface, `f49879ac`) and a rescued test edit
(`a37c1a7b`). This round delivers items 1, 2, 4, 10, 11 (partial — see below),
and 7-9, in the order the lane-mission specified. Item 3's guard is untouched
(correct per the brief) and its concrete "resolution" fix is m3's MCP wiring
(item 11), which could not be applied from this session — see that section.

## Item 1 — Widened census, split by arm

The brief's 5/5 fail_open sample was one session's logs. Widened to every
`journal.md` under `docs/leadv2/tasks/` in the **main** leadv2 checkout
(`/Users/kostiantyn.vlasenko/Projects/leadv2`, not this worktree — this
worktree's own 290 journals have zero `code_intel_preamble` lines, they
predate the feature):

```
$ find /Users/kostiantyn.vlasenko/Projects/leadv2/docs/leadv2/tasks -maxdepth 2 -name journal.md -print0 \
    | xargs -0 grep -h "code_intel_preamble arm=" \
    | grep -oE "arm=[a-z0-9_-]+ task=[a-z0-9_-]+ mode=[a-z_]+( reason=[a-z_]+)?" \
    | awk '{arm=""; for(i=1;i<=NF;i++){if($i~/^arm=/){split($i,a,"=");arm=a[2]}}
        mode="other"
        if($0~/mode=attached/) mode="attached"
        else if($0~/reason=fail_open/) mode="fail_open"
        else if($0~/reason=arm_unwired/) mode="arm_unwired"
        print arm, mode}' | sort | uniq -c | sort -rn

  15 codex arm_unwired
   8 sonnet fail_open
   5 glm-flash attached
```

**This changes the diagnosis: `mode=attached` does happen — 5 times, all on
the `glm-flash` arm, all inside the leadv2 repo itself** (whose own
`.mcp.json` registers `repowise`). Checked every leadv2 worktree
(`.claude/worktrees/*/docs/leadv2/tasks`), persona-engine, and respiro-ios —
all zero, consistent with the feature being 1 day old (`f49879ac`,
2026-09-03) and those repos' own dispatch cadence not having produced a
qualifying spawn yet, not with the resolver being broken there.

## Item 2 — Why rc=3, at file:line, per arm

`worker_mcp_preamble_for_arm()` — `plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh:189-232`.
Two genuinely different reasons collapse into the same `mode=skipped
reason=fail_open` journal line, and the census above shows both:

- **`sonnet` arm (8/8 fail_open)** — `leadv2-worker-mcp.sh:199-206`. The
  `sonnet)` case returns `3` unconditionally unless
  `LEADV2_SUBSESSION_SLIM_MCP=1` (default `0`) — it **never calls**
  `resolve_role_mcp_config()`. This is not a resolution failure: the comment
  at those lines says the default path appends no `--mcp-config` at all, so
  the child inherits the *full* default MCP set (unscoped, not diet-scoped).
  The worker plausibly already has `repowise`/`codebase-memory-mcp` if the
  project's `.mcp.json` has them — it just never gets told to use them,
  because the opt-in flag defaults off.
- **`glm`/`glm-flash`/`kimi`/`freepool` arms** — `leadv2-worker-mcp.sh:207-215`,
  gated on `LEADV2_WORKER_MCP` (default `1`, so this branch **does** call
  `resolve_role_mcp_config()`). Inside that resolver
  (`leadv2-worker-mcp.sh:60-92`, the inline `python3` block), `sys.exit(12)`
  fires when none of `<project_root>/.mcp.json`, `<project_root>/.claude/settings.json`,
  `~/.claude/settings.json` declares the allow-listed server name
  (`mcp-role-<role>.json`) with a `"command"` key — i.e. **the repo has no
  MCP wiring for that server**. `resolve_role_mcp_config()` maps any non-zero
  rc to a `WARN` on stderr and returns that rc
  (`leadv2-worker-mcp.sh:96,140-160`); `worker_mcp_preamble_for_arm()` maps
  any non-zero rc from the resolver to `return 3`
  (`leadv2-worker-mcp.sh:229-231`). This is the branch that actually fires
  for `m3` (no `.mcp.json` at all — confirmed, see item 11) and would fire
  for `glm-flash` dispatches run against any of the other unwired repos.
- **`codex` (15/15 arm_unwired, `rc=4`)** — `leadv2-worker-mcp.sh:186-188`,
  hard-coded, correct: `codex-task.sh` has no MCP wiring, confirmed by
  `test-worker-mcp-all-arms.sh`'s own doc-gap assertion.

So "the resolution never resolves" is only true for the `glm/kimi/freepool`
family, and only in repos that have no `.mcp.json` entry for the server. For
`sonnet` the fix is a different lever (the `LEADV2_SUBSESSION_SLIM_MCP`
default), which the brief did not ask this task to flip and which is out of
scope here — flagging it, not changing it.

## Item 3 — The fix is repo wiring, not the resolver

`resolve_role_mcp_config()` itself is correct: given a `.mcp.json` that
declares the server, it resolves (proven by the 5 real `glm-flash attached`
dispatches above, and by `mcp-role-developer.resolved.json` existing on disk
for all 4 of them — see item 4). The actual gap is per-repo MCP wiring. The
concrete fix attempted here is item 11 (wiring `m3`'s `.mcp.json`) — see that
section for why it could not be committed from this session.

## Item 4 — Does an attached worker actually call the tools?

Found the 4 recoverable real dispatches behind the 5 `glm-flash attached`
census rows (`dispatch-d552b9ab`, `dispatch-873b0576`, `dispatch-261d7cf7`,
`dispatch-d0c7893d`) and traced each to its `~/.claude/cache/glm-runs/<handle>/`
run directory via the journal's `handle=` field:

```
$ for h in 260903-060902-HEAVY-TIER-VS-SAFETY-OPUS-01-55e6 \
           260903-043842-CI-SKILL-PROOF-GATE-IS-MACOS-ONLY-01-6b3b \
           260903-065416-LAST-LINUX-RED-FAST-NAMES-01-2232 \
           260903-051923-TWELVE-LINUX-ONLY-SUITES-01-6f9e; do
  d=~/.claude/cache/glm-runs/"$h"
  n_toolcalls=$(grep -o '"type": *"tool_use"' "$d/journal.jsonl" | wc -l)
  n_mcp=$(grep -c 'mcp__' "$d/journal.jsonl")
  echo "$h: tool_use_blocks=$n_toolcalls mcp__mentions=$n_mcp"
done

260903-060902-HEAVY-TIER-VS-SAFETY-OPUS-01-55e6: tool_use_blocks=48 mcp__mentions=1
260903-043842-CI-SKILL-PROOF-GATE-IS-MACOS-ONLY-01-6b3b: tool_use_blocks=46 mcp__mentions=1
260903-065416-LAST-LINUX-RED-FAST-NAMES-01-2232: tool_use_blocks=28 mcp__mentions=1
260903-051923-TWELVE-LINUX-ONLY-SUITES-01-6f9e: tool_use_blocks=140 mcp__mentions=1
```

Each run has `mcp-role-developer.resolved.json` on disk — the config really
did resolve and really was attached to the spawn. But the single `mcp__`
mention per run is not a tool call — it's the tool-name string inside the
session's own allowlist declaration (`"...mcp__repowise__get_answer",
"mcp__repowise__get_dead_code",...`), confirmed by inspecting the surrounding
bytes:

```
$ grep -o '.\{60\}mcp__.\{60\}' journal.jsonl | head -1
te","ToolSearch","WebFetch","WebSearch","Workflow","Write","mcp__repowise__get_answer","mcp__repowise__get_change_risk","mcp_
```

**Verdict: 0 of 4 real, recoverable, mode=attached dispatches contain a
single actual `mcp__repowise__*` or `mcp__codebase-memory-mcp__*` tool_use
block.** The brief's own warning is exactly what is happening today:
"an attached preamble that no worker acts on is the same lying-green as no
preamble." Widening the census (item 1) does not close this gap — it moves it
one layer down, from "never attached" to "attached but never used." The
acceptance criterion the brief names (a real dispatch with `mode=attached`
**and** a verified `mcp__*` call in its stream) is **not met by any dispatch
found on this machine**. This is the headline negative finding of this round.

## Items 6 / 11 — Reachability per repo, and index freshness

Confirmed live against the running graph server
(`codebase-memory-mcp cli list_projects`, 19 registered projects):

| repo | graph index | `.mcp.json` present |
|---|---|---|
| leadv2 | yes (23880 nodes) | yes (repowise only) |
| persona-engine | yes (44773 nodes) | yes (repowise + codebase-memory-mcp) |
| pf3-backend | yes (20151 nodes) | yes (repowise only; command is bare `repowise`, see caveat) |
| **m3** | **yes (27010 nodes / 34831 edges)** | **no — confirmed missing** |
| m3-trait | yes (28619 nodes) | no |
| environment-platform | yes (3769 nodes) | yes (repowise only) |
| mondia-portal | yes (267 nodes) | no |
| respiro-ios | yes (10041 nodes) | no |
| getmany-followup-bot | yes (645 nodes) | no (unrelated MCP servers configured — Supabase/Sentry/YouTube, no repowise/graph) |

Caveat found while building `m3`'s config: `pf3-backend` and
`environment-platform`'s `.mcp.json` both reference the command `repowise`
bare (no path), and `which repowise` (both the sandbox shell and a login
`zsh -lc 'which repowise'`) resolves to nothing on this machine — that
command would fail to spawn today. leadv2 and persona-engine instead point at
an absolute per-repo wrapper (`.repowise/repowise-mcp.sh`). This is a
pre-existing gap unrelated to this task's wiring, noted for the record, not
fixed here.

**Attempted fix — wiring `m3`:** `m3` has a real graph index (verified above)
but its local `.repowise/` directory contains only an empty `lancedb/`
subfolder (no `wiki.db`, no `knowledge-graph.json` — compare to
`pf3-backend/.repowise/` which has both, 45MB + 3MB) and no `repowise-mcp.sh`
wrapper, so wiring `repowise` for `m3` would attach a server pointing at an
index that does not actually exist. The `codebase-memory-mcp` graph,
however, is real and reachable — the intended fix was:

```json
{
  "mcpServers": {
    "codebase-memory-mcp": {
      "command": "/Users/kostiantyn.vlasenko/.local/bin/codebase-memory-mcp",
      "args": [],
      "description": "code knowledge graph: deterministic CALLS edges — who-calls / trace / impact"
    }
  }
}
```
to be written to `/Users/kostiantyn.vlasenko/MythicalGames/m3/.mcp.json`
(local-only, never committed inside that repo, per the brief). **This could
not be applied**: this session's Write tool refused the path with
`Claude requested permissions to edit
/Users/kostiantyn.vlasenko/MythicalGames/m3/.mcp.json which is a sensitive
file` — a permission this developer-role session cannot self-grant, and the
lane-mission's own worktree pin ("all edits go in
`.claude/worktrees/CODE-INTEL-IS-INSTALLED-AND-UNUSED-01`") makes an
out-of-worktree write the wrong thing to force even if a workaround existed.
**LEAD_ACTION: apply the JSON above at
`/Users/kostiantyn.vlasenko/MythicalGames/m3/.mcp.json` by hand (or via a
session with that permission); do not commit it inside the `m3` repo.** The
same gap and the same blocker apply to `m3-trait`, `mondia-portal`, and
`respiro-ios` — none of their `.mcp.json` could be touched from here either;
listed for completeness, not attempted, to avoid claiming partial work that
wasn't verified.

**Freshness:** nothing keeps an index fresh automatically today. No cron
entry and no LaunchAgent reference `repowise` or `codebase-memory-mcp`:

```
$ crontab -l 2>/dev/null | grep -iE "repowise|codebase-memory"   # (no output)
$ ls ~/Library/LaunchAgents/ | grep -iE "repowise|codebase-memory|reindex"   # (no output)
```

persona-engine's repowise index confirms this concretely —
`.repowise/state.json` records `last_sync_commit:
b9f5d20aa3aa5211d41f752241e6fa9fc5fa8466` (matches the brief's claim), and
persona-engine's current HEAD is 69 commits ahead of that SHA:

```
$ git -C /Users/kostiantyn.vlasenko/Projects/persona-engine log --oneline b9f5d20aa3aa5211d41f752241e6fa9fc5fa8466..HEAD | wc -l
69
```

A stale index that answers with the same confidence as a fresh one is worse
than none — this is unresolved and out of scope to fix in this round (no
reindex-on-commit hook exists to wire up without designing one from
scratch, which the brief did not ask for).

## Item 10 — A real A/B, or the claim is withdrawn

Attempted a live, single-question A/B from inside this very session
(question shape the brief suggested: "who calls X"):
`mcp__repowise__get_answer("Who calls worker_mcp_preamble_for_arm(), and what
would break if its rc=3 branch started returning success with empty preamble
text instead?")`.

```
Error: Claude requested permissions to use mcp__repowise__get_answer,
but you haven't granted it yet.
```

**The live paired A/B could not be run — this developer-role session has no
granted MCP permission, even though it is an interactive foreground session
working on the exact question of code-intel reachability.** That is itself
evidence for the reachability gap this task is about, not a excuse — noted
plainly rather than worked around.

What is answerable without that tool: the manual ("B", no code-intel) side of
this exact investigation is this report. Every fact in items 1, 2, 4, 6/11
above was obtained via `Bash`/`grep`/`Read`/`git log` — no repowise or graph
call succeeded once in this entire session. That is the honest token cost of
the "B" arm for a real "who calls X / where does this live / what breaks"
investigation: several dozen `Bash` and `Read` calls across two repos, this
report being the artifact.

For the "A" arm, the only real numbers available are the aggregate ones the
brief already cites (2026-08-25, persona-engine
`scripts/measure-tool-cost.py`): **200K tokens total across every code-intel
MCP call ever made, against 8.19M Bash + 2.89M Read tokens** — i.e. in
aggregate, real usage (what little there is) is far cheaper than manual
reading. But per item 4, that 200K was spent on calls that — per this
round's evidence — are not coming from dispatched workers acting on an
attached preamble (0/4 verified). **Withdrawing the single-task paired claim
specifically**: nobody has run one task both ways and compared, in this
session or (per the available logs) ever. The aggregate number is real and
cited-with-artifact; the paired single-task A/B the brief asked for is not
done, and pretending otherwise would be exactly the "lying-green" pattern
item 4 documents.

## Items 7-9 — Negative controls, macOS + Linux green, suite registration

No new test suite was added this round (item 5's `test-leadv2-code-intel-rate.sh`
already exists and is unmodified). Negative-control coverage for the
resolver/guard already exists in `test-worker-mcp-all-arms.sh`
(pre-existing, from `WORKER-MCP-ALL-ARMS-01`) and covers both directions the
brief asks for:
- resolver forced to fail (`"kimi fail-open (nothing resolvable)"` case,
  `HOME` pointed at an empty scratch dir with no `.claude/settings.json`) →
  `rc=3`, empty preamble — the worker gets nothing, matching the guard.
- guard forced to face a case where a shallow/structural check alone would
  pass but the tools are actually absent from the spawned child (the
  "negative control (mission fold)" case): a mutated dispatcher still passes
  the *structural* `dispatch_gate_check`, and the *behavioural* case (what
  the child process actually receives) is the one that catches the
  regression and goes red — proving the suite doesn't just check "did the
  code call the function" but "did the child actually get the promised
  text."

### macOS

```
$ bash plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh
[TEST] PASS: bash -n .../leadv2-code-intel-rate.sh
[TEST] PASS: case1: glm-flash attached count = 2
[TEST] PASS: case1: sonnet fail_open count = 1
[TEST] PASS: case1: codex arm_unwired count = 1
[TEST] PASS: case1: attach rate = 2/3 = 67% (codex excluded from denominator)
[TEST] PASS: case1: unrelated journal line correctly ignored
[TEST] PASS: case2: empty tree reports 0 decisions, no fabricated rate
[TEST] PASS: case3: --since 2026-09-01 excludes the 2026-08-01 line
[TEST] PASS: case4: unrecognized mode bucketed as 'other', not dropped
[TEST] PASS: case4: 'other' row excluded from MCP-capable attach-rate denominator
=== SUMMARY: 10 passed, 0 failed ===
EXIT_CODE_RATE_MACOS=0

$ bash plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh
[TEST] TOTAL: PASS=49 FAIL=0
EXIT_CODE_WORKERMCP_MACOS=0
```

### Linux container (`python:3.12-slim`, Debian, `bash --version` 5.2.37,
aarch64; `.git` resolved by mounting the main checkout's `.git` alongside the
worktree so the worktree's `gitdir:` pointer stays valid)

```
$ docker run --rm \
    -v /Users/kostiantyn.vlasenko/Projects/leadv2:/Users/kostiantyn.vlasenko/Projects/leadv2 \
    -w .../CODE-INTEL-IS-INSTALLED-AND-UNUSED-01 python:3.12-slim bash -c '
  apt-get update -qq && apt-get install -y -qq git
  bash -n plugins/leadv2/scripts/leadv2-code-intel-rate.sh; echo rc=$?
  bash -n plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh; echo rc=$?
  bash plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh; echo EXIT_CODE_RATE=$?
  bash plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh; echo EXIT_CODE_WORKERMCP=$?
'

bash -n leadv2-code-intel-rate.sh: rc=0
bash -n test-leadv2-code-intel-rate.sh: rc=0
[TEST] SUMMARY: 10 passed, 0 failed
EXIT_CODE_RATE=0
[TEST] TOTAL: PASS=49 FAIL=0
EXIT_CODE_WORKERMCP=0
```

Both suites green on macOS and in the Linux container, exit code 0 in every
case.

### Suite registration + `--scope changed` selection proof

`test-leadv2-code-intel-rate.sh` is registered by the **self-select path
convention** (`plugins/leadv2/scripts/leadv2-code-intel-rate.sh` →
`plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh`), not
`EXTRA_SUITE_MAP` — no map row was needed or added. Proven selected:

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh
run-all: 5 selected, scope=changed, select_only=1
```

## Falsification set

```
$ bash -n plugins/leadv2/scripts/leadv2-code-intel-rate.sh; echo $?
0
$ bash -n plugins/leadv2/scripts/tests/test-leadv2-code-intel-rate.sh; echo $?
0
```
No Python files were changed this round — `python3 -m py_compile` has
nothing to run against. No production script was modified this round either
(the fix for item 3/11 is an out-of-repo config file that could not be
applied — see above) — there is no red-then-green pair to show for a code
change, because no code changed. What *is* red-then-green is the existing
`test-worker-mcp-all-arms.sh` negative-control suite itself (items 7-9,
above): its mutation cases go red on the mutant and green on the real code,
proving the suite is falsifiable, not just green by construction.

## Restored files (branched-early cleanup)

`git diff --stat main..HEAD` showed 4 files this lane would have deleted
purely because it branched before `main` gained them — restored verbatim
from `main`, unrelated to this task's own change:
`docs/handoff/CONTROL-PLANE-HAS-NO-OWNER-01/census.md`,
`docs/handoff/SUBSCRIPTION-MIX-DECISION-01/assessment-claude.md`,
`docs/handoff/SUBSCRIPTION-MIX-DECISION-01/data-pack.md`,
`docs/handoff/TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01/brief.md`.

## What is still missing (reported, not buried)

- **Item 11's concrete wiring** (`m3` and the rest) is not applied — blocked
  by this session's write permission on files outside the worktree. The
  exact JSON is above; a session with that permission (or the founder by
  hand) needs to apply it.
- **Item 3's "resolution" is diagnosed and scoped, not code-changed** — the
  resolver itself is correct; the fix is the repo wiring above, which
  couldn't be applied.
- **Item 10's paired single-task A/B is explicitly not done** — see that
  section; only the aggregate historical number exists.
- **Item 4's acceptance criterion is not met by any dispatch found on this
  machine** — this is the round's main finding, not a gap in the
  investigation.
- **`sonnet` arm's fail-open cause** (the `LEADV2_SUBSESSION_SLIM_MCP`
  default) is named but not changed — out of the brief's stated scope.

## Round 3 — item 5 actually wired to a surface, item 10's block reconfirmed

Round 2 shipped `leadv2-code-intel-rate.sh` (a CLI) but nothing called it —
`grep -rl leadv2-code-intel-rate plugins/leadv2/scripts` found only the
script itself. A tool nobody runs is exactly the "cannot silently regress to
0/5 again" failure item 5 was written to prevent, so this round closes that
gap.

### Item 5, closed: wired into founder-status via the repo_facts hook

`leadv2-status-collector.sh` already has a per-repo extension point for
exactly this shape (`_sc_repo_facts_section`, sourcing
`.claude/leadv2-overrides/status-collector-facts.sh` if present, folding its
one JSON object into `docs/leadv2/status-snapshot.json`'s `repo_facts`
section) — this repo (leadv2 itself) had never populated that hook. Added
`.claude/leadv2-overrides/status-collector-facts.sh` defining
`collect_repo_facts()`, which shells out to `leadv2-code-intel-rate.sh` and
folds its summary line + per-arm breakdown into two flat keys
(`code_intel_attach_rate`, `code_intel_by_arm`). `render_repo_facts()`
(`leadv2-status-surface.sh:3275-3307`) already prints every `repo_facts` key
on `--mode all`/`--mode repo-facts`, which is the path `founder-status.md`
reads — so the rate is now on the surface the founder actually sees, with
zero new rendering code.

Verified the hook directly (isolated call, not the full collector, which
timed out in this sandbox for unrelated reasons — some other section hangs
here; not investigated, out of scope):

```
$ PROJECT_ROOT="$(pwd)" bash -c 'source .claude/leadv2-overrides/status-collector-facts.sh; collect_repo_facts'
{"code_intel_attach_rate": "code-intel attach rate: 0 decisions recorded", "code_intel_by_arm": "no data"}

$ # scratch tree with 1 attached, 1 fail_open, 1 arm_unwired:
{"code_intel_attach_rate": "attach rate among MCP-capable arms (excludes codex arm_unwired): 1/2 = 50%", "code_intel_by_arm": "codex:arm_unwired=1 glm-flash:attached=1 sonnet:fail_open=1"}
```

New suite `test-status-collector-facts.sh` (10 cases: valid-JSON contract,
honest zero on an empty tree, real percentage + per-arm breakdown on a
populated scratch tree, graceful `"unavailable"` when the rate script is
missing — never a crash, matching the collector's own per-section isolation
contract). Registered by self-select convention
(`plugins/leadv2/scripts/tests/test-status-collector-facts.sh`).

`tests/run-all.sh`'s `--scope changed` carrier map needed a new stem row: the
hook lives under `.claude/leadv2-overrides/`, not `plugins/leadv2/scripts/`,
so the generic scripts allowlist in the else-branch would `continue` past it
and select zero suites for a hook-only change (same shape as the existing
`.gitignore`/`freepool-arm.yaml` special cases). Added the `elif` mapping
`stem="status-collector-facts"`.

**Negative control, isolated to only the hook file being "changed"** (the
brief's item 7/9 shape — force it to fail, show red/dropped; revert, show
selected again):

```
$ # only .claude/leadv2-overrides/status-collector-facts.sh dirty, elif mapping PRESENT:
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-status-collector-facts.sh   <-- present
[SELECT] .../tests/test-run-all-carrier-map.sh
run-all: 6 selected, scope=changed, select_only=1

$ # same dirty file, elif mapping REMOVED (mutant tests/run-all.sh):
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
[SELECT] .../tests/test-run-all-carrier-map.sh
run-all: 5 selected, scope=changed, select_only=1   <-- test-status-collector-facts.sh dropped
```
tests/run-all.sh restored to the mapped version afterward (`diff` against
the pre-mutation backup showed zero difference); the mutant was never
committed.

A real cross-platform bug surfaced building this: the test's `run_hook()`
originally set `PROJECT_ROOT` via `PROJECT_ROOT="$X" source "$HOOK"` (prefix
assignment on a `source` command). Whether that assignment persists into
later commands in the *same* shell is a POSIX special-builtin nuance that
measurably differs between bash builds — green on this machine's bash, but
`PROJECT_ROOT: unbound variable` under `set -u` on bash 5.2 in the Linux
container (caught by item 8's own macOS+Linux gate, not by inspection).
Fixed to a plain assignment before `source`, matching how
`leadv2-status-collector.sh`'s own `_sc_repo_facts_section` actually does it
in production (which was never at risk — it never used the prefix-assignment
idiom). 10/10 green on both platforms after the fix; see the exit codes
below.

### macOS

```
$ bash plugins/leadv2/scripts/tests/test-status-collector-facts.sh
[TEST] PASS: bash -n .../status-collector-facts.sh
[TEST] PASS: case1: collect_repo_facts exits 0
[TEST] PASS: case1: output is exactly one valid JSON object
[TEST] PASS: case1: both expected keys present
[TEST] PASS: case2: empty tree reports 0 decisions honestly
[TEST] PASS: case2: by_arm reports 'no data' when nothing recorded
[TEST] PASS: case3: populated tree surfaces the real attach-rate percentage
[TEST] PASS: case3: per-arm breakdown present in by_arm
[TEST] PASS: case4: missing rate script does not crash the hook
[TEST] PASS: case4: missing rate script reports 'unavailable', not a fabricated rate
=== SUMMARY: 10 passed, 0 failed ===
EXIT_CODE_MACOS=0
```
Pre-existing suites re-run clean, no regression:
`test-leadv2-code-intel-rate.sh` → 10 passed, 0 failed.
`test-worker-mcp-all-arms.sh` → TOTAL: PASS=49 FAIL=0.

### Linux container (`python:3.12-slim`, bash 5.2.37, aarch64; same
main-checkout `.git` mount as round 2)

```
$ docker run --rm -v .../leadv2:/.../leadv2 -w .../CODE-INTEL-IS-INSTALLED-AND-UNUSED-01 \
    python:3.12-slim bash -c '
  apt-get update -qq && apt-get install -y -qq git
  bash -n .claude/leadv2-overrides/status-collector-facts.sh; echo rc_hook=$?
  bash -n plugins/leadv2/scripts/tests/test-status-collector-facts.sh; echo rc_test=$?
  bash -n tests/run-all.sh; echo rc_runall=$?
  bash plugins/leadv2/scripts/tests/test-status-collector-facts.sh; echo EXIT_CODE_LINUX=$?
'
rc_hook=0
rc_test=0
rc_runall=0
=== SUMMARY: 10 passed, 0 failed ===
EXIT_CODE_LINUX=0
```

### Falsification set (round 3's own changed files)

```
$ bash -n .claude/leadv2-overrides/status-collector-facts.sh; echo $?
0
$ bash -n plugins/leadv2/scripts/tests/test-status-collector-facts.sh; echo $?
0
$ bash -n tests/run-all.sh; echo $?
0
```
No Python files changed. The red-then-green pair for this round is the
`PROJECT_ROOT: unbound variable` failure documented above (red on Linux
bash 5.2, green after the plain-assignment fix, on both platforms) plus the
selection negative-control (red/dropped with the `elif` mapping removed,
green/selected restored).

### Item 10, reconfirmed blocked (not re-attempted-and-hidden)

Re-tried the live paired-A/B call from this session
(`mcp__repowise__get_answer`, same question shape as round 2: who calls
`worker_mcp_preamble_for_arm()` and what breaks if its rc=3 branch silently
succeeded) via a fresh subagent call, in case this round's session had
different MCP grants:

```
Permission to use mcp__repowise__get_answer has been denied.
```

Same result as round 2 — this is not a one-off fluke, it reproduces on a
second, independent attempt. The paired single-task A/B claim remains
withdrawn; the aggregate 2026-08-25 number is the only real evidence, and it
was already flagged in round 2 as measuring calls that (per item 4) are not
demonstrably coming from dispatched workers acting on an attached preamble.

### Item 11, unchanged

Still blocked by the worktree/write-root boundary — `m3`'s `.mcp.json` is
outside this lane's writable scope by the mission's own explicit rule
("Writable scope — $WRITE_ROOT... Main-repo paths are off-limits during
worktree tasks", doubly true for a repo entirely outside `leadv2`). Not
reattempted this round because attempting it would itself be a protocol
violation, not a permission accident to route around. The exact JSON to
apply and the `LEAD_ACTION` are unchanged from round 2, above.

### What changed vs round 2's "still missing" list

- Item 5 is now genuinely closed (was: script exists, unused).
- Items 4, 10, 11 are unchanged and reconfirmed, not re-guessed.
