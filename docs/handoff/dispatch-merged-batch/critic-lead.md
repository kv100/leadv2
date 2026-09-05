# Adversarial review — dispatch-merged-batch (origin/main..main, 4 merges + 1 fix commit)

**VERDICT: FAIL (BLOCK)** — 6 High, 7 Medium, 8 Low. No Critical.

Scope reviewed: `docs/handoff/dispatch-merged-batch/review.diff` (4229 lines, 50 files) **plus**
the 4 files the artifact omits (see H4), read directly from `git diff origin/main..main`.
Evidence below is from live runs on this checkout, not from reading the authors' claims.

---

## Critical

None. (No unreviewed new module is completely test-free except `repowise-launch.sh`, which is
folded into H6 rather than escalated, because it fails silent-open rather than silent-destructive.)

---

## High — these block the push

### H1 — `plugins/leadv2/codex-lead/deny-extra.yaml:39-44` — the plugin self-removal floor is bypassable by two one-liners
Category: security / guard bypass.

The rule's own message asserts *"a floor the guarded agent can remove with one command is no
floor."* Two commands that remove the floor are not matched. Probed live on this tree:

```
$ for c in ...; do bash lv2guard.sh --check -c "$c"; done
codex plugin remove leadv2@leadv2-local        -> rc=97   (blocked)
codex plugin marketplace remove leadv2-local   -> rc=0    (ALLOWED)
codex plugin disable leadv2                    -> rc=0    (ALLOWED)
codex plugin uninstall leadv2                  -> rc=97   (blocked)
```

`codex plugin marketplace remove leadv2-local` is the exact command the runbook itself prints in
its own Rollback section (`plugins/leadv2/docs/codex-lead-pilot-runbook.md`, Rollback block), so
the guarded agent has a copy-pasteable disable path sitting in its own brief. `codex plugin
disable leadv2` is the shorter one.

**Required fix:** the regex must not require `remove|uninstall` to be adjacent to `plugin`, and
must cover `disable`:
`'codex\s+plugin\b(?:\s+(?!remove\b|uninstall\b|disable\b)\S+)*\s+(remove|uninstall|disable)\b.*\bleadv2\b'`
— or three explicit rules. Add all four shapes above as `assert_rc` rows in
`plugins/leadv2/codex-lead/tests/test-lv2guard.sh` next to the existing `--check` block, so the
bypass cannot silently reopen.

### H2 — `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh:166,171,189` — `worktree remove --force` widens deliverable loss from "refused" to "destroyed"
Category: data loss / regression to a fail-safe contract.

`_MW_ORCH_RE` (line 166) classifies **all** of `docs/handoff/` as regenerated bookkeeping, and
line 171 filters it out of the real-dirt check. Line 189 then runs `git worktree remove --force`.

Before this change the flow was: discard the orch paths (a `git checkout --` that *fails* for
untracked paths, then `rm -f` that *fails* on a directory), then plain `git worktree remove` —
which **refuses** when untracked files remain, and the lane landed in `KEPT_DIRTY`. So a lane whose
only uncommitted content was an untracked `docs/handoff/<id>/developer.full.md` was **kept**.
After this change that same lane is force-deleted, deliverable and all.

The batch's own doc admits the hazard exists (`plugins/leadv2/docs/worktree-sweepers.md`,
"Deliberate boundaries": *"may force-discard uncommitted `docs/handoff/**` bookkeeping … tracked
separately"*) but presents it as unchanged residual risk. It is not unchanged — the ordering fix
(correct, keep it) was bundled with a `--force` that converts a refusal into a deletion. Handoff
dirs are precisely where every subagent deliverable in this system lives.

**Required fix:** keep the decide-then-remove ordering, drop `--force`, and handle the
untracked-orch case explicitly: either (a) `rm -rf` only the paths that `git status --porcelain
-uall` proves match `_MW_ORCH_RE` *after* the decision, then plain `worktree remove`; or (b) copy
`"${wt}/docs/handoff/"` into the main checkout (`${JOURNAL_ROOT}/docs/handoff/_swept/<id>/`)
before forcing. Add a case to `test-merged-sweep-orchestration-dirt.sh`: merged lane whose only
dirt is an **untracked** `docs/handoff/<id>/deliverable.md` → assert the file survives somewhere.

