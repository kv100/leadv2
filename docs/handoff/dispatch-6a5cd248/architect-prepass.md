<!-- leadv2-prepass base_head=65664adfceba0f798bb294a1eb5229ee728c7ac4 generated_at=2026-08-25T15:36:55Z -->
# CTX-COST-GUARDS-01 (v3) — architect prepass, mechanism-closed

Base: `4b51d96`. Worktree `/Users/kostiantyn.vlasenko/Projects/leadv2`.

---

## 0. Where code discovery contradicts the mission's framing

**FIX B is already implemented and committed.** The mission says "nothing guards diff reading on
the Bash side" and asks for a new sub-guard. The tree disagrees:

- `git log --oneline -3 -- plugins/leadv2/hooks/leadv2-warn-bash-diff-read.sh`
  → `4b51d96 feat: warn/deny sub-guard for Bash-side diff reads (CTX-COST-GUARDS-01)`
- The file exists (13381 bytes, mode 755) and IS registered as a third sub-guard in
  `plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh:52` (doc comment) and `:67` (dispatch table
  row), alongside `leadv2-block-bash-heredoc.sh:57` and `leadv2-block-fg-dispatch.sh:58`.
- On top of that commit the worktree carries an **uncommitted** delta:
  `git diff --stat plugins/leadv2/hooks/` → `leadv2-bash-pre-dispatch.sh +9/-…`,
  `leadv2-warn-bash-diff-read.sh +116/-…`, `leadv2-loop-detect-hook.sh +29/-…`.

So FIX B is **not a build item — it is a verification-and-land item.** The implementer must run
the mission's red/green table against the code that is already on disk, and either land the
uncommitted delta or reduce it, but must NOT re-author the guard from scratch. Re-authoring would
discard `4b51d96` plus 116 uncommitted lines and is the single most likely way this task
regresses. If any row of the mission's table fails against the current file, fix that row only.

`leadv2-loop-detect-hook.sh` also carries an uncommitted +29 delta. It is **not in scope for this
task** and must not be bundled into this lane's commit — it belongs to whatever lane authored it.
Declare it out of scope explicitly (see §7).

**FIX A is real and unfixed.** `_PC_PORCELAIN_EXCLUDE_RE`
(`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh:1192`) is exactly as the mission
describes and covers only `docs/leadv2/`, `docs/handoff/`, `docs/LEAD_V2_STATE.md`,
`__pycache__/`, `*.pyc`. This repo's own `git status` right now shows `?? .claude/commands/`.

---

## 1. CALLERS / CALLEES — the mechanism FIX A touches

### `_PC_PORCELAIN_EXCLUDE_RE` (constant, `leadv2-dispatch-product-close.sh:1192`)

| Consumer | file:line | Path it sits on |
|---|---|---|
| `_pc_lane_dirty` body | `leadv2-dispatch-product-close.sh:1199-1200` | shared helper |
| scope partition (inline porcelain, second site) | `leadv2-dispatch-product-close.sh:2105-2106` | blocked-reason branch |

No other file in `plugins/leadv2/scripts` or `plugins/leadv2/hooks` references either symbol —
verified by `grep -rn '_PC_PORCELAIN_EXCLUDE_RE\|_pc_lane_dirty' plugins/leadv2/scripts` with
`leadv2-dispatch-product-close.sh` filtered out: zero hits. The mechanism is single-file.

### Callers of `_pc_lane_dirty` — THREE, not two

| # | Caller | file:line | What a `dirty` verdict means there |
|---|---|---|---|
| 1 | scope partition `elif` | `:2093` | enter the declared/undeclared partition → can emit `unscoped_lane_work` |
| 2 | `pc_silent_arm_probe` step 5 | `:1448` (`_pc_lane_dirty "${_lane_root}" && return 1`) | dirty ⇒ **NOT silent** ⇒ probe declines to emit `arm_produced_nothing` |
| 3 | review-gate lane guard | `:1448` is the same site as #2; the `REVIEW-GATE-LANEROOT-01` comment at `:1444-1447` documents it | — |

