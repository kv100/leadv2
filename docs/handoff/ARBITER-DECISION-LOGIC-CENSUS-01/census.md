# report — codex effort wiring probe (ARBITER-DECISION-LOGIC-CENSUS-01)

Read-only probe. No source files changed. Question: where does reasoning effort
come from and where does it land on the wire, on every path that can start a Codex run?

## Census of wiring paths

| # | Path | Effort source | Wire |
|---|------|---------------|------|
| 1 | `codex-task.sh` `task` subcommand | tier resolver (`plugins/leadv2/scripts/codex-task.sh:1357-1380`): top→sol/high (terra/ultra if sol absent from `~/.codex/models_cache.json`), standard→terra/medium, volume→luna/low; explicit `--effort` wins | `--effort $WIRE_EFFORT` with `ultra`→`xhigh` translation at :1380 |
| 2 | `codex-task.sh` `adversarial-review`/`review` | **no effort wire** — "codex-companion's review command does not accept --effort" (header :20-21, log :1389) → runs at the global default (see finding F2) | model only |
| 3 | `leadv2-codex-planner.sh` | same tier table (:96-121) + `--effort` override; `--tier top` REFUSES without `--reason` (CODEX-WAIT-AND-TIER-01, :80-88); `--print-model` prints the logical label, dispatch sends `WIRE_EFFORT` with ultra→xhigh (:261-268) | `task --model --effort` |
| 4 | `leadv2-dispatch-code.sh` codex arm | arbiter's `RESOLVED_EFFORT` appended as `--effort` (:5606-5612, EFFORT-IS-NOT-WIRED-01); absent → falls back to tier default | via `codex-task.sh task` |
| 5 | `leadv2-session-route.sh` | `CODEX_STANDARD_EFFORT=medium` / `CODEX_LIGHT_EFFORT=low` (:54-56), env-overridable `LEADV2_CODEX_*_EFFORT` (:183-185), class-light switch (:265-269) | emitted `_effort` for the route decision |
| 6 | `leadv2-codex-session-runner.sh` | `LEADV2_LEAD_EFFORT` default medium (:33), set by `leadv2-fanout.sh:1194,1303` | `-c model_reasoning_effort="$EFFORT"` on both `exec` and `exec resume` (:474,:492) |
| 7 | Guard: `hooks/leadv2-codex-direct-exec-guard.sh` | blocks bare `codex exec` in lead sessions ("defaults to reasoning effort XHIGH and bypasses the router's quota gate"); allowlists the 4 sanctioned launchers + `LEADV2_ALLOW_DIRECT_CODEX=1` | — |
| 8 | Global default | `~/.codex/config.toml:2` → `model_reasoning_effort = "ultra"` | applies to any invocation that passes no explicit effort |

Also verified single-inode: `~/.claude/scripts/{codex-task.sh,leadv2-codex-planner.sh,leadv2-codex-session-runner.sh}` are symlinks into `~/Projects/leadv2/plugins/leadv2/scripts/`, md5 identical to canonical.

## Probe artifacts

### P1 — planner tier resolution (live)
```
$ LEADV2_PROJECT_ROOT=~/Projects/persona-engine bash plugins/leadv2/scripts/leadv2-codex-planner.sh --print-model --tier <t>
tier=standard -> model=gpt-5.6-terra effort=medium
tier=volume   -> model=gpt-5.6-luna effort=low
tier=top (no --reason) -> REFUSED, rc=2 (CODEX-WAIT-AND-TIER-01 gate fires)
tier=top --reason probe -> model=gpt-5.6-sol effort=high   # sol present in models_cache (jq count=1)
--effort high -> model=gpt-5.6-terra effort=high           # explicit effort beats tier default
```

### P2 — policy gate default-disabled (live)
In the leadv2 repo (no `.claude/leadv2-overrides/codex-policy.yaml`), `_lv2_codex_enabled`
returns 1 ("default: disabled", `leadv2-helpers.sh:220-221`), so every `--print-model` run
printed `codex_skipped_by_policy` until `LEADV2_PROJECT_ROOT` pointed at persona-engine
(`codex_enabled: true`).

### P3 — direct-exec guard fires (live)
```
$ codex exec -c 'model_reasoning_effort="ultra"' "reply ok"
BLOCKED direct 'codex exec' — route via codex-task.sh --tier standard (effort+quota-gated).
```

### P4 — falsification set
No files changed this lane, so `py_compile`/test-runner have no changed scope. Syntax
re-check of the four scripts read:
```
$ LEADV2_ALLOW_FG_DISPATCH=1 bash -c 'for f in codex-task.sh leadv2-codex-planner.sh \
    leadv2-codex-session-runner.sh leadv2-session-route.sh; do bash -n ...$f; done'
bash -n OK
```

## Findings

- **F1 (healthy):** every sanctioned launcher pins effort explicitly; the logical label
  `ultra` is translated to `xhigh` at the wire boundary in both codex-task.sh (:1380) and
  the planner (:262), while `--print-model`/codex-plan.json keep the logical label.
- **F2 (gap):** `adversarial-review`/`review` have NO effort wire (codex-companion
  limitation) → those runs inherit `~/.codex/config.toml` default, which is `ultra`.
  UNVERIFIED: whether codex-cli 0.145.0-alpha.1 accepts `ultra` as an effort value or
  silently falls back to the model default — could not probe directly (P3 guard, by
  design). The plugin's own comment (:259) treats `xhigh` as the companion's actual
  ceiling, implying `ultra` in config.toml is either invalid-or-aliased. If invalid, it
  likely falls back to the model default (xhigh on terra) — i.e. the review arm runs at
  max effort with no router say. Worth a founder decision if unintended.
- **F3 (note):** dispatch-code.sh arm journaling records `effort_dropped ... reason=no_effort_control`
  for arms without effort control; codex and glm arms now wire it (`effort_applied`,
  GLM-EFFICIENCY-01 :5310-5325).
