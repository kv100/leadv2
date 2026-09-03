# CLAIM-EVIDENCE-GATE-01 — ROUND-2 implementation design (lane d784b987, base 98ce586)

Architect prepass. No code written here. Round-1 verdict FAIL (H1, H2 blocking) —
`docs/handoff/dispatch-2e675c98-review/critic.full.md` read in full and treated as the contract.

## 0. Lane state (verified this pass)

```
$ git -C .claude/worktrees/d784b987 log --oneline -2
98ce586 feat(review): CLAIM-EVIDENCE-GATE-01 …
559cf15 fix(tests): PLUGIN-CORE-OFFLINE-4RED-01 …
$ git log --oneline -1 origin/main            → 512ecda (supervise-v2 3b symlink fix)
$ git merge-base origin/main HEAD             → 559cf15
```

So the lane is one commit off `559cf15`, `origin/main` has advanced by three commits
(`71c4cef`, `0c23a1a`, `512ecda`). **Step 0 of the build is `git rebase origin/main`** —
`512ecda` is byte-identical to the lane's `test-supervise-v2.sh` hunk, so the 3-way merge
resolves it to a no-op and M3 disappears without a manual hunk edit. **Do not `git checkout`
that file from main and do not commit to main.**

Consequence for M4: after the rebase the `test-supervise-v2.sh:267-271` comment is main's
(`512ecda`), not this lane's. Per the mission's own parenthetical — **M4 is SKIPPED**, and
`test-supervise-v2.sh` must not appear in the lane diff at all.

---

## 1. Layers affected

| Layer | File | Findings addressed |
|---|---|---|
| Worker prompt assembly (claude arm) | `plugins/leadv2/scripts/claude-subsession.sh` | H1, M5, L1, + C7 hook |
| Canonical contract text | `plugins/leadv2/scripts/leadv2-helpers.sh` | H2 (one inode of truth) |
| Dispatch mission assembly (all 4 arms) | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | H2 |
| GLM launcher direct path | `plugins/leadv2/scripts/glm-coder.sh` | H2 |
| Suite | `plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh` | M1, M2, L2, L3, L4, L5 |
| Protocol doc | `plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md` | H1 (§11 kept — it becomes rendered) |

Not touched: `leadv2-review-run.sh` (round-1 lens text is correct as-is; only the *test's*
C4 grep pattern widens), `leadv2-dispatch-product-close.sh` (off_limits),
`tests/run-core-offline.sh` (suite already registered at `:227`).

---

## 2. Data flow — where the contract text travels (numbered)

Today (post-round-1):

1. `claude-subsession.sh` → `SHARED_PROTOCOL_BOILERPLATE` (bullets, lines 246-255) →
   `build_cached_prefix()` → `/tmp/leadv2-cache/prefix-<role>.<sum>.md` → claude arm worker. **lands**
2. `build_cached_prefix():285` → `$PROJECT_ROOT/.claude/skills/leadv2-subagent-protocol/SKILL.md`
   → **missing in every live repo** → `awk … 2>/dev/null` → empty `skill_body` → "Protocol
   reference:" section is empty in every rendered prefix. **§11 lands nowhere.** (H1)
3. `leadv2-dispatch-code.sh:_spawn_worker_body()` → raw `${mission}` → `glm-coder.sh bg` /
   `kimi-coder.sh bg` / `codex-task.sh task` → **no contract text at all.** (H2)
4. `leadv2-review-run.sh:705` (round-1 exhaustive) → BLOCKS untagged claims from (3). Rule with
   no reader on the writing side.

After this round:

