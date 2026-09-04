# LANE-STATE-LEAK-01 fix round — mechanism-closed design (architect prepass)

Lane tree: `.claude/worktrees/273da7e9` (branch `worktree-273da7e9`, merge-base `aed1f2b`).
The nine touched files in the mission are the `aed1f2b..HEAD` diff of that worktree — the main
checkout has an unrelated dirty tree, so every file:line below is read from the lane worktree.

---

## 0. Root cause of the one red test — stated once

**`test-glm-deferred-ladder.sh` case (d) is red because leg (a) and leg (d) resolve
`.arm-exceptions-<day>` under two different control-plane roots: the writer runs with no
`LEADV2_STATE_ROOT` (so the resolver takes the no-git degrade branch and writes inside the
sandbox root), while the reader is invoked with `LEADV2_STATE_ROOT=${TMP_ROOT}/state-d` and
reads an empty directory.**

Probe (run in the lane worktree, `date -u +%Y%m%d` = 20260823):

```
$ T=$(mktemp -d); R="$T/root"; mkdir -p "$R/docs/leadv2"; D=$(date -u +%Y%m%d)
$ PROJECT_ROOT="$R" bash plugins/leadv2/scripts/leadv2-state-path.sh ".arm-exceptions-$D"
/var/folders/.../tmp.A9dbwCzOpQ/root/docs/leadv2/.arm-exceptions-20260823      # ← leg (a) writer
$ PROJECT_ROOT="$R" LEADV2_STATE_ROOT="$T/state-d" bash plugins/leadv2/scripts/leadv2-state-path.sh ".arm-exceptions-$D"
/var/folders/.../tmp.A9dbwCzOpQ/state-d/.arm-exceptions-20260823                # ← leg (d) reader
```

Why it was green before this lane and is red now: the renderer used to read
`os.path.join(root, "docs", "leadv2", f".arm-exceptions-{today}")` off `PROJECT_ROOT`
(`leadv2-broad-status.sh:615`, pre-image), and `PROJECT_ROOT` **is** `${ROOT}` in leg (d) — same
file the writer used. This lane correctly routed that read through the resolver
(`leadv2-broad-status.sh:203`), and the resolver honours `LEADV2_STATE_ROOT`
(`leadv2-state-path.sh:106-107`), which leg (d) has been setting since before this lane and leg
(a) has never set.

Why the neighbouring legs stay green and hid this for the other two names:
`.codex-credits-empty.stamp` is STANDARD class and `glm-deferred.jsonl` is MERGE class — both get
a symlink planted at `<root>/docs/leadv2/<name>` by the migration block
(`leadv2-state-path.sh:315-503`), so a raw read at the old path still lands on the control-plane
file. `.arm-exceptions-<day>` is GLOB class and is **deliberately never symlinked**
(`leadv2-state-path.sh:520-524`). It is the only one of the three where a state-root split is
observable. The lane's own comment at `leadv2-broad-status.sh:194-201` already says this; what it
did not follow through on is that the *test harness*, not the production code, is where the split
lives.

**The assertion is right and must not be weakened.** The defect is in the suite's env threading:
leg (d) sandboxes the control plane for the reader only. Fixing the pairing means giving writer
and reader one root.

### Chosen fix — Option A (reader stops overriding)

Delete `LEADV2_STATE_ROOT="${TMP_ROOT}/state-d"` from the leg-(d) renderer invocation
(`test-glm-deferred-ladder.sh:283`) and `LEADV2_STATE_ROOT="${TMP_ROOT}/state-neg"` from the
negative leg (`:303`). Both roots (`${ROOT}`, `${ROOT_NEG}`) are `mktemp -d` trees that
`make_tenant_root` never `git init`s, so the resolver takes the no-git degrade branch
(`leadv2-state-path.sh:110-137`) and pins state at `<that root>/docs/leadv2` — per-root
isolation by construction, identical to what every writer leg in this suite already gets, and
provably not the developer's real control plane (the degrade branch returns before the ephemeral
redirect and before the B1 net).

