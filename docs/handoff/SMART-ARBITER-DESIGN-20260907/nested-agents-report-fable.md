# Nested agents: depth 1 / read-only / two-type allowlist — fable arm

Task `dispatch-62f2f47e`, lane `40c0337e885f`, base `34e9fefa`, 2026-09-08. Report only; no
workflow, script or config was modified. A second arm answers the same mission into its own file;
this report was written without reading it.

## Decision in one paragraph

Keep `max_depth: 1`. Keep `tool_class: read_only` for what the yaml actually governs. Let the
arbiter pick the nested arm, but recognise that it already does — since 2026-09-04 every Agent
spawn, nested or not, must match a recorded arbiter decision, and the static allowlist stacked on
top of that is precisely what makes both allowlist entries unreachable today. The fix for that is
the already-filed task `10ee163f7a3e`, not a new mechanism: the arbiter must not decide an arm the
Agent tool cannot run. Codex and GLM are a second question with a different executor and different
hooks; this report does not answer it. Two facts change the framing more than any of the four
answers: the nested-spawn policy has produced **zero allowed spawns in its entire life**, and the
lane-worker prompt that promises "nested agents" describes a population the yaml does not govern.

## 0. Measured facts (each with its artifact)

**F1 — the policy is what the mission quotes.** `plugins/leadv2/config/nested-spawn-policy.yaml:26-28`
reads `max_depth: 1`, `max_nested_per_task: 3`, `tool_class: read_only`; base allowlist
explore/general-purpose at haiku|sonnet (`:30-37`); per_caller developer→explore(haiku),
architect→general-purpose(sonnet) (`:39-47`). Read by `plugins/leadv2/hooks/leadv2-routing-guard.sh:108-143`.