1. `build_cached_prefix()` resolves `skill_file` with a **two-step order**:
   `$PROJECT_ROOT/.claude/skills/leadv2-subagent-protocol/SKILL.md` (repo-local override, kept
   first so a project can still override) → else
   `${CLAUDE_PLUGIN_ROOT:-<script_dir>/..}/skills/leadv2-subagent-protocol/SKILL.md`.
   `CLAUDE_PLUGIN_ROOT` is **not a new env var** — already read in `leadv2-helpers.sh`,
   `leadv2-dispatch-code.sh`, `leadv2-session-route.sh`, `leadv2-deploy-merge.sh`,
   `leadv2-self-spawn.sh`. §11 now reaches the claude arm.
2. Empty `skill_body` after both candidates → **warn on stderr, never silent**:
   `[claude-subsession] WARN: subagent-protocol SKILL.md not resolvable (tried <a>, <b>) — prefix
   will omit the protocol reference`. Fail-open on the spawn (a worker without the appendix is
   still better than no worker), loud in the log.
3. `leadv2-helpers.sh` defines the canonical mission-side contract string
   `LEADV2_EVIDENCE_CONTRACT_MISSION` (see §3).
4. `_spawn_worker_body()` prepends it to `${mission}` **once, before the `case "${arm}"`**,
   immediately alongside the existing `WORKTREE_PIN_LINE` prepend at `:2519` — one insertion,
   all four arms, zero per-arm drift. Same placement invariant as LANE-PLACEMENT-01: this runs
   **after** `compute_sig`/classify/router, so `sig8`, the dedup ledger and routing stay
   byte-identical.
5. `glm-coder.sh` prepends its own copy for **direct** (non-dispatch) `bg`/`run` invocations,
   idempotently (skip when the resolved prompt already carries the marker), so a lane launched
   straight from supervise or by hand is covered too and never gets the block twice.

---

## 3. Interface contracts

### 3.1 Canonical mission-side contract (new, `leadv2-helpers.sh`)

| Item | Value |
|---|---|
| Name | `LEADV2_EVIDENCE_CONTRACT_MISSION` |
| Kind | plain shell string (`readonly` — **not** an env var, not exported, no `LEADV2_*` config knob added) |
| Grep markers | `EVIDENCE CONTRACT` and `UNVERIFIED:` — the *same two tokens* the preamble and the suite already use |
| Charset rule | no double-quote, no backtick anywhere in the text (it flows into double-quoted shell strings and, for codex, into an argv word) |
| Content | the same three sentences as `claude-subsession.sh:246-252`, with the M5-corrected `round-1 reviewers` qualifier |

Consumers and their fallback:

| Consumer | How it gets the text | Fallback if unavailable |
|---|---|---|
| `leadv2-dispatch-code.sh` | already `source`s `leadv2-helpers.sh` at `:299` (with `\|\| true`) | `[[ -n "${LEADV2_EVIDENCE_CONTRACT_MISSION:-}" ]]` guard → else use an embedded one-line literal **and** `log_err` a warning. Never silently empty — that fail-open shape *is* H1. |
| `glm-coder.sh` | own `readonly EVIDENCE_CONTRACT_PREAMBLE` beside `AGENT_BAN_PREAMBLE` | n/a |
| `claude-subsession.sh` | keeps its existing inline bullets in `SHARED_PROTOCOL_BOILERPLATE` | n/a |

**Design decision — three textual copies, pinned by a test, instead of one sourced inode.**
`glm-coder.sh` sources no shared lib today; making a ~1.4k-line helpers file a load-bearing
dependency of the GLM launcher is a larger blast radius than the drift it removes.
Mitigation: new suite case **C9** asserts a canonical marker sentence appears byte-identically
in all three files. If C9 is judged insufficient by the implementer, the alternative (guarded
`source` in `glm-coder.sh`) is acceptable — but then it must be `[[ -f … ]] && source … || true`
plus the same non-empty guard.

### 3.2 `claude-subsession.sh` prefix-path observability (new, required by C7)

`build_cached_prefix()` currently logs the prefix path **only when it writes a new file**
(`:322-324`). A test cannot then assert on the artifact when the checksum already exists in
`/tmp/leadv2-cache` (and `CACHE_DIR` is `readonly` at `:146`, non-overridable without a new env
var — which is off_limits).

