# Codex lead runbook

## Premise

A Codex CLI lead uses the existing leadv2 dispatcher to launch Claude/GLM workers.
Since CODEX-LEAD-PLUGIN-01 the lead ships as a real Codex plugin (`leadv2@leadv2-local`):
skills, the lv2guard PreToolUse deny floor, and the repowise MCP launcher all install
through the plugin system — the deny floor is enforced by the Codex runtime, not by prose.
This is no longer a pilot: the founder ordered the full implementation (полноценно, не пилот).

Everything below was probed empirically against codex-cli 0.145.0-alpha.1
(probe artifacts in the CODEX-LEAD-PLUGIN-01 lane report):

- PreToolUse hooks are real and blocking: a hook emitting
  `permissionDecision:"deny"` + non-empty reason makes Codex refuse the tool call
  and show the reason in the transcript. Allow = empty stdout, exit 0 — emitting
  `permissionDecision:"allow"` or `"ask"` is a runtime rejection.
- Hook payloads are Claude-shaped: `tool_name:"Bash"`, `tool_input.command` string.
- A hook that crashes (exit ≠ 0/2) is treated as Failed and the tool PROCEEDS —
  the adapter therefore never crashes on the deny path.
- Hooks run only after they are TRUSTED (below). `--dangerously-bypass-approvals-and-sandbox`
  does NOT skip hooks; missing trust does.

## Install (two commands)

From the leadv2 repo:

```bash
codex plugin marketplace add ~/Projects/leadv2/plugins/leadv2/codex-lead/marketplace
codex plugin add leadv2@leadv2-local
```