**F2 — there are two populations called "nested", and the yaml governs only one.**
The routing guard enters its nested path only when the hook input carries `agent_type`
(`leadv2-routing-guard.sh:62-63`: "agent_type is injected by Claude Code only for subagent callers;
lead has no agent_type"). Population A: an Agent-tool subagent (critic, architect, explore …)
spawning another Agent. Population B: a dispatched lane worker — a headless `claude -p` session
launched by `leadv2-dispatch-code.sh` — spawning an Agent. The lane prompt at
`leadv2-dispatch-code.sh:6137-6146` addresses population B ("You may spawn nested subagents for
bulk reads, censuses, or mechanical edits … sonnet for edits"). For population B the nested yaml
never fires; what fires is the common PreToolUse:Agent chain from `hooks/hooks.json`, in order:

```
block-fg-agent, spawn-arbiter-gate, codex-first-nudge, worktree-enforce, tool-blowup-gate,
routing-guard (LEAD path = warn-only), model-inherit-guard, gate-artifact-guard,
blocker-drift-guard, thinking-audit-gate, workflow-bypass-guard, judge-shaped-agent-guard
```

UNVERIFIED: that a headless `claude -p` session's hook input carries no `agent_type`. It is
inferred from the guard's own comment and from the audit log (every recorded caller is an
Agent-tool type), not from a live dump of hook input. One scratch hook writing `agent_type` to a
file from inside a lane would settle it.

**F3 — population A has never been allowed to spawn anything.** The entire audit history:

```
$ find docs/leadv2 -name nested-spawns.log -exec cat {} +      # main checkout, read-only
2026-08-04T17:21:56Z caller=general-purpose target=developer model= verdict=deny reason=route.subrun.write_role_denied
2026-08-04T17:21:56Z caller=general-purpose target=developer model= verdict=deny reason=route.subrun.write_role_denied
$ find docs/handoff -name escalation-budget.yaml | wc -l
0
```

Two lines, one event, zero `verdict=allow`, zero escalation budgets ever issued. The scorecard's
`nested_spawns` field counts `verdict=allow` lines (`leadv2-scorecard-write.sh:236-243`), so it has
read 0 in every scorecard ever written. That is the never-varied value this report keys on.

**F4 — both allowlist entries are unreachable as written, and the mechanism is the stack, not
one gate.** Arbiter decision journal (`$TMPDIR/leadv2-route-arbiter-decisions.jsonl`, 359 rows):

```
4  ('recon', 'Explore', 'freepool')        # every recon decision for subtype Explore
arm,model strings: ('freepool','freepool-default') x11, ('haiku','haiku') x2
```

The arbiter treats `recon` as a first-class read-only kind (`scripts/lib/leadv2-route-arbiter.sh:181,186,199,221-223`)
and `cheapest_capable` picks freepool (cost 1, `config/leadv2-routing.yaml:212`) over haiku
(cost 2, `:216`). Then, for `Agent(subagent_type="Explore", ...)`:

| spawn form | model-inherit-guard `:60-63` | spawn-arbiter-gate `:96` | routing-guard allowlist `:214-218` |
|---|---|---|---|
| no `model=` | DENY (built-in inherits caller) | — | — |
| `model=haiku` | pass | DENY (decided `freepool-default` ≠ `haiku`) | — |
| `model=freepool-default` | pass | pass | DENY (not `haiku`/`sonnet` substring); Agent tool has no such model |

The only passing path is "freepool excluded or in outage → arbiter decides haiku → pin
`model=haiku`". The journal shows haiku decided twice in 359 rows. This confirms the mission's
input and is the body of `10ee163f7a3e`; it is not re-diagnosed here beyond what the design needs.
The Agent tool's model space is closed: its schema in this session enumerates
`model: ["sonnet","opus","haiku","fable"]` — no freepool, glm, kimi or codex arm exists there.

**F5 — `max_nested_per_task` is dead for Claude lanes.** The per-task count log is keyed on
`LEADV2_TASK_ID` (`leadv2-routing-guard.sh:232`); when it is empty the guard takes the
"No task id: record forensics, never cap" branch (`:268-271`). Exporters of that variable:

```
$ grep -rnE 'export LEADV2_TASK_ID|LEADV2_TASK_ID=' plugins/leadv2/scripts | grep -v tests/
leadv2-backlog-pump.sh:762,767   leadv2-codex-session-runner.sh:44   leadv2-kimi-session-runner.sh:68
leadv2-codex-lead.sh:31          (leadv2-dispatch-code.sh: 0 hits)
```

Codex and kimi runners export it and never call the Agent tool; the Claude lane launch does not
export it. So the count cap has never had a task to count against.

**F6 — `LANE_WRITES` is enforced per lane, at dispatch and at close, never at write time, and it
is agent-blind.** Mechanism 1 refuses a dispatch whose mission demands a path outside
`LANE_WRITES` (`leadv2-dispatch-code.sh:541-548`, `lib/leadv2-mission-writeset.sh`);
`leadv2-acceptance-shape.sh:28-35` reads `lane_writes:` for precedence; `leadv2-mutation-control.sh:23-26`
hashes `git diff <base> HEAD` of the lane's committed history. No PreToolUse:Write hook references
`LANE_WRITES` (grep over `hooks/*.sh` hits only `lib/leadv2-hook-session-kind.sh:77`, which uses the
string to classify a session as `worker`). A child's writes inside the lane worktree are therefore
indistinguishable from the parent's at close — which is exactly why the contract survives
delegation unchanged.

**F7 — write-capable spawns are happening somewhere, ungoverned by the nested yaml.**
`~/.claude/leadv2-state/leadv2/direct-spawn-gate.jsonl`, 94 rows: `deny 45, sanctioned_bypass 39,
allow_with_reason 10`; denied subtypes led by `developer 12, 04-go-developer 8, 02-react-developer 6`.
The gate's default mode is `warn` (`leadv2-codex-first-nudge.sh:42`), so a journaled `deny` did
not stop the spawn. The journal carries `session_id` but no task id or caller kind, so these rows
cannot be attributed to lanes vs lead sessions. The demand for write-capable children is real
and unmeasured per lane.

**F8 — codex CLI surface, probed.**

```
$ codex --version
codex-cli 0.153.4
$ codex --help | grep -E '^\s{2}[a-z-]+'      # subcommands
agents  exec  review  login  logout  mcp  plugin  mcp-server  app-server  remote-control
app  completion  update  doctor  sandbox  debug  apply  resume  queue  archive
```

`mcp-server`, `agents`, `exec` and `app-server` exist. `exec-server` and `cloud`, named in the
mission text, are not subcommands on this version.

## 1. Is depth 1 correct? — Yes. Keep it.

A task shape that genuinely needs a grandchild would be: lead → reviewer → Explore → Explore, or
lane worker → sub-orchestrator → workers. I could not name one from this repo's work. The first is
a wider fan-out wearing a hat: whatever the middle Explore would delegate, the reviewer can spawn
directly (three probes at depth 1 are the same cost as one probe that spawns two). The second is
a second lead inside a lane, with no registry entry, no arbiter journal of its own, no
`LANE_WRITES`, and no close gate — every property the doctrine puts in `dispatch-code.sh` and the
arbiter, re-created ad hoc by prose. The platform's depth-3 default exists for agent teams, which
leadv2 deliberately does not run inside a lane.

Two honesty notes on the cap as implemented. First, the depth check identifies "already nested"
callers by type name — `explore|general-purpose` (`leadv2-routing-guard.sh:163-170`) — not by any
depth counter; a caller typed `claude` or a namespaced agent is not in that list. UNVERIFIED: I did
not probe whether Claude Code exposes a depth value in hook input; if it does not, the real depth
enforcement is the platform pin `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=2`, and the yaml's
`max_depth` is documentation of intent. Second, depth 1 has never been exercised (F3), so "is depth
1 enough" has no empirical side yet. That is a reason to leave it, not to widen it.

Measurement: the value is the count of `reason=route.subrun.depth_exceeded` lines in
`nested-spawns.log`. Today 0, emitted at `leadv2-routing-guard.sh:166`. Negative control: set
`max_depth: 2` in a scratch per-repo override and spawn from an `explore` caller — the deny line
must stop appearing and an `allow` must appear; if the file edit changes nothing, the cap is inert
and the platform pin is doing all the work.

## 2. Is `tool_class: read_only` correct? — Yes for population A. It does not reach population B.

What it costs today, measured: for population A, the whole recorded demand for a write-capable
child is the one 2026-08-04 event (F3). The cost is not zero — that caller wanted a developer child
and had to return a blocker — but it is one event in a month, against zero allowed reads. For
population B the yaml costs nothing because it does not apply (F2); what a lane worker pays
instead is the arbiter gate (F4): a `developer` child needs a recorded decision, the arbiter
decides `glm`/`glm-5.3` for build (journal: `('build','developer','glm') x4`), and the Agent tool
cannot run that arm, so the only passing form is an unpinned spawn whose frontmatter model runs
while the journal says glm. That is a truth gap in the journal, not a block on the worker.

Could write authority be granted without making `LANE_WRITES` unenforceable? For population B it
already is granted and the contract already holds: the child writes in the lane worktree, the
lane's committed diff is what mutation-control hashes, and the diff does not know which agent
wrote a hunk (F6). The prompt's "sonnet for edits" is therefore consistent with the close gate.
For population A the answer is no: those subagents run in the lead's checkout, not a lane
worktree; there is no `LANE_WRITES` to check against; and a write-capable child there is a direct
write-capable spawn one level down — the thing `direct-spawn-gate.yaml` exists to deny by default.
`route.subrun.write_role_denied` is the same posture applied recursively and should stay.

Recommendation: keep `tool_class: read_only`. Change nothing in the policy. The one defect worth a
task is documentary: the yaml header and `NESTED-SPAWNS.md` describe population A, the lane prompt
describes population B, and both use the word "nested" — a reader of either believes the other is
covered. The lane prompt should say which gates actually bind a worker's spawn (arbiter gate,
worktree-enforce, inherit-guard) and that the nested yaml is not among them.