Rejected — **Option B** (thread a shared per-root `LEADV2_STATE_ROOT` into the dispatch legs too):
it is more hermetic on paper but it moves leg (a)'s `glm-deferred.jsonl` assertions onto a
freshly-planted symlink whose target does not exist at plant time, and leg (a) asserts an
*ordering* property against a snapshot the stub sonnet takes with `cp` at spawn instant
(`test-glm-deferred-ladder.sh:105-119`). That converts a green ordering proof into a
symlink-timing proof. Not worth it for this round. If a later lane wants full hermeticity it must
thread one `LEADV2_STATE_ROOT` **per tenant root** (`state-ab`, `state-c`, `state-neg`,
`state-empty`, `state-e2`) — never one global export, which would let leg (b)'s
"no deferred glm tasks" and leg (d)-negative see leg (a)'s rows and go red.

### Anti-regression guard (required, not optional)

Option A alone restores green but leaves the failure mode silent: if a future edit re-sandboxes
one side, leg (d) fails again with "line missing", which reads like a renderer bug and cost this
lane a whole round. Add, immediately before the leg-(d) render:

- resolve the reader's path exactly as the renderer will (`PROJECT_ROOT="${ROOT}" bash
  "${STATE_PATH_SH}" ".arm-exceptions-$(date -u +%Y%m%d)"`), and
- assert that file exists and is non-empty; on miss `fail "(d) setup: writer/reader state-root
  mismatch"` naming both paths.

That turns "the rendered line is missing" into "the two halves resolved to different roots", which
is the sentence this round had to be spent deriving.

---

## 1. CALLERS / CALLEES

### 1a. `_leadv2_arm_exceptions_path` — the writer half

| Direction | Symbol | file:line | Note |
|---|---|---|---|
| callee-of | `_arm_exception_bump` | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:1248` | only caller in production |
| caller-of `_arm_exception_bump` | arm-refusal site in `cmd_resolve` | `leadv2-dispatch-code.sh:5181` | `\|\| true` — bump failure never aborts a dispatch |
| calls | `leadv2-state-path.sh` via `STATE_PATH_BIN` | `leadv2-dispatch-code.sh:882` | `2>/dev/null \|\| true`, empty ⇒ fallback `:885` + `log_err :886` |
| calls | `date -u +%Y%m%d` | `:878` | only when `$1` is not 8 digits (§3.6 guard) |
| memoised in | `_LEADV2_ARM_EXC_DAY` / `_LEADV2_ARM_EXCEPTIONS_PATH` | `:871-872` | bash 3.2, one resolver fork per day per process |
| **independent copy** | the extracted-into-a-stub copy in the test | `tests/test-glm-deferred-ladder.sh:396` (`awk` range) | leg (e2) re-executes the *real* function body out of the source file; a signature change to `_leadv2_arm_exceptions_path` or to the comment anchor `# LANE-STATE-LEAK-01: all four now resolve` silently changes what leg (e) runs. This is the copy on a different path that nobody named. |

Sibling helpers on the same pattern, same file, **not** touched by this round but sharing the
failure mode: `_leadv2_glm_deferred_path` (`:856`, callers `:936`, `:1040`),
`_leadv2_codex_credits_stamp_path` (`:895`).

### 1b. `_lv2_state_resolve` — the reader half

| Direction | Symbol | file:line |
|---|---|---|
| defined | `_lv2_state_resolve` | `plugins/leadv2/scripts/leadv2-broad-status.sh:43-53` |
| callers (6) | `FOUNDER_STATUS_PATH` `:56`, `FOUNDER_STATUS_FULL_PATH` `:64`, `EMPTY_SINCE_PATH` `:81`, `FOUNDER_STATUS_EPOCH_PATH` `:82`, `ARM_EXCEPTIONS_PATH` `:203`, `CODEX_CREDITS_STAMP_PATH` `:204`, `GLM_DEFERRED_PATH` `:205` |
| consumed by | the render heredoc, `sys.argv[1:12]` | `:212`; used at `:615` (arm exceptions), `:632` (credits stamp), `:643` (glm-deferred) |
| calls | `leadv2-state-path.sh` | `:46` |

