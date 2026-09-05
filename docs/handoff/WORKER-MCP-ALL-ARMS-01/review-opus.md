LABEL=critic-dispatch-WORKER-MCP-ALL-ARMS-01-review-1788308758 SESSION_ID=e5a60b9c-42f9-4658-8e95-4f0cf84c9be8
--- body from: docs/handoff/dispatch-WORKER-MCP-ALL-ARMS-01-review/critic.full.md ---
REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=2 medium=10 low=5

FINDING: severity=High file=plugins/leadv2/scripts/kimi-coder.sh line=1120 dimension=correctness desc=journal target is journal.jsonl but the tee at :1135 has no -a, so it truncates the file and destroys every worker_mcp_attached/worker_mcp_skipped record on the only path the dispatcher uses
FINDING: severity=High file=plugins/leadv2/scripts/leadv2-dispatch-code.sh line=5089 dimension=correctness desc=code-intel preamble is injected unconditionally for ALL arms including codex (documented unwired by this same diff) and every MCP fail-open path, instructing workers to call mcp__* tools that provably do not exist in those sessions

---

# Adversarial review — WORKER-MCP-ALL-ARMS-01 / build-attempt-2.diff

Target: `docs/handoff/WORKER-MCP-ALL-ARMS-01/build-attempt-2.diff` (9 files, +810 / −8).
Reviewer: independent of the author (glm). No `context.yaml` exists for this review task,
so no `decisions` / `off_limits` constrain the finding set.

Read in full: the diff; `plugins/leadv2/scripts/glm-coder.sh` (the already-shipped
reference implementation this diff ports); `plugins/leadv2/scripts/lib/leadv2-worker-mcp.sh`
(resolver signature); `plugins/leadv2/scripts/kimi-coder.sh` and `freepool-coder.sh`
post-application (`cmd_run_child` pipelines); `plugins/leadv2/scripts/tests/test-worker-mcp-all-arms.sh`;
`tests/run-all.sh`; `docs/handoff/WORKER-MCP-ALL-ARMS-01/report.md`.

**What is correct.** The freepool/kimi additions are a faithful port of glm-coder.sh's
shipped pattern, not a second implementation: same lib-resolution block with the
`readlink -f` symlink-chain fallback, same `worker_mcp_journal` / `worker_mcp_resolve`
wrapper bodies, same fail-open contract (`LEADV2_WORKER_MCP` default 1, `LEADV2_WORKER_ROLE`
default `developer`, role regex-guarded), same two-site wiring (`run_claude` + `cmd_run_child`).
The resolver call `resolve_role_mcp_config "${role}" "${out_dir}" "${project_root}"` matches
the lib's documented signature (`lib/leadv2-worker-mcp.sh:16-22, 38-41`: role, handoff dir,
project root) — verified, no finding. The negative controls are real mutation controls, not
assertion-flips, and the suite does dual `bash -n` (`bash` + `/bin/bash`) for the Bash 3.2
floor. This is above the median quality bar for this repo. The verdict is FAIL on two
specific defects, not on the shape of the work.

---

## Lens 1 — Correctness

### H1 (High) — kimi's MCP journal line is destroyed by `tee` truncation

`plugins/leadv2/scripts/kimi-coder.sh:1120` (added by this diff):

```
mcp_cfg="$(worker_mcp_resolve "${cwd_dir}" "${run_dir}/journal.jsonl" "${run_dir}")" || true
```

`worker_mcp_resolve` appends its record (`worker_mcp_attached config=… role=…`, or
`worker_mcp_skipped reason=disabled|lib_missing|resolve_rc_N`) to `$2` via
`worker_mcp_journal` → `printf … >> "$1"`. Fifteen lines later, `kimi-coder.sh:1135`:

```
) | tee "${run_dir}/journal.jsonl" | ( parse_stream "${run_dir}" … )
```

`tee` without `-a` **truncates**. The record is written before the spawn, so it is
unconditionally erased the moment the CLI produces its first byte. On the `bg` →
`__supervise` → `__run_child` path — the only path the dispatcher uses — kimi's MCP
attach/skip decision leaves no trace anywhere.

Evidence this is a port defect, not a design choice: the reference implementation
`glm-coder.sh:1181` passes `"${run_dir}/progress.log"` for exactly this reason, and its
own `tee` at `glm-coder.sh:1203` is likewise `tee "${run_dir}/journal.jsonl"` with no `-a`.
glm chose `progress.log` *because* `journal.jsonl` is truncated. The diff swapped the target
back to the truncated file.

**Census — all same-shape sites (2 of 2 enumerated, 1 affected):**