### H3 — `plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh:136-145` — `case_newborn_kept` is a tautology; it never reaches the newborn guard
Category: tautological test (this is the merge seam the mission flagged).

`_mk` was updated to write `$d/state/active.yaml` (the control-plane half of the merge), and
`_swept()` was updated to pass `LEADV2_STATE_ROOT="$repo/state"`. **`case_newborn_kept` invokes the
hook directly (line 139) and was not updated**, so the fixture's `active.yaml` is never used.
Reproduced on this checkout with the identical fixture and invocation:

```
OUT=[[leadv2-merged-worktree-sweep] protected(read-error) lane — sweeping nothing this pass (read-error:active-yaml-missing)]
resolved active.yaml: /Users/…/.claude/leadv2-state/.ephemeral/n1/active.yaml   <- does not exist
/tmp/leadv2-sweep.log: …|protected id=lane rc=5 reason=read-error:active-yaml-missing
```

rc 5 is the fail-closed "protect everything" path. The lane survives, stderr contains the word
`protected`, and the assertion `grep -qiE "young|protect"` (line 143) accepts it. **Delete the
newborn guard, delete the lib's age probe, delete probes A–C — this case still passes.** It pins
nothing about SWEEP-KILLS-NEWBORN-LANE-01.

Corollary: the guard it claims to test is itself unreachable in default config — see M1.

**Required fix:** add `LEADV2_STATE_ROOT="$repo/state"` to line 139 and tighten the assertion to
`grep -q "young"` only (the newborn message), so the fail-closed path cannot satisfy it. Then
re-run: if it goes red, the guard ordering (M1) is the real defect.

### H4 — `docs/handoff/dispatch-merged-batch/review.diff` is not the change under review
Category: process / evidence integrity.

`review.diff` contains 50 files; `origin/main..main` contains 53. Missing entirely:

```
plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh
plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh
plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh
```

plus the `leadv2-fanout.sh` registry-resolution hunk (the artifact carries only the drift-message
hunk; the live file has both). All four come from `b8ac631`, which landed after the artifact was
generated. A reviewer working from the artifact would have approved unreviewed code that changes
how *every* fanout lane resolves its active-session registry (see H5). I reviewed them from git;
the artifact must be regenerated before anyone else signs off.

**Required fix:** regenerate `review.diff` from `origin/main..main` and re-run the gate, or record
in the close that the fanout-fix commit was reviewed out of band with a pointer to this file.

### H5 — `leadv2-fanout.sh:44-54` / `leadv2-fanout-lane-launcher.sh:79-92` — resolution order reversed against a documented invariant, with no test on the property that mattered
Category: correctness / silent contract change (this is in the code H4 omitted).

The removed comment stated the ordering rationale explicitly: *"source the repo-vendored copy …
rather than the shared-tree original — the vendored copy resolves active.yaml through
scripts/leadv2-state-path.sh (control-plane root), **the shared original still hardcodes
docs/leadv2/active.yaml**"*. The new code puts `${SCRIPT_DIR}/leadv2-active-registry.sh` first and
demotes the vendored copy to second. The invariant that actually protects the control plane is not
"vendored wins" but "**the resolved copy is state-path-aware**" — and nothing enforces it. With 5
known copies of these scripts in circulation (the drift guard counts them, same file, line 92), a
lane executing from a stale sibling silently regresses to a per-worktree
`docs/leadv2/active.yaml`, which is exactly the fragmentation LEAD-CONTROL-PLANE-01 exists to
prevent — and which the sweeper gate in this same batch now depends on for correctness (a
fragmented registry reads as `sessions: []` → lane not protected → swept).