### 1c. Callers of `leadv2-broad-status.sh` and other readers of the same artifacts — different paths

| Caller | file:line | Independent? |
|---|---|---|
| `leadv2-pulse-beat.sh` | `:40` (`LEADV2_BROAD_STATUS_BIN` override) | drives the same composer, adds no path logic |
| `leadv2-single-lead-beat.sh` (hook) | `:142-145` | **independent resolution** of `founder-status.md` — its own resolver call with its own empty-guard and its own fallback. RENDER-class symlink is a *contract* for it (`leadv2-state-path.sh:32-36`), not a convenience. Not touched by this round; listed so nobody "simplifies" the RENDER symlink away. |
| `leadv2-task-anchor.sh` (hook) | `:223,:228,:707,:712` | emits the relay instruction naming `docs/leadv2/founder-status.md` as a **string in prose**, not a filesystem read. Safe. |

### 1d. Callees of the three new suites

All three call only `plugins/leadv2/scripts/leadv2-state-path.sh` plus coreutils/git; the
no-raw-paths suite additionally greps the whole of `plugins/leadv2/` (its `PLUGIN_ROOT`,
`test-state-path-no-raw-paths.sh:27`). That grep root is what makes it falsifiable only if it is
parameterised — see §5.

---

## 2. STATES AND RETURN CODES

`leadv2-state-path.sh` is the mechanism. It runs `set -euo pipefail`.

| # | State | rc | stdout | What the caller does | User-visible consequence |
|---|---|---|---|---|---|
| 1 | git repo resolved, name given | 0 | `<STATE_BASE>/<slug>/<name>` | uses it | normal: one control plane per repo, shared by every worktree |
| 2 | git repo, scratch fixture (no remote, no `REAL-REPO`), neither `LEADV2_STATE_ROOT` nor `LEADV2_STATE_BASE` set | 0 | `<base>/.ephemeral/<slug>/<name>` | uses it | test junk is quarantined under a dot-dir the project renderer's non-dotglob never lists |
| 3 | `LEADV2_STATE_ROOT` set, LINK_ROOT is a scratch tree | 0 | `<LEADV2_STATE_ROOT>/<name>` | uses it | **this is the leg-(d) state** — sandbox honoured |
| 4 | no git repo at LINK_ROOT (mktemp sandbox) | 0 | `<LINK_ROOT>/docs/leadv2/<name>` | uses it | **this is the leg-(a) state** — pre-fix layout, per-root |
| 5 | no git repo **and** LINK_ROOT is `/` | 3 | *(empty; msg on stderr)* | `\|\| true` ⇒ empty ⇒ fallback branch | dispatch/renderer log one WARN and use `$PROJECT_ROOT/docs/leadv2/<name>`; with `PROJECT_ROOT` also unset that is `/docs/leadv2/...` and the write fails — the fallback counter reads 0 forever |
| 6 | no git repo, parent of `<LINK_ROOT>/docs/leadv2` not writable | 3 | empty | same as 5 | same as 5 |
| 7 | `LEADV2_STATE_ROOT` set **and** LINK_ROOT is a real checkout (remote or marker) | 1 | empty | same as 5 | B1 net: refuses to retarget a real repo's symlinks from a sandboxed test. Correct and loud. |
| 8 | `mkdir -p "$STATE_ROOT"` fails (`:172`) | non-0 (from mkdir, `set -e`) | empty | same as 5 | same as 5 |
| 9 | migration lock busy > 5s | 0 | path | uses it | `[leadv2-state-path] WARN: migration lock busy` on stderr; path still correct, migration retried next invocation. **No hang** — this is the designed degrade. |
| 10 | migration python raises | 0 | path | uses it | `2>/dev/null \|\| true` at `:264` — content stays in the worktree, resolver still returns the control-plane path. Silent; see §4. |