**Caller #2 is the independent path nobody named in the mission, and it moves in the opposite
direction from caller #1.** Today a lane whose only dirt is the bootstrap symlink is graded
*dirty*, so `pc_silent_arm_probe` returns 1 (not silent) and never emits `arm_produced_nothing`.
After FIX A the same lane is graded *clean*, so the probe proceeds past step 5 to the
commits-ahead check at `:1454-1460` and, if `commits_ahead == 0`, **can now emit
`arm_produced_nothing` where it previously stayed silent**. That is a real behaviour change on a
second path, and it overlaps the open founder question `GATE-FALSE-SILENT-01` currently on the
status board. The implementer must not treat caller #2 as collateral: run the arm-probe suites
and state the delta in the deliverable.

### Callees of the code being edited

`_pc_lane_dirty` calls only `git -C … rev-parse` and `git -C … status --porcelain
--untracked-files=all`, then `grep -vE`. The partition site at `:2105` additionally calls
`_pc_join_capped` (`:2084`, `:2133`), `_pc_phys` (`:1212`, used at `:2130`),
`_pc_lane_root_is_own_worktree` (`:1215`, used at `:2085`), `_pc_lane_produced_files` (`:2091`).
None of those are touched by this design.

### Who creates the offending path

`plugins/leadv2/hooks/leadv2-command-bootstrap.sh:56-58` —
`mkdir -p "${repo}/.claude/commands"` then `ln -s "$src" "$dst"`. One path, one symlink, created
per fresh worktree by a plugin hook. `plugins/leadv2/scripts/leadv2-repo-install.sh` is the
manual/`--check` sibling: `:105-113` links `.claude/scripts/**`, `:131-137` links
`.claude/agents/*`, `:164-166` links `.claude/commands/leadv2.md`, `:175` `mkdir -p
docs/leadv2/tasks`, `:192` `mkdir -p "$STATE"` (outside the repo, `~/.claude/leadv2-state/<slug>/`
— never appears in porcelain).

`.gitignore` already ignores `.claude/scripts/` (line 10) and `.claude/worktrees/` (line 15). It
does **not** ignore `.claude/commands/` or `.claude/agents/`. So in *this* repo only
`.claude/commands/` and `.claude/agents/` can reach porcelain — but foreign lanes
(persona-engine, m3-market, respiro-ios) have their own `.gitignore`, and this gate runs against
them too, so `.claude/scripts/` must be in the prefix set regardless.

---

## 2. DESIGN — FIX A

### 2.1 The blocking constraint: a regex cannot express "only if it is a symlink"

Mission requirement #2 ("exclude ONLY when it is a symlink or an untracked bootstrap artifact")
**cannot be implemented by widening `_PC_PORCELAIN_EXCLUDE_RE`.** The constant is a
`grep -vE` pattern applied to porcelain *text*; it has no access to the filesystem. Widening it to
`^.. "?\.claude/commands/` would also swallow a real file a worker wrote at
`.claude/commands/foo.md` — the exact overreach the mission forbids. The existing test proves the
constant is text-only: `test-scope-gate-orchestration-dirt.sh:87-96` (`_survives`) pipes a literal
porcelain string through the extracted regex with no repo on disk.

**Therefore: two filter stages, not one wider regex.**

### 2.2 Shape

Add, adjacent to the constant at `:1192`:

```
_PC_BOOTSTRAP_PREFIX_RE='^\.claude/(commands|scripts|agents)/'
```

Add a filter function that reads porcelain lines on stdin and writes the survivors:

```
_pc_drop_bootstrap_dirt() {   # <lane-root> ; stdin=porcelain, stdout=porcelain minus bootstrap
  ...
}
```

Per line the drop predicate is the conjunction of THREE conditions — dropping any one of them
reintroduces the overreach:

1. the porcelain status field is exactly `??` (untracked). A tracked-modified ` M` /
   `M ` / `A ` line under the same prefix is **never** dropped — a worker that edited a tracked
   `.claude/agents/critic.md` is still a scope violation.