The new `test_5_registry_resolution_no_host_deps` (test-fanout-classify-guard.sh) asserts only that
`class=Standard` appears in the output. It does not assert *which* copy was sourced or that the
resolved copy routes through `leadv2-state-path.sh`.

**Required fix:** after resolution, assert the property, not the path — e.g. refuse to launch when
`grep -q 'leadv2-state-path.sh' "$_REGISTRY_SH"` fails — and make Test 5 assert that the active.yaml
the run wrote is the one under `LEADV2_STATE_ROOT`, not `<proj>/docs/leadv2/active.yaml`.

### H6 — new live-path modules shipped with no behavioural test
Category: test coverage.

- `marketplace/plugins/leadv2/scripts/repowise-launch.sh` — **zero** behavioural coverage. The only
  assertion anywhere is `bash -n` (test-lv2guard.sh:1207, test-codex-plugin-manifest.sh:1020).
  Every branch is untested: the `LEADV2_REPOWISE_MCP` override, the upward `$PWD` walk, and the
  silent `exit 0`. It is the MCP entry point for every Codex session on the plugin path, and its
  failure mode is silent (see M3).
- `install.sh` plugin path — the `codex plugin marketplace add` **failure** branch (line ~140,
  prints ACTION REQUIRED and falls through to the prompt-pack fallback) is never exercised;
  `STUB_NOPLUG` fails `plugin --help` so it never reaches that branch.
- `install.sh` fallback→plugin **upgrade** path — untested, and it is broken (M2).
- `leadv2-burn-governor.sh --provider` codex `limit_reached` branch (line 1939 of the diff,
  `if d.get("limit_reached") is True … print(100)`) — tests 21–26 never feed a `limit_reached`
  fixture in provider mode, so the second, independently-written copy of the sentinel logic is
  unverified.
- `_contract_write_gate`'s `qpath=""` quarantine-unavailable branch — untested.

**Required fix:** a `tests/test-repowise-launch.sh` covering override / found / not-found, an
upgrade-path case in `test-codex-install.sh` (fallback first, then plugin), and a `limit_reached`
row in `test-burn-governor.sh`.

---

## Medium — fix or write the justification into the commit message

### M1 — two different age floors, two different defaults, one documented kill switch that doesn't work
`plugins/leadv2/docs/worktree-sweepers.md` ("Age window"): *"`LEADV2_SWEEP_MIN_AGE_S` is the
preferred seconds setting … `LEADV2_SWEEP_MIN_AGE_H` is the legacy hours setting … Their effective
default is 48 hours; `0` disables **only** the age probe."*

`leadv2-merged-worktree-sweep.sh:145` carries a **second, independent** age floor,
`min_age="${LEADV2_SWEEP_MIN_AGE_S:-1800}"`, which:
- does not read `LEADV2_SWEEP_MIN_AGE_H` at all, so the documented `…_H=0` kill switch does **not**
  turn it off (`…_S=0` does — undocumented asymmetry);
- defaults to **30 minutes**, not 48 hours, for the same concept in the same code path;
- is **unreachable in default config**: `lv2_worktree_protected` already returns rc 4 (`young`) for
  anything under 48h, so the newborn guard only ever runs when the lib's probe has been disabled.
  It is dead code that the suite (H3) does not reach either.

This is precisely the SWEEPER-LANE-SAFETY-01 × SWEEP-KILLS-NEWBORN-LANE-01 merge seam.
**Fix:** delete the hook-local guard and let `lv2_worktree_protected` own probe D, or have it read
`LV2_WT_PROTECT_MIN_AGE_S` (already exported by the lib) instead of re-deriving a default.

### M2 — `codex-lead/install.sh:167-178` — the plugin path skips the repowise block but never removes the one it previously wrote
The comment says: *"On the plugin path the plugin's `.mcp.json` owns the repowise declaration;
writing the block too would leave two repowise servers racing for one name."* Correct — but the
guard only prevents *adding*. Any host that ran the pre-CODEX-LEAD-PLUGIN-01 installer already has
the sentinel block in `~/.codex/config.toml`; re-running produces exactly the two-servers-one-name
state the comment forbids. `test-codex-install.sh` only tests a virgin `$FIX_HOME` on the plugin
path, so the upgrade is invisible.
**Fix:** on the plugin path, strip the self-owned sentinel block (it is delimited by
`SENTINEL_BEGIN`/`SENTINEL_END`, so removal is safe and does not touch hand-written blocks) and
print `config.toml: repowise block removed (owned by the plugin now)`. Add the upgrade test case.

