# CODEX-PULSE-HOOK-02 — architect prepass (scoped design)

Base: feb253b. Scope: Codex-native lead profile only (`plugins/leadv2/codex-lead/**`
+ its docs/tests). No application changes, no Claude-side runtime changes.

## 1. What exists today (verified in-tree, not from memory)

| Fact | Evidence |
|---|---|
| Codex plugin registers exactly three hook events | `codex-lead/marketplace/plugins/leadv2/hooks.json` — `PreToolUse` (matcher `.*` → `lv2guard-pretooluse.sh`), `SubagentStart`, `SubagentStop` (→ `leadv2-subagent-lifecycle.sh start|stop`) |
| Live native-agent state is a per-agent file registry | `hooks/leadv2-subagent-lifecycle.sh` writes `<sha256(agent_id)>.json` with `started_at`/`last_pulse` into `$LEADV2_NATIVE_AGENT_REGISTRY` (default `$CLAUDE_PLUGIN_ROOT/.native-agent-registry`), atomic `os.replace`, `stop` unlinks |
| PreToolUse stdout contract in use = empty (allow) or `{"permissionDecision":"deny",...}` | `codex-lead/tests/test-codex-hooks.sh` `allow()`/`deny()` assertions |
| The 60s cadence is today a *prose rule for the model*, not a machine timer | `prompts/leadv2-status.md` and `docs/codex-lead-AGENTS-pilot.md:16-17` — "Do not claim a 60-second machine timer" |
| External lane/task facts come from two shell producers | `prompts/leadv2-status.md` → `codex-lead/leadv2-codex-status.sh`, `scripts/leadv2-status-surface.sh --oneline` |
| Plugin cache-bust is the manifest version | `marketplace/plugins/leadv2/.codex-plugin/plugin.json` → `1.0.0+codex.20260824225325` |

UNVERIFIED: whether the Codex CLI renders a `hookSpecificOutput.additionalContext`
(or `systemMessage`) field from a `PreToolUse` hook into the lead transcript. No
probe artifact exists in-tree; nothing in `hooks.json`, the hook scripts, or the
tests exercises a non-deny stdout payload. **This single unknown is what decides
whether the pulse reaches chat, so the lane must probe it before wiring — see §5
step 0 and Risk R1.**

## 2. Design — event-driven pulse, no fabricated timer

The honest primitive: **Codex hooks fire only on lead activity.** There is no
idle/tick event in the three registered ones. So the pulse is defined as
*change-or-cadence, evaluated on every tool call*:

```
PreToolUse (.*)  ──▶ lv2guard-pretooluse.sh        (unchanged, still first)
                 └─▶ leadv2-native-pulse.sh        (new, second entry, never decides permission)
SubagentStart/Stop ─▶ leadv2-subagent-lifecycle.sh (unchanged)
                   └─▶ leadv2-native-pulse.sh --force  (new, second entry: agent set changed)
```

`leadv2-native-pulse.sh` (new, ~90 lines bash + one embedded python3 block, same
style as the lifecycle hook):

1. Reads state → `digest` = sha256 of: sorted `agent_id`s in the native-agent
   registry, `leadv2-status-surface.sh --oneline` output, `docs/leadv2/active.yaml`
   mtime+size. Every producer runs under `timeout 5` and fails to `?`, never `0`
   (same fail-open contract as `leadv2-codex-status.sh`).
2. Reads `$PULSE_STATE/last.json` (`{digest, emitted_at}`), default
   `$CLAUDE_PLUGIN_ROOT/.native-pulse/`.
3. Emits iff `digest != last.digest` **or** `now - emitted_at >= LEADV2_CODEX_PULSE_MIN_SECONDS`
   (default 60). `--force` skips the digest comparison.