**Terminal traces.** No rc from this script ever reaches a `return`/`exit` in a caller: both
`_leadv2_arm_exceptions_path:882` and `_lv2_state_resolve:46` swallow rc and branch on *empty
stdout only*. So states 5–8 are indistinguishable at the call site and all collapse into one
behaviour: WARN + repo-relative fallback. In a lane worktree that fallback is per-worktree, which
is the exact bug LANE-STATE-LEAK-01 exists to kill — the founder's 30-minute status then reports
`sonnet-фолбэков сегодня: 0` on a day the ladder fell back on every dispatch, and the only trace
is one stderr line in the beat log that nobody reads. That is the plain-words consequence of the
whole rc column.

`_arm_exception_bump` is called with `|| true` at `leadv2-dispatch-code.sh:5181`: a bump that
fails never fails the dispatch. The dispatch still runs on sonnet; only the *visibility* of the
fallback is lost.

---

## 3. CONFIGURATION BOUNDARIES

| Input | Absent | Empty | Minimum | Max / over-cap | Malformed |
|---|---|---|---|---|---|
| `LEADV2_STATE_ROOT` | normal production path (states 1/2/4) | `[[ -n ]]` at `:106` treats empty as absent — falls through to git resolution. Correct. | any non-empty string | n/a | a path that does not exist: `mkdir -p` at `:172` creates it; unwritable ⇒ state 8 |
| `LEADV2_STATE_BASE` | `${HOME}/.claude/leadv2-state` and the ephemeral redirect is *armed* | same as absent (`:155` default), **but** the redirect predicate at `:156` tests `-z` on the raw var, so empty = unset ⇒ redirect armed. Consistent. | — | — | non-writable ⇒ state 8 |
| `PROJECT_ROOT` | LINK_ROOT ← `git rev-parse --show-toplevel` of cwd, else `pwd` | same | — | — | `/` ⇒ state 5 |
| `$1` (name) | `root` ⇒ prints STATE_ROOT, rc 0 | `-z NAME` ⇒ same as `root` (`:555`) | — | — | a value containing `/` or `..` escapes STATE_ROOT via `:560-561`. Guarded **only at the dispatch caller** (`:878` 8-digit regex). **Not guarded in `leadv2-broad-status.sh`** — see below. |
| `_TODAY_UTC` (broad-status `:202`) | — | if `date -u +%Y%m%d` fails, `\|\| true` yields empty and the resolved name becomes `.arm-exceptions-` | — | — | **defect-shaped**: the reader would then read a file no writer ever writes and render `0` fallbacks with no warning. Asymmetric with the writer's §3.6 guard. Cheap fix in this round: `[[ "${_TODAY_UTC}" =~ ^[0-9]{8}$ ]] \|\| _TODAY_UTC="$(date -u +%Y%m%d)"`, and if that is still empty, skip the arm-exceptions read entirely rather than resolving a truncated name. |
| `glm-deferred.jsonl` (MERGE input) | nothing to merge, symlink planted | 0-byte: `new_lines` empty, local removed, symlink planted | 1 line | `> 8 MiB` ⇒ **skipped, left un-migrated, one stderr line** (`MERGE_SIZE_CAP`, `:301`). Bounded — it does not abort the other classes. Correct. | a non-JSON line is unioned as text and never parsed — by design (`:31-34`); one bad line cannot abort the loop. Proven by S4 in `test-state-path-migration.sh:64`. |
| `.arm-exceptions-<day>` (GLOB input) | nothing to move | moved as-is | — | no cap — a large file is `shutil.move`d (rename, O(1) same-fs) | `glob_re` at `:525` matches only `\.arm-exceptions-\d{8}(\.lock)?`; anything else is left in the worktree, untracked-but-gitignored (S9). |
| migration advisory lock | `flock` absent ⇒ `mkdir` spin, 5 s deadline | — | — | contended > 5 s ⇒ state 9, migration skipped, path still returned | fd 7 chosen because dispatch reserves 8 and 9; verified `grep -n '7[<>]' plugins/leadv2/scripts/*.sh` is empty |