### M3 — `marketplace/plugins/leadv2/.mcp.json:5-7` vs `scripts/repowise-launch.sh:41-49` — `cwd:"."` contradicts the launcher's `$PWD`-walk assumption, and the failure is silent
The manifest pins `"cwd": "."` alongside the plugin-relative `"command": "./scripts/repowise-launch.sh"`.
The launcher's own header says it *"resolves the server at spawn time by walking `$PWD` upward"* —
i.e. it assumes `$PWD` is the **session repo**. If `"."` resolves plugin-relative (the natural
reading, and consistent with the `command` value right above it), `$PWD` is
`~/.codex/plugins/cache/leadv2-local/leadv2/1.0.0`, the walk finds no `.repowise/repowise-mcp.sh`,
and the launcher `exit 0`s **with no message anywhere** — repowise is simply absent for the whole
session and nothing says so.
This is the one wire-contract claim in CODEX-LEAD-PLUGIN-01 with **no probe artifact**; the hook
payload/deny/rc-7 contract was probed and recorded, cwd resolution was not.
**Fix:** drop `"cwd"` (or probe it and record the artifact next to the hook ones), and make the
launcher print one stderr line before `exit 0` naming the directory it started from. Cover both in
the new `test-repowise-launch.sh` (H6).

### M4 — `tests/test-worktree-lane-safety.sh:44-57, 264-281` — the "red-first dual pass" measures the wrong thing post-merge
`PRE_HOOK` is `git show HEAD:…` — i.e. the **already-fixed** hook — copied to `${WORK}/pre-hook.sh`,
where `${SCRIPT_DIR}/../scripts/lib/leadv2-worktree-protected.sh` does not exist, so the "pre-fix"
binary is today's code running on the missing-lib stub (`return 5` = protect everything). Live run:

```
Results: 9 passed(red->green), 0 failed, 13 green-pre-fix
[TEST] GREEN-PRE-FIX: P1-registered-lane-kept(hook) …
[TEST] RED-then-GREEN: P3-arm-terminal-lane-swept(hook) (pre_rc=1 -> post_rc=0)
```

Every `RED-then-GREEN` line proves only *"a sweeper that cannot find its lib sweeps nothing"*;
every keep-case (P1/P2/P4/P5/P7/P9/P12) degrades to `GREEN-PRE-FIX`. Worse, `run_case` increments
`PASS` **only** when `pre_rc != 0` (line 4025-4030 of the diff), so a future run where pre == post
prints `0 passed, 0 failed` and still exits 0 — a suite that asserts nothing exits green.
(The suite is still *internally* discriminating — P3/P6 require an actual sweep, so a
protect-everything regression is caught — but the reported signal is noise.)
**Fix:** pin the pre-fix revision explicitly (`git show <sha-before-SWEEPER-LANE-SAFETY-01>:…`) and
symlink the lib next to it, or delete the dual pass and count every post-fix case as PASS.

### M5 — `leadv2-burn-governor.sh:186-243` — `--provider` has zero callers; speculative 55-line second quota model
Grepped the whole tree (excluding tests/docs/worktrees): nothing invokes
`leadv2-burn-governor.sh --provider`. It re-implements `leadv2-provider-quota-gate.sh`'s python
parser (including a second copy of the `limit_reached` → 100 sentinel) with a different verdict
model (`soft = ceiling-10`), plus 6 tests, for no consumer. YAGNI.
Second defect in the same dispatch table: `case "${1:-verdict}" in … *) cmd_verdict ;;` routes any
typo'd flag (`--providr`, `--provider-x`, `--Provider`) to the **24h token-burn** verdict and prints
a confident `verdict=…` line — a caller cannot distinguish "provider quota is fine" from "you
misspelled the flag and got the wrong gate".
**Fix:** delete `--provider` until a caller exists. If it stays, add `-*) usage; exit 2 ;;` before
the catch-all.