2. the path matches `_PC_BOOTSTRAP_PREFIX_RE`.
3. `[ -L "${root}/${path}" ]` — the path on disk **is a symlink**. This is the predicate that
   enforces strictness (mission req #2); a real regular file a worker wrote under the same prefix
   fails `-L` and survives the filter, reaching the declared/undeclared partition unchanged.

Path extraction must reuse the partition's existing conventions verbatim (`:2112-2116`): slice
from index 3, take the right side of `" -> "` for renames, strip surrounding quotes. A `??` line
is never a rename, but sharing the extraction keeps the two sites textually parallel.

### 2.3 Both call sites, kept in sync

`_pc_lane_dirty` (`:1199-1200`) becomes:

```
status="$(git -C "${root}" status --porcelain --untracked-files=all 2>/dev/null | \
  grep -vE "${_PC_PORCELAIN_EXCLUDE_RE}" | _pc_drop_bootstrap_dirt "${root}")"
```

Partition (`:2105-2106`) becomes the same two-stage pipeline with `"${_lane_root}"` as the root.

**Constraint the implementer must not break:** `test-scope-gate-orchestration-dirt.sh:76-84`
(`_both_sites_use_constant`) asserts that the count of `grep -vE "${_PC_PORCELAIN_EXCLUDE_RE}"`
equals the count of `status --porcelain --untracked-files=all`, and that both are ≥ 2. Appending a
pipeline stage keeps that literal intact at both sites, so the assertion still passes. The
implementer must add a **parallel** assertion for the new stage (count of
`| _pc_drop_bootstrap_dirt ` == count of porcelain sites) so the second filter cannot drift the way
the first one did on 2026-08-21. Extend the `SCOPE-GATE-ORCHESTRATION-DIRT-01` comment block at
`:1178-1192` and the mirror at `:2101-2104` to name both stages.

### 2.4 The `no_work` requirement falls out — no new branch

Mission point 4 ("when the ONLY dirt is excluded bootstrap, the verdict is `no_work` with its real
cause") needs **no code beyond the filter**. Trace: filter empties the set → `_pc_lane_dirty`
returns rc 1 → the `elif` at `:2093` is false → control reaches the `else` at `:2144` →
`_pc_terminal="no_work"; _pc_cause="empty_diff"`, upgraded to `asked_into_void` at `:2146-2148`
when the Design-C marker file is present. The real cause is preserved. Adding a dedicated
"bootstrap-only" cause word would be a new terminal-vocabulary entry
(`leadv2-dispatch-ledger.sh`) for no diagnostic gain — **explicitly out of scope**.

---

## 3. STATES AND RETURN CODES

### 3.1 `_pc_drop_bootstrap_dirt` (new)

| State | rc | stdout | Consequence |
|---|---|---|---|
| root empty / not a dir | 0 | stdin passed through unfiltered | fail-open: nothing is dropped, gate stays as strict as today |
| line is `??` + prefix match + `-L` true | 0 | line omitted | bootstrap dirt ignored |
| line is `??` + prefix match + `-L` false (real file) | 0 | line kept | still a candidate violation |
| line is ` M`/`M `/`A ` under prefix | 0 | line kept | still a candidate violation |
| any other line | 0 | line kept | unchanged |
| stdin empty | 0 | empty | unchanged |

It must never return non-zero. A non-zero rc at the tail of the `$( … )` pipeline is invisible
(command substitution takes the last stage's status only where `pipefail` is set — this script's
`set -o pipefail` state must be checked by the implementer; if `pipefail` is on, a non-zero tail
would blank `status` and silently grade every lane clean). **Design mandate: the function returns
0 unconditionally.**

### 3.2 `_pc_lane_dirty`

| State | rc | Caller #1 (`:2093`) | Caller #2 (`:1448`) |
|---|---|---|---|
| root empty/missing/not a work tree | 1 (unchanged) | falls to `else` → `no_work`/`empty_diff` | `&& return 1` not taken; probe continues to commits-ahead |
| survivors non-empty | 0 | enters partition | probe returns 1 = **not silent** |
| survivors empty (incl. bootstrap-only, NEW) | 1 | falls to `else` → `no_work`/`empty_diff` | probe continues → may emit `arm_produced_nothing` |

### 3.3 Terminal outcomes reached, in plain words

| `_pc_terminal` / `_pc_cause` | Emitted at | What a human sees |
|---|---|---|
| `refused` / `unscoped_lane_work` | `:2132`, ledger row `review_gate … reason=unscoped_lane_work` | The lane is rejected and **re-dispatched**; the worker's finished diff is discarded and the work is done over. This is the outcome the bug causes today, for a symlink the plugin itself created. |
| `refused` / `lane_root_not_a_worktree` | `:2087` | Unchanged by this design. |
| `refused` / `declared_no_bytes` | `:2142` | Unchanged. |
| `refused` / `cross_repo_elsewhere` | `:2140` | Unchanged. |
| `no_work` / `empty_diff` | `:2145` | The lane is recorded as having produced nothing; retryable, and the founder-status row reads as an empty lane rather than a scope violation. **This is the target outcome for a bootstrap-only lane.** |
| `no_work` / `asked_into_void` | `:2147` | Worker asked a question nobody answered. |
| `no_work` / `arm_produced_nothing` | `:2287` (`pc_silent_arm_probe` path) | The arm is graded silent. **Newly reachable** for a bootstrap-only-dirty lane — see §1 caller #2. |

Exit code of the blocked branch stays 5 throughout (`:2069` comment). No caller-contract change.

---

## 4. CONFIGURATION BOUNDARIES

Every input the FIX-A mechanism reads:

| Input | Absent | Empty | Minimum | Maximum / over-cap | Malformed |
|---|---|---|---|---|---|
| `_lane_root` (shell var) | `-n`/`-d` guards at `:2093`, `:1447`, `:1196` → treated as no lane → `no_work`/`empty_diff` | same as absent | one dir | — | a path that is inside but not equal to a worktree root is caught earlier by `_pc_lane_root_is_own_worktree` (`:2085`) |
| `git status --porcelain` output | git failure → `2>/dev/null`, empty output → rc 1 → `no_work` | rc 1 → `no_work` | 1 line | thousands of lines: filter is one `while read` pass, O(n) with one `[ -L ]` stat **only for lines that already matched the prefix regex** — put the regex test BEFORE the stat so a 5000-line porcelain does not do 5000 stats | quoted paths with spaces already handled at `:2116`; rename arrows at `:2115` |
| `_PC_BOOTSTRAP_PREFIX_RE` | it is a literal constant, cannot be absent | — | — | — | — |
| the symlink target | dangling symlink: `[ -L ]` is still **true** for a dangling link (unlike `[ -e ]`) — correct, since a lane whose canonical checkout moved still has plugin-created dirt, not worker dirt | — | — | — | — |
| `writes[]` (declared write-set, partition only) | `"${writes[@]:-}"` guards at `:2084`, `:2118` | every dirty path is undeclared → `unscoped_lane_work` | — | `_pc_join_capped` truncates the evidence string, not the decision | unchanged by this design |

**Blast-radius rule the mission states and this design honours:** no input here can take down more
than the one lane it belongs to. The filter is per-lane-root, invoked inside a command
substitution, and returns 0 unconditionally. There is no path by which a malformed porcelain line
in lane A affects lane B.

**One over-cap hazard the implementer must not introduce:** do not build the survivor set by
repeated string concatenation in a `for` loop over an unbounded porcelain — use the `while IFS=
read -r` + `printf` shape already used at `:2110-2128`.

---

## 5. COUNTEREXAMPLE — what still violates the invariant after every finding is fixed

The invariant: *a lane is refused for scope only when a worker wrote something it did not
declare.*

After this fix, three things can still violate it, and one of them is not addressable here.

**(a) Bootstrap artifacts that are real files, not symlinks.** `leadv2-repo-install.sh:242-245`
**writes** `.claude/settings.json` (it adds missing env keys via the Python block at `:221`), and
`:175` creates `docs/leadv2/tasks` — the first is a real tracked file the plugin modifies, and it
is *not* covered by `_PC_PORCELAIN_EXCLUDE_RE`, *not* under `.claude/commands|scripts|agents/`,
and *not* a symlink, so all three conditions of the new drop predicate fail and it survives as
undeclared dirt. If a session ever runs repo-install (or any settings-writing hook) inside a lane
worktree, the gate refuses that lane for exactly the class of reason this task exists to
eliminate. This design deliberately does **not** exclude `.claude/settings.json`: excluding a real
tracked file by path would be the overreach mission req #2 forbids, and the honest fix is for the
bootstrap to not write into a lane worktree. **Flagged for the lane, not fixed by it.**

**(b) Any future plugin-created dirt outside the three prefixes.** The prefix list is a closed set
derived from today's `leadv2-command-bootstrap.sh` and `leadv2-repo-install.sh`. A new bootstrap
step that scaffolds, say, `.claude/hooks/` reproduces the identical failure. Nothing in the design
detects that; the mitigation is the test in §6, which pins the prefix set so a change to it is a
deliberate edit with a red test, not a silent drift.

**(c) A worker that writes a *symlink* under `.claude/commands/`.** The `-L` predicate cannot
distinguish a plugin-created symlink from a worker-created one — `ctime` would, but ctime is not
reliably comparable across a worktree's lifetime and any ctime threshold is a new tunable that can
be wrong. This design accepts the gap: the failure mode is a missed refusal (too permissive) for a
worker who writes symlinks into `.claude/commands/`, which no worker in this system does, versus
today's failure mode of refusing every lane in every fresh worktree. I checked
`leadv2-command-bootstrap.sh`, `leadv2-repo-install.sh`, `.gitignore`, and both porcelain call
sites; I did not find a way to distinguish the two symlink authors without adding a manifest of
plugin-created paths, which is a larger design than this task.

For FIX B: since the guard already exists, the residual risk is not "the guard is missing" but
"the uncommitted 116-line delta changes behaviour the mission's table does not cover." The
counterexample there is a reviewer worker whose legitimate diff read is blocked because
`LEADV2_DIFF_READ_DENY` was set globally rather than per-session — the mission's own default
(WARN, exit 0) is what prevents it, and the implementer must confirm the current file still
defaults to WARN.

---

## 6. TEST PLAN (what the implementation must add)

Extend `plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh` — do not create a new
suite; the drift guard lives there.

New cases requiring a **real scratch worktree** (the existing `_survives` string harness cannot
express `-L`):

| # | Setup in scratch worktree | Assert |
|---|---|---|
| 8 | only `.claude/commands/leadv2.md` as a symlink | partition yields **not** `unscoped_lane_work`; terminal `no_work`, cause `empty_diff` |
| 9 | that symlink **plus** a real undeclared file | still `unscoped_lane_work`, `offending` names the real file **and not the symlink** |
| 10 | a **real regular file** at `.claude/commands/leadv2.md` | `unscoped_lane_work` (the `-L` predicate must not be bypassed by prefix alone) |
| 11 | a tracked-modified path under `.claude/agents/` | `unscoped_lane_work` (the `??` predicate) |
| 12 | drift guard: count of `| _pc_drop_bootstrap_dirt ` == count of porcelain sites | rc 0 |

Red-first is required (RED-FIRST-GATE-01): cases 8 and 9 must be shown red on `4b51d96` and green
after. Cases 10–12 are anti-overreach and will be green both before and after — label them as
such rather than claiming them as falsifications.

FIX B: run the mission's red/green table verbatim against the **existing**
`leadv2-warn-bash-diff-read.sh`. `bash -n` both hook files plus one heredoc-guard regression case.

---

## 7. NON-GOALS (the implementer must ignore these)

- Re-authoring `leadv2-warn-bash-diff-read.sh`. It exists; verify and land.
- The uncommitted `leadv2-loop-detect-hook.sh` +29 delta. Not this task; must not enter this
  lane's commit.
- `hooks.json` — untouched (mission hard requirement).
- The two existing sub-guards' behaviour — untouched.
- `_pc_git_diff`'s `:(exclude)` pathspec set (`:1190-1191`, `:1540`) — governs what a *reviewer*
  sees, a separate decision from what counts as a scope violation. Do not sync it.
- A new terminal/cause vocabulary word for "bootstrap-only dirt" (see §2.4).
- Excluding `.claude/settings.json` (see §5a) — flag it, do not fix it.
- Changing `.gitignore`. Adding `.claude/commands/` there would fix this repo and leave every
  foreign lane broken; the gate is the right place.
- The open `GATE-FALSE-SILENT-01` founder question about test case C5. Separate lane.

---

## 8. Mandatory constraint checklist

1. **Env var naming.** FIX B's `LEADV2_DIFF_READ_MAX_LINES`, `LEADV2_DIFF_READ_DENY`,
   `LEADV2_DIFF_READ_GUARD` all carry the `LEADV2_` prefix. No `LEAD_V2_*` drift. FIX A
   introduces no env var. PASS.
2. **File paths.** All paths cited exist on disk and were read this session, except the new test
   cases (additions to an existing file). PASS.
3. **`claude -p` commands.** This design introduces none. N/A.
4. **Concurrent access.** `_pc_drop_bootstrap_dirt` is read-only (`[ -L ]` stat only) and never
   touches the index or working tree — same property `:1175-1177` claims for `_pc_lane_dirty`. No
   new race surface, no lock needed. The pre-existing race (a hook bootstrapping a symlink *while*
   the gate reads porcelain) is unchanged: the worst case is a line that git listed and the stat
   no longer resolves, which fails `-L` and survives — strict, not permissive.
5. **Config contradiction.** `_PC_BOOTSTRAP_PREFIX_RE` is new and referenced only by the new
   filter; grep confirms no existing symbol of that name. PASS.

`decisions[]`, `source: architect(self-check)`:
- **D-A1** — the exclusion is two-stage (text regex + filesystem predicate), never one wider
  regex, because mission req #2 is not expressible in `grep -vE`.
- **D-A2** — the drop predicate is `?? AND prefix AND -L`, all three; `-L` is the strictness
  enforcer named in the comment.
- **D-A3** — `no_work`/`empty_diff` is reached by the existing `else` at `:2144`; no new branch,
  no new cause word.
- **D-A4** — the literal `grep -vE "${_PC_PORCELAIN_EXCLUDE_RE}"` stays at both sites so
  `_both_sites_use_constant` keeps passing; a parallel drift assertion covers the new stage.
- **D-B1** — FIX B is verify-and-land, not build.

---

## 9. Acceptance

```
acceptance:
  - surface: log_line
    observable: >
      In the dispatch ledger for a lane whose only uncommitted change is the
      plugin-created .claude/commands/leadv2.md symlink, the review_gate row reads
      "no_work" with cause "empty_diff" — the words "unscoped_lane_work" and
      ".claude/commands/leadv2.md" do not appear anywhere in that lane's rows.
    authored_at: 2026-08-25T15:40:00Z
  - surface: log_line
    observable: >
      For a lane that has that same symlink AND an undeclared file a worker actually
      wrote, the review_gate row still reads "unscoped_lane_work", and the offending
      list names the worker's file only — the symlink path is absent from it.
    authored_at: 2026-08-25T15:40:00Z
  - surface: file_artifact
    observable: >
      docs/handoff/CTX-COST-GUARDS-01/developer.full.md contains both verbatim scratch-worktree
      outputs above, the FIX-B red/green table run against the already-committed guard, and a
      sentence stating that leadv2-warn-bash-diff-read.sh was verified rather than rewritten.
    authored_at: 2026-08-25T15:40:00Z
  - surface: rendered_line
    observable: >
      A lead session that runs an unbounded diff read in Bash sees a three-line advisory
      pointing at "git diff --stat", the handoff dir's review-findings.json, and
      "repowise distill" — and the command still runs.
    authored_at: 2026-08-25T15:40:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-scope-gate-orchestration-dirt.sh, plugins/leadv2/hooks/leadv2-warn-bash-diff-read.sh, plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh

DELIVERABLE_COMPLETE
