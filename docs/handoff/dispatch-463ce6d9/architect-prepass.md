# GATE-ROOT-ARITH-01 — architect prepass

Scope: canonical `plugins/leadv2/scripts/tests/run-core-offline.sh` root arithmetic. Design only.

## 0. Live facts confirmed on this main (9158921)

| Fact | Evidence |
|---|---|
| persona-engine + respiro-ios `.claude/scripts/tests/run-core-offline.sh` are symlinks → canonical | `ls -la` both are `-> /Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/tests/run-core-offline.sh` (absolute, 91 bytes) |
| m3-market has **no** such symlink | path absent |
| canonical header lines 8–10 | `TEST_DIR=logical dirname`; `PLUGIN_ROOT=$TEST_DIR/../..`; `REPO_ROOT=$PLUGIN_ROOT/../..` |
| `REPO_ROOT` has exactly **one** consumer | line 74: `run_check "status surface single-lead + census" bash "$REPO_ROOT/tests/test-status-surface-single-lead.sh"` |
| `PLUGIN_ROOT` consumers | line 38 `syntax_all` find root; line 46 `claude plugin validate`; lines 67, 69 (two `$PLUGIN_ROOT/tests/…` suites) |
| `TEST_DIR` consumers | ~27 sibling suite registrations |
| registrations on this main | `grep -c '^run_check'` = **33** (mission says 32 — stale by one; see D3) |
| leadv2 repo-root COPY at `.claude/scripts/tests/run-core-offline.sh` | real file, 22 registrations, **11 behind** canonical, and missing the whole `MISSING=` accounting block. Same `../..` header verbatim. |
| `tests/run-all.sh` | already git-anchored (`_git_toplevel` root_escape guard) + plugin-preferred C3 probe. **No `../..` root pattern.** Requires no change. |
| bash on box | `bash` 5.3.9, `/bin/bash` 3.2.57 |

### Why the overshoot happens
Through a 3-deep symlink path, `dirname "${BASH_SOURCE[0]}"` yields the **logical** dir
`persona-engine/.claude/scripts/tests`. Two `../..` hops from there give
`PLUGIN_ROOT=persona-engine/.claude`, `REPO_ROOT=/Users/kostiantyn.vlasenko/Projects` — the
parent of every checkout. Same arithmetic family as the Aug-3 false-dead lanes
(`docs/handoff/dispatch-3c663543/e2e-gate.log` → `repo=/Users/kostiantyn.vlasenko/Projects`).

## 1. Design — three roots, three different derivations

The mission's two clauses ("TEST_DIR stays LOGICAL" and "TEST_DIR siblings must keep pointing at
the canonical plugin tree") are only reconcilable by **splitting the variable**. One logical
anchor, used *solely* for the git question; everything plugin-internal derives physically.

```
LOGICAL_DIR   = logical dirname of BASH_SOURCE   ──git rev-parse──▶ REPO_ROOT   (invoking checkout)
PHYS_TEST_DIR = symlink-resolved dirname          ──../..──────────▶ PLUGIN_ROOT (canonical plugin)
TEST_DIR      = "$PLUGIN_ROOT/scripts/tests"      (physical; sibling suite registrations)
```

Replace lines 8–10 with:

```bash
# --- root arithmetic (GATE-ROOT-ARITH-01) -------------------------------------
# LOGICAL_DIR: the entry path as written by the caller — symlink NOT resolved.
# It is the only thing that answers "which checkout was this invoked from?".
LOGICAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT: derived from git, never from ../.. hops. A symlink entry from
# persona-engine resolves to persona-engine's toplevel; a canonical entry (incl.
# any leadv2 worktree lane) resolves to that worktree's toplevel.
REPO_ROOT="$(git -C "$LOGICAL_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ] || [ ! -e "$REPO_ROOT/.git" ]; then
  printf -- '[CORE-OFFLINE] FATAL repo_root_unresolvable from=%s resolved=%s\n' \
    "$LOGICAL_DIR" "${REPO_ROOT:-<not-a-git-checkout>}" >&2
  exit 2
fi

# PHYS_TEST_DIR / PLUGIN_ROOT: physical location of THIS file. Plugin-internal
# siblings must resolve into the canonical plugin tree regardless of entry path.
# bash-3.2 safe: manual readlink chain, no `readlink -f` / `realpath`.
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
PHYS_TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
PLUGIN_ROOT="$(cd -P "$PHYS_TEST_DIR/../.." && pwd)"
TEST_DIR="$PLUGIN_ROOT/scripts/tests"
unset _src _dir
# -----------------------------------------------------------------------------
```

Everything below line 10 is untouched: `TEST_DIR`, `PLUGIN_ROOT`, `REPO_ROOT` keep their names
and meanings, so the 33 registrations and both `$PLUGIN_ROOT/tests/…` lines need no edit.