### M6 — `docs/routing-enforcement.md` "Env knobs" overstates `LEADV2_QUOTA_CEILINGS`
The doc lists `LEADV2_QUOTA_CEILINGS` as *"override the ceilings file"* with no scope. Only
`leadv2-provider-quota-gate.sh:8` honours it. `leadv2-glm-quota-gate.sh:38` and
`leadv2-burn-governor.sh` (`cmd_verdict_provider`) both hardcode
`"${SCRIPT_DIR}/../config/leadv2-quota-ceilings.sh"`. A test that exports it (as
`test-codex-quota-guardrails.sh` now does) is hermetic for one of the three and silently reads the
repo config for the other two.
**Fix:** honour the env var in all three (one-line change each), or scope the doc bullet to the one
script by name.

### M7 — `lib/leadv2-worktree-protected.sh:70-76, 106` — every control-plane failure collapses to one opaque reason
`import yaml` failure, an unopenable `active.yaml`, an empty/comment-only `active.yaml`
(`yaml.safe_load` → `None` → `not isinstance(data, dict)`), and a malformed one all `sys.exit(3)`
→ `LV2_WT_PROTECT_ERR="control-plane-unreadable"`. A host without PyYAML therefore disables **both**
sweepers permanently, and the single visible warning names neither the cause nor the remedy. Given
the gate is fail-closed by design, the only way anyone notices is unbounded worktree growth.
**Fix:** distinct exit codes → distinct reasons (`pyyaml-absent`, `active-yaml-empty`,
`active-yaml-malformed`), so the one stderr line an operator sees is actionable.

---

## Low — advisory

- **L1** `leadv2-merged-worktree-sweep.sh:151,209` — lanes kept by the **lib's** `young` probe (rc 4)
  are not counted in `KEPT_YOUNG` (they `continue` at line 114, before the counter), so a pass that
  protects every lane prints **nothing at all** on stderr (reproduced above: empty output, one
  `/tmp/leadv2-sweep.log` line). Also `%d too young (<%ss)` prints `${min_age:-1800}` — a
  loop-local from the last iteration — so it reports `1800` even when `LEADV2_SWEEP_MIN_AGE_S` is set.
- **L2** `leadv2-merged-worktree-sweep.sh:108` — unbounded append to the fixed path
  `/tmp/leadv2-sweep.log`; no rotation, and a pre-created symlink at that path is written through.
  Use `${TMPDIR:-/tmp}/leadv2-sweep.$(id -u).log` and cap it.
- **L3** `leadv2-provider-quota-gate.sh:16` — the kill switch is `[[ "${…:-1}" == 0 ]]`, so
  `LEADV2_PROVIDER_QUOTA_GATE=false`/`no`/`off` does **not** disable the gate although the doc calls
  it a kill switch. Accept `0|false|no|off` or document the exact literal.
- **L4** `leadv2-provider-quota-gate.sh:90` — a variable literally named `source` in a file that also
  calls the `source` builtin. Legal, but rename to `pct_source`.
- **L5** `tests/test-codex-plugin-manifest.sh:113-125` — the CLI version pin **fails** the suite on
  any codex version other than `0.145.0-alpha.1`, while a *missing* codex CLI passes. A routine
  `codex` upgrade turns this suite red for everyone with no code change. Make the mismatch a warn +
  a scheduled-decisions row demanding the re-probe; keep the hard fail for a *downgrade* if you
  must have one.
- **L6** `tests/test-deny-floor.sh:378` — the bare `[[ "$DRIFT_RESULT" -eq 0 ]]` sits above the
  summary under `set -euo pipefail` (line 5), so a drift failure exits before
  `N passed, M failed` is ever printed, hiding both the count and any earlier failures. Move it below
  the summary or fold it into `FAIL`.