| Site | journal arg | writer downstream | Affected? |
|---|---|---|---|
| `kimi-coder.sh:1120` (`cmd_run_child`) | `journal.jsonl` | `tee` (:1135, **no -a**) | **YES — truncated** |
| `freepool-coder.sh:1263` (`cmd_run_child`) | `journal.jsonl` | `tee -a` (:1283, :1285) | No |
| `kimi-coder.sh` / `freepool-coder.sh` `run_claude` | `""` (stderr) | — | No |

freepool is genuinely fine, and deliberately so: `freepool-coder.sh:1256-1260` already
writes a plain-text launcher line (`freepool_select role=… model=…`) into `journal.jsonl`
under a comment that explicitly justifies mixing one grep-friendly record into the JSONL
stream, and both freepool tees use `-a`. So the fix is one line in kimi (`progress.log`,
matching glm), not a two-arm change. I report freepool here only to close the census.

Fix: `kimi-coder.sh:1120` → `"${run_dir}/progress.log"`.

### H2 (High) — the preamble is injected for arms that have no MCP

`plugins/leadv2/scripts/leadv2-dispatch-code.sh` `_spawn_worker_body()` (~:5089) prepends
`prompts/worker-code-intel-preamble.md` to `mission` with **no conditionality whatsoever** —
not on arm, not on whether MCP resolution succeeded. The preamble tells the worker to route
how/where/why questions through `mcp__repowise__get_answer`, `mcp__codebase-memory-mcp__search_graph`,
`query_graph`, `trace_path`, `get_code_snippet`, `get_context`, `get_symbol`, `get_why`, and to
prefer the `repowise distill` / `repowise expand` CLI.

Populations that receive the preamble and cannot honour it:

1. **codex arms** — this same diff (`codex-task.sh`, +10) adds a NOTE stating code-intel MCP
   "is not yet wired for Codex arms", and `config/codex-mcp-servers.toml` is an allowlist with
   no consumer. So the diff instructs codex workers to call tools it documents as absent.
2. **`LEADV2_WORKER_MCP=0`** — the documented kill switch. `worker_mcp_resolve` returns 1,
   no flag is added to the spawn line, and the preamble still ships.
3. **Every fail-open branch** — `lib_missing` (the `readlink -f` fallback failed) and
   `resolve_rc_11|12|13|14` (no allowlist / nothing resolved / parse failure / **python3 missing**).
   `rc=14` in particular is an environment condition, not a config error.
4. **sonnet arms** whose repo `.mcp.json` does not carry these servers — the resolver reads
   `.mcp.json` / `.claude/settings.json` from the *project root* (lib:17-19), which in a
   per-task worktree may legitimately be thinner than the machine's user settings.

Consequence is not cosmetic: a worker told to use a nonexistent tool burns turns on failing
calls, or — worse for this repo's economics — reads whole files "because the graph tool
didn't work", which is the exact behaviour the preamble exists to prevent. There is also no
existence check for the `repowise` CLI the preamble recommends.

The injection point is right (one site, all arms); the gating is missing. Minimum fix: gate
on the same signal the launcher already computes (attach succeeded), or emit an
arm-appropriate variant. Deriving that signal in the dispatcher is not free — the resolution
happens inside the launcher child — which is precisely why this needs a decision rather than
a silent unconditional prepend.

---

## Lens 2 — Tests can fail (falsification)

The suite (`tests/test-worker-mcp-all-arms.sh`, 451 lines, `PASS=34 FAIL=0` per report.md)
is stronger than most in this repo — four real detached `bg` runs against an argv/env-dumping
stub `claude`, plus two scratch-copy mutation controls. It nevertheless cannot fail on either
High finding.

- **M2 (Medium) — nothing asserts the journal record.** `grep -n "worker_mcp_attached"` across
  the suite returns **zero hits**. The suite asserts the resolved-JSON contents and the stub's
  argv (`--strict-mcp-config` / `--mcp-config` present), never the launcher's own journal line.
  So H1 — the entire observability half of the feature, silently zeroed for kimi — is invisible
  to the green suite. `report.md` quotes a `worker_mcp_attached config=mcp-role-developer.resolved.json role=developer`
  line as evidence; no test locks it, and for kimi it cannot survive the run.
- **M8 (Medium) — the green fixture dodges a footgun the report itself documents.**
  `report.md` §5 records that `load_secret()` under active `set -e` kills the child at
  `readonly FREEPOOL_BASE_URL` (`freepool-coder.sh:65`). The round-2 `bg` fixtures therefore
  use a token-only secrets file plus `FREEPOOL_PROXY_URL`. The passing test consequently never
  exercises the production-shaped secrets file. A test tuned around a known live defect proves
  the code path only for the shape that avoids it.