4. Emission has two surfaces, always both:
   - **file_artifact:** append one line to `$PULSE_STATE/pulse.log`
     `<ISO-8601Z> pulse agents=<n> lanes=<n> task=<id|-> reason=<changed|cadence|lifecycle>`
     then atomically rewrite `last.json` (mkstemp + `os.replace`, per-hook-invocation
     temp name — same pattern as the lifecycle hook, so concurrent tool calls cannot
     interleave a partial write).
   - **rendered_line:** print the same line as hook stdout in the injection shape,
     **only if** `LEADV2_CODEX_PULSE_INJECT=1` (default `1`, flipped to `0` by the
     lane if the §5-step-0 probe shows Codex ignores or mangles it). Never prints a
     `permissionDecision` — a pulse must not be able to deny a tool call.
5. Exit 0 unconditionally, including on every internal failure. A pulse must never
   break the lead.

**Documented boundary (goes in the pilot brief and the status prompt, replacing the
current "do not claim a timer" sentence with the now-true mechanism):** while the
lead is idle — no tool call, no subagent transition — no pulse is emitted, because
Codex exposes no idle/tick hook. Cadence is therefore *at most one pulse per 60s of
lead activity*, not *at least one pulse per 60s of wall clock*. `pulse.log` is the
audit trail: a gap in it is a gap in lead activity, not a lost pulse.

## 3. Interface contract

| Name | Kind | Default | Meaning |
|---|---|---|---|
| `LEADV2_CODEX_PULSE_STATE` | env, dir | `$CLAUDE_PLUGIN_ROOT/.native-pulse` | pulse state + log (test seam) |
| `LEADV2_CODEX_PULSE_MIN_SECONDS` | env, int | `60` | cadence floor; `0` = emit on every call |
| `LEADV2_CODEX_PULSE_INJECT` | env, 0/1 | `1` | print the rendered line to stdout |
| `LEADV2_NATIVE_AGENT_REGISTRY` | env, dir | existing | reused verbatim, not redefined |
| `leadv2-native-pulse.sh [--force]` | argv | — | `--force` = lifecycle-triggered, skip digest gate |

Naming cross-check: all four use the existing `LEADV2_*` prefix; no `LEAD_V2_*`
form appears anywhere in the codex-lead tree. No `claude -p` invocation is
introduced, so the `--max-turns/--permission-mode/--output-format` checklist item
is N/A.

## 4. Concurrency

Two parallel tool calls can run the hook simultaneously. `last.json` is
read-modify-write, so both may emit once (duplicate pulse, benign). Contract:
never lock, never block a tool call on a lock. Writes are atomic-replace, so the
file is never torn; `pulse.log` uses a single `>>` append of one `<4096`-byte line
(atomic on local FS). Documented as an accepted duplicate, not a defect.

## 5. Implementation order

0. **Probe first** (blocking): run one real `codex` turn with a stub PreToolUse hook
   printing a known additionalContext string; record the invocation + verbatim
   output to `plugins/leadv2/docs/evidence/codex-native-pulse-probe.md`. That file is
   the evidence artifact for the §1 UNVERIFIED claim and sets `LEADV2_CODEX_PULSE_INJECT`'s
   shipped default. If injection does not work, ship `INJECT=0` + file surface only
   and say so in the brief — do not simulate a timer, do not shell out to a sleeper.
1. Write `leadv2-native-pulse.sh`; register both entries in `hooks.json`.
2. Hermetic tests in `tests/test-codex-native-pulse.sh` (no `codex` binary, no network,
   `LEADV2_CODEX_PULSE_STATE` in `mktemp -d`): unchanged digest inside the window → no
   emit; changed digest → emit `reason=changed`; unchanged digest with a back-dated
   `emitted_at` → `reason=cadence`; `--force` → `reason=lifecycle`; missing/corrupt
   `last.json` → emits and self-heals; unreadable producer → renders `?`, exit 0;
   `INJECT=0` → empty stdout, log still appended; 32 concurrent invocations → `last.json`
   parses as JSON and every log line is well-formed.