- **L7** `marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh:439-463` — a payload whose
  `tool_input.command` is whitespace-only collapses to an empty `$PARSED` after command
  substitution and is denied with the misleading reason *"unreadable PreToolUse payload"*. Emit a
  sentinel from python (`__EMPTY__`) rather than relying on a non-empty stdout.
- **L8** `leadv2-review-run.sh:1105` / `leadv2-dispatch-product-close.sh:2475` — a new
  `emit decision` line is injected into the stderr of two scripts whose stderr is parsed by
  downstream consumers. `test-codex-dead-reroute.sh` asserts the line's *content* and that both call
  sites exist, but nothing asserts that an extra line does not break a consumer of review-run's
  stderr contract. Cheap to cover; not blocking.

---

## Things I checked and found correct (no finding)

- `SCRIPT_DIR`, `TASK`, `reviewer`, `pool` are all defined before the new
  `source lib/leadv2-review-reroute-note.sh` line at both call sites; `emit()` exists in both with
  the `<type> <text>` signature used. No `set -u` abort.
- Ledger schema match: `lib/leadv2-worktree-protected.sh` reads `terminal ∈ {landed,dead}` keyed on
  `task_sig`/`founder_task_id`, and resolves the ledger via `leadv2-state-path.sh --no-link
  dispatch-ledger.jsonl` — byte-identical to `dispatch_terminal_ledger_file()`'s primary path.
- Lane id keying works on the live tree: worktree basenames (`5266d747`, `6df07ac1`) match
  `docs/handoff/dispatch-<id>/`, so probe B (`arm_open`) fires in production — confirmed by live
  `/tmp/leadv2-sweep.log` rows `protected id=e5be9e72 rc=2 reason=arm_open`.
- The ERR trap in the merged-sweep hook does not fire inside the sourced lib (ERR traps are not
  inherited by functions without `errtrace`), and every protection call sits in an `if` condition,
  so the `set -e`/ERR-trap interaction is safe in both sweepers.
- Bash 3.2: no associative arrays, no `${var,,}`, no `mapfile`; `stat -f`/`stat -c` and
  `date -v`/`date -d` both have fallbacks; `realpath` is guarded. Clean.
- GITGLOBAL fragment: no false-positive path found (`gitfoo reset --hard`, `git status && reset
  --hard` do not match); `-C <path>`, `-C/path`, `-c k=v` repeated, `--git-dir=` and `--git-dir <p>`
  all match; `clean -n`, `stash pop`, `log`, non-force `push` still allowed. The drift check
  correctly catches a sixth git rule authored without the fragment.
- `codex_spawn_gate` purpose derivation is sound; `leadv2-codex-session-runner.sh:502` passes `exec`
  → build ceiling 90 for a review session, which is **stricter** than declared, not a hole.
- `_contract_write_gate` correctly runs gate 1 before gate 2 and quarantines before refusing.

## Pre-finalize contradiction scan

| Checked | Result |
|---|---|
| `LEADV2_SWEEP_MIN_AGE_S` / `_H` semantics: doc vs lib vs hook | **CONTRADICTION** → M1 |
| `LEADV2_QUOTA_CEILINGS` documented as a global override | **CONTRADICTION** → M6 |
| `LEADV2_PROVIDER_QUOTA_GATE=0` "kill switch" vs `== 0` string test | **CONTRADICTION (minor)** → L3 |
| `.mcp.json` `cwd:"."` vs `repowise-launch.sh` `$PWD`-walk header | **CONTRADICTION** → M3 |
| deny-extra `plugin_uninstall_floor` message vs runbook Rollback commands | **CONTRADICTION** → H1 |
| `worktree-sweepers.md` "force-discard … not changed by this gate" vs the new `--force` | **CONTRADICTION** → H2 |
| `review.diff` file list vs `origin/main..main` | **CONTRADICTION** → H4 |
| fanout comment rationale ("vendored wins because state-path-aware") vs new sibling-first order | **CONTRADICTION** → H5 |
| `LEADV2_MERGED_WORKTREE_SWEEP=0`, `CODEX_SKIP_QUOTA_GATE=1`, `GLM_SKIP_QUOTA_GATE=1`, `LEADV2_SKIP_DRIFT_GUARD=1`, `LEADV2_BURN_SOFT_24H/HARD_24H` (default path), `--name` ungated | all intact, none regressed |
| every path named in the new docs exists on disk | yes (`lib/leadv2-worktree-protected.sh`, `config/leadv2-quota-ceilings.sh`, `marketplace/…`, `docs/worktree-sweepers.md`) |
| `leadv2-state-path.sh --no-link` flag exists | yes (`leadv2-state-path.sh:61`) |
| ledger field names (`terminal`, `task_sig`, `founder_task_id`) | yes (`leadv2-dispatch-ledger.sh:19`) |