- **M9 (Medium) — tautological source-text assertions.** A substantial block of the 34
  assertions is `grep` over source: `grep -c "_LEADV2_CODE_INTEL_PREAMBLE" >= 2`,
  `grep -q 'worker-code-intel-preamble.md'`, `grep -q "code-intel MCP.*not yet wired for Codex arms"`,
  the two toml `names` greps, the preamble content greps, and `[[ "${_lines}" -le 25 ]]`.
  These fail only if someone deletes the line; they cannot fail on a behavioural regression.
  They are cheap and fine as anti-deletion locks — they should not be counted toward
  behavioural coverage, and the report does count them.
- **M10 (Medium) — the `bash -n` loop excludes the one file this diff edits blind.**
  `codex-task.sh` is skipped with the comment "pre-existing heredoc false positive". That is
  an untagged claim (see L-lens 5) *and* it removes the only syntax check from a file the diff
  modifies. The 10 added lines are simple, but the exclusion is permanent and unexplained by
  evidence.
- **L3 (Low) — the kimi mutation reuses freepool's needle.** `FP_CHILD_NEEDLE`
  (`test-…:441`) is applied to both `bg_negative_control "${FREEPOOL_SCRIPT}"` and
  `bg_negative_control "${KIMI_SCRIPT}"`. It works today only because the two lines are
  byte-identical. Fixing H1 in kimi (`progress.log`) will make the needle miss — the control
  must fail loudly on a missed needle, not degrade to a vacuous green. Worth an explicit
  needle-found assertion regardless of H1.
- **L4 (Low) — runtime / flake surface.** Four real detached runs, each `wait_finalized`
  polling `.finalized` at `sleep 1` bounded at 120s ⇒ up to ~8 min worst case in a suite
  wired into `--scope changed` for six stems.

---

## Lens 3 — Product invariant / contract

- **M1 (Medium) — `--strict-mcp-config` can *narrow* the child's server set.** Added at four
  sites (freepool `run_claude` + `cmd_run_child`, kimi `run_claude` + `cmd_run_child`). The flag
  means "use only this config"; the resolver builds that config from the **project root's**
  `.mcp.json` / `.claude/settings.json` (lib:17-19). The diff's own
  `config/codex-mcp-servers.toml` comment states `codebase-memory-mcp` is "hard-pinned per
  machine in `~/.claude/settings.json`" — a path the resolver does not read. So in any
  worktree whose project-root config is thinner than the machine's user settings, a worker
  that previously inherited servers now gets a strictly smaller set. That is the inverse of
  this task's goal. `report.md` shows the resolved JSON, but no probe establishing
  resolved ⊇ pre-change effective set. This is an inherited pattern (glm shipped it), so it is
  Medium and not High — but the diff extends it to two more arms without ever checking the
  direction of the change, and the check should be done once, for all arms.
- **M3 (Medium) — the codex NOTE fires only under `--tier`.** The block is inside the `--tier`
  handling branch, guarded by `LEADV2_CODEX_MCP_WARNED`. Its own comment says the point is to
  "log once so the gap is visible"; a non-tiered codex dispatch emits nothing. The visibility
  invariant holds for a subset of invocations only.
- **M7 (Medium) — `tests/run-all.sh` mapping overstates coverage.** Six stems are mapped to
  this suite, but for four of them — `codex-task.sh`, `leadv2-codex-planner.sh`,
  `leadv2-worker-mcp.sh`, `leadv2-dispatch-code` — the suite's only coverage is `bash -n`
  and source greps (and `codex-task.sh` is excluded from even the `bash -n` loop, M10). A
  future editor of `lib/leadv2-worker-mcp.sh` sees a suite selected and green and infers
  behavioural protection that does not exist.

---

## Lens 4 — Census (all same-shape instances in touched files)

