# CODEX-QUOTA-GUARDRAILS-01 — implementation design (architect prepass)

Repo: `~/Projects/leadv2` (canonical plugin). Design only; no implementation here.

---

## 1. Invocation-site audit (evidence-backed, before/after)

Every place the plugin reaches the codex CLI or codex-companion. `effort today` is what
actually lands on the wire.

| # | Site | file:line | Effort today | Verdict | After |
|---|------|-----------|--------------|---------|-------|
| 1 | session-runner, fresh exec | `plugins/leadv2/scripts/leadv2-codex-session-runner.sh:455` | `-c model_reasoning_effort="$EFFORT"`, `EFFORT=${LEADV2_LEAD_EFFORT:-medium}` (`:30`) | **effort OK / gate MISSING** | unchanged effort; add gate + circuit consult before the exec |
| 2 | session-runner, resume exec | `leadv2-codex-session-runner.sh:473` | same `$EFFORT` | **effort OK / gate MISSING** | same |
| 3 | codex-task.sh `task` **with** `--tier` | `codex-task.sh:1027-1034` | `--effort` from tier table; `standard=medium`, `volume=low`, `top=high|xhigh` | OK | unchanged |
| 4 | codex-task.sh `task` **without** `--tier` | no pin; comment at `codex-task.sh:1104-1108` says "No model pin in that case; codex-companion inherits its default" | **UNPINNED — CLI default** | **GAP (primary)** | default `_TIER` to `standard` when unset, so model+effort are always pinned |
| 5 | codex-task.sh `review` / `adversarial-review` | `codex-task.sh:1019-1021` | model only — "review has no `--effort` wire" (`:20-21`) | GAP-by-wire | keep model pin; add explicit comment + test asserting no `xhigh` reaches the review wire. Effort is not settable on this subcommand; documented, not fixed |
| 6 | codex-task.sh model-reject fallback | `codex-task.sh:1228` `_FALLBACK_EFFORT="high"` | `high` | **GAP** | `medium` (standard) |
| 7 | codex-task.sh timeout tier-down retry | `codex-task.sh:1290-1307` | rewrites an existing `--effort` token in argv | **derived GAP** — if argv had no `--effort` (case #4), the retry adds none | fixed transitively by #4; add assertion |
| 8 | planner, `standard` tier | `leadv2-codex-planner.sh:92` | `gpt-5.6-terra` / **`high`** | **DRIFT** vs codex-task `standard=medium` | `medium` — one tier table, two consumers must agree |
| 9 | planner, `volume` tier | `leadv2-codex-planner.sh:95` | `luna` / `medium` | **DRIFT** vs codex-task `volume=low` | `low` |
| 10 | planner, `top` tier | `leadv2-codex-planner.sh:84-88` | `high`, or `ultra`→`xhigh` on sol-absent fallback | xhigh permitted, **but ungated** — codex-task gates `top` on `--reason` (`codex-task.sh:845`), the planner does not | require `--reason` for `--tier top`, mirroring codex-task |
| 11 | dispatch-code codex arm | `leadv2-dispatch-code.sh:1859-1861` | `--tier ${RESOLVED_CODEX_TIER:-standard}` → codex-task | OK | **no edit** (keeps req-5 lane-conflict scope at zero) |
| 12 | codex-lead relay | `leadv2-codex-lead.sh:71` → detaches the session-runner; zero positional args, effort via `LEADV2_LEAD_EFFORT` | OK (inherits #1/#2) | no edit; gate lands in the runner it calls |

Non-sites checked and excluded: `leadv2-codex-round-gate.sh`, `codex-poll-done.sh`,
`leadv2-codex-lockout.sh`, `leadv2-lane-liveness.sh` — all read status/state, none spawn.

**Dead-hook finding:** `plugins/leadv2/hooks/leadv2-block-codex.sh` exists but is **not
registered** in `hooks.json` (grep for `block-codex` in hooks.json: zero hits). It is not
the guard req 4 asks for and it is currently inert. Leave it alone; the new hook is separate.

---

## 2. Layers affected

```
LEAD session (Bash tool)
  └─[NEW] hooks/leadv2-codex-direct-exec-guard.sh   ← req 4, PreToolUse:Bash, additive
sanctioned launchers
  ├─ codex-task.sh ──────┐
  ├─ leadv2-codex-planner.sh ──→ codex-task.sh
  ├─ leadv2-dispatch-code.sh ──→ codex-task.sh (unchanged)
  └─ leadv2-codex-session-runner.sh ──→ `codex exec` (direct)
                          │
                          ├─[NEW] lib/leadv2-codex-quota-gate.sh   ← req 2, shared gate
                          └─[NEW] lib/leadv2-codex-circuit.sh      ← req 3, circuit state
control plane
  └─ leadv2-state-path.sh --no-link codex-circuit.json  ← one circuit per repo, all worktrees
```

---

## 3. Data flow (numbered)

**Spawn path (every arm):**
1. Launcher resolves tier → model + effort. No-tier ⇒ `standard`. Effort is now always
   an explicit argv/`-c` token.
2. Launcher calls `codex_spawn_gate <sub>`:
   1. `arm_cooldown_state codex` (existing bounded memory, `lib/leadv2-arm-cooldown.sh`) —
      `cooling *` ⇒ refuse.
   2. `codex_circuit_state` (**new**) — `open <until>` ⇒ refuse.
   3. live-quota threshold check (existing `_codex_quota_read` + routing-yaml thresholds) —
      over threshold ⇒ refuse.
3. Refuse ⇒ `LEADV2_DISPATCH_REFUSED: quota_gate` on stderr + `exit 2` (existing router
   contract, `leadv2-dispatch-code.sh refusal_reason()` maps rc 2 → next candidate → glm → sonnet).
4. Pass ⇒ exec codex with the pinned effort.

**Circuit-open path:**
5. codex output (session-runner log tail, or the job log the existing
   `_codex_quota_watch_record` already polls at `codex-task.sh:387`) matches
   `hit your usage limit | usage limit reached | rate limit exceeded`.
6. `try again at <date>` is parsed by the **existing** parser
   (`codex-task.sh:307-333`, hoisted into the new circuit lib verbatim) → ISO-8601 UTC.
   Unparseable ⇒ `now + 24h`.
7. `codex_circuit_open <until_iso> <source>` writes the marker **and journals
   `codex_circuit_open until=<ts>` exactly once** (skip both if an open circuit with a
   `until >=` this one already exists — idempotent across concurrent workers).
8. Every later spawn hits step 2.2 and spills. Circuit auto-closes when `now >= until`
   (evaluated at read time; no sweeper needed).

---

## 4. Interface contracts

### `lib/leadv2-codex-circuit.sh` (new, sourceable, fails open on read errors it cannot attribute)

| Function | Args | Stdout | Exit | Notes |
|---|---|---|---|---|
| `codex_circuit_path` | — | absolute path to `codex-circuit.json` | 0 / 1 | `leadv2-state-path.sh --no-link codex-circuit.json`; honors `LEADV2_STATE_ROOT` (test seam). rc 1 = **cannot reach the control plane** |
| `codex_circuit_state` | — | `open <until_iso> <source>` \| `closed` \| `unknown` | 0 | `unknown` when the path is unresolvable **or** the file exists but is unparseable |
| `codex_circuit_open` | `<until_iso\|""> <source>` | — | 0 | empty/unparseable `until` ⇒ `now+24h`; idempotent; journals once |
| `codex_circuit_parse_until` | stdin: provider text | ISO-8601 UTC | 0/1 | verbatim lift of `codex-task.sh:311-333` |

Marker file (JSON, single object, atomic write via `mktemp` + `mv`):
```json
{"until":"2026-08-08T08:49:00Z","opened_at":"2026-08-03T14:02:11Z","source":"session-runner","reason":"usage_limit"}
```

### `lib/leadv2-codex-quota-gate.sh` (new, extracted)

| Function | Args | Behaviour |
|---|---|---|
| `codex_spawn_gate` | `<sub>` `[launch args…]` | steps 2.1–2.3 above; on refuse prints the marker + `return 2` |

`codex-task.sh` sources it and its `_codex_quota_gate` becomes a thin caller — the existing
refusal strings, stderr-only discipline, `CODEX_SKIP_QUOTA_GATE=1` hatch, and every
fail-open message are preserved **byte-for-byte** so `tests/test-codex-quota-gate.sh` and
`tests/test-codex-lockout-agreement.sh` stay green unmodified.

### Fail-open vs fail-closed — the one real judgement call

Req 2 says "a path that cannot reach the resolver fails toward NOT spawning". The existing
gate is deliberately **fail-open** on every error (`codex-task.sh:87-88`), and two tests bond
that. Splitting the two rather than flipping one:

- **live-quota reader / routing-yaml / python3 unavailable ⇒ FAIL-OPEN** (unchanged; a
  missing reader must never brick codex — existing contract, existing tests).
- **circuit check ⇒ FAIL-CLOSED**: `codex_circuit_state` returning `unknown` (control plane
  unreachable, or a marker present but unreadable) ⇒ **refuse, spill to the ladder**.
  Rationale: `unknown` is exactly the "cannot reach the resolver" case req 2 names, and the
  cost asymmetry is one-sided — spilling to glm costs a slightly worse model for one task,
  an ungated spawn during an open circuit costs a guaranteed-dead job's full repo-context
  input (the RCA's double-billing multiplier).
  Escape hatch: `CODEX_SKIP_QUOTA_GATE=1` still skips everything.

### Hook contract — `hooks/leadv2-codex-direct-exec-guard.sh` (new)

| | |
|---|---|
| Event | `PreToolUse`, matcher `"Bash"`, additive entry appended to the existing Bash array in `hooks/hooks.json` (currently 11 PreToolUse groups) |
| Deny when | `.tool_input.command` matches `(^\|[^A-Za-z0-9_/.-])codex[[:space:]]+exec([[:space:]]\|$)` |
| Allow when | the command invokes a sanctioned launcher (`codex-task.sh`, `leadv2-codex-session-runner.sh`, `leadv2-codex-planner.sh`, `leadv2-codex-lead.sh`) — matched **before** the deny rule; or `LEADV2_CODEX_SANCTIONED=1`; or `LEADV2_ALLOW_DIRECT_CODEX=1` (allowed, and one line logged to stderr) |
| Deny output | one line: `[leadv2-codex-direct-exec] BLOCKED direct 'codex exec' — route via codex-task.sh --tier standard (effort+quota-gated). Override: LEADV2_ALLOW_DIRECT_CODEX=1` → `exit 2` |
| Fail-open | `set -u` only (no `-e`), `trap '… exit 0' ERR`, empty/malformed stdin ⇒ `exit 0`; never blocks non-codex Bash |
| Timeout | 5 (matches sibling hooks) |

**Scope note the implementer must not get wrong:** a PreToolUse hook only ever sees a
*lead session's Bash tool call*. The runner scripts fork `codex` themselves and never pass
through this hook. So the env markers are belt-and-braces for a lead that legitimately
sets them; the launcher-path allowlist is what actually keeps sanctioned commands working.
Do not "fix" this by trying to inspect subprocess env.

---

## 5. State / config changes

No DB. One new state file. No new env-var *semantics* beyond:

| Var | Default | Where read | Convention check |
|---|---|---|---|
| `LEADV2_CODEX_SANCTIONED` | unset | new hook | `LEADV2_*` ✓ |
| `LEADV2_ALLOW_DIRECT_CODEX` | unset | new hook | `LEADV2_*` ✓ |
| `LEADV2_CODEX_CIRCUIT_FILE` | derived from `leadv2-state-path.sh` | circuit lib (test seam) | `LEADV2_*` ✓ |

Reused unchanged: `LEADV2_LEAD_EFFORT`, `LEADV2_STATE_ROOT`, `LEADV2_ROUTING_YAML`,
`LEADV2_QUOTA_READ`, `CODEX_SKIP_QUOTA_GATE`, `LEADV2_ARM_COOLDOWN_DIR`.
Grepped for `LEAD_V2_*` drift on these names: none.

---

## 6. Risks + mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | Extracting `_codex_quota_gate` into a lib silently changes a refusal string and breaks `test-codex-quota-gate.sh` / `test-codex-lockout-agreement.sh` | Verbatim lift; run both suites before and after as a bonded pair. Any diff in stderr text = revert the extraction and instead `source` the lib *additively* from the runner only |
| R2 | Circuit marker in the control plane is written concurrently by N worktrees | Atomic `mktemp`+`mv`; "later `until` wins" read semantics (max-of); journal suppressed when an equal-or-later circuit is already open |
| R3 | `arm-cooldown` hard-caps at 3600 s (`ARM_COOLDOWN_HARD_MAX_S`), but a weekly usage limit is days out | **Do not** widen that cap. The circuit is a *separate*, longer-horizon marker; cooldown keeps its short re-probe role. Gate consults both |
| R4 | Fail-closed circuit could brick codex on a machine where `leadv2-state-path.sh` genuinely can't resolve (no git) | `CODEX_SKIP_QUOTA_GATE=1` hatch, plus a stderr line naming the unresolved path so the failure is diagnosable, not silent |
| R5 | Planner effort drop `high→medium` is a quality change, not just a cost change | It aligns the planner with the already-shipped EFFORT-RECAL 2026-07-10 decision in codex-task.sh (`standard=medium`); the drift is the bug. Rollback line: restore `high`/`medium` in `_resolve_tier` |
| R6 | Defaulting no-tier to `standard` also pins a **model** (`gpt-5.6-terra`) where none was pinned — changes behaviour for bare `codex-task.sh task "…"` | Intended and stated. `codex-task.sh:1104` currently relies on the companion default (gpt-5.5); pinning terra/medium is the explicit-over-implicit fix the mission asks for. Note it in the report as a behaviour change |
| R7 | `hooks.json` edit races another lane | Append-only single-object edit inside the existing `"Bash"` group; re-diff `hooks.json` immediately before staging |
| R8 | Hook cache staleness (documented plugin gotcha) | New hook file must be copied into the plugin cache + session restarted before it loads; state this in the report — do not claim the hook is live from source alone |

---

## 7. Test plan — `plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh` (new)

Sandbox: `LEADV2_STATE_ROOT=$TMP/state`, `LEADV2_ARM_COOLDOWN_DIR=$TMP/cool`,
stub `codex` on `PATH` recording argv to `$TMP/argv.log`, stub `codex-companion.mjs`.

| Case | Asserts |
|---|---|
| a1 | `codex-task.sh task "x"` (no `--tier`) → argv contains `--effort medium` |
| a2 | `codex-task.sh task "x" --tier standard` → `--effort medium` |
| a3 | `codex-task.sh task "x" --tier volume` → `--effort low` |
| a4 | session-runner spawn → argv contains `-c model_reasoning_effort="medium"` |
| a5 | `leadv2-codex-planner.sh --print-model` (no tier) → `effort=medium` |
| b1 | `--tier top` without `--reason` → refused (both codex-task and planner) |
| b2 | `--tier top --reason "…"` → `xhigh`/`high` permitted |
| b3 | no path emits `xhigh` unless `--tier top` |
| c1 | usage-limit output with `try again at Aug 8th, 2026 08:49 AM` → marker `until=2026-08-08T08:49:00Z` |
| c2 | unparseable refusal → `until ≈ now+24h` (±120 s) |
| c3 | while open → gate refuses, stderr has `LEADV2_DISPATCH_REFUSED: quota_gate`, rc 2, **no** codex argv recorded |
| c4 | `until` in the past → gate passes, codex spawns |
| c5 | second refusal while open → journal has exactly **one** `codex_circuit_open` line |
| d1 | hook: `codex exec "x"` → rc 2, deny line on stderr |
| d2 | hook: `LEADV2_CODEX_SANCTIONED=1` → rc 0 |
| d3 | hook: `LEADV2_ALLOW_DIRECT_CODEX=1` → rc 0 + logged line |
| d4 | hook: `bash .../codex-task.sh task "x"` → rc 0 |
| d5 | hook: `ls -la` / `git status` / malformed JSON / empty stdin → rc 0 |
| e1 | control plane unresolvable (`LEADV2_STATE_ROOT` → unwritable) → gate refuses, **no** codex argv recorded |
| e2 | quota reader missing → still fail-OPEN (regression guard on the existing contract) |

Registered in `scripts/tests/run-core-offline.sh` next to the other Codex checks (`:56-58`).
**Baseline first:** record `run-core-offline.sh` pass count on current main *before* the
change; the mission notes it grew several times today, so the only valid comparison is
same-day-before vs after (expected: baseline + 1).

Also required: `bash -n` under both bash 5 and `/bin/bash` 3.2 for every touched `.sh`.

---

## 8. Out of scope (implementer: ignore)

- Review-arm selection policy; `leadv2-router.sh` arm ordering.
- Any new quota accounting or ledger — reuse `leadv2-quota-read.py`, `arm-cooldown`,
  the routing-yaml thresholds.
- GLM / kimi / sonnet paths.
- `leadv2-dispatch-product-close.sh`; `leadv2-dispatch-code.sh` (**zero edits** — its codex
  arm already routes through `codex-task.sh --tier standard`, so the gate lands transitively).
- The inert `hooks/leadv2-block-codex.sh` — do not register, do not delete.
- Widening `ARM_COOLDOWN_HARD_MAX_S`.
- Committing. Report only.

---

## acceptance:

```yaml
acceptance:
  authored_at: 2026-08-03T00:00:00Z
  items:
    - surface: log_line
      observable: >
        In docs/handoff/<task>/codex-session-runner.log the launch line reads
        "provider=codex model=<slug> effort=medium" on a run where no effort
        was configured anywhere — the founder can read the pinned effort off
        the log without knowing which flag set it.
    - surface: rendered_line
      observable: >
        A lead session that types a bare `codex exec ...` into Bash sees, in the
        terminal, a single blocked line naming codex-task.sh as the route and
        LEADV2_ALLOW_DIRECT_CODEX=1 as the override; the command does not run.
        The same session's `ls`, `git status`, and `codex-task.sh task ...`
        commands run normally with nothing printed.
    - surface: file_artifact
      observable: >
        After codex answers "You've hit your usage limit ... try again at Aug 8th,
        2026 08:49 AM", the file ~/.claude/leadv2-state/<repo>/codex-circuit.json
        exists and shows until 2026-08-08T08:49:00Z; opening it from a different
        worktree of the same repo shows the same one file.
    - surface: log_line
      observable: >
        The journal shows exactly one "codex_circuit_open until=2026-08-08T08:49:00Z"
        line no matter how many workers hit the refusal, and subsequent dispatches
        show the codex arm refused with the work spilling to glm.
```

LANE_WRITES: plugins/leadv2/scripts/codex-task.sh, plugins/leadv2/scripts/leadv2-codex-session-runner.sh, plugins/leadv2/scripts/leadv2-codex-planner.sh, plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh, plugins/leadv2/scripts/lib/leadv2-codex-circuit.sh, plugins/leadv2/hooks/leadv2-codex-direct-exec-guard.sh, plugins/leadv2/hooks/hooks.json, plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
