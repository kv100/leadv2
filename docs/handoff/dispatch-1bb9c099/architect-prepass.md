# architect prepass — PLUGIN-SYNC-CLAUDE-SCRIPTS-01 round 2

Lane root confirmed in `git worktree list`:
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/67198a6e  f05eddf [worktree-67198a6e]`.
All line numbers below are from that tree's `plugins/leadv2/scripts/leadv2-plugin-sync.sh`
(919 lines at `f05eddf`).

---

## 0. Where the mission's framing and the code disagree

Two of the five required cases describe behaviour that **does not exist in the tree**. Stating
this up front, because designing the tests against the mission's wording alone guarantees a
round 3.

| Mission case | Code reality | Consequence for the design |
|---|---|---|
| 3 — DRIFT "reports it (exit code and message both asserted)" | `_link_project_scripts` logs a WARN and increments `project_drift_files`; the script's exit status is **0** (`leadv2-plugin-sync.sh:917-918` is the last statement and a false `if` yields rc 0). | Asserting the current rc would assert *silent survival*. Design adds **D1** (rc 4 on drift). |
| 5 — "a path listed as a deliberate per-repo override is left alone and is not converted to a symlink" | plugin-sync has **no exception list of any kind**. The declared-override vocabulary lives in a *different* script — `leadv2-one-copy-convert.sh:28` (`LEADV2_ONE_COPY_EXCEPTIONS_FILE`, default `plugins/leadv2/ref/one-copy-exceptions.txt`) — and plugin-sync never reads it. Today a byte-identical deliberate override is classified `CONVERT` and **is** symlinked. | The test cannot pass without new behaviour. Design adds **D3** (~20 lines) rather than re-defining case 5 into something already true. |

The mission is the reason to look; the code is what the design targets.

---

## 1. CALLERS / CALLEES

### 1.1 The mechanism under test

- `_link_one_file()` — `leadv2-plugin-sync.sh:150`. Pure classifier + writer. Prints exactly one
  token on stdout, **always returns 0**. Callees: `readlink -f`, `cmp -s`, `ln -s`, `mv -f`,
  `mkdir -p`, `rm -f`, `dirname`.
- `_link_diff_detail()` — `:217`. Callees: `git --no-pager diff --no-index --stat`, fallback
  `diff | grep -c`. Called only from the two DRIFT log lines.
- `_link_project_scripts()` — `:231`. Enumerates canonical, calls `_link_one_file` at `:254`,
  tallies, writes `project_link_tallies` / `project_drift_files` / `project_drift_repos` (`:271`).

### 1.2 Callers of `_link_one_file` — **two, on different paths**

This is the independent copy the mission does not name.

1. **(c) `.claude/scripts`** — `_link_project_scripts` at `:254`. Full token vocabulary handled;
   DRIFT increments the drift counters at `:271`.
2. **(c2) `<repo>/scripts` top-level curated set** — `_sync_project_root` at `:664`, over the
   fixed `toplevel_curated_files` array (`:648-657`). Same classifier, **different and weaker
   handling**: the `DRIFT` branch logs a WARN and *does not touch `project_drift_files`*
   (`:667`). See **D2**.

### 1.3 Caller of `_link_project_scripts` — one

`_sync_project_root` `:626`, reached only when all of: `proj_scripts` is not a symlink (`:610`),
`vendors_scripts != false` (`:617`), `proj_scripts` already exists as a directory (`:622-624`),
canonical `scripts/` exists.

### 1.4 Callers of the whole script (blast radius of an exit-code change)

| Caller | file:line | Reads plugin-sync's rc? |
|---|---|---|
| `leadv2-plugin-sync-drift-warn.sh` (PostToolUse hook) | `plugins/leadv2/hooks/leadv2-plugin-sync-drift-warn.sh:34`, registered `hooks/hooks.json:491` | **No.** Matches on the command string, then runs `leadv2-drift-guard.sh` itself; documented warn-only, always exit 0. |
| `test-lane-truth-batch-01.sh` Row 3 | `:182`, `:200`, `:218`, `:231` | **No** — every invocation is `… || true`. |
| `test-drift-guard-quarantine-perimeter.sh` | `:68`, `:118` | **No** — drives `fixtures/pe_run_cache_sync.sh`, which `source`s only lines `1 .. (line of ^changed_summary=()) - 1`. The exit-code change at `:917` is far below that cutoff. |
| `test-drift-guard-safety-fixes.sh` | `:255` | **No** — sources a single function by name. |
| `test-drift-direction-gates.sh` | `:310` | `bash -n` only. |
| Human / lead from chat, and the remediation string in `leadv2-fanout.sh:85` | — | rc is the point; a non-zero drift exit is the desired signal. |

**Verdict: no production caller breaks on a new non-zero exit.** The fixture's line-based cutoff
is computed by `grep -n "^changed_summary=()"` (`fixtures/pe_run_cache_sync.sh:22`), so it also
survives the ~135-line insertion `f05eddf` already made — no hardcoded line number anywhere.

### 1.5 The other write paths into the same trees (NOT covered by this mechanism)

`_sync_project_root` is one of six targets. (a) plugin cache, (b) `~/.claude/leadv2-shared`,
(d) `<repo>/.claude/contracts`, (e) `~/.claude/scripts`, (f) `~/.codex/skills/...` all still go
through `_rsync_or_dry` (`:131`) or bare `cp -p` (`:680`). They copy. See §4.

---

## 2. STATES AND RETURN CODES

### 2.1 `_link_one_file` token table (rc is always 0; the token is the return value)

| Token | Precondition | Write performed | (c) handling `:257-268` | (c2) handling `:665-670` | User-visible consequence |
|---|---|---|---|---|---|
| `SKIP` | canonical is not a regular file | none | WARN "canonical file vanished" | *not in the case list → silently dropped* | (c2) a vanished canonical file produces no output at all |
| `DANGLING` | dst is a symlink whose target is missing | none | WARN, untouched | WARN, untouched | broken script stays broken; run still exits 0 |
| `OK` | dst symlink, `readlink -f` == canonical `readlink -f` | none | counted, no log | *not in the case list → silent* | steady state |
| `BADLINK` | dst symlink resolving elsewhere | none | WARN, untouched | WARN | a link pointing at a stale tree survives every sync |
| `TYPECLASH` | dst is a directory | none | WARN | WARN | — |
| `LINK` | dst absent | `mkdir -p` + `ln -s` (skipped in dry-run) | log LINK/WOULD LINK | log | **the case that regressed** — new canonical scripts now arrive as links |
| `CONVERT` | dst real file, `cmp -s` equal | `ln -s` to `dst.tmp.$$` + `mv -f` | log CONVERT | log | an identical real copy becomes a link — **including a deliberate override (D3)** |
| `DRIFT` | dst real file, `cmp` rc 1 | none | WARN + `project_drift_files++`, `project_drift_repos++` | WARN **only** — counters untouched (**D2**) | divergent content survives; **script still exits 0** (**D1**) |
| `ERROR` | unreadable dst, or `mkdir`/`ln`/`mv` failed | possible `rm -f` of the tmp link | WARN | WARN | a failed link is indistinguishable from success in the exit status |
| *anything else* | — | — | WARN "unknown link classification" | *no default branch → silently dropped* | (c2) an unknown token is invisible |

`cmp` disambiguation at `:207-212` is correct: inside the `else`, `$?` is still `cmp`'s status
(no intervening command), so rc 1 → `DRIFT` and rc ≥ 2 → `ERROR`. Do not "clean this up".

### 2.2 Script exit codes

| rc | Trigger | file:line | What the caller sees |
|---|---|---|---|
| 0 | normal completion — **including any number of DRIFT/BADLINK/DANGLING/ERROR files** | falls off `:918` | "sync succeeded"; drift is a WARN line buried in a multi-hundred-line stderr stream |
| 2 | unknown arg; `--project-root` with no/empty value | `:100-107` | usage error |
| 3 | invoked from the plugin cache; pinned `PLUGIN_ROOT` missing | `:66`, `:83` | hard refusal |
| non-zero (uncontrolled) | `set -euo pipefail` on an unguarded failure | `:56` | — |

**D1 — the terminal outcome in plain words:** a project's `.claude/scripts/leadv2-foo.sh` diverges
from canonical; the sync run prints one WARN among hundreds of lines and exits 0; the PostToolUse
hook only re-runs drift-guard and never fails; every automated caller records a clean sync. The
divergent copy stays on disk indefinitely and the next lane that edits canonical is silently not
applied in that repo — the exact 2026-07-29 defect this whole change exists to prevent.

**D1 fix (minimal):** after `:918`, `exit 4` when `project_drift_files > 0`. Document rc 4 in the
usage header (`:19-20`). Callers verified safe in §1.4.

**D2 fix (minimal):** in `_sync_project_root`'s `DRIFT` branch (`:667`), increment
`project_drift_files` and set a per-repo flag so `project_drift_repos` counts the repo once
across (c) and (c2). Without this, a divergent file in `<repo>/scripts/` is reported but never
counted, never reaches the ACTION REQUIRED summary, and — after D1 — still exits 0. Also add
`OK|SKIP` to the (c2) case list so the token vocabulary is closed there too.

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at absent / empty / minimum / over-cap / malformed:

| Input | Absent | Empty | Minimum | Over-cap | Malformed | Verdict |
|---|---|---|---|---|---|---|
| `LEADV2_CANONICAL_ROOT` (`:78`) | defaults `$HOME/Projects/leadv2` | `:-` treats empty as absent | — | — | path not a dir → **exit 3** with a named path | correct, fail-closed |
| `HOME` | — | — | — | — | — | drives `CACHE_TARGET`/`SHARED_TARGET`/`CROSS_REPO_CONFIG` (`:124-126`) and the cache-refusal glob (`:65`). **This is the test-isolation seam.** |
| `--project-root` (`:100`) | falls through to `LEADV2_PROJECT_ROOT`, then yaml | **exit 2** (fixed in `f05eddf`) | — | — | non-existent dir → WARN + skip, rc 0 (`:591`) | ok |
| `LEADV2_PROJECT_ROOT` (`:543`) | yaml path | `-n` guard → treated as absent | — | — | same as above | ok |
| `cross-repo-paths.yaml` (`:126`) | WARN + skip (`:548`) | new WARN "resolved 0 project roots" (`:887-889`) | 1 repo | 3 repos live | **PyYAML raises → `roots_rc≠0` → WARN, then `<<< ""` iterates one empty line → `continue`** | **nothing syncs, rc 0.** Same silent-failure class as D1; out of scope for this lane, flag it. |
| `vendors_scripts` per repo | defaults `true` (`:566`) | — | — | — | quoted `"false"` handled (`:560-565`) | correct |
| `<repo>/.claude/scripts` | "absent — not creating it", no-op (`:622`) | dir exists, empty → every canonical file is `LINK` | — | ~200 canonical files (top-level + `lib/` + `tests/`) → ~200 command substitutions + `readlink -f`/`cmp` each; acceptable | is a symlink → whole (c) skipped (`:610`); is a *plain file* → `-L` and `-d` both false → treated as "absent", no-op | ok |
| canonical `scripts/` layout (`:239-249`) | `-d` guard → return 0 | — | — | — | only top-level files + `lib/` + `tests/` are enumerated; **any other canonical subdir is never linked into a project** | deliberate; do not write a test asserting full coverage |
| `one-copy-exceptions.txt` (**to add, D3**) | mirror `leadv2-one-copy-convert.sh:84-87`: WARN + empty list | empty list | — | linear scan × ~200 files — fine | comment/blank trimming already specified at `:88-95` of that script | must be overridable via `LEADV2_ONE_COPY_EXCEPTIONS_FILE` so the test never reads the real file |

**Over-cap / malformed blast rule check:** no input here takes down more than its own operation.
The one exception is malformed `cross-repo-paths.yaml`, which silently zeroes the *entire* (c)/(d)
surface at rc 0 — named above, not fixed here.

### D3 — declared per-repo exception, minimal design

- Reuse `plugins/leadv2/ref/one-copy-exceptions.txt` and the env override
  `LEADV2_ONE_COPY_EXCEPTIONS_FILE` (identical name and semantics to
  `leadv2-one-copy-convert.sh:28` — one vocabulary, not two).
- Existing root-keys are `agents/` and `scripts/` (`one-copy-exceptions.txt:3`). Add a third,
  unambiguous against both: **`project/<repo-basename>/<relpath>`**, where `<repo-basename>` is
  `${root##*/}` and `<relpath>` is the path under `.claude/scripts/` (for (c)) or under
  `scripts/` prefixed `toplevel/` (for (c2)). Document the new key in the file's header comment.
- Load once per run (not per repo), ~12 lines: same trim/comment rules as
  `leadv2-one-copy-convert.sh:88-95`.
- New token `EXCEPTION`, checked in `_link_one_file`'s caller **before** the classifier — a
  declared exception must be skipped whether it is currently identical (would be `CONVERT`) or
  divergent (would be `DRIFT`). Log once per run per file: `EXCEPTION: <path> (declared override,
  left untouched)`. It must **not** count toward `project_drift_files`, i.e. it must not trigger
  the D1 exit.
- Mirror `leadv2-one-copy-convert.sh:179`'s `STALE-EXCEPTION` courtesy only if free; not required.

---

## 4. COUNTEREXAMPLE

**After all five cases pass and D1/D2/D3 land, what can still put a silently-drifting real copy of
a plugin-owned file on disk?**

Plenty, and one instance is live right now. `_link_project_scripts` governs exactly two of the six
sync targets — (c) `<repo>/.claude/scripts` and (c2) `<repo>/scripts`. Target (b),
`~/.claude/leadv2-shared/scripts`, is still an rsync copy path, and this session's own SessionStart
hook output is the artifact: dozens of lines of the form
`[one-copy] REGRESSION: /Users/kostiantyn.vlasenko/.claude/leadv2-shared/scripts/leadv2-answer.sh is
a real file, identical to canonical (…/plugins/leadv2/scripts/leadv2-answer.sh)` — the shared tree
that all three live repos symlink their `.claude/leadv2/` into is, today, a tree of real copies,
and not one of the five cases looks at it. Target (e) `~/.claude/scripts` is an additive rsync with
the same property; target (a), the plugin cache, is a deliberate copy by design and is the reason
the hook-cache exception exists in the global policy. Beyond the target list: a canonical file
living in a subdirectory other than `lib/` or `tests/` is never enumerated (§3), so it can never be
linked and will be re-copied by whatever else touches it; a repo-native script that happens to
share a canonical basename but is absent from canonical is likewise never enumerated, so it is
neither linked nor reported; and `BADLINK`/`DANGLING` files survive every run at rc 0 even after
D1, because only `DRIFT` feeds the counter. What I checked to say this: the six target sections of
`leadv2-plugin-sync.sh` (`:697` onward), the enumerator at `:239-249`, the token dispatch at
`:257-268` and `:665-670`, and the live one-copy regression list emitted by this session's
SessionStart hook.

**The invariant is narrower than the mission implies:** these five tests protect
*"a canonical-named file under a project's `.claude/scripts/` or curated `scripts/` never becomes a
silent divergent copy"* — not the global one-copy rule. Say so in the report; do not claim the
broader property.

---

## 5. Implementation design

### 5.1 Files

| File | Change |
|---|---|
| `plugins/leadv2/scripts/tests/test-plugin-sync-claude-scripts.sh` | **(to-create)** the five cases |
| `plugins/leadv2/scripts/leadv2-plugin-sync.sh` | D1 (rc 4 + usage header), D2 ((c2) counters + closed token vocabulary), D3 (exceptions loader + `EXCEPTION` token) |
| `plugins/leadv2/scripts/tests/run-core-offline.sh` | one `SUITE_DEFS` entry **and** one `_CORE_OFFLINE_OWNED_SUITES` entry |
| `plugins/leadv2/ref/one-copy-exceptions.txt` | header comment documenting the `project/<repo>/…` root-key (no new exception lines) |

### 5.2 Test harness — copy the proven isolation pattern

`test-lane-truth-batch-01.sh:170-201` already runs the real script hermetically. Reuse it verbatim
in shape:

```
env -u LEADV2_PROJECT_ROOT -u LEADV2_STATE_ROOT -u PROJECT_ROOT \
    HOME="$tmp/home" LEADV2_CANONICAL_ROOT="$canon" \
    LEADV2_ONE_COPY_EXCEPTIONS_FILE="$tmp/exceptions.txt" \
    bash "$PLUGIN_SYNC" --project-root "$tmp/proj" --write 2>"$tmp/run1.log"
```

Non-negotiable harness facts, each verified above:

1. `HOME` must be redirected — targets (a)/(b)/(e)/(f) and `CROSS_REPO_CONFIG` are all
   `$HOME`-derived (`:124-126`). Without it the test writes into the founder's real trees. This
   satisfies the mission's off-limits clause structurally, not by convention.
2. `$canon` must be a **git repo** (`git init` + one commit), as batch-01 does at `:170-172` —
   direction-safety on the (b)/(e) rsync legs reads canonical's git history.
3. `$canon/plugins/leadv2/scripts/` holds 2–3 fake scripts only. The mechanism links *all* of
   canonical, so a real canonical tree would make assertions unreadable.
4. `$tmp/proj/.claude/scripts/` must be **pre-created** — the script refuses to create it
   (`:622`).
5. Use `--project-root`, never the yaml. With `--project-root`, `vendors_scripts` defaults true
   (`:566`).
6. `--write` is mandatory; the default is dry-run since `07d8c56`.
7. Capture stderr — every `log*` writes to fd 2 (`:110-112`).

### 5.3 Case-by-case assertions

| # | Fixture | Assert |
|---|---|---|
| 1 LINK | canonical `a.sh`; no `proj/.claude/scripts/a.sh` | `[[ -L $p ]]`; `readlink $p` == `$canon/plugins/leadv2/scripts/a.sh` (the link is **absolute**, `:180`); stderr matches `LINK: .*a\.sh` |
| 2 CONVERT | `proj/.claude/scripts/b.sh` a real file, byte-identical | `[[ -L $p ]]`; `cat $p` equals canonical content; stderr matches `CONVERT: .*b\.sh` |
| 3 DRIFT | `proj/.claude/scripts/c.sh` a real file with different content | `[[ ! -L $p ]]`; content byte-for-byte the pre-run divergent text; stderr matches `DRIFT: .*c\.sh` **and** `ACTION REQUIRED`; **rc == 4** (after D1). Capture rc with `set +e`/`rc=$?` — the suite runs under `set -e`. |
| 4 Idempotence | run twice | second run's stderr has **no** `LINK:`/`CONVERT:` for the case-1/2 paths (only silent `OK`); `readlink` unchanged; the symlink's **own** inode unchanged — capture with `ls -ldi "$p" \| awk '{print $1}'` (portable across BSD/GNU; `stat -c/-f` is not) |
| 5 EXCEPTION | `$tmp/exceptions.txt` contains `project/proj/d.sh`; `proj/.claude/scripts/d.sh` a real file **identical** to canonical | `[[ ! -L $p ]]` (the CONVERT that would otherwise fire did not); stderr matches `EXCEPTION: .*d\.sh`; and — the assertion that makes the test load-bearing — the run's rc is unaffected by it |

Case 5's fixture must use the *identical* variant, not a divergent one: divergent-and-untouched is
already case 3 and would pass without D3, making the test vacuous.

### 5.4 Suite wiring

- `SUITE_DEFS` entry, matching the sibling format at `run-core-offline.sh:281`:
  `"plugin sync .claude/scripts link classification|||bash $TEST_DIR/test-plugin-sync-claude-scripts.sh"`.
- **Also** add that exact name to `_CORE_OFFLINE_OWNED_SUITES` (`:134-142`). The hermeticity gate
  (`:129-132`) FAILs only for owned suites and merely WARNs for the rest — an unregistered new
  suite could go red while `run-core-offline.sh` still exits 0, which would make the whole guard
  decorative. The two strings must match exactly (`_core_offline_suite_is_owned`, `:143-149`).
- `test-one-copy-drift.sh` is **not** in `SUITE_DEFS` today. Leave it that way; adding it is a
  separate blast radius.

### 5.5 Concurrent-access surface

`run-core-offline.sh` shards in parallel. This suite writes only under its own `mktemp -d` and a
redirected `HOME`, so it has no shared write surface — provided `--project-root` is used and
`$tmp/proj` is inside the mktemp dir. No lock needed. Do **not** add it to the `SERIAL` tail.

---

## 6. Out of scope for the implementing agent

- Targets (a), (b), (d), (e), (f) — the rsync/`cp` legs. The live shared-tree regression in §4 is
  real and is **not** this lane's to fix.
- The malformed-`cross-repo-paths.yaml` rc-0 silence (§3).
- `BADLINK` / `DANGLING` / `ERROR` not feeding the exit code (only `DRIFT` does, by D1).
- Registering `test-one-copy-drift.sh` in `run-core-offline.sh`.
- The three known-foreign reds named in the mission (`deferred-GLM ladder`, `fanout
  classifier/runner guard`, `parked worker contract`). Name them in the report; do not fix.
- Any reshaping of `_link_one_file`'s `cmp`/`$?` idiom (§2.1) — it is correct as written.

---

## 7. Constraint checklist

1. **Env var naming** — `LEADV2_CANONICAL_ROOT`, `LEADV2_PROJECT_ROOT`,
   `LEADV2_ONE_COPY_EXCEPTIONS_FILE`, `LEADV2_CORE_OFFLINE_HERMETIC_GATE` all follow `LEADV2_*`.
   No new env var is introduced; D3 reuses the existing one. PASS.
2. **File paths** — every path cited exists on disk in the lane worktree except
   `plugins/leadv2/scripts/tests/test-plugin-sync-claude-scripts.sh` **(to-create)**. PASS.
3. **`claude -p` commands** — none in this design. N/A.
4. **Concurrent access** — §5.5. No shared write surface. PASS.
5. **Config contradiction** — `LEADV2_ONE_COPY_EXCEPTIONS_FILE` is grepped and used in exactly one
   place today (`leadv2-one-copy-convert.sh:28`); D3 gives it a second reader with identical
   file-format semantics and an additive root-key. No contradiction. PASS.

---

acceptance:
  - surface: log_line
    observable: "A sync run over a project whose .claude/scripts/ holds one file with content
      different from canonical prints a line naming that file as diverging and a final
      ACTION REQUIRED line, the file's own text is still there afterwards unchanged, and the
      command finishes reporting failure rather than success."
    authored_at: 2026-08-23T13:52:00Z
  - surface: file_artifact
    observable: "In a project's .claude/scripts/, a script that canonical has but the project
      did not is now an arrow pointing at the canonical file rather than a second copy of it,
      and a project copy that was already identical to canonical has become the same kind of
      arrow."
    authored_at: 2026-08-23T13:52:00Z
  - surface: file_artifact
    observable: "Running the sync a second time leaves those arrows exactly as they were — same
      target, same underlying directory entry — and the second run says nothing about them."
    authored_at: 2026-08-23T13:52:00Z
  - surface: log_line
    observable: "A file the founder has declared a deliberate per-repo override is still a real
      file after the run, and the run names it as a declared override that was left alone."
    authored_at: 2026-08-23T13:52:00Z
  - surface: log_line
    observable: "The offline core test run lists the new plugin-sync suite among the suites it
      executed, and its counts and final pass/fail line reflect it."
    authored_at: 2026-08-23T13:52:00Z

LANE_WRITES: plugins/leadv2/scripts/tests/test-plugin-sync-claude-scripts.sh, plugins/leadv2/scripts/leadv2-plugin-sync.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/ref/one-copy-exceptions.txt

DELIVERABLE_COMPLETE