| Defect shape | Sites enumerated | Affected |
|---|---|---|
| journal arg pointing at a `tee`-truncated file | 4 (kimi ×2, freepool ×2) | 1 (`kimi-coder.sh:1120`) — H1 |
| unconditional preamble injection | 1 injection point, ≥4 unsupported populations | H2 |
| `--strict-mcp-config` added to a spawn | 4 (freepool `run_claude`+`cmd_run_child`, kimi ×2) | all 4 — M1 |
| tautological source-text assertion | ≥8 in the new suite | all — M9 |
| evidence-free external-system claim | 3 (toml `codex exec --help`; `codex-task.sh` NOTE wording; suite's "pre-existing heredoc false positive") | M4, M10 |
| malformed / missing `UNVERIFIED:` tag | 1 (`report.md`) | M5 |
| unfilled evidence placeholder | 1 (`report.md` §4) | M6 |
| lib-resolution block (`readlink -f` fallback) | 2 (freepool, kimi) | none — faithful to glm |
| `worker_mcp_resolve` arg order vs lib signature | 4 call sites | none — verified correct |

---

## Lens 5 — Claims without evidence

Every factual claim about an external system or API in the diff, its comments, or the
deliverable:

1. **`config/codex-mcp-servers.toml` STATUS comment** — "`codex exec --help` **on this machine**
   offers only `-c key=value` overrides and `-p/--profile`, neither of which the companion
   forwards." Names a probe, pastes **no output**, carries **no `UNVERIFIED:` tag**, and it
   **drives the decision** not to wire codex (and to land an allowlist file with no consumer).
   Per the stated contract this is blocking-shaped. I record it as **M4 (Medium)** rather than
   High only because the decision it drives is "do nothing for codex" — the failure mode is a
   deferred feature, not a wrong code path. If the claim is wrong, the whole codex gap is
   unnecessary; paste the `--help` output.
2. **`codex-task.sh` NOTE** — "code-intel MCP … is not yet wired for Codex arms". Backed by
   `report.md`'s probe (`grep -c mcp … codex-companion.mjs → 0 occurrences in 1027 lines`).
   Adequate evidence. No finding.
3. **`report.md` tag `UNVERIFIED-below-otherwise`** — **M5 (Medium)**. The contract requires
   the literal token `UNVERIFIED:`. A non-matching variant defeats any mechanical grep for
   unverified claims, which is the entire point of the literal.
4. **`report.md` §4** — "`tests/run-all.sh --scope changed`: (selected-suite line appended
   below after run completes.)" — **M6 (Medium)**. An unfilled placeholder standing where the
   evidence for a claimed gate should be. The gate is asserted, not shown.
5. **`test-…-all-arms.sh` "pre-existing heredoc false positive"** — folded into **M10**. An
   untagged claim about `bash -n` behaviour that justifies excluding a modified file from
   syntax checking. One `bash -n codex-task.sh` transcript settles it.
6. **`report.md` journal-line quote** (`worker_mcp_attached config=… role=…`) — the arm is not
   stated, and no test locks it; for kimi it cannot survive the run (H1). Counted under M2.
7. **Preamble tool names** (`mcp__codebase-memory-mcp__*`, `mcp__repowise__*`, `repowise distill`) —
   consistent with this repo's `.claude/CLAUDE.md`, so grounded as *names*; ungrounded as
   *availability in the spawned session*, which is H2.

---

## Low / nits

- **L1** — the new suite lands as mode `100644`. Harmless on the wired path: `tests/run-all.sh:410`
  invokes `bash "${suite}"`. It breaks a human `./test-worker-mcp-all-arms.sh` and diverges from
  its siblings. `chmod +x`.
- **L2** — `_lines="$(wc -l < "${PREAMBLE_FILE}" 2>/dev/null || echo 999)"`: under `set -uo pipefail`
  a redirection failure aborts the command substitution before `echo 999` can run, so the
  intended 999 sentinel never materialises. Cosmetic here (the file's existence is asserted
  earlier), but the idiom is wrong wherever it is copied next.
- **L3** — shared mutation needle across arms (detailed in Lens 2).
- **L4** — suite wall-time up to ~8 min (detailed in Lens 2).
- **L5** — `cp -pR "${PLUGIN_SCRIPTS}" …` runs twice (once per negative control), copying the
  whole scripts dir each time. Fine, just wasteful.

---

## Verdict

**FAIL** — two High findings.

Required to clear:
1. `kimi-coder.sh:1120` → `progress.log` (match `glm-coder.sh:1181`), **and** add an assertion
   that the launcher journal actually contains `worker_mcp_attached` on the `bg` path for both
   new arms — otherwise the same class of defect lands again unnoticed.
2. Decide and implement the preamble gating for arms/paths without MCP, or state explicitly
   (with the founder's sign-off) that unconditional injection is accepted and why.

Recommended in the same round because they are cheap and each closes an evidence hole:
paste the `codex exec --help` output (M4), fix the `UNVERIFIED:` tag (M5), fill the §4
placeholder (M6), move the codex NOTE out of the `--tier` branch (M3), and either add
behavioural coverage for the four grep-only stems or drop them from the `run-all.sh` mapping (M7).

M1 (`--strict-mcp-config` narrowing) is inherited from the shipped glm path and should be
settled once for all four arms with a single before/after server-set probe — not as part of
this diff's blocking set, but it should not be forgotten.

DELIVERABLE_COMPLETE