### Non-obvious constraints the implementer MUST honour

| # | Constraint | Why |
|---|---|---|
| C1 | `|| true` on the `git rev-parse` assignment | file runs `set -euo pipefail`. `X="$(failing-cmd)"` aborts with git's exit code **before** the named error ever prints — the guard would be dead code and the failure unnamed. |
| C2 | `[ ! -e "$REPO_ROOT/.git" ]`, **never** `-d` | leadv2 lanes are git **worktrees**, where `.git` is a regular *file*. `-d` fails every lane → every lane blocked. |
| C3 | exit code `2`, not `1` | `1` is already "a suite failed". `2` distinguishes "never ran" from "ran and failed" for the gate classifier, matching `run-all.sh`'s own `exit 2` for `root_escape`. |
| C4 | guard placed **before** the first `run_check` | requirement 2: zero suites may run. It is currently placed before all function definitions too — safe, they are only defined, not called. |
| C5 | `cd -P` in the readlink loop | without `-P`, the loop re-introduces the logical path it is trying to escape. |
| C6 | `readlink` bare (no `-f`) | macOS `/usr/bin/readlink` has no GNU `-f`; the manual loop is the fallback-free portable form. |

## 2. Probe hook (enables the mission's manual acceptance probe cheaply)

Add immediately after the block above:

```bash
if [ -n "${LEADV2_CORE_OFFLINE_PROBE:-}" ]; then
  printf -- '[CORE-OFFLINE] probe LOGICAL_DIR=%s REPO_ROOT=%s PLUGIN_ROOT=%s TEST_DIR=%s\n' \
    "$LOGICAL_DIR" "$REPO_ROOT" "$PLUGIN_ROOT" "$TEST_DIR"
  exit 0
fi
```

Two reasons this is load-bearing, not convenience:
1. **The new test suite is registered inside run-core-offline.sh itself** (requirement 5). Without
   a header-only entry point, the suite would re-invoke the full runner → unbounded recursion,
   ~33 suites × N. The probe flag is the recursion cut.
