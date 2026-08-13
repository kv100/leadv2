# GATE-WRONG-ROOT-FALSE-DEAD-01 — architect prepass

Scope: design only. No implementation. Diagnosis is runtime-verified against the real failing
artifact `docs/handoff/dispatch-3c663543/e2e-gate.log`.

---

## 1. Diagnosis (Requirement 1) — five independent defects, all confirmed

The mission posits two wrongs (W1 wrong suite, W2 wrong root). Runtime evidence shows **five**
distinct defects on the gate path. Each is independently sufficient to bury a green lane; they
compound.

### D1 — The gate never enters the lane. It runs the MAIN checkout. (root cause of W2)

`leadv2-dispatch-product-close.sh:1038,1046`:

```
elif ! e2e_cmd="$(bash "${SCRIPT_DIR}/leadv2-e2e-entrypoint.sh" "${ROOT}")"; then
...
  bash -c "${e2e_cmd} --scope changed" > "${HANDOFF}/e2e-gate.log" 2>&1; e2e_rc=$?
```

- `ROOT` is `$1` — the **PROJECT_ROOT** (`~/Projects/leadv2`), not the lane worktree.
- The same script already computes the correct lane path 240 lines earlier as `diff_root`
  (`:795-802`, `LEADV2_LANE_WORK_ROOT` → `leadv2-lane-worktree.sh path-of` fallback). The review
  half of the gate uses `diff_root`; **the e2e half never does.**
- `bash -c` inherits cwd; there is no `cd`. cwd is implicit — whatever the dispatcher had.

Consequence: the entrypoint resolves `~/Projects/leadv2/tests/run-all.sh` (main checkout),
`run-all.sh` recomputes its own `ROOT` from `BASH_SOURCE` → main checkout, and
`git -C "${ROOT}" diff --name-only HEAD` reports the **main checkout's** dirty files. The lane's
diff is never observed. This is the answer to mission question (a) and (c): scope=changed did not
"select the repo-root family for a plugins-only lane" — it never saw the lane at all.

`leadv2-phase8-e2e-gate.sh:31` has the same disease in a worse form:
`PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"` —
root derived from ambient cwd.

### D2 — `repo=/Users/kostiantyn.vlasenko/Projects` is a `../../..` off-by-one, verified

`tests/run-all.sh:52` unconditionally adds `${ROOT}/.claude/scripts/tests/run-core-offline.sh`.
`run-core-offline.sh` resolves its own anchors relative to its own location:

```
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
```

That arithmetic is correct **only** for its canonical home `plugins/leadv2/scripts/tests/`
(`../..` → `plugins/leadv2`, `../../..` → repo root). Executed from `.claude/scripts/tests/` it
yields (simulated on disk, exact):

| anchor | value |
|---|---|
| `TEST_DIR` | `<repo>/.claude/scripts/tests` |
| `PLUGIN_ROOT` | `<repo>/.claude` ← not a plugin root |
| `REPO_ROOT` | `/Users/kostiantyn.vlasenko/Projects` ← **the parent of all checkouts** |

This reproduces the mission's headline string exactly. No `git rev-parse` is involved; no symlink
is involved. It is a path-depth mismatch. All 8 failures follow mechanically:
`claude plugin validate <repo>/.claude` → "No manifest found" (seen verbatim in the log),
`$PLUGIN_ROOT/tests/*` and `$REPO_ROOT/tests/*` resolve to nonexistent paths, and `syntax_all`
walks the wrong tree.

### D3 — `.claude/scripts/tests/` is a 100-file drifted REAL copy, not a symlink farm

```
find .claude/scripts/tests -maxdepth 1 -type l  → 0
find .claude/scripts/tests -maxdepth 1 -type f  → 100
find plugins/leadv2/scripts/tests -name 'test-*.sh' → 111
diff .claude/.../run-core-offline.sh plugins/.../run-core-offline.sh → differ (stale, 2026-07-29)
```