Env-name convention check: every var above is `LEADV2_*`. No `LEAD_V2_*` drift in the touched
files. `LEADV2_TEST_FALSIFICATION_GATE` (`lib/leadv2-builder-selfcheck.sh:449`) is the only new
name §5 depends on and it already exists.

---

## 4. COUNTEREXAMPLE — what still violates the invariant after every finding here is fixed

The invariant is: *no session-global leadv2 state is stored per-worktree; every worktree of one
repo resolves one file.* After the leg-(d) pairing fix, the three falsification harnesses, and the
`_TODAY_UTC` guard, three holes remain and I could not close them from within this round's scope.

First, **the fallback branch is itself a leak generator.** Every routed caller degrades to
`$PROJECT_ROOT/docs/leadv2/<name>` on an empty resolution (states 5–8). That is by design — R8
says a resolver failure must never abort a dispatch — but it means the invariant holds only while
the resolver succeeds, and a single `mkdir` failure or a `/`-cwd hook invocation reinstates the
exact per-worktree split this task exists to remove, with the only evidence being a stderr WARN
that no test asserts and no gate reads. `test-state-path-no-raw-paths.sh` *allow-lists* those
fallback lines, so it cannot see this either.

Second, **migration is best-effort and silent on failure** (state 10: `PYEOF 2>/dev/null || true`
at `:264`). If the python block dies — a permission error on one entry, a symlink loop, a
read-only `docs/leadv2` — the resolver still prints the control-plane path while the worktree's
real content stays behind at the old path. Readers then see an empty control-plane file and
writers append to it; the pre-existing local content is never merged and never reported. That is
data loss shaped exactly like "the feature works".

Third, **`no-raw-paths` guards the plugin tree only** (`PLUGIN_ROOT`,
`test-state-path-no-raw-paths.sh:27`). Per the global shared-trees policy, `~/.claude/leadv2-shared/`
and each project's `.claude/scripts/` hold repo-native scripts that this grep never visits, and the
SessionStart hook in this very session reports real-file drift in `~/.claude/leadv2-shared/`. A raw
`docs/leadv2/active.yaml` reintroduced there is invisible to the guard. Out of scope here; it belongs
to the durable half.

What I checked to say that: the resolver end-to-end (`leadv2-state-path.sh:84-562`), both routed
callers and all seven of their call sites, every non-test grep hit for `arm-exception`,
`founder-status`, `_leadv2_glm_deferred_path`, and the caller list of `leadv2-broad-status.sh`.

---

## 5. Falsification harness — design for the three suites

Convention (`lib/leadv2-builder-selfcheck.sh:473`): the suite's own stdout must match
`RED-then-GREEN: .*\(pre_rc=1 -> post_rc=0\)`. The reference implementation is
`tests/test-claim-evidence-gate.sh:113-140` — a `run_case <name> <fn>` that executes the **same**
assertion function twice, once against a deliberately-broken artifact (`pre_rc` must be non-zero)
and once against the real one (`post_rc` must be 0), and treats `pre_rc=0` as a `GREEN-PRE-FIX`
failure so a forged marker cannot pass. Copy that shape; do not `echo` the marker.

| Suite | Negative control (mutant) | Assertion re-run against it | Expected pre_rc |
|---|---|---|---|
| `test-state-path-worktree-identity.sh` | copy `leadv2-state-path.sh` to `${TMP_ROOT}/mutant/`, replace the `LEADV2_STATE_ROOT`/git-common-dir resolution block so `STATE_ROOT="${LINK_ROOT}/docs/leadv2"` unconditionally (the raw per-worktree path the mission names) | the existing main-vs-worktree identity comparison, pointed at the mutant | 1 — the two roots diverge |
| `test-state-path-migration.sh` | same copy, but rewrite the `MERGE_FILE` collision branch to `shutil.move(local, target)` (clobber instead of union) | the S4 line-union assertion | 1 — wt-a's line is gone from the merged file |
| `test-state-path-no-raw-paths.sh` | copy `plugins/leadv2/scripts` + `hooks` into `${TMP_ROOT}/corpus`, append one line `X="${PROJECT_ROOT}/docs/leadv2/active.yaml"` to a file that is **not** on the allow-list | the scanner, run against `${TMP_ROOT}/corpus` | 1 — un-allow-listed raw reference |