The missing value: a per-lane count of Agent spawns issued by the worker session. It does not exist.
It would be emitted at `leadv2-routing-guard.sh:86-103` (`_audit_log`) if the Claude lane exported
`LEADV2_TASK_ID` the way the codex/kimi runners do (F5) — a one-variable change in the lane launch
that also revives `max_nested_per_task`. Negative control: launch a lane without the export; the
per-task log must not appear and the global log must still record the spawn.

## 3. Should the arbiter pick the nested agent? — It already must. Finish that, do not add a second chooser.

Same kind of decision or different? The arbiter maps (work_kind, size, tags, hard flags) to (arm,
model, tier) over the capability matrix with `cheapest_capable`. A nested spawn's choice is (type,
model) where type is a tool set the caller needs (Explore = read-only search; general-purpose =
synthesis with tools) and model is the arm. Split the two: the **type** is the caller's decision,
exactly as the dispatcher, not the arbiter, decides a lane's role; the **model** is the same kind
of decision the arbiter makes for a lane arm — cheapest capable for `recon`. The arbiter already
owns `recon` as a kind (F4) and the spawn-arbiter-gate already binds every Agent spawn to a
decision (founder order 2026-09-04, `leadv2-spawn-arbiter-gate.sh:1-10`).

What differs, and it is the whole defect: the arbiter's answer space contains arms the Agent tool
cannot execute, and it has no input saying "the executor is the Agent tool". So it answers
`freepool-default` for a recon Explore (F4), and the spawn cannot honour a decision it cannot run.
The static allowlist in the yaml then denies whatever the arbiter did decide. Two choosers, each
correct alone, jointly unreachable — which is why the allow-count is zero for life.