---

## Type / syntax check output (verbatim)

```
=== python3 -m py_compile (only .py in range) ===
py_compile: OK

=== mypy --strict plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py ===
plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:91: error: Function is missing a type annotation  [no-untyped-def]
plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:98: error: Missing type arguments for generic type "dict"  [type-arg]
plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:207: error: Function is missing a return type annotation  [no-untyped-def]
plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:228: error: Missing type arguments for generic type "list"  [type-arg]
plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:236: error: Library stubs not installed for "yaml"  [import-untyped]
plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:236: note: Hint: "python3 -m pip install types-PyYAML"
...
plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:1143: error: Call to untyped function "_best_effort_floor_pool" in typed context  [no-untyped-call]
Found 80 errors in 1 file (checked 1 source file)

=== baseline (origin/main version of the same file) ===
Found 80 errors in 1 file (checked 1 source file)

=== errors inside the changed hunk (lines 330-365) ===
plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:360: error: Function is missing a type annotation  [no-untyped-def]
--- count: 1 (pre-existing: `def live_codex_weekly_pct(quota_live_bin):` was already untyped) ---
```

**mypy verdict:** 80 errors before, 80 after — this diff introduces **no new** type errors. The file
is untyped as a whole and is not brought to `--strict` by this batch; not a blocking finding, but
`CODEX_LIMIT_REACHED_PCT: float` and a signature on `live_codex_weekly_pct(quota_live_bin: str) ->
float | None` would be a two-line down payment.

```
=== npx tsc --noEmit ===
N/A — zero TypeScript/TSX files in origin/main..main (no frontend surface in this batch;
modern-web-guidance self-guard: not applicable).

=== shellcheck -S error (4 highest-risk new/changed shell files) ===
(no output — clean)

=== bash -n over all 40 changed shell files ===
(no output — all clean)
```

## Suite runs performed for this review (raw tails)

```
$ bash plugins/leadv2/tests/test-deny-floor.sh
PASS: fragment-drift: every git rule in leadv2-deny-patterns.yaml carries GITGLOBAL
PASS: fragment-drift: every git rule in deny-extra.yaml carries GITGLOBAL
51 passed, 0 failed

$ bash plugins/leadv2/codex-lead/tests/test-lv2guard.sh
PASS: 61  FAIL: 0

$ bash plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
Results: 1 passed(red->green), 0 failed, 4 green-pre-fix        <- see H3, M4

$ bash plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
Results: 9 passed(red->green), 0 failed, 13 green-pre-fix       <- see M4
```

The suites are green. Green is not the same as "asserts the thing it says it asserts" — H3 and M4
are exactly that gap, and H2/H5 are behaviours no suite covers at all.

---

## Verdict

**BLOCK.** H1 (guard bypass), H2 (deliverable-destroying `--force`), H3 (tautological regression
test for the incident that motivated the lane), H4 (the artifact under review is not the change),
H5 (silent control-plane contract change shipped inside the omitted commit), and H6 (untested
live-path modules) must be resolved before this is pushed. H1, H2 and H3 are each a single small
patch plus one test row.

DELIVERABLE_COMPLETE