Contract: emit, unconditionally, after the `if`:

```
[claude-subsession] prefix path: <path>
```

on **stderr**. Safe: `leadv2-dispatch-code.sh` parses the sonnet handle from **stdout**
(`PID=… LABEL=… SESSION_ID=…`), never stderr.

### 3.3 Preamble text edits (`claude-subsession.sh`)

| Line | Now | After |
|---|---|---|
| 251-252 | `…is a protocol violation, and reviewers treat one that drives a decision as BLOCKING.` | `…is a protocol violation, and round-1 reviewers treat one that drives a decision as BLOCKING.` (M5, mirrors `SKILL.md:192-194`) |
| 253 | `- See full protocol: .claude/skills/leadv2-subagent-protocol/SKILL.md` | `- See full protocol: the protocol reference appended below (plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md).` (L1) |

L1 note: the pointer must stay a **static** string. Interpolating the resolved absolute path
would put `$PROJECT_ROOT` into `SHARED_PROTOCOL_BOILERPLATE`, which is checksummed by
`build_cached_prefix()` — one cache entry per repo per role, for no benefit.

---

## 4. Test plan — `tests/test-claim-evidence-gate.sh`

| Case | Change | Finding |
|---|---|---|
| C1 | keep (source grep) — it is the cheap canary | — |
| **C7 (new)** | rendered-prefix probe, through `run_case` (red-first) | M1, H1 |
| **C8 (new)** | rendered dispatch-mission probe for glm + codex arms | H2 |
| **C9 (new)** | contract text identical across the three definition sites | H2 drift |
| C4 | widen the review-run pattern to `FIVE lenses\|claims-without-evidence`; add the same quote/backtick guard over the new dispatch/glm lines | L3 |
| baseline guard `:52` | grep **three** markers, not one | L4 |
| baseline fallback `:56` | `559cf15`, not `HEAD` | L2 |
| cleanup | `trap 'rm -rf "${PREFIX_DIR}" "${c6_stub_dir:-}" "${c6_root:-}" …' EXIT INT TERM`; drop the now-redundant explicit `rm -rf` at `:191,:193` (or keep — the trap is idempotent) | L5 |
| tail `:198` | `printf -- 'FAIL: %s\n' "${ERRORS[@]+"${ERRORS[@]}"}"` **and** push the case name into `ERRORS` in the green-pre-fix branch (`:96-99`) | M2 |

### C7 — rendered-prefix probe (the case that would have caught H1)

Shape (must go through `run_case` so it is red against the baseline tree):

1. `mktemp -d` a scratch `PROJECT_ROOT` containing **only** `.claude/agents/critic.md`
   (minimal frontmatter + one body line) and **deliberately no** `.claude/skills/…` — this is
   exactly the live-repo shape that produced H1.
2. `PROJECT_ROOT=<scratch> LEADV2_DRY_RUN=1 bash "${scripts_dir}/claude-subsession.sh"
   --role critic --model sonnet --task-id CEGP7 --mission-file <tmp mission> --wait`,
   stderr captured.
3. Parse `prefix path: <p>` (§3.2) from stderr; return 1 if absent.
4. Assert the file at `<p>` contains **both** `EVIDENCE CONTRACT` (preamble half) **and**
   `Evidence contract for external-system claims` (the §11 heading — the half that was inert).

Red-first behaviour: the baseline tree (`git archive` of `plugins/leadv2/scripts` — note the
sibling `leadv2-temp.sh` / `leadv2-helpers.sh` it sources are in the same archived dir, so the
baseline copy runs) prints no `prefix path:` line at all → `pre_rc=1`. Post-fix → 0.
Return `2` (could-not-run) only if `claude-subsession.sh` is missing from `scripts_dir`.

### C8 — rendered dispatch mission for the non-claude arms