Recommendation: yes, the arbiter picks the model for nested spawns, under one added input
(executor = agent-tool → eligible cells restricted to `provider: claude`), and the yaml's
`base_allowlist`/`per_caller` model lists go away in favour of the arbiter's record. The yaml
keeps what the arbiter cannot express: `max_depth`, `max_nested_per_task`, `tool_class`. This is
the same seam as `10ee163f7a3e`; design it once there, not twice. It is **not ready to ship from
this report**: it needs that task's fix landed first, and it needs the `LEADV2_TASK_ID` export
(F5) or the per-task cap stays dead under the new chooser too.

Measurement, day one: `verdict=allow` lines in `docs/leadv2/nested-spawns.log` — 0 in the file's
whole life (F3), emitted at `leadv2-routing-guard.sh:237` (task path) and `:270` (taskless path).
First reachable Explore moves it to ≥1. Second value: arbiter journal rows with
`subtype=Explore, arm=freepool` — 4 of 4 today — must go to 0 under the executor filter. Negative
control for both: mutate the filter to admit freepool; the journal returns `freepool-default`, the
inherit-guard/arbiter-gate pair refuses every spawn form again, and the allow-count stays 0.

## 4. Do codex and GLM belong here? — Two questions. This report answers only the first.

A nested spawn is an Agent-tool call; the tool's model space is `sonnet|opus|haiku|fable` (F4) and
there is no codex or GLM arm in it. "Codex inside a lane" is a Bash-launched external process —
`codex exec`, or `codex mcp-server` wired as an MCP tool (F8) — with its own hooks already in the
chain (`leadv2-block-codex.sh`, `leadv2-codex-direct-exec-guard.sh`, `leadv2-codex-nopoll-guard.sh`)
and its own journal. Different executor, different gate, different evidence; the arbiter's full
arm set applies there and only there. The two questions meet at exactly one point, later: the
executor input proposed in §3 is the same knob that would tell the arbiter "this spawn is
Bash+codex, the whole matrix is eligible". That is the only design dependency, and it is a reason
to decide §3 first, not to merge the questions. The mission's list of codex features should be
corrected: on 0.153.4 the subcommands are `agents`, `exec`, `mcp-server`, `app-server`;
`exec-server` and `cloud` do not appear.

## Summary table

| Q | Decision | Change now? | Value to watch (today) | Emitted at |
|---|---|---|---|---|
| 1 depth | keep 1 | none | `depth_exceeded` denies (0) | routing-guard.sh:166 |
| 2 read-only | keep for A; B is not governed by it | doc/prompt wording only | per-lane Agent-spawn count (does not exist) | would be routing-guard.sh:86-103 |
| 3 arbiter | arbiter picks model, yaml keeps depth/count/class | not from this report — it is `10ee163f7a3e` | `verdict=allow` count (0 for life); recon/Explore→freepool rows (4/4) | routing-guard.sh:237,270; arbiter journal |
| 4 codex/GLM | different question | none here | — | — |

## Open at my level

- Whether headless lane sessions present `agent_type` in hook input (decides whether population B
  could ever be governed by the nested yaml without a session-kind check). Needs one scratch hook
  run inside a lane.
- Whether Claude Code exposes spawn depth in hook input (decides whether `max_depth` is enforced
  or documented). Needs the same dump.
- Whether the founder wants population B counted per lane. Needs a yes; the mechanism is F5.

## Self-check

No shell or Python file was changed, so `bash -n` and `py_compile` have nothing to check; the
changed-scope runner's output on this docs-only diff is pasted in `docs/handoff/dispatch-62f2f47e/developer.full.md`.