2. The ACCEPTANCE manual probe ("`bash ~/Projects/persona-engine/.claude/scripts/tests/run-core-offline.sh`
   … or its header logic") becomes a single sub-second command instead of a full foreign-repo run.

Env var name follows the `LEADV2_*` convention (checklist item 1); `grep -rn LEADV2_CORE_OFFLINE_PROBE`
returns nothing today — no collision (checklist item 5).

## 3. The repo-root COPY — convert to a relative symlink

Requirement 3 offers "same fix, or replace with a symlink — whichever is smaller". **Symlink wins**
and is the only option consistent with the global shared-trees policy ("never a real copy of a
plugin-owned file"). It also retires an 11-suite-stale fork in one move instead of maintaining the
same header fix in two places forever.

```
.claude/scripts/tests/run-core-offline.sh
  → ../../../plugins/leadv2/scripts/tests/run-core-offline.sh
```

**The target MUST be relative.** An absolute `/Users/.../Projects/leadv2/plugins/...` target — the
form the other repos use — would make every leadv2 worktree lane read the *main* checkout's file,
re-creating a cross-tree read one task after GATE-WRONG-ROOT-FALSE-DEAD-01 closed that class.

Interaction check with the just-shipped `run-all.sh` (requirement 4 — do not undo C3): C3's
`plugins/leadv2/` probe makes leadv2's own gate prefer the canonical path, so this conversion is a
no-op for the leadv2 gate path. It only changes what *direct* invokers of the `.claude/` path see:
33 current suites instead of 22 stale ones, with correct roots. `add_suite`'s `out_of_tree`
containment check still passes — a relative in-repo symlink's logical dirname stays under `ROOT`.

## 4. Full `../..` inventory (requirement 3)

**In-scope — repo-root arithmetic anchored on a plugin path (the defect family):**

| File:line | Expression | Disposition |
|---|---|---|
| `plugins/leadv2/scripts/tests/run-core-offline.sh:10` | `REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"` | **FIX** (§1) |
| `.claude/scripts/tests/run-core-offline.sh:10` | identical | **REPLACE FILE WITH SYMLINK** (§3) |
| `plugins/leadv2/scripts/leadv2-skill-proof.sh:24` | `REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"` | **Same defect, OUT OF SCOPE** → open-threads follow-up. Not reached by this gate; changing it drags the skill-proof gate into a root-arith lane. |

**Textually similar, semantically different — DO NOT TOUCH:**

- ~30 `PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"` across `plugins/leadv2/scripts/*.sh`
  (`leadv2-resume`, `phase-advance`, `leadv2-router-v2`, `leadv2-helpers.sh:523,2118,2227`, …).
  Two hops from `scripts/` targets the **plugin root**, not the repo root — correct by
  construction, and most already carry a `LEADV2_PROJECT_ROOT`/`CLAUDE_PROJECT_DIR` override.
- `../../..` three-hop variants: `leadv2-one-copy-convert.sh:25` (`CANONICAL_ROOT`),
  `leadv2-provider-canary.sh:132` (`CHECKOUT_ROOT`), `plugins/leadv2/tests/test-memory-index-gc.sh:3`.
  Correct arithmetic for canonical entry; symlink-fragile in principle but not on any path this
  task touches.
- `leadv2-route-bandit.sh:69` already prefers `git rev-parse` — the pattern this task generalises.

**`tests/run-all.sh` carries no `../..` root pattern** — it is already git-anchored. Requirement 3's
"run-all search-path logic" audit resolves to: **no change needed**, C2/C3/C4 stay exactly as shipped.

## 5. Tests — `plugins/leadv2/scripts/tests/test-core-offline-root-arith.sh` (to-create)

Registered in `run-core-offline.sh` as the 34th line:
`run_check "core-offline root arithmetic (git-derived REPO_ROOT)" bash "$TEST_DIR/test-core-offline-root-arith.sh"`

| Case | Setup | Assertion (on the probe's rendered line) |
|---|---|---|
| (a) 3-deep symlink from a fixture repo | `mktemp -d` → `git init -q` → `mkdir -p .claude/scripts/tests` → symlink `run-core-offline.sh` → canonical → run with `LEADV2_CORE_OFFLINE_PROBE=1` | `REPO_ROOT=` equals the fixture's own `git rev-parse --show-toplevel`; `PLUGIN_ROOT=` equals canonical plugin root; **not** the fixture's parent |
| (b) canonical invocation | run canonical path with probe from the current checkout | `REPO_ROOT=` equals `git -C <canonical> rev-parse --show-toplevel`; `TEST_DIR=` equals canonical `scripts/tests` |
| (b′) worktree entry | `git worktree add` a throwaway lane, invoke that lane's `plugins/leadv2/scripts/tests/run-core-offline.sh` with probe | `REPO_ROOT=` equals the **lane's** toplevel (proves C2 — `.git`-as-file passes the guard) |
| (c) non-git location | copy canonical into `mktemp -d` outside any repo (or symlink from there), run **without** the probe flag | stderr contains `repo_root_unresolvable`; exit status `2`; stdout contains **zero** `[CORE-OFFLINE] ` suite-name lines |

Test-authoring gotchas:
- macOS `mktemp -d` yields `/var/folders/...` which is a symlink to `/private/var/...`. Never
  compare against the literal `mktemp` output — compare against `git -C "$fixture" rev-parse --show-toplevel`.
- Wrap every fixture invocation in `env -u GIT_DIR -u GIT_WORK_TREE`. If the runner is ever invoked
  from inside a git hook or a `git` subprocess, an inherited `GIT_DIR` makes `rev-parse` answer for
  the *wrong* repo and case (a) silently passes for the wrong reason.
- Case (c) must ensure the temp dir has no git ancestor — `/tmp` on macOS is safe, but assert it:
  `git -C "$d" rev-parse --show-toplevel` must fail before running the case.
- `trap … EXIT` cleanup of fixtures and `git worktree remove --force` for (b′).

## 6. Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | **Foreign-repo runs still exit nonzero.** Line 74 registers `$REPO_ROOT/tests/test-status-surface-single-lead.sh` — a leadv2-repo-native suite. With REPO_ROOT correctly = persona-engine, that file does not exist there → `MISSING=1` → exit 1. | High (expectation, not regression) | Today it is *already* MISSING (`/Users/.../Projects/tests/…` doesn't exist either), so this is **no behavioural regression** — it just becomes correctly attributed. Requirement 4 forbids touching the registration list, so **leave it**. The ACCEPTANCE probe asks only that persona-engine print `REPO_ROOT=persona-engine`, which it will. Gating repo-native suites on repo identity is a follow-up thread, not this lane. |
| R2 | `set -e` kills the script before the named error | Critical | C1 — `|| true`. Must be verified by case (c) asserting the *string* `repo_root_unresolvable`, not merely a nonzero exit. |
| R3 | `-d "$REPO_ROOT/.git"` blocks every worktree lane | Critical | C2 — `-e`, plus test case (b′) as the live proof. |
| R4 | Absolute symlink target for the `.claude/` copy breaks worktree lanes | Critical | §3 — relative `../../../plugins/...`. Verify with `readlink .claude/scripts/tests/run-core-offline.sh` from inside a lane. |
| R5 | Self-recursion: the new suite is registered inside the runner it tests | High | §2 probe flag; the suite must never invoke the runner without `LEADV2_CORE_OFFLINE_PROBE=1` except in case (c), where the guard exits before any `run_check`. |
| R6 | Baseline count drift | Medium | See D3 — capture the real `suites passed=N` line **before** editing, not the mission's remembered number. |
| R7 | Concurrent access (checklist item 4) | Low | Both writes are single-file, single-step; no two parallel steps read+write the same path. Fixtures live under `mktemp -d`, so parallel lanes cannot collide. No lock needed. |
| R8 | `claude plugin validate "$PLUGIN_ROOT"` (line 46) now always validates *canonical* even when entered via a foreign symlink | Low, intended | This is the point of physical PLUGIN_ROOT — previously it validated `persona-engine/.claude`, which is not a plugin at all. |

## 7. decisions[]

- **D1** `source: architect` — Split the single logical anchor into `LOGICAL_DIR` (git question only) + physical `PHYS_TEST_DIR`/`PLUGIN_ROOT`, and re-derive `TEST_DIR` from `PLUGIN_ROOT`. The mission's two clauses are otherwise contradictory; this satisfies both intents and makes foreign-symlink entry run canonical siblings rather than a repo's stale copies.
- **D2** `source: architect` — `.claude/scripts/tests/run-core-offline.sh` → **relative** symlink, not a duplicated header fix. Smaller, policy-aligned, kills an 11-suite-stale fork. Relative is mandatory (R4).
- **D3** `source: architect(self-check)` — Mission states baseline 32; `grep -c '^run_check'` on 9158921 returns **33**. Implementer must record the actual `[CORE-OFFLINE] suites passed=N` line from an untouched-tree run as the baseline and compare against `N+1` after registering the new suite. Do not trust the number in the brief.
- **D4** `source: architect(self-check)` — Checklist item 3 (`claude -p` flags) N/A: no `claude -p` invocation in scope. Checklist item 2: all paths verified on disk except the two marked `(to-create)`.

## 8. Non-goals (explicit — implementer ignores)

- No change to the registration list beyond **appending** the one new suite (requirement 4).
- No change to `tests/run-all.sh` — its C2/C3/C4 guards are correct and must not be undone.
- No change to `leadv2-dispatch-product-close.sh` or `leadv2-phase8-e2e-gate.sh`.
- No change to any file outside `~/Projects/leadv2` — persona-engine and respiro-ios symlinks
  already point at canonical; fixing canonical fixes them. m3-market has no symlink; nothing to do.
- No fix to `leadv2-skill-proof.sh:24` (same family, separate lane — open-threads item).
- No deletion or de-duplication of the rest of the stale `.claude/scripts/tests/` copy tree.
- **No commit.** Rollback = `git checkout` of the touched files.

## 9. acceptance

```yaml
acceptance:
  - surface: log_line
    observable: >-
      Running the persona-engine symlink probe prints one line reading
      "[CORE-OFFLINE] probe LOGICAL_DIR=/Users/kostiantyn.vlasenko/Projects/persona-engine/.claude/scripts/tests
      REPO_ROOT=/Users/kostiantyn.vlasenko/Projects/persona-engine
      PLUGIN_ROOT=/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2 ..." — the REPO_ROOT
      field names the persona-engine checkout, never the shared parent /Users/kostiantyn.vlasenko/Projects.
    authored_at: 2026-08-04T02:19:11Z
  - surface: log_line
    observable: >-
      The final summary line of a full canonical run reads
      "[CORE-OFFLINE] suites passed=<baseline+1> failed=0 missing=0
      repo=/Users/kostiantyn.vlasenko/Projects/leadv2" — the repo= field names the invoking
      leadv2 checkout (or lane worktree), the failed and missing counts are both zero, and the
      passed count is exactly one higher than the same line captured on the untouched tree.
    authored_at: 2026-08-04T02:19:11Z
  - surface: log_line
    observable: >-
      Invoking the runner from a directory that is not inside any git checkout prints a single
      error line containing "repo_root_unresolvable" and nothing else — no suite-name lines
      appear at all — and the shell reports a nonzero exit.
    authored_at: 2026-08-04T02:19:11Z
  - surface: file_artifact
    observable: >-
      .claude/scripts/tests/run-core-offline.sh is listed as a symbolic link whose target is the
      relative path ../../../plugins/leadv2/scripts/tests/run-core-offline.sh — no absolute
      /Users/... prefix appears in the target.
    authored_at: 2026-08-04T02:19:11Z
  - surface: log_line
    observable: >-
      Both bash 5 and /bin/bash 3.2 syntax-check the two edited/created shell files silently —
      no parse-error output on either interpreter.
    authored_at: 2026-08-04T02:19:11Z
```

LANE_WRITES: plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/test-core-offline-root-arith.sh, .claude/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