Model it on **`tests/test-lane-placement-pin.sh`** — that suite already drives
`leadv2-dispatch-code.sh` through `LEADV2_DISPATCH_GLM_BIN` / `LEADV2_DISPATCH_CODEX_BIN`
stubs to assert exactly this shape of mission-text prepend (`WORKTREE_PIN_LINE` at `:2519`).
Reuse its stub/env scaffolding verbatim rather than inventing a new harness; the stub writes
`$2` (glm) / `$2` (codex `task`) to a file, and the case greps `EVIDENCE CONTRACT` +
`UNVERIFIED:` in it. If a full dispatch run proves too heavy or flaky inside this suite, the
acceptable fallback is a `_spawn_worker_body`-scoped probe **plus** a raw terminal artifact of
the full-dispatch grep pasted into the deliverable — but the suite case is preferred.

### C9 — drift pin

`grep -c '<canonical marker sentence>'` == 1 in each of `leadv2-helpers.sh`, `glm-coder.sh`,
`claude-subsession.sh`; fail if any is 0.

---

## 5. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | Contract text arrives **twice** on the claude arm (prefix + injected mission) and on a dispatched glm lane (dispatch + glm-coder) | Harmless duplication, but ugly in the prompt: `glm-coder.sh` skips its prepend when the prompt already contains the marker. The claude-arm double is left alone (prefix is cached, mission is not — deduping across the two would couple the two scripts). Note it in the commit body. |
| R2 | `sig8` / dedup-ledger drift from mission injection | Insert at `_spawn_worker_body:2519`, i.e. **after** `compute_sig`. Same invariant the LANE-PLACEMENT-01 comment documents. Verify: `test-lane-placement-pin.sh` + `test-dispatch-resume-sentinel.sh` stay green in `run-core-offline.sh`. |
| R3 | Backtick/quote in the injected text command-substitutes (mission flows into `"${mission}"` and into codex argv) | Charset rule in §3.1 + C4-style guard extended to the new lines. |
| R4 | Prefix cache invalidated for every role (L7) | One-time regeneration, no action. Already accepted in round 1. |
| R5 | `source leadv2-helpers.sh \|\| true` at `:299` fails ⇒ empty contract, silently — the H1 shape again | Non-empty guard + `log_err` + embedded fallback literal (§3.1). This is a **must**, not a nicety. |
| R6 | Baseline self-nullification once this lands (every case reports green-pre-fix → suite red forever) | Three-marker content probe (L4) + pinned `559cf15` floor (L2). Note: after the rebase, `merge-base(origin/main, HEAD)` = `512ecda`, which carries **none** of the markers, so the merge-base path stays live and honest for this round. |
| R7 | C7's scratch `PROJECT_ROOT` makes `claude-subsession.sh` do real work (cost log, journal writes) | `LEADV2_DRY_RUN=1` + `--wait`, proven by the reviewer's own probe (`[DRY_RUN] subsession spawn: …`). Everything else is scoped to the scratch dir. |
| R8 | Concurrent lanes share `/tmp/leadv2-cache` | C7 never deletes cache entries — it only reads the path the run reports. Do **not** `rm /tmp/leadv2-cache/prefix-*` in the test. |

---

## 6. Mandatory constraint checklist

1. **Env var naming** — no new env vars. `CLAUDE_PLUGIN_ROOT` is platform-provided and already
   read in five sibling scripts; `LEADV2_TEST_BASELINE_REF`, `LEADV2_DRY_RUN`,
   `LEADV2_DISPATCH_GLM_BIN`, `LEADV2_DISPATCH_CODEX_BIN` all pre-exist.
   `LEADV2_EVIDENCE_CONTRACT_MISSION` is a **non-exported shell variable**, not a config knob —
   if the implementer prefers zero ambiguity, name it `_LEADV2_EVIDENCE_CONTRACT_MISSION`.
