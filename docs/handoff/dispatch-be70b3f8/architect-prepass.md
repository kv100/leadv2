# REVIEW-GATE-LANEROOT-01 — architect prepass (mechanism-closed design)

Target: `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, `pc_scope_diff`'s
empty-diff classifier (L1838–L1946) and `pc_silent_arm_probe` (L1250–L1276).

---

## 0. Discovery vs. the mission's framing — three corrections

The mission's root cause is **confirmed against the live tree**, and three of its
surrounding assumptions are not.

**Confirmed (probe, run 2026-08-23 in `~/Projects/leadv2`):**

```
$ git -C .claude/worktrees/f72c8c9c rev-parse --show-toplevel
/Users/kostiantyn.vlasenko/Projects/leadv2
$ git -C .claude/worktrees/f72c8c9c rev-parse --is-inside-work-tree
true
$ ls -a .claude/worktrees/f72c8c9c
.  ..  .claude  docs  plugins            # no .git entry
$ git worktree list
/Users/kostiantyn.vlasenko/Projects/leadv2                      6fa4823 [main]
.../.claude/worktrees/67198a6e                                  f05eddf [worktree-67198a6e]
.../.claude/worktrees/6f1dded5                                  b32d740 [worktree-6f1dded5]
.../.claude/worktrees/6f1dded5/.claude/worktrees/05d28614        53d4465 [worktree-05d28614]
.../.claude/worktrees/6f1dded5/.claude/worktrees/0e7cd03d        53d4465 [worktree-0e7cd03d]
.../.claude/worktrees/6f1dded5/.claude/worktrees/6409fada        53d4465 [worktree-6409fada]
.../.claude/worktrees/6f1dded5/.claude/worktrees/9289462d        53d4465 [worktree-9289462d]
.../.claude/worktrees/be70b3f8                                  aed1f2b [worktree-be70b3f8]
```

`f72c8c9c` is absent from `worktree list`, has no `.git`, and `rev-parse --show-toplevel`
from inside it answers with the MAIN repo. `_pc_lane_dirty` (L1149-1157) guards only with
`rev-parse --is-inside-work-tree`, which is **true for any subdirectory of the main repo** —
so it passed, and `git -C "${_lane_root}" status --porcelain` at L1889 returned the main
checkout's dirt. Every one of those paths is undeclared relative to the lane's write-set →
`_pc_undeclared_n > 0` → `unscoped_lane_work` at L1898. Mechanism confirmed exactly as stated.

**C-1 — why the lane's OWN work never showed up either.** `.claude/worktrees/` is
gitignored:

```
$ git check-ignore -v .claude/worktrees
.gitignore:15:.claude/worktrees/	.claude/worktrees
```

So even `--untracked-files=all` cannot see `plugins/leadv2/scripts/lib/leadv2-trace.sh`
inside `.claude/worktrees/f72c8c9c/`: from the main repo's point of view the whole lane
directory is ignored. This is why the gate saw 100 % foreign dirt and 0 % lane work. The
mission's "the lane never touched any of those four" is right; the complement — "and the
gate could not have seen what the lane DID touch, by construction" — is the other half and
is what makes `produced:` (§3, change 3) necessary rather than cosmetic.

**C-2 — the empty diff was not caused by the same walk-up.** `diff_root` is also set to
`_lane_root` (L1608), but `_pc_repo_diff` is pathspec-scoped to the declared write-set
(L1773, `_pc_git_diff … -- "$@"`). The declared path
`plugins/leadv2/scripts/lib/leadv2-trace.sh` does not exist in the MAIN tree, so the
pathspec matched nothing → 0 bytes → `blocked_reason=unscopable_diff` (L1778) → the dirty
branch ran. Main's four dirty files were never in the write-set, so they contributed no
diff bytes; they only reached `_pc_offending`. Both halves matter: fixing only the
attribution would still leave `refused`, which is correct and retryable.

**C-3 — mission item 4 ("add the new reason to vocabulary/verdict lists … `leadv2-backlog-pump.sh`
also references it") is based on a wrong premise.** There is no vocabulary list to extend:

- `leadv2-backlog-pump.sh:250` is a *narrative comment* in the cache-path rationale, not a
  list. **Do not edit it.**
- `leadv2-dispatch-ledger.sh` accepts `cause` as free text (`cause="$(json_safe "${cause}")"`,
  L218) and never validates it against an enum. Only the **terminal word** is enumerated
  (`landed|parked|refused|dead|no_work`, L19/L200) and this design does not add one.
- Every downstream renderer passes `reason:` through as opaque text —
  `leadv2-broad-status.sh:424-435` (`terminal_reason` / `status_reason` straight into the
  cell), `plugins/leadv2/docs/phases.md:292` ("see the engine's `reason:` line").
  Grepping `unscopable_diff|declared_no_bytes|cross_repo_elsewhere` across
  `plugins/**` outside `tests/` returns only comments and the one assignment site each.

  The one real "list" is the **documentation comment** at
  `leadv2-dispatch-ledger.sh:36-44`, which enumerates the causes that legitimately produce
  `refused`. That is the single doc edit item 4 actually asks for.

---

## 1. CALLERS / CALLEES

### 1a. Functions this design touches

| Function | Defined | Called from | Notes |
|---|---|---|---|
| `_pc_lane_dirty` | L1149 | `pc_silent_arm_probe` L1273; `pc_scope_diff` L1860 | **Two independent call paths.** Hardening the helper itself is wrong — see §1c. |
| `pc_scope_diff` (empty-diff classifier) | L1838-L1946 | top level L2038 (single call site) | after `pc_silent_arm_probe`, before `pc_stop_gate_autocommit` |
| `pc_silent_arm_probe` | L1250-L1276 | top level ~L2030 | runs **before** `pc_scope_diff`; can `exit 5` first |
| `_pc_join_capped` | L1337 | L1855 (`_pc_declared_list`), L1899 (`_pc_offending`) | reused for the new `produced:` line |
| `_pc_arm_advance` | L1290 | `pc_silent_arm_probe` branch only, ~L2035 | side-effecting: re-spawns the next arm |

### 1b. `_lane_root` producers — every path that can hand this gate a directory

| # | Producer | file:line | Can it yield an UNREGISTERED dir? |
|---|---|---|---|
| P1 | `LEADV2_LANE_WORK_ROOT` env, exported by the detached per-lane launcher | `leadv2-fanout-lane-launcher.sh:372` | **YES** — value captured at spawn; registration can be lost during the lane's life |
| P2 | `LEADV2_LANE_WORK_ROOT` re-exported by dispatch-code | `leadv2-dispatch-code.sh:394, 822, 3137, 4469` | **YES** — same value, threaded through |
| P3 | `leadv2-lane-worktree.sh path-of` fallback | product-close L1607 / L2023 | **NO** — `cmd_path_of` (lane-worktree.sh:244) already requires a `worktree list --porcelain` match |
| P4 | `leadv2-lane-worktree.sh ensure` | launcher:368 | **NO** — every success branch (L173, L187, L193) is a registered worktree; the failure branch calls `fallback` → prints `PROJECT_ROOT` (see §4 counterexample) |

**Conclusion the mission does not state:** `path-of` and `ensure` both already verify
registration. The ONLY vector for an unregistered `_lane_root` is the **env var** (P1/P2) —
a value that was registered when the launcher captured it and was de-registered afterwards.
This narrows the dispatch-side bug (§5) and it means the fix must sit at the *consumer*, not
at `path-of`.

### 1c. The independent copy nobody named — `pc_silent_arm_probe`

`_pc_lane_dirty` has a **second** caller at L1273 that this mission's findings list does not
mention, and it fails the same way with the opposite sign:

```
1273:  _pc_lane_dirty "${_lane_root}" && return 1     # dirty => NOT silent
```

Today, with an unregistered `_lane_root` and a **dirty** main tree, the walk-up makes this
read "dirty" → `return 1` → not silent → accidentally correct. With an unregistered
`_lane_root` and a **clean** main tree, it reads "clean" → `return 0` → the gate stamps
`terminal=no_work cause=arm_produced_nothing` **and calls `_pc_arm_advance`**, which
re-spawns the whole mission on the next arm while the finished work still sits in the
unregistered directory. That is strictly worse than the reported symptom, and it is
reachable the moment the founder's tree is clean.

Therefore: **do not harden `_pc_lane_dirty` itself.** Hardening it would flip the probe from
accidentally-correct to actively-wrong on today's dirty tree. Add the identity check at both
call sites explicitly, with opposite polarity (§3 change 2).

### 1d. Callees of the changed block

`git -C <root> rev-parse --show-toplevel` (new), `_pc_join_capped` (L1337), `find` (new,
for `produced:`), `basename`, `_dl_note` (L102) → `leadv2-dispatch-ledger.sh write-terminal`,
`emit decision` → journal, `_stamp_review_terminal`, `printf > "${HANDOFF}/review-gate.md"`.

### 1e. Who consumes the outcome — and the fact that rc is discarded

`leadv2-dispatch-code.sh:3139` launches the close gate **in the background with output
discarded**:

```
"${BASH:-bash}" "${close_bin}" "${PROJECT_ROOT}" "${sig8}" … >/dev/null 2>&1 &
```

**Nothing ever reads product-close's exit code.** The entire user-visible outcome of this
gate is three artifacts:

1. `docs/handoff/dispatch-<sig8>/review-gate.md` (`status:`/`reason:`/`dirty:`/`offending:`)
2. the journal `review_gate …` decision line (L1941)
3. the ledger row written by `_dl_note` → `dispatch_terminal task=<sig8> terminal=… cause=…`

which is what `leadv2-broad-status.sh:424` renders into the founder's board and what
`leadv2-dispatch-ledger.sh exists` (L58) consults for retryability. This is why §2's rc
column reads "nobody" and why the **reason word is the whole deliverable** of this fix.

---

## 2. STATES AND RETURN CODES

### 2a. States of the mechanism (`_lane_root` × tree × write-set)

| # | `_lane_root` | tree state | today | after fix | user-visible consequence after fix |
|---|---|---|---|---|---|
| S1 | unset / empty | — | `no_work` / `empty_diff` (L1911) | unchanged | "lane produced nothing", retryable |
| S2 | set, dir missing | — | `no_work` / `empty_diff` | unchanged | as S1 |
| S3 | **set, dir exists, toplevel ≠ dir** (the bug) | parent dirty | `refused` / `unscoped_lane_work`, offending = parent's paths | `refused` / **`lane_root_not_a_worktree`**, `offending:` absent, `produced:` names the lane's real files | founder reads "the gate was pointed at a directory that is not a git worktree; it resolved to <main repo>; the lane did write <files>" — and re-dispatches instead of hunting a scope violation that never happened |
| S4 | set, dir exists, toplevel ≠ dir | parent clean | `refused` / `declared_no_bytes` (dirty-check false) | `refused` / `lane_root_not_a_worktree` | same as S3; previously mislabelled as "the declared path produced no bytes" |
| S5 | registered worktree, undeclared dirty path | — | `refused` / `unscoped_lane_work` | **unchanged, byte-identical** | genuine scope violation still refused (mission non-goal held) |
| S6 | registered worktree, declared-only dirt, cross-repo | — | `refused` / `cross_repo_elsewhere` | unchanged | unchanged |
| S7 | registered worktree, declared-only dirt | — | `refused` / `declared_no_bytes` | unchanged | unchanged |
| S8 | registered worktree, clean, no diff | — | `no_work` / `empty_diff`\|`asked_into_void` | unchanged | unchanged |
| S9 | `_lane_root` == main checkout (worktree off / launcher fallback) | main dirty | `refused` / `unscoped_lane_work` on the founder's dirt | **still `unscoped_lane_work`** + new evidence key `lane_root_shared=1` | §4 counterexample — same symptom survives, now labelled |
| S10 | unregistered dir, silent-arm probe, parent clean | — | `no_work` / `arm_produced_nothing` **+ arm advance** | probe returns "not silent"; falls through to S3/S4 | the mission is no longer re-spawned on a fresh arm while finished work sits on disk |

### 2b. Return codes and what the caller does with each

| rc | emitted at | who reads it | consequence |
|---|---|---|---|
| `exit 5` (blocked — every refused/no_work/parked path incl. the new reason) | L1944, L2035, L2049 | **nobody** — backgrounded with `>/dev/null 2>&1 &` (`leadv2-dispatch-code.sh:3139`) | none directly. Outcome travels only via review-gate.md + journal + ledger row (§1e) |
| `exit 0` (pass) | end of script | nobody | as above |
| `_pc_lane_root_is_own_worktree` rc0 | new helper | `pc_scope_diff` L1860, `pc_silent_arm_probe` L1273 | rc0 → proceed to today's partition logic unchanged |
| `_pc_lane_root_is_own_worktree` rc1 | new helper | same | in `pc_scope_diff` → the new terminal; in `pc_silent_arm_probe` → `return 1` (conservative NOT-silent, no arm advance) |
| `git rev-parse --show-toplevel` non-zero | inside helper | helper only | treated as rc1 (not a worktree) — a directory `git` cannot classify must never be graded |
| ledger `write-terminal` non-zero | `_dl_note` → L112+ | `_dl_note` | already fail-open (`|| true` semantics upstream); row missing, journal line still present |

**Terminal-word contract:** `refused` is unchanged and, per
`leadv2-dispatch-ledger.sh:36-44`, is documented as covering "a gate structurally could not
run at all". `lane_root_not_a_worktree` is exactly that. It stays **retryable** — a later
attempt at the same sig8 can still record `landed`/`dead` (`exists` returns rc1 on a
refused-only history, L58-60). No new terminal word, no caller-contract change.

---

## 3. THE CHANGES

### Change 1 — new helper, next to `_pc_lane_dirty` (insert after L1157)

```sh
# REVIEW-GATE-LANEROOT-01: `git -C <dir>` walks UP. A directory that is merely INSIDE
# the main checkout (an unregistered .claude/worktrees/<tid> left behind by a partial
# worktree removal) answers `rev-parse --is-inside-work-tree` with `true` and then
# reports the MAIN repository's status. Identity, not membership, is the question:
# the toplevel git resolves from <dir> must BE <dir>.
# Physical-path comparison (`cd -P … pwd -P`) for the same reason lane-worktree.sh's
# `phys` exists: on macOS git answers /private/var where the caller passed /var.
# Deliberately NOT folded into _pc_lane_dirty: that helper's OTHER caller
# (pc_silent_arm_probe L1273) reads rc1 as "not dirty" => "arm produced nothing", so
# making it fail closed there would flip a wrong-verdict into a worse one (advance the
# arm and re-run the whole mission). Both call sites check identity explicitly instead.
_pc_phys() { ( cd -P "$1" 2>/dev/null && pwd -P ) ; }

_PC_LANE_TOPLEVEL=""          # set by the probe below; read by the evidence line
_pc_lane_root_is_own_worktree() {  # <root> -> rc0 iff <root> IS a git work tree root
  local root="$1" top
  _PC_LANE_TOPLEVEL=""
  [[ -n "${root}" && -d "${root}" ]] || return 1
  top="$(git -C "${root}" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -n "${top}" ]] || return 1
  _PC_LANE_TOPLEVEL="${top}"
  [[ "$(_pc_phys "${top}")" == "$(_pc_phys "${root}")" ]]
}
```

bash-3.2 safe: no `[[ =~ ]]`, no associative arrays, no `${var@Q}`, no process substitution.

### Change 2 — `pc_silent_arm_probe`, insert immediately before L1273

```sh
  # REVIEW-GATE-LANEROOT-01: an unregistered lane dir makes _pc_lane_dirty grade the
  # PARENT repo. On a clean parent that reads "clean" => "arm produced nothing" =>
  # _pc_arm_advance re-spawns the mission while the finished work sits on disk. Fail
  # conservative: unknown tree is never proof of silence.
  _pc_lane_root_is_own_worktree "${_lane_root}" || return 1
```

### Change 3 — `pc_scope_diff`, restructure the branch head at L1860

Today:

```sh
if [[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] && _pc_lane_dirty "${_lane_root}"; then
```

Becomes a three-way head. New branch FIRST (it must pre-empt `_pc_lane_dirty`, which
would otherwise return true on the parent's dirt):

```sh
if [[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] && ! _pc_lane_root_is_own_worktree "${_lane_root}"; then
  # requirement 3: _pc_offending stays EMPTY on this path, structurally — the porcelain
  # walk below is the ONLY producer of _pc_undeclared, and it now runs exclusively under
  # a proven-identical toplevel. No fallback re-enters it.
  _pc_terminal="refused"; _pc_cause="lane_root_not_a_worktree"; _pc_rg_reason="lane_root_not_a_worktree"
  _pc_dirty_n=0
  _pc_offending=""
  _PC_LANE_RESOLVED_TOP="${_PC_LANE_TOPLEVEL:-<unresolved>}"
  _PC_LANE_PRODUCED="$(_pc_lane_produced_files "${_lane_root}")"
  _pc_dirty_evidence="lane_root=$(basename "${_lane_root}") resolved_toplevel=${_PC_LANE_RESOLVED_TOP} expected=${_lane_root} produced=${_PC_LANE_PRODUCED}"
elif [[ -n "${_lane_root:-}" && -d "${_lane_root}" ]] && _pc_lane_dirty "${_lane_root}"; then
  … today's block, byte-identical …
else
  … today's no_work block, byte-identical …
fi
```

`_pc_dirty_evidence` non-empty is what selects the rich `review-gate.md` writer at L1925,
so the new reason lands in the same artifact shape (and `dirty: 0` is honest — zero dirty
paths were legitimately observed in the lane's own tree).

### Change 4 — `produced:` enumeration helper (requirement 2's "name the lane's files")

```sh
# REVIEW-GATE-LANEROOT-01: .claude/worktrees/ is GITIGNORED in this repo
# (.gitignore:15), so an unregistered lane dir's contents are invisible to every
# porcelain query — including the parent's. `find` is the only way to say "the lane
# did produce something" and it is what stops the next reader concluding the lane was
# idle. Bounded twice: -maxdepth keeps a deep tree cheap, head -N caps the walk, and
# _pc_join_capped caps what is printed to first-5 + "+N more".
_pc_lane_produced_files() {  # <root> -> capped, comma-joined, root-relative file list
  local root="$1" rel out=() f
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    rel="${f#${root}/}"
    out+=("${rel}")
  done <<< "$(find "${root}" -type f \
                -not -path "${root}/.git/*" -not -name '.git' \
                -not -path "${root}/docs/leadv2/*" -not -path "${root}/docs/handoff/*" \
                -not -path '*/__pycache__/*' -not -name '*.pyc' \
                2>/dev/null | head -"${LEADV2_PC_PRODUCED_SCAN_MAX:-500}")"
  [[ ${#out[@]} -eq 0 ]] && { printf 'none'; return 0; }
  _pc_join_capped "${out[@]}"
}
```

Exclusion set deliberately mirrors `_PC_PORCELAIN_EXCLUDE_RE`'s intent (orchestration-owned
paths are not lane product) without reusing the regex — that constant matches *porcelain
lines*, not bare paths, and its single-definition rule (L1133-1140) is about the two
porcelain sites only. Note this in the code so the next reader does not "unify" them.

### Change 5 — `review-gate.md` gains two keys on this path only

At L1925-1932 the writer already emits `status/reason/kind/base/dirty`, then optional
`declared_writes:`, `offending:`, `undiffable:`. Append, additively, after `offending:`:

```sh
      [[ -n "${_PC_LANE_RESOLVED_TOP:-}" ]] && printf 'resolved_toplevel: %s\nexpected_lane_root: %s\n' "${_PC_LANE_RESOLVED_TOP}" "${_lane_root}"
      [[ -n "${_PC_LANE_PRODUCED:-}" ]] && printf 'produced: %s\n' "${_PC_LANE_PRODUCED}"
```

Both variables are empty on every other path, so every existing artifact stays
byte-identical (the same additive discipline `kind:` used, L1921-1923).

### Change 6 — journal + ledger evidence

`emit decision` at L1941 needs no edit: `reason=${_pc_rg_reason}` and
`cause=${_pc_cause}` carry the new word automatically, and `offending=` is suppressed
because `_pc_offending` is empty. `_dl_note` at L1942 already receives
`${_pc_dirty_evidence}` which now carries `resolved_toplevel=…  expected=…  produced=…`.

### Change 7 — documentation (the only real "vocabulary list", per C-3)

`plugins/leadv2/scripts/leadv2-dispatch-ledger.sh`, the `refused` paragraph at L36-44:
append one clause naming `lane_root_not_a_worktree` as a `refused` cause — "the gate was
pointed at a directory that is not a git work tree root, so it had nothing it was entitled
to grade". No code change; `cause` remains free text (L218).

**Explicitly NOT edited:** `leadv2-backlog-pump.sh:250` (narrative comment, not a list —
see C-3).

### Change 8 — regression test (new file)

`plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh`, red-first, following
`test-review-gate-scope-evidence.sh`'s exact harness: each case runs twice, against
`git archive HEAD` extraction (must FAIL) and the working tree (must PASS); reuses
`new_repo`, `ensure_worktree`, `make_resolver_stub`, `make_review_pass_stub`.

| Case | Fixture | Assertion |
|---|---|---|
| C1 (the bug) | `new_repo`; `mkdir -p $root/.claude/worktrees/$tid/plugins/lib` + a file inside; dirty the PARENT with two undeclared files; `LEADV2_LANE_WORK_ROOT=<that dir>` | `review-gate.md` has `reason: lane_root_not_a_worktree`, has NO `offending:` line, has `resolved_toplevel:` == the parent root, and `produced:` naming the file in the lane dir |
| C2 (positive control, must not regress) | `ensure_worktree` (genuinely registered) + an undeclared written file inside it | `reason: unscoped_lane_work` and `offending:` names that file — identical to `test-review-gate-scope-evidence.sh` case 2 |
| C3 (silent-arm, §1c) | unregistered lane dir, **clean** parent, no assistant events in the stream | `reason:` is NOT `arm_produced_nothing`; no `.arm-advanced-*` marker was created |
| C4 | `bash -n` and `/bin/bash -n` (bash 3.2 syntax) on the changed script | both parse |

The parent-repo fixtures are `mktemp -d` throwaways. **Nothing in this design reads,
stashes, resets, cleans, or commits `~/Projects/leadv2`'s own five dirty files** — the
mission's hard rule.

---

## 4. CONFIGURATION BOUNDARIES

| Input | absent | empty | minimum | maximum / over-cap | malformed |
|---|---|---|---|---|---|
| `LEADV2_LANE_WORK_ROOT` | falls back to `path-of` (L1607), which returns "" unless registered → S1 `no_work/empty_diff` | same as absent (`-z` test L1606) | a 1-char existing dir that IS a worktree root → normal path | n/a | non-existent path → `-d` fails → `path-of` fallback → S1. A path that is a **file** → `-d` fails → same. A dir git cannot classify (permission denied, corrupt `.git`) → `rev-parse` non-zero → helper rc1 → **new reason**, never `unscoped_lane_work` |
| `_lane_root` == main checkout | — | — | — | — | identity check **passes** (toplevel == itself). Behaviour unchanged; new evidence key `lane_root_shared=1`. See §5 counterexample |
| `writes[]` (`LEADV2_DISPATCH_LANE_WRITES`) | `${writes[@]:-}` guarded at L1855/L1884; empty write-set → every dirty path undeclared → but on the new path the porcelain walk never runs, so the write-set is irrelevant to this verdict | same | 1 path → normal | 100s of paths → `_pc_join_capped` caps `declared_writes:` at 5+`+N more`; O(n·m) inner loop unchanged and only on the registered path | a path with spaces/quotes: already handled by the porcelain quote-strip (L1882-1883); untouched by this change |
| `produced:` scan (`find`) | dir empty → prints `none`, never an empty key | — | 1 file → named | `LEADV2_PC_PRODUCED_SCAN_MAX` (default 500) bounds the walk; `_pc_join_capped` bounds the output to 5 + "+N more". **The cap must never abort the gate** — `head` closing the pipe is absorbed because the loop reads from a command substitution, not a live pipe | a filename with a newline: the `while read` splits it into two entries. Cosmetic only — this line is human evidence, never a decision input. Document that explicitly so a future reader does not build on it |
| `LEADV2_LANE_WORKTREE=off` | `ensure` calls `fallback` → prints `PROJECT_ROOT`; launcher exports it → `_lane_root` == main root → identity check passes → today's behaviour byte-for-byte | — | — | — | — |
| `_PC_PORCELAIN_EXCLUDE_RE` | unchanged by this design; the new path does not run porcelain at all | — | — | — | — |
| `git` binary missing / older | `rev-parse --show-toplevel` predates git 1.7 — no version risk. If `git` is absent entirely, `rev-parse` fails → rc1 → new reason. A gate with no git is a gate that must not grade | — | — | — | — |

**Blast-radius rule applied:** every malformed input above degrades to *this one lane's*
verdict. Nothing in this design can abort the close gate, poison another lane, or touch a
shared file. `find` is read-only; `rev-parse` is read-only; no index, no worktree mutation.

---

## 5. COUNTEREXAMPLE — what still violates the invariant after every fix here

The invariant: *no path from a tree other than the lane's own may ever be reported as the
lane's scope violation.*

**Two things still violate it, and one of them is by design.**

(1) **`_lane_root` == the main checkout.** `leadv2-fanout-lane-launcher.sh:369` reads
`[[ -n "$_lane_dir" && -d "$_lane_dir" ]] || _lane_dir="$PROJECT_ROOT"`, and
`leadv2-lane-worktree.sh`'s `ensure` calls `fallback` (printing `PROJECT_ROOT`) whenever
`git worktree add` fails twice (L198-199) or `LEADV2_LANE_WORKTREE=off`. In every one of
those cases `LEADV2_LANE_WORK_ROOT` is exported as the **main repo root**, whose toplevel
is itself — so the identity check passes cleanly, `_pc_lane_dirty` sees the founder's five
uncommitted files, and the gate refuses the lane with `unscoped_lane_work` naming paths the
worker never touched. **The exact symptom this mission reports, reachable through a
different door, and this fix does not close it.** It cannot be closed by simply refusing
when `_lane_root == ROOT`, because that is also the *legitimate* shared-tree mode where
main really is the lane's tree — telling the two apart needs the launcher to record which
one it chose. In scope here: add `lane_root_shared=1` to `_pc_dirty_evidence` when
`_pc_phys "${_lane_root}" == _pc_phys "${ROOT}"`, so the next occurrence is diagnosable
from the artifact in one read. Out of scope here: changing that verdict. Recommend a
follow-up task `LANE-ROOT-IS-MAIN-CHECKOUT-01` — the launcher stamps
`lane_worktree=fallback` into the cache and the gate refuses with a distinct
`lane_root_shared_tree` cause.

(2) **A registered worktree that a second session is also writing.** Two lanes pointed at
the same worktree (nested lanes exist today — `git worktree list` shows four registered
under `6f1dded5`) both see each other's uncommitted files as undeclared dirt. Identity holds,
so no check here fires. This is a real residual hole, but it is a concurrency-ownership
problem, not a wrong-tree problem, and it needs a per-lane owner stamp rather than a path
check.

Everything else I checked is closed: `path-of` (lane-worktree.sh:244) and `ensure`
(L173/187/193) both verify registration, so they cannot introduce an unregistered root;
`_pc_offending` has exactly one assignment site (L1899) and it now sits under a proven
toplevel identity; and the second `_pc_lane_dirty` caller (L1273) is explicitly guarded by
change 2.

---

## 6. Observations on the dispatch-side registration bug (record only — mission says do not fix)

- The unregistered directory cannot have come from `ensure` or `path-of`: both verify
  registration on every return branch (lane-worktree.sh:173, 187, 193, 244). It therefore
  entered as `LEADV2_LANE_WORK_ROOT`, captured at
  `leadv2-fanout-lane-launcher.sh:372` when the worktree **was** registered, and lost its
  registration afterwards.
- What the directory looks like now — files present, `.git` gone — is the residue of a
  `git worktree remove` whose admin/`.git` unlink completed and whose recursive directory
  removal did not. Two removers exist:
  `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh:95` (`git worktree remove "${wt}"`,
  no `--force`, added in `aed1f2b` on 2026-08-22 — one day before the incident) and
  `plugins/leadv2/scripts/leadv2-worktree-cleanup.sh:136/242/344`
  (`git worktree remove --force`, followed by `worktree prune` at L141/251).
  A `--force` remove over a tree containing gitignored content, or a `prune` after a partial
  removal, both produce exactly this shape.
- **UNVERIFIED:** which of the two ran against `f72c8c9c` — I did not read the hook's run
  log and this design does not depend on the answer. Naming the culprit is the follow-up
  task's job.
- The stop-gate at product-close L1481 already has the check this mission adds, in a
  different form: `[[ -d "${_sg_lane_root}/.git" || -f "${_sg_lane_root}/.git" ]] || return 0`.
  So the stop-gate autocommit silently skipped this lane too, which is why the lane's work
  was never checkpoint-committed and had to be preserved by hand at
  `docs/handoff/SCRIPT-SIZE-AUDIT-20260821/partial-lane-f72c8c9c/`. Two guards for one
  question, in two shapes, in one file — the follow-up should collapse them onto
  `_pc_lane_root_is_own_worktree` (the `.git`-presence form is the weaker of the two: it
  passes for a `.git` file whose gitdir pointer is dangling).

---

## 7. NON-GOALS (the implementing agent ignores all of these)

1. Any change to the partition logic at L1877-1894 — it is correct and stays byte-identical.
2. Any weakening of `unscoped_lane_work`: S5 in §2a must remain refused (test case C2 proves it).
3. Any change to `_pc_lane_dirty`'s own body (§1c explains why hardening it is a regression).
4. Any fix to worktree registration in `leadv2-lane-worktree.sh`,
   `leadv2-fanout-lane-launcher.sh`, `leadv2-merged-worktree-sweep.sh`, or
   `leadv2-worktree-cleanup.sh` — observation only (§6).
5. The `lane_root == main checkout` verdict (§5 item 1) — evidence key only, no verdict change.
6. Any edit to `leadv2-backlog-pump.sh` (C-3: it holds a comment, not a vocabulary list).
7. Any new terminal word — `refused` is reused deliberately (§2b).
8. Any `git stash` / `reset` / `clean` / commit of the five dirty files in
   `~/Projects/leadv2`, or of `.claude/worktrees/f72c8c9c`. Hard rule.
9. Recovering the stranded `leadv2-trace.sh` work — separate task.

---

## 8. Acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >
      docs/handoff/dispatch-<sig8>/review-gate.md, for a lane whose LEADV2_LANE_WORK_ROOT
      points at a directory that is not itself a git worktree root, reads
      "reason: lane_root_not_a_worktree"; it carries a "resolved_toplevel:" line naming the
      parent repository and an "expected_lane_root:" line naming the lane directory, the two
      being visibly different; it carries a "produced:" line naming at least one file the
      lane actually wrote; and it contains no "offending:" line at all.
    authored_at: 2026-08-23T03:20:00Z
  - surface: file_artifact
    observable: >
      For a lane whose worktree IS correctly registered and which wrote a file outside its
      declared write-set, the same artifact still reads "reason: unscoped_lane_work" with an
      "offending:" line naming that file — unchanged from today.
    authored_at: 2026-08-23T03:20:00Z
  - surface: log_line
    observable: >
      The dispatch journal for that lane shows one review_gate line whose reason and cause
      both read lane_root_not_a_worktree, with no offending= field, followed by a
      dispatch_terminal line whose terminal word is refused — so the founder's board shows
      the lane as retryable and names the wrong-directory cause rather than a scope
      violation.
    authored_at: 2026-08-23T03:20:00Z
  - surface: file_artifact
    observable: >
      For an unregistered lane directory inside a CLEAN parent repository, no
      .arm-advanced-<arm> marker file is created under the lane's handoff directory and the
      gate artifact does not read "reason: arm_produced_nothing" — the mission is not
      re-spawned on a fresh arm while its finished work sits on disk.
    authored_at: 2026-08-23T03:20:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-ledger.sh, plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh

DELIVERABLE_COMPLETE