Structural precondition: the third suite currently hard-codes its scan root at
`test-state-path-no-raw-paths.sh:27`. Parameterise it — `scan_root() { local root="$1"; … }`
defaulting to `PLUGIN_ROOT` — so the mutant corpus can be passed in. The mutant must be a **copy**;
never mutate the tree in place, and never leave a mutant behind on a failed run (`trap` cleanup).

Because the mutants are copies of production code and the assertion functions are the real ones,
these markers attest to an executed counterfactual, not to a printed sentence — which is the
distinction `lib/leadv2-builder-selfcheck.sh:431-448` says the current gate cannot make on its own.

---

## 6. Non-goals — explicitly out of scope for this round

- The durable half (state outside the repo entirely, the write guard, the migration command) —
  `docs/handoff/LANE-STATE-LEAK-01/round-2-durable.md`, lands after this.
- Any production change to `leadv2-state-path.sh`, `leadv2-dispatch-code.sh`, the hooks, or the
  migration classes. The one exception is the `_TODAY_UTC` validation in
  `leadv2-broad-status.sh` (§3), which is three lines and closes a reader-side malformed-input
  hole this round's own change opened.
- The pre-existing raw-path violations already named on the `no-raw-paths` allow-list
  (`leadv2-resume.sh`, `leadv2-lane-liveness.sh`, `active.yaml`/`tombstones.yaml`/`questions`).
- `~/.claude/leadv2-shared/` drift reported by SessionStart. Different blast radius, different lane.
- Option B (fully hermetic per-tenant `LEADV2_STATE_ROOT` threading) — recorded above, not done.
- Rebasing the lane onto current `main`. The lane is 5 commits behind; `main` added
  `test-lane-behind-base.sh` and others. Landing order is the lead's call, not this design's.

---

## 7. Implementation order

1. `test-glm-deferred-ladder.sh` — drop the two `LEADV2_STATE_ROOT` overrides (`:283`, `:303`),
   add the writer/reader pairing pre-assert to leg (d), and one comment naming why the sandbox
   override is wrong *here* specifically.
2. `leadv2-broad-status.sh` — `_TODAY_UTC` validation (§3).
3. The three falsification harnesses (§5), each verified red-then-green by actually running the
   mutant — the report must say which mutant produced which non-zero rc, not that a marker was added.
4. `run-core-offline.sh` + `test-broad-status-lanes-blind.sh` +
   `test-broad-status-renderer-truth.sh` + `test-pulse-empty-board.sh`, then `git diff --stat`.

---

acceptance:
  - surface: file_artifact
    observable: "Running test-glm-deferred-ladder.sh prints a PASS line for case (d) saying the rendered founder-status.md contains 'sonnet-фолбэков сегодня: 1 (glm_refused_quota_gate)', and the suite's tail reports zero failures."
    authored_at: 2026-08-23T03:45:00Z
  - surface: log_line
    observable: "Each of the three state-path suites prints its own 'RED-then-GREEN: <case> (pre_rc=1 -> post_rc=0)' line, so the builder selfcheck's falsification row for those three files reads 0 instead of 'ADVISORY (no_falsification_marker)'."
    authored_at: 2026-08-23T03:45:00Z
  - surface: file_artifact
    observable: "A founder-status.md rendered from a lane worktree on a day with one glm→sonnet fallback shows the same fallback count as one rendered from the main checkout of the same repo — the number no longer depends on which worktree the beat ran in."
    authored_at: 2026-08-23T03:45:00Z

LANE_WRITES: plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh, plugins/leadv2/scripts/tests/test-state-path-migration.sh, plugins/leadv2/scripts/tests/test-state-path-no-raw-paths.sh, plugins/leadv2/scripts/tests/test-state-path-worktree-identity.sh, plugins/leadv2/scripts/leadv2-broad-status.sh

DELIVERABLE_COMPLETE