This is precisely the defect the global CLAUDE.md forbids ("Never create a real copy of a
plugin-owned file inside a project… while a file is a copy it will drift, and it will drift
silently"). The always-on suite the gate executes is a 5-day-stale fork missing 11 suites,
including every suite the recent lanes registered. The `[TEST] FAIL: routine Standard -> Codex`
lines in the log are the stale copy asserting pre-GLM-FIRST-01 routing. **This is W1's real
mechanism**: not "wrong family" but "stale fork of the right family, reached by a path that also
breaks its anchors."

### D4 — Stem matching cannot reach the lane's own tests

`run-all.sh:78-84` searches only:
`${ROOT}/.claude/scripts/tests/`, `${ROOT}/plugins/leadv2/tests/`, `${ROOT}/tests/`.
It never searches `${ROOT}/plugins/leadv2/scripts/tests/` — the directory where every lane in this
repo registers its new suite. A lane's own tests are structurally unreachable by the gate.

### D5 — The foreign-failure path is parsing a log format that does not exist (Requirement 4)

`leadv2-e2e-ownership.sh:45-53` parses:

```
  Failures (blocking):
    - <suite-name>
```

`tests/run-all.sh` emits `[FAIL] <abs-path>` and `run-all: N passed, M failed, scope=...`. **The
two formats have never matched.** Verified by executing the real classifier against the real log:

```
$ bash plugins/leadv2/scripts/leadv2-e2e-ownership.sh . 3c663543 <writes> docs/handoff/dispatch-3c663543/e2e-gate.log
own=
foreign=
undecidable=harness_unparsed
owner_lane=unknown
```

`undecidable` non-empty → product-close's pure-foreign condition
(`-n foreign && -z own && -z undecidable`, `:1078`) is false → falls through to
`dead / e2e_regression`. **Every** failure in this repo is unclassifiable by construction; the
foreign-failure apparatus is dead code on the real path.

Second, latent bug in the same file: suites are located as `${SCRATCH}/tests/unit/${suite}` — a
convention this repo does not use. Even with the parser fixed, every suite would land in
`undecidable`.

Third: `plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh:77` builds a **fake entrypoint
that mirrors the `Failures (blocking):` shape**. The test passes against a fixture contract that
the production entrypoint never honours. That is why GATE-FOREIGN-FAILURE-01 shipped green and
never fired in production.

### Causal chain

```
D1 gate runs main checkout, implicit cwd
  └─ run-all sees main-checkout dirty set, not the lane's
       └─ D2+D3 always-on suite = stale fork at wrong depth → REPO_ROOT=~/Projects → 8 foreign failures
            └─ D4 lane's own suites never selected → lane's green evidence never produced
                 └─ D5 ownership parser returns harness_unparsed → not pure-foreign
                      └─ dead / e2e_regression  →  write-once terminal + dup-guard  →  lane permanently buried
```

Every one of the five lanes (M-8/99f0fe0f, 3c663543, c0d41b9b, f0752b69) hits this chain
identically; the verdict is independent of lane content, which is exactly why all five were false.

---

## 2. Design

Five surgical changes. Guiding constraint: **other repos must not change behaviour**
(Requirement 5). Every new path is guarded by `plugins/leadv2/` existence — persona-engine and
m3-market have no such directory, so all new branches are inert there.

### C1 — Pin the gate to a validated lane root (Requirement 2)

**File:** `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`

Add a helper `_pc_resolve_e2e_root()` used only by the e2e block. It reuses the already-resolved
`diff_root` (single source of truth for "where the lane's code actually is" — see the C1 comment
at `:788`, which makes exactly this argument for the diff half) and then **validates**:

| check | failure reason (named) |
|---|---|
| directory exists | `e2e_root_missing` |
| `git -C "$r" rev-parse --show-toplevel` equals `$r` (physical-path compared) | `e2e_root_not_toplevel` |
| `git -C "$r" rev-parse --git-common-dir` resolves into the same repo as `${ROOT}`'s | `e2e_root_foreign_repo` |
| resolved root is not an ancestor of `${ROOT}` (escape guard) | `e2e_root_escaped` |

On any failure: write `status: blocked / reason: <named>` to `e2e-gate.md`, `_dl_note refused
<reason>`, remove the passed flag, exit 4. **Blocked, never dead** — an unresolvable root is an
infrastructure fault, not a lane regression.

On success, the invocation becomes:

```
( cd "${_e2e_root}" && bash -c "${e2e_cmd} --scope changed" ) > "${HANDOFF}/e2e-gate.log" 2>&1
```

and the entrypoint is resolved from `${_e2e_root}`, not `${ROOT}`. The chosen root is echoed as
the first line of the log (`e2e-root: <path>`) so the artifact is self-describing.

**Same change in** `leadv2-phase8-e2e-gate.sh` (`:31`, `:146`, `:152`): replace the ambient
`git rev-parse --show-toplevel || pwd` derivation with the same validated helper, sourced from a
shared function so there is one mechanism, not two.

### C2 — Root-escape guard inside `run-all.sh` (Requirement 2, defence in depth)

**File:** `tests/run-all.sh`

1. After `ROOT` is computed from `BASH_SOURCE`, assert
   `git -C "${ROOT}" rev-parse --show-toplevel` == `${ROOT}`; on mismatch print
   `run-all: FATAL root_escape expected=<ROOT> resolved=<X>` and exit 2. Never run suites from an
   unverified root.
2. `add_suite()` currently does `cd "$(dirname "$p")" && pwd` — physical resolution that silently
   follows a symlink out of the tree. Add a containment check: a resolved suite path that is not
   under the physical `${ROOT}` is skipped with
   `run-all: SKIP out_of_tree <path>` on stderr. This makes D2-class escapes visible instead of
   silent.

Both guards are repo-agnostic and strictly additive — in a healthy repo they are no-ops.

### C3 — Right suite family (Requirement 3)

**File:** `tests/run-all.sh`. Smallest compliant change, chosen over an override-file mapping.

Rationale for the choice: an `e2e.yaml` prefix→entrypoint map adds a new config surface, a new
parser, and a new drift vector, and would still leave `run-all.sh` pointing at the stale
`.claude/` fork for every other caller. Teaching `run-all.sh` repo detection is ~6 lines, has no
new file format, and fixes every caller at once.

1. **Always-on suite, plugin-preferred:**

```
if [[ -f "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh" ]]; then
  add_suite "${ROOT}/plugins/leadv2/scripts/tests/run-core-offline.sh"
else
  add_suite "${ROOT}/.claude/scripts/tests/run-core-offline.sh"
fi
```

The `plugins/leadv2/` probe **is** the repo detection Requirement 5 asks for. persona-engine /
m3-market have no `plugins/leadv2/` → they take the existing `.claude/` branch verbatim. Zero
behavioural delta outside this repo. This simultaneously kills D2 (canonical path → correct
`../../..` arithmetic → correct `REPO_ROOT`) and D3 (canonical file → no stale fork).

2. **Stem search list** gains `${ROOT}/plugins/leadv2/scripts/tests/test-${stem}.sh` as the
   *first* candidate (D4). Non-existent elsewhere → inert.
3. **`--scope all` find list** gains `${ROOT}/plugins/leadv2/scripts/tests`. `find` already
   tolerates missing dirs via `2>/dev/null`.

Note: this design does **not** delete the drifted `.claude/scripts/tests/` tree. That is a
100-file hygiene cleanup with its own blast radius (other tooling may reference those paths) and
belongs in a separate task. C3 makes the gate stop *reading* it, which is what unblocks the lanes.
Flag for `docs/leadv2/open-threads.md`.

### C4 — Make the failure block machine-readable (Requirement 4, part 1)

**File:** `tests/run-all.sh`, summary section. Emit, before the existing `run-all:` line, the exact
block `leadv2-e2e-ownership.sh` already documents as the contract:

```
  Failures (blocking):
    - plugins/leadv2/scripts/tests/test-foo.sh
```

Suite names are **repo-relative to `${ROOT}`** (not basenames, not absolute) so the classifier can
locate them in the scratch tree by direct path. Emitted only when `FAIL > 0`; the existing
`[FAIL] <abs>` lines and the `run-all:` summary line are untouched, so any human or tooling reading
the current format keeps working. Additive for other repos.

### C5 — Make the classifier locate this repo's suites (Requirement 4, part 2)

**File:** `plugins/leadv2/scripts/leadv2-e2e-ownership.sh`

Suite location becomes ordered, first hit wins:

1. `${SCRATCH}/${suite}` — repo-relative path (new; what C4 emits)
2. `${SCRATCH}/tests/unit/${suite}` — legacy convention (unchanged, other repos)

Everything else — the `git archive HEAD` scratch tree, the lane-write overlay, the re-run,
fail-closed-to-`own` on any preparation failure, `owner_lane` attribution — is unchanged. With C4+C5
the reproduced case classifies as `foreign` (the 8 stale-fork failures are in files untouched by
any of the five lanes' `LANE_WRITES`) → product-close's `:1078` pure-foreign branch fires →
`verdict=foreign_failure`, sentinel stamped `scope=lane_writes`, ledger note `parked`, **never**
`dead`.

**Also fix the fixture lie:** `test-e2e-foreign-failure.sh:77`'s fake entrypoint must be re-pointed
at the real `tests/run-all.sh` output shape (or, better, must invoke the real `run-all.sh` against a
fixture tree). A test whose fixture asserts a contract production does not emit is worse than no
test — it is what let D5 ship green.

### Data flow, after

```
1. product-close  →  diff_root  (LEADV2_LANE_WORK_ROOT | lane-worktree path-of)
2.                →  _pc_resolve_e2e_root: exists ∧ is-toplevel ∧ same-repo ∧ not-ancestor
3.                →  FAIL → e2e-gate.md status=blocked reason=<named>, exit 4      [never dead]
4.                →  OK   → leadv2-e2e-entrypoint.sh "${_e2e_root}"
5.                →  ( cd "${_e2e_root}" && bash -c "<cmd> --scope changed" )
6. run-all.sh     →  ROOT from BASH_SOURCE, asserted == git toplevel               [C2]
7.                →  always-on: plugins/leadv2/scripts/tests/run-core-offline.sh   [C3]
8.                →  changed = git -C ROOT diff HEAD  (now the LANE's diff)
9.                →  stem match incl. plugins/leadv2/scripts/tests/                [C3]
10.               →  on FAIL: "  Failures (blocking):" + repo-relative names       [C4]
11. ownership.sh  →  parse block → locate ${SCRATCH}/${suite} → differential re-run [C5]
12. product-close →  own=∅ ∧ foreign≠∅ ∧ undecidable=∅ → foreign_failure / parked
```

### Interface contracts

| producer | consumer | contract | status |
|---|---|---|---|
| `run-all.sh` stdout | `leadv2-e2e-ownership.sh` | `  Failures (blocking):` + `    - <repo-rel path>` | **new (C4)** — was undefined |
| `run-all.sh` exit | product-close `:1046` | 0 = all selected suites green | unchanged |
| `_pc_resolve_e2e_root` | e2e block | abs path, or named reason on stderr + rc≠0 | **new (C1)** |
| `leadv2-e2e-entrypoint.sh <root>` | both gates | command string, no scope args | unchanged; **argument now the lane root** |
| `ownership.sh` stdout | product-close `:1070` | `own=/foreign=/undecidable=/owner_lane=` | unchanged |

No DB schema changes. No migrations. This subsystem is filesystem + ledger only.

---

## 3. Risks

| # | risk | mitigation |
|---|---|---|
| R1 | C3 flips this repo's always-on suite from the stale 100-file fork to the canonical 111-file set — the new suites have never run in the gate and may surface real pre-existing failures. | Requirement's own acceptance already demands "green vs current-main baseline, **verify count first**": run the canonical suite on clean main BEFORE the change and record pass/fail counts. Any pre-existing failure is a separate task, not a blocker for this one — but it must be named in the report, not absorbed. |
| R2 | `diff_root` may be `${ROOT}` when no lane worktree exists (manual re-run, direct harness invocation). Pinning to it is then a no-op that still runs the main checkout. | Correct and intended — that IS the right root for a non-lane run. Validation still applies. Log the `e2e-root:` line so the artifact says which mode ran. |
| R3 | Two lanes share `${ROOT}` and both run `git archive HEAD` scratch trees concurrently. | Pre-existing; `mktemp -d` with `$$` already isolates. C1 reduces exposure (each lane now runs in its own worktree). No new race. |
| R4 | C4's failure block is a new stdout contract — a third consumer might parse `run-all` output. | Additive only; no existing line changes. Grep confirmed the only parser is `ownership.sh`. |
| R5 | `--scope all` now enumerates 111 more suites in this repo; runtime grows. | The gate uses `--scope changed`, not `all`. `all` is a manual/CI path. Accept. |
| R6 | The drifted `.claude/scripts/tests/` tree stays on disk and will drift further; something else may still read it. | Out of scope here (see C3 note). Must be queued as its own thread — recommend `docs/leadv2/open-threads.md` entry the same turn. |
| R7 | `git rev-parse --show-toplevel` returns a physical path; `${diff_root}` may be a logical path through a symlink → false `e2e_root_not_toplevel`. | Compare via `python3 -c 'os.path.realpath'` on both sides — the codebase already has `_pc_realpath` at `:806` for exactly this reason. Reuse it; do not add a second realpath. |
| R8 | Fixing D5 makes the foreign-failure branch fire for the first time in production. If `LANE_WRITES` is inaccurate for a lane, a genuine own-regression could be laundered as foreign. | The differential re-run is the guard: an own regression still fails against the lane-only tree → `own` → dead. `own` always wins (`:1066` comment). Test case (b) is the regression proof. |

### Constraint checklist

1. **Env vars** — no new env vars. Existing `LEADV2_E2E_OWNERSHIP`, `LEADV2_LANE_WORK_ROOT`,
   `LEADV2_E2E_CMD` reused as-is, all `LEADV2_*`. No drift. PASS.
2. **Paths** — all listed paths verified on disk except `plugins/leadv2/scripts/tests/test-e2e-gate-lane-root.sh` **(to-create)**. PASS.
3. **`claude -p`** — this change introduces none. N/A.
4. **Concurrent access** — R3. No new shared-write surface.
5. **Config contradiction** — none introduced; C3's repo detection is a filesystem probe, not config.

---

## 4. Tests (Requirement 6)

New suite `plugins/leadv2/scripts/tests/test-e2e-gate-lane-root.sh`, registered in
`plugins/leadv2/scripts/tests/run-core-offline.sh`. Fixture pattern: a scratch `git init` tree
plus a real `git worktree add` lane, a stub `tests/run-all.sh` where the case needs a controlled
verdict, and the real `run-all.sh` where the case is about `run-all` itself.

| case | fixture | expected observable |
|---|---|---|
| (a) green plugin-suite lane | lane worktree, plugin suite present and passing | `e2e-gate.log` first line `e2e-root: <lane worktree>`; `e2e-gate-passed.flag` written; ledger `verdict=pass` |
| (b) lane's OWN new suite fails | lane's `LANE_WRITES` suite exits 1, reproduces on the lane-only scratch tree | `e2e-gate.md` `reason: e2e_regression`; ledger `dead` — real failures still die |
| (c) foreign suite fails, lane diff plugins-only | failing suite untouched by lane `LANE_WRITES`, passes on lane-only tree | ledger `verdict=foreign_failure`; `e2e-gate.md` `status: fail_foreign`; passed-flag present with `foreign_failures:` — **not** dead |
| (d) root-resolution escape | `diff_root` pointed at a non-toplevel subdir / foreign repo | `e2e-gate.md` `status: blocked` with the named reason (`e2e_root_not_toplevel` / `e2e_root_foreign_repo`); NO suite executed; ledger `refused`, not dead |
| (e) D2 regression guard | invoke `run-core-offline.sh` from a copy at `.claude/scripts/tests/` depth | `run-all` prints `SKIP out_of_tree` or the always-on selection resolves to the `plugins/` path; the string `repo=/Users/kostiantyn.vlasenko/Projects` never appears |
| (f) ownership parse round-trip | real `run-all.sh` output with 2 failures → `ownership.sh` | `foreign=` / `own=` populated; `undecidable=harness_unparsed` never emitted |
| (g) other-repo no-op | fixture tree with `tests/run-all.sh` but no `plugins/leadv2/` | suite selection byte-identical to pre-change output |

Case (g) is the Requirement-5 guard and is not optional — it is the only mechanical proof that
persona-engine and m3-market are untouched.

**Baseline discipline:** record `run-core-offline.sh` pass/fail/missing counts on clean main
BEFORE any edit, and compare after. A count that only rises because the stale fork was swapped for
the canonical set is expected; a count that falls is a regression.

---

## 5. Non-goals (explicit — implementing agent must not touch)

- Review-gate logic, the reviewer arm, critic rounds.
- The DWR resume block (`GLM-DIED-WITH-WORK-RESUME-01`, just landed).
- `run-all.sh`'s general contract for other repos — every new branch is guarded by a
  `plugins/leadv2/` filesystem probe; case (g) proves it.
- Deleting or de-duplicating the drifted `.claude/scripts/tests/` tree (100 files) — separate task,
  queue as its own thread.
- Any relaxation of the gate for genuinely-failing own suites — case (b) is the regression proof.
- Fixing the individual stale-fork test failures (e.g. the GLM-FIRST routing assertions). They
  disappear when C3 points at the canonical file; if any survive against canonical, report — do not
  fix here.
- Ledger surgery / un-burying the five already-dead lanes. Separate remediation.
- `LEADV2_E2E_CMD` semantics, the `e2e.yaml` override format.
- Committing. Report only.

---

## 6. Requirement traceability

| req | covered by | note |
|---|---|---|
| 1 diagnose first, runtime evidence | §1 D1–D5 | classifier re-run + `../../..` simulation + symlink/file census, all executed |
| 2 root pinned, fail hard named reason | C1, C2 | blocked/refused, never dead |
| 3 right suite family | C3 | plugin-preferred always-on + stem dir; smallest change, rationale in C3 |
| 4 foreign-failure honesty | C4, C5 | root cause was a never-matching log format, not policy |
| 5 non-goals respected | §5 + case (g) | repo detection via `plugins/leadv2/` probe |
| 6 tests (a)–(d) + registration | §4 (a)–(g) | (e)(f)(g) added as regression/no-op guards |

---

acceptance:
- surface: log_line
  observable: In `docs/handoff/dispatch-<sig8>/e2e-gate.log`, the first line names the lane's own
    worktree directory, and the summary line at the bottom names the repository the lane lives in —
    never the parent folder that contains all checkouts.
  authored_at: 2026-08-03T21:05:00Z
- surface: file_artifact
  observable: For a lane whose only failing suites are files it never touched,
    `docs/handoff/dispatch-<sig8>/e2e-gate.md` reads `status: fail_foreign` with
    `reason: foreign_failure` and lists the foreign suites — and the lane is parked, not buried.
  authored_at: 2026-08-03T21:05:00Z
- surface: file_artifact
  observable: For a lane whose own newly-added suite genuinely fails,
    `docs/handoff/dispatch-<sig8>/e2e-gate.md` still reads `reason: e2e_regression` — a real
    regression is still fatal.
  authored_at: 2026-08-03T21:05:00Z
- surface: file_artifact
  observable: When the lane's working directory cannot be validated,
    `docs/handoff/dispatch-<sig8>/e2e-gate.md` reads `status: blocked` and names why, and the log
    shows no test suite was executed at all.
  authored_at: 2026-08-03T21:05:00Z

LANE_WRITES: tests/run-all.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-phase8-e2e-gate.sh, plugins/leadv2/scripts/leadv2-e2e-ownership.sh, plugins/leadv2/scripts/tests/test-e2e-gate-lane-root.sh, plugins/leadv2/scripts/tests/test-e2e-foreign-failure.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