3. Extend `tests/test-codex-hooks.sh`: the pulse hook never emits `permissionDecision`
   for any payload, including malformed JSON. Extend `tests/test-codex-install.sh`:
   the installed brief + status prompt carry the new boundary sentence.
4. Bump `.codex-plugin/plugin.json` `version` build metadata (cache-bust — an
   unchanged version is a known no-op on directory-source marketplaces) and re-run
   `scripts/leadv2-validate-skills.sh`.
5. Docs: boundary paragraph into `docs/codex-lead-AGENTS-pilot.md`, the runbook, the
   status prompt, and `skills/leadv2-status/SKILL.md` (tell the lead to read
   `pulse.log` as the pulse audit trail).

## 6. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Codex ignores hook stdout that is not a permission decision → no chat surface | Probe is step 0 and gates the shipped default; file surface ships either way; boundary documented as fact, not aspiration |
| R2 | Two PreToolUse entries both writing stdout → guard's deny JSON corrupted by pulse text | Pulse never prints a decision; probe must include a denied-tool case; if outputs collide, ship `INJECT=0` |
| R3 | Hook latency added to every tool call | All producers under `timeout 5`; digest short-circuits before the expensive `--oneline` call when the registry mtime is unchanged; test asserts a no-emit run does no lane scan |
| R4 | Pulse hook crash blocks the lead | `set -u`, no `set -e`, `exit 0` on all paths, asserted by the malformed-payload test |
| R5 | Stale marketplace cache — fix present in-tree, absent at runtime | Manifest version bump in step 4 + runbook line: re-install and restart Codex |
| R6 | Duplicate pulses under parallel tool calls | Accepted and documented (§4); dedup would need a lock, which would be worse |

## 7. Non-goals (implementer must ignore)

- Any Claude-side pulse path: `scripts/leadv2-pulse*.sh`, `leadv2-broad-status.sh`,
  `hooks/leadv2-auto-status.sh`, `docs/leadv2/founder-status.md` — untouched.
- Any background daemon, `cron`, `sleep`-loop, launchd job, or detached process to
  manufacture a wall-clock beat. Explicitly forbidden by the mission.
- Changing `lv2guard` deny semantics, the subagent-lifecycle registry format, or
  `leadv2-codex-status.sh` output.
- Application/product code, and `install.sh` logic (it already syncs prompts and the
  brief by content; no new step is needed).

## 8. Acceptance

```yaml
acceptance:
  authored_at: 2026-08-25T00:05:00Z
  - surface: rendered_line
    observable: >
      In the Codex lead chat, immediately after the lead runs a tool while a lane is
      active, the founder sees a one-line pulse of the form
      "2026-08-25T00:07:11Z pulse agents=2 lanes=1 task=a6b168fe reason=changed",
      and sees no second such line until either the counts change or ~a minute of
      further lead activity has passed.
    note: >
      ships only if the step-0 probe shows Codex renders hook-injected context;
      otherwise this surface is reported as unavailable with the probe as evidence.
  - surface: file_artifact
    observable: >
      Opening the plugin's .native-pulse/pulse.log, the founder reads one dated pulse
      line per state change and no more than one per minute of lead activity, with a
      visible gap covering the period the lead sat idle.
```

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/leadv2-native-pulse.sh, plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks.json, plugins/leadv2/codex-lead/marketplace/plugins/leadv2/.codex-plugin/plugin.json, plugins/leadv2/codex-lead/marketplace/plugins/leadv2/skills/leadv2-status/SKILL.md, plugins/leadv2/codex-lead/prompts/leadv2-status.md, plugins/leadv2/codex-lead/tests/test-codex-native-pulse.sh, plugins/leadv2/codex-lead/tests/test-codex-hooks.sh, plugins/leadv2/codex-lead/tests/test-codex-install.sh, plugins/leadv2/docs/codex-lead-AGENTS-pilot.md, plugins/leadv2/docs/codex-lead-pilot-runbook.md, plugins/leadv2/docs/evidence/codex-native-pulse-probe.md

DELIVERABLE_COMPLETE