2. **File paths** — every path in §1 verified present on disk this pass, including
   `plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md` (exists in the plugin;
   **absent** under all three project roots — that is H1).
3. **`claude -p` commands** — none added or modified by this round.
4. **Concurrent access** — `/tmp/leadv2-cache` is shared across lanes (R8); the suite is
   read-only against it. `PREFIX_DIR`/`c6_*` are per-run `mktemp -d`.
5. **Config contradiction** — `_spawn_worker_body:2519` already owns exactly one
   mission-prepend (`WORKTREE_PIN_LINE`); the new prepend joins it, order:
   pin line, then contract, then mission (keeps the pin line first, as its own comment requires).

---

## 7. Out of scope (implementer: ignore)

- `leadv2-dispatch-product-close.sh` (off_limits).
- Any round-detection / arm-selection / router change (off_limits) — the injection is
  arm-agnostic by construction.
- `leadv2-review-run.sh` lens text — correct as shipped; only the test's grep widens (L3).
- `test-supervise-v2.sh` — M3 resolves via rebase, M4 skipped (comment is `512ecda`'s, on main).
- L6/L7 — informational, no change.
- New env vars, new gates, new runtime machinery.

---

## 8. Build order

1. `git rebase origin/main` (M3).
2. `leadv2-helpers.sh`: canonical contract string.
3. `claude-subsession.sh`: skill_file resolution + empty-warn (H1), unconditional prefix-path
   log (C7 hook), M5 wording, L1 pointer.
4. `leadv2-dispatch-code.sh:2519`: injection + non-empty guard (H2/R5).
5. `glm-coder.sh`: own const + idempotent prepend (H2 direct path).
6. Suite: C7, C8, C9, M2, L2, L3, L4, L5.
7. `bash -n` (bash 5 **and** `/bin/bash` 3.2) + `shellcheck -S warning` on all changed files.
8. `tests/run-core-offline.sh` forward, then `LEADV2_CORE_OFFLINE_REVERSE=1`.
9. Commit on the lane branch; terminal artifact = sha + per-finding note + raw probe output.

---

acceptance:
  - surface: file_artifact
    observable: "The materialised worker-prompt file that claude-subsession.sh reports for role
      critic, when run from a project root that has no .claude/skills/ directory, contains both
      the line beginning 'EVIDENCE CONTRACT:' and the heading 'Evidence contract for
      external-system claims' — where today the section after 'Protocol reference:' is empty and
      the file ends there."
    authored_at: 2026-08-19T16:05:00Z
  - surface: file_artifact
    observable: "The mission text handed to the GLM launcher and to the Codex launcher by a
      dispatch run contains the evidence-contract paragraph with the token UNVERIFIED: — today
      those launchers receive the mission with no contract text anywhere in it."
    authored_at: 2026-08-19T16:05:00Z
  - surface: log_line
    observable: "test-claim-evidence-gate.sh prints a RED-then-GREEN line for the new
      rendered-prefix case and for the rendered-dispatch-mission case, and its final Results line
      reads 0 failed and 0 green-pre-fix, under both /bin/bash (3.2) and bash 5."
    authored_at: 2026-08-19T16:05:00Z
  - surface: log_line
    observable: "run-core-offline.sh ends with a CORE-OFFLINE summary line reporting failed=0 and
      missing=0, in the forward order and again in the reverse order."
    authored_at: 2026-08-19T16:05:00Z
  - surface: log_line
    observable: "When the subagent-protocol document cannot be found under either the project root
      or the plugin root, the subsession log carries a WARN line naming both paths it tried —
      instead of silently producing a prompt with an empty protocol section."
    authored_at: 2026-08-19T16:05:00Z

LANE_WRITES: plugins/leadv2/scripts/claude-subsession.sh, plugins/leadv2/scripts/leadv2-helpers.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/glm-coder.sh, plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh, plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md

DELIVERABLE_COMPLETE