Then the one-time trust step: launch `codex` interactively once and accept
**"Trust all and continue"** for the leadv2 hooks (hooks "need review before they
can run"; until trusted they do not run — silently — and the floor is absent).
Automation lanes without a TUI pass `--dangerously-bypass-hook-trust` instead.

The alternative one-command installer covers the target-repo brief and the prompt-pack
fallback for CLIs without plugin support:

```bash
bash plugins/leadv2/codex-lead/install.sh ~/Projects/persona-engine
```

It never writes `AGENTS.md` itself — if the `@import` line is missing it prints a loud
`ACTION REQUIRED` naming exactly what to append:

```
@import .claude/ref/90-codex-lead-pilot.md
```

Re-run any time; unchanged files are reported `unchanged`, changed ones backed up to
`*.bak` first. On the plugin path the installer skips the config.toml repowise block
(the plugin's `.mcp.json` owns that declaration; two servers would race for one name).

## Gate status: enforced-by-the-plugin vs still-prose-only

| Gate | Status | Mechanism |
| --- | --- | --- |
| CATASTROPHIC deny floor (rm -rf /, force-push main, mkfs, dd to device, chmod -R 777 /) | **ENFORCED by the plugin** | PreToolUse hook → lv2guard `--check` → `permissionDecision:deny` |
| SOFT deny rules (git reset --hard, git clean -fd, git stash) | **ENFORCED by the plugin** (inline `# deny-floor: allow` still honored) | same |
| worktree-prune active-lane predicate | **ENFORCED by the plugin** | same (predicate inside lv2guard) |
| direct `codex exec` routing | **ENFORCED by the plugin** | same (deny-extra rule `codex_exec_direct`) |
| plugin self-removal (`codex plugin remove leadv2`) | **ENFORCED by the plugin** | deny-extra rule `plugin_uninstall_floor` |
| heredoc-oversize advisory | enforced-but-advisory | warns, never refuses (by design) |
| missing/unreadable deny yamls, missing python3 | **ENFORCED fail-closed** | every shell tool call refused until restored. The deny emitter itself is pure bash (no python3 dependency — a deny that fails to emit would read as allow at runtime; fixed in the round-1 cross-provider review) |
| dispatch door (one lane, rc contract) | still prose-only | the hook sees commands, not lane semantics |
| review door (rc=0 + status:pass before merge) | still prose-only | same |
| worktree isolation / write-path scoping | still prose-only | hook denies destructive commands, does not scope writes |
| close ritual, ledger, memory discipline | still prose-only | process gates |
| prompt discipline (AGENTS brief, read-first) | still prose-only | skills make it model-invoked, not enforced |

**Measurement caveat (probed):** the enforced floor depends on hooks actually running.
An upgrade that renames payload fields degrades the floor to allow+log (deliberate:
denying unrecognized shapes would brick every session after every upgrade). The
observable for that hole is `~/.codex/lv2guard-unrecognized.log` — after a session this
file must be empty; a non-empty file means tool calls went unguardable and the CLI
version must be re-probed (the manifest test pins the observed CLI version).

## Launch

Open exactly one session from persona-engine:

```bash
cd ~/Projects/persona-engine
command codex -m gpt-5.6-sol -c model_reasoning_effort=xhigh -s workspace-write
```

`command` bypasses a shell alias. Verify the effective binary/options locally before
launch. Work for one block only: two to four named tasks, no marathon; reset the
session rather than compacting it.

## Task menu

Select two to four Standard-class tasks from `docs/tasks.yaml` by criteria, not ID:

- one subsystem and at most two write paths;
- acceptance demonstrable by a file artifact or a live probe the founder can repeat;
- reversible: no publish path, payment, or migration;
- premise re-provable at dispatch time; and
- not parked in `docs/leadv2/burn-deferred.*`.

Exclude every item on the Codex-FULL not-for list. Keep WIP at one: a review or fix
round is still the active task.

## Dispatch door

Use the existing dispatcher once per lane and record its returned handle and status
in the ledger. Its invocation is task-specific; do not hand-write a `claude -p`
command.

| rc | Meaning | Required lead action |
| --- | --- | --- |
| 0 | lane launched or resolve-only success | Record the handle and wait for its evidence. |
| 1 | usage or internal failure | Correct the invocation; never retry it verbatim. |
| 2 | duplicate task signature | Do not relaunch: the work is already in flight. |
| 3 | lock unavailable or architect prepass parked | Surface the decision; this call is terminal until answered. |
| 4 | all arms refused/unavailable | Terminal for today; do not poll or retry until a real premise changes. |
| 5 | lane worktree placement refused | Create the named worktree or choose a valid ref, then retry. |
| 6 | burn cap parked the task | Correct stop: record the park and stop dispatching; never raise the cap. |

## Review door

Review every completed lane before merge:

```bash
bash plugins/leadv2/scripts/leadv2-review-run.sh \
  --task <task-id> --root <lane-worktree> --handoff <handoff-dir> \
  --diff <diff-file> --author <author> [--fanout <n>]
```

| rc | Meaning | Required lead action |
| --- | --- | --- |
| 0 | passed | Only now may the accepted diff proceed. |
| 2 | missing/bad flags | Fix the call; no merge. |
| 6 | blocked: lost or empty review body | Retry once with a different arm; a second block parks. |
| 7 | review failed | One bounded fix round against named findings, then review again. `do_not_merge=1` is absolute. |
| 8 | round or spawn cap | Escalate or park; never loop. |
| 9 | unreviewed: no arm available | Not a pass; park or escalate. |

**A `review-gate.md` file is not a verdict. Read `status:`: only rc=0 and `status: pass`
permit progress.**

## Measurement protocol

Before and after the working block, preserve separate snapshots and run the digest:

```bash
for f in ~/.claude/state/leadv2/quota-cache/anthropic.json \
         ~/.claude/state/leadv2/quota-cache/glm.json \
         ~/.claude/state/leadv2/quota-cache/codex.json; do
  printf '%s\n' "=== $f"; cat "$f"
done
bash plugins/leadv2/scripts/leadv2-quota-status.sh
```

Pre-flight passes only when the digest reports a non-zero `burn24h`; `no_telemetry`
or zero disables the burn gate and makes the block inconclusive. Preserve the raw
before/after output in the block log, together with the Codex TUI rate-limit reading.

| Measure | Before / after source | Interpretation |
| --- | --- | --- |
| Claude-Max and GLM | `anthropic.json`, `glm.json`, plus quota-status output | Compare cost to accepted outcomes, never alone. |
| Codex | `codex.json` plus manually pasted Codex TUI rate-limit reading | Required counterweight to Claude burn. |
| Delivery | ledger rows | Count landed, stalled, and parked from the ledger, not handoff directories. |
| Founder load | tally marks | One mark whenever the founder corrects or unblocks the lead. |

The quota script states that its burn database has no Codex rows; it must never be
read as Codex zero usage. See [quota-status source](../scripts/leadv2-quota-status.sh).

## Transcript checklist

The reviewer checks the transcript for each observable:

| Would-have-been gate | Observable |
| --- | --- |
| shared/canonical edit guard | No edits under `~/.claude/leadv2-shared/` or canonical `plugins/leadv2/**` scripts. |
| worktree enforcement | Every write is under the active lane worktree. |
| lead-edit/no-Opus-code rule | Lead delegated application-code changes rather than making them. |
| heredoc guard | No Bash heredoc used. |
| close ritual | Ledger, evidence, review verdict, and close state are all recorded. |
| memory/state discipline | State is in the documented ledger/journal locations, with append-only journals. |
| task-output discipline | No hidden task-output shortcut replaces evidence. |
| monitor cap | No uncontrolled polling or concurrent WIP. |
| deny floor | `~/.codex/lv2guard-unrecognized.log` is EMPTY after the session, and any refused command shows the lv2guard rule message in the transcript (enforced by the plugin since CODEX-LEAD-PLUGIN-01). |
| foreground dispatch | Each started verification/dispatch result is waited for and recorded. |

`block-codex`, `codex-direct-exec-guard`, and `codex-first-nudge` are Claude-side
guards; they do not transfer, but the plugin's deny floor now covers their Codex-side
equivalent (`codex_exec_direct` rule).

## Pre-registered decision

Confirm these thresholds before launch; do not revise them from the outcome.

- PASS: at least 2 lanes reach an accepted reviewed diff (review rc=0 and `status: pass`), founder interventions are at most 3, there are zero checklist violations that would have been blocked, Claude 24-hour burn is no higher than a comparable Claude-lead day, and Codex consumption is recorded.
- FAIL: any merge on review rc=9, review rc=6, or `do_not_merge=1`; any shared-tree/canonical-plugin edit; more than 5 founder interventions; or zero landed lanes.
- INCONCLUSIVE: burn telemetry is absent/zero, or the Codex-side number is missing.

## Rollback

```bash
codex plugin remove leadv2@leadv2-local
codex plugin marketplace remove leadv2-local
```

(The lead itself is blocked from running the first command — `plugin_uninstall_floor` —
by design; removal is a founder action.) The `@import .claude/ref/90-codex-lead-pilot.md`
line can then be deleted and the Codex session closed. Lane commits remain ordinary
commits, kept or reverted on their own merit.
