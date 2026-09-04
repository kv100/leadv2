# WORKER-CONTEXT-DIET-01 fix round 1 — mechanism-closed design

Worktree: `.claude/worktrees/9341e2eb` (branch `worktree-9341e2eb`, HEAD `e908a5f`).
All line numbers below are HEAD `e908a5f` in that worktree.

Mechanism under design: the two context-diet gates in `claude-subsession.sh` and the
fail-open contract of `resolve_role_mcp_config()`.

**Invariant the mechanism exists to protect:** *a context-diet resolution problem must
never kill a worker spawn, and must never fail silently — every fail-open path emits
exactly one `WARN context-diet:` line on stderr, and the spawn proceeds with the full
MCP set.* (Stated at `claude-subsession.sh:387-391`; the failure mode it guards is a
lane that "opens and closes with no work produced" on the backgrounded sonnet arm.)

---

## 1. CALLERS / CALLEES

### 1.1 `resolve_role_mcp_config()` — defined `plugins/leadv2/scripts/claude-subsession.sh:400-524`

**Callers — complete set (verified by grep over the whole repo tree, not just the file):**

| # | Call site | Path class | Notes |
|---|-----------|-----------|-------|
| 1 | `claude-subsession.sh:574` — `MCP_CFG=$(resolve_role_mcp_config "$ROLE" "$HANDOFF_DIR") \|\| true` | **production, top-level script body** (not inside a function) — runs on BOTH arms: the `--wait` critic/architect arm and the backgrounded sonnet-arm dispatch | the only production caller |
| 2 | `tests/test-subsession-context-diet.sh:273` — `sed -n '/^resolve_role_mcp_config() {/,/^}$/p'` then `source` | **test, extracted-body copy** — Test 10 calls the function *directly*, bypassing the script body | this is the independent copy the design must not break: it re-derives the function from source text, so a change to the `resolve_role_mcp_config() {` opening line or the closing `^}$` breaks extraction, and the test fails with "renamed/removed?" rather than a wrong answer. Neither planned edit touches those two lines. |
| 3 | `tests/test-subsession-context-diet.sh:107` — `source "$SUBSESSION_SH" ... --wait` under `LEADV2_DRY_RUN=1` | **test, whole-script sourcing** — Tests 1-9 reach the function through the real script body at :574 | |

There is no second production copy: `claude-subsession.sh` is one file, and the
`~/.claude/leadv2-shared/scripts/` view is a per-file symlink to canonical (global
CLAUDE.md shared-trees policy), i.e. the same inode, not a copy. **Nothing in
`leadv2-dispatch-code.sh`, `leadv2-fanout.sh`, or the workflows calls
`resolve_role_mcp_config` directly** — they all spawn through `claude-subsession.sh`,
so the gate is reached exactly once per spawn.

**Callees of the function:**

| Callee | file:line | Failure behaviour today |
|---|---|---|
| `mkdir -p "$handoff_dir"` | :428 | `2>/dev/null \|\| true` — failure silently swallowed, execution continues to :515 |
| `python3 - <heredoc>` (resolver) | :433-502 | rc captured in `py_rc` under `set +e` |
| `printf '%s' "$py_out" > "$resolved_path"` | :515 | **UNGUARDED — finding 2** |
| `python3 -c json.load` (round-trip) | :516 | guarded, `>/dev/null 2>&1`, emits WARN + rc 13 |
| `rm -f "$resolved_path"` | :518 | `2>/dev/null \|\| true` |
| `command -v python3` | :423 | guarded, WARN + rc 14 |

### 1.2 The `EXCLUDE_DYNAMIC` gate — `claude-subsession.sh:582`

Not a function; a top-level `if` in the script body between `CLAUDE_ARGS` assembly
(:555-567) and `export CLAUDE_ROLE` (:591). Its only consumer is `CLAUDE_ARGS`,
consumed by `run_subsession()` at :594-596 (`claude "${CLAUDE_ARGS[@]}" > "$STREAM_OUT"`)
and, in tests, by the `trap ... EXIT` capture at test:105. No other reader.

### 1.3 Where the write at :515 lands

`$handoff_dir` is the caller's `$HANDOFF_DIR`. Resolved path:
`${HANDOFF_DIR}/mcp-role-${safe_role}.resolved.json`. This is the **only** file
`resolve_role_mcp_config()` creates, and it is passed by path to the spawned `claude`
via `--mcp-config` at :576 — so the spawned process reads it *after*
`claude-subsession.sh` has moved on. It must therefore exist and be valid at spawn
time, which is exactly why :516 round-trip-validates it.

---

## 2. STATES AND RETURN CODES

`resolve_role_mcp_config()` — every state, every rc, and what the caller at :574 does
with it. **Caller behaviour is uniform by construction:** `|| true` swallows the rc, and
the only thing the caller inspects is whether stdout was non-empty (:575). So the rc is
*never* branched on in production — it exists for the tests and for the reader. This is
the correct design (fail-open), and the table records the *user-visible* consequence.

| State | rc | stdout | stderr WARN? | Caller at :574-577 | User-visible consequence |
|---|---|---|---|---|---|
| Gate off (`SLIM_MCP` unset/≠1) | 10 | empty | **no** (deliberate — Test 7) | appends nothing | Worker spawns with the full MCP set. Normal operation post-`e908a5f`; nothing in any log. |
| Allowlist file missing AND default missing | 11 | empty | yes | appends nothing | Worker spawns fat; operator sees one WARN naming the role. |
| `python3` absent | 14 | empty | yes | appends nothing | Worker spawns fat; one WARN. |
| Allowlist malformed / `servers` not a list | 13 | empty | yes | appends nothing | Worker spawns fat; one WARN. |
| Named servers all unresolvable in the config chain | 12 | empty | yes | appends nothing | Worker spawns fat; one WARN naming the three sources searched. |
| Resolved file fails round-trip validation | 13 | empty | yes | appends nothing | Worker spawns fat; one WARN; partial file removed at :518 so no stale config is left for a later spawn to trip over. |
| `{"servers": []}` explicit empty | 0 | path | no | appends `--strict-mcp-config --mcp-config <path>` | Worker spawns with **zero** MCP servers — deliberate per-role "no MCP" (documented, Test 5). |
| Normal resolve | 0 | path | no | appends both flags | Worker spawns with only its role's servers. |
| **Handoff dir missing/unwritable** | **currently: subshell dies at :515** | empty | **no — raw bash `No such file or directory` instead** | `\|\| true` catches, appends nothing | **Today: the worker still spawns fat (invariant #1 holds), but the operator gets a bare shell error with no `context-diet` tag and no role name — grep-for-WARN monitoring misses it entirely. Invariant #2 (never fail silently) is broken.** |

**Trace of the last row, in full.** `mkdir -p` at :428 fails → swallowed by `|| true`.
The python resolver at :433 does not touch `$handoff_dir`, so it succeeds and `py_rc=0`.
Control reaches :515; the `>` redirection cannot create the file. The function body runs
inside `$( )` (command substitution) at :574, and the script runs under `set -e`
(re-armed at :504) — so the redirection failure terminates the *subshell*, not the
script. stdout is empty; `|| true` neutralises the rc; :575 sees empty `MCP_CFG` and
appends nothing. **Net effect: the spawn survives.** The defect is not a dead lane — it
is a *silent* fail-open on a path the mechanism promises will be loud, plus an
untagged bash error in the stream file that looks like a script bug to anyone reading it.
I am recording this plainly because the critic's finding text ("breaks the WARN
contract when the handoff/dir is missing … so a missing directory can never kill a
spawn") frames it as a kill risk; **the code says otherwise and the design is against
the code**. It is still worth fixing: the WARN contract is the whole observability
story for a fail-open mechanism, and a `set -e`-dependent survival is one refactor away
from being a real kill.

### 2.1 `EXCLUDE_DYNAMIC` gate states — before and after

| `LEADV2_SUBSESSION_EXCLUDE_DYNAMIC` | today (`:-0" != "0"`) | after (`:-0" == "1"`) | user-visible |
|---|---|---|---|
| unset | off | off | no change |
| `0` | off | off | no change |
| `1` | on | on | no change |
| `2`, `yes`, `true`, `on` | **ON** (any non-0 enables) | **off** | **behaviour change**: a typo'd or truthy-string value silently enabled the flag; now only the literal `1` does |
| empty string `""` | ON (`""` ≠ `"0"`; `:-` does not substitute for a set-but-empty var… — correction: `${VAR:-0}` DOES substitute on empty, so empty → `0` → off) | off | no change |

`SLIM_MCP` at :404 is already strict (`!= "1"` → return 10); no code change there, only
the doc/comment alignment. Post-change both gates read the same way: **enabled iff the
value is exactly `1`.**

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at every boundary.

### 3.1 `LEADV2_SUBSESSION_SLIM_MCP` (env)
| Boundary | Value | Behaviour after this change |
|---|---|---|
| absent | unset | off, rc 10, no WARN |
| empty | `""` | `${:-0}` → `0` → off, no WARN |
| minimum / enabling | `1` | on |
| any other | `0`, `2`, `true`, `-1`, `01` | off, no WARN |
| malformed / huge | 10 KB string, embedded newline, `$(rm -rf /)` | off — the value is only ever compared with `[[ "$x" != "1" ]]`, never expanded, never passed to a command. **Blast radius: this spawn only.** |

### 3.2 `LEADV2_SUBSESSION_EXCLUDE_DYNAMIC` (env)
Identical table, with `== "1"` as the enabling test. Same containment: compared, never
expanded. **No over-cap or malformed value of either env var can affect more than the
one spawn that reads it** — they are read once, per spawn, in the script body.

### 3.3 `$ROLE` → allowlist filename
| Boundary | Behaviour |
|---|---|
| absent | earlier `agents/<role>.md` gate rejects before :400 |
| well-formed `^[a-z0-9-]+$` | used as-is |
| traversal / unsafe (`../../evil`, spaces, `$(...)`) | coerced to `default` at :409 — **Test 10 asserts exactly this** |
| very long (>255 chars, all `[a-z0-9-]`) | passes the regex; `open()` on the resulting path fails → file-not-found branch → rc 11 + WARN. Fat spawn, one WARN. Contained. |

### 3.4 `plugins/leadv2/config/mcp-role-<role>.json`
| Boundary | Behaviour |
|---|---|
| absent | falls back to `mcp-role-default.json` (:415-417) |
| both absent | rc 11 + WARN, fat spawn (Test 3) |
| empty file (0 bytes) | `json.load` raises → exit 13 → rc 13 + WARN (Test 4) |
| `{"servers": []}` | rc 0, flags appended with empty `mcpServers` (Test 5) — deliberate |
| `servers` present but not a list | exit 13 + WARN |
| non-string entries in the list | that entry skipped with `WARN_SKIP` on stderr, rest resolved — **note: this is a second stderr line that does not carry the `context-diet` tag.** Test 7 / the new Test 11 grep for `context-diet`, so this does not false-positive them; called out so a future change does not accidentally start emitting it on the default path. |
| duplicate names | de-duped (:456-458) |
| very large (e.g. 10k server names) | all unresolvable → many `WARN_UNRESOLVED` lines then exit 12. Contained to this spawn; stderr volume is the only cost. |
| malformed source (`.mcp.json` etc.) | skipped with `WARN_SKIP`, next source tried (:478-480) — a broken `.mcp.json` degrades to fat, never to dead |

### 3.5 `$HANDOFF_DIR` (the finding-2 input)
| Boundary | Today | After |
|---|---|---|
| exists, writable | file written | unchanged |
| absent, parent writable | `mkdir -p` creates it | unchanged |
| absent, parent unwritable / read-only FS | `mkdir -p` fails silently → redirect fails → **raw bash error, no WARN**, fat spawn | `mkdir -p` failure detected → tagged WARN, rc 15, fat spawn |
| exists but not writable | redirect fails → **raw bash error, no WARN** | tagged WARN, rc 15, fat spawn |
| exists, is a file not a dir | `mkdir -p` fails → same as above | tagged WARN, rc 15 |
| disk full mid-write | redirect partially succeeds → round-trip validation at :516 catches it → rc 13 + WARN + partial file removed | unchanged (already correct) |

---

## 4. COUNTEREXAMPLE

**After all four findings are fixed, what can still violate the invariant?** Three
things, none of which I propose to fix in this narrow finisher — I am naming them so
the next round is not spent rediscovering them.

(a) The `python3` heredoc's own `WARN_SKIP` / `WARN_UNRESOLVED` lines (:454, :479, :494)
go to stderr **without** the `[claude-subsession] WARN context-diet:` prefix. They can
therefore appear on a *successful* (rc 0) resolve, so "no `context-diet` line on stderr"
is a weaker signal than "no diagnostic output at all". The new default-unset test greps
for the `context-diet` tag specifically, which is the right assertion for the gate-off
path (the function returns at :405, before any python runs), but an operator grepping
stderr for problems will see untagged noise on other paths.

(b) The invariant's survival on the write path is `set -e`-dependent, not
structurally guaranteed. After the fix the write is explicitly guarded, so this is
closed *for the write* — but the same pattern (`|| true` at :574 as the only thing
standing between a subshell death and a hard abort) still protects every other
statement in the function. Any future statement added inside the function inherits the
silent-death behaviour unless its author remembers to guard it. A structural fix
(running the whole body under `set +e` with explicit rc checks) is out of scope here.

(c) Nothing in this mechanism validates that the *resolved server definition* actually
points at the right repo — the stated reason the config is an allowlist of names
(:393-398). A `~/.claude/settings.json` `repowise` entry hard-pinned to another repo
resolves successfully, rc 0, no WARN, and the worker queries the wrong index. That is a
correctness hole in the diet mechanism that no finding in this mission touches, and it
is invisible at every surface this design defines acceptance on. It is off-scope for a
mechanical fix round; it belongs in `docs/leadv2/open-threads.md`.

What I checked to reach these three: every `>`/`>>` redirect and every command
substitution inside `resolve_role_mcp_config()` (:400-524); every `stderr` write in the
function and its heredoc; the full caller set (§1.1); and both gate expressions.

---

## 5. CHANGES — exact files and edits

### C1 — finding 4: normalize `EXCLUDE_DYNAMIC` to strict opt-in
`plugins/leadv2/scripts/claude-subsession.sh:579-584`

- Line 581, comment: replace `Only the literal "0" disables (LEADV2_SUBSESSION_EXCLUDE_DYNAMIC).`
  with a statement of strict opt-in — enabled **iff** the value is exactly `1`; default
  OFF per the 2026-08-23 live probe (delta ≈ 0 vs the mission gate "delta <10K → no
  default-on"). Note the symmetry with `SLIM_MCP` at :404.
- Line 582: `if [[ "${LEADV2_SUBSESSION_EXCLUDE_DYNAMIC:-0}" != "0" ]]; then`
  → `if [[ "${LEADV2_SUBSESSION_EXCLUDE_DYNAMIC:-0}" == "1" ]]; then`

`SLIM_MCP` at :404 is **not** edited — it is already strict.

### C2 — finding 2: guard the resolved-config write
`plugins/leadv2/scripts/claude-subsession.sh:428` and `:515`

- :428 — capture the `mkdir -p` outcome instead of discarding it, so a missing/unwritable
  handoff dir is a *detected* state rather than a deferred redirect failure.
- :515 — wrap the write so a failure produces a tagged WARN and a fail-open return
  instead of a bare shell error:

```
  if ! mkdir -p "$handoff_dir" 2>/dev/null || ! printf '%s' "$py_out" > "$resolved_path" 2>/dev/null; then
    echo "[claude-subsession] WARN context-diet: role=${role} cannot write ${resolved_path} — spawning with full MCP set" >&2
    return 15
  fi
```
(shape, not final keystrokes — the implementer keeps :428 and :515 as two separate
guarded steps if that reads better, as long as **both** failure modes reach the same
tagged WARN + `return 15`.)

- Header comment at :384-385: add `15 write/mkdir failure` to the rc list.

Constraint: `return 15` must be a value the caller ignores — it is, `|| true` at :574.
Constraint: the function's opening line `resolve_role_mcp_config() {` and its closing
`^}$` must stay byte-identical, or Test 10's `sed` extraction (§1.1 row 2) breaks.

### C3 — finding 1: new test for the default-unset path
`plugins/leadv2/scripts/tests/test-subsession-context-diet.sh`

Two edits:

1. **Harness hermeticity (prerequisite).** In `_it_run_subsession()`, immediately after
   `set +e` at :91 and **before** the `extra_env` export at :92, add:
   `unset LEADV2_SUBSESSION_SLIM_MCP LEADV2_SUBSESSION_EXCLUDE_DYNAMIC 2>/dev/null || true`.
   Without this, a "no extra env" case inherits whatever the *invoking operator's* shell
   exports, and the new test passes or fails for reasons unrelated to the code. Ordering
   matters: unset first, export second, so cases 1-9 are unaffected.
2. **New `test_11_defaults_fully_off()`**, registered in the runner list after
   `test_10_role_sanitised` at :329. Task id `CD-11`, role `developer`, **no** extra env.
   Four assertions on one spawn:
   - `--strict-mcp-config` absent
   - `--mcp-config` absent
   - `--exclude-dynamic-system-prompt-sections` absent
   - stderr contains no `context-diet` line

   Use the existing `_has_flag` / `_stderr_of` helpers; follow Test 7's shape. Note
   `_has_flag` matches whole array elements (`$0==f`), so asserting `--mcp-config`
   absent is exact and does not need to account for the path argument.

### C4 — finding 4, test side: prove non-`1` does not enable
`plugins/leadv2/scripts/tests/test-subsession-context-diet.sh`, inside
`test_8_exclude_dynamic_killswitch()` — add one assertion with
`LEADV2_SUBSESSION_EXCLUDE_DYNAMIC=2` (task id `CD-08b`) proving the flag is **absent**.
This is the only test that would have caught the asymmetry, and it is the direct
regression test for C1. No existing test relies on the loose parsing (no case passes a
value other than `0` or `1`), so nothing else needs updating.

### C5 — finding 3: docs
`plugins/leadv2/docs/context-diet.md`
- §1 heading (~:10): `default `1`` → `default `0` (opt-in)`
- §2 heading (~:63): same
- §2 body (~:79-80): replace the "Only the literal `0` disables … any other value is
  treated as on" paragraph with the strict-opt-in rule, stated once for **both** gates:
  enabled iff the value is exactly `1`; every other value, including unset and empty,
  leaves the gate off. Fail-open direction is unchanged.
- One reason line, once: live probe 2026-08-23 (`leadv2-context-diet-probe.sh`)
  measured `cache_creation` delta ≈ 0; mission gate "delta <10K → no default-on" →
  shipped opt-in.

`plugins/leadv2/docs/phases.md` (~:478)
- `LEADV2_SUBSESSION_SLIM_MCP` (default 1) → (default 0, opt-in `=1`)
- `LEADV2_SUBSESSION_EXCLUDE_DYNAMIC` (default 1) → (default 0, opt-in `=1`)
- Keep the "Both fail open … a fat worker, never a dead one" sentence — still true.

### C6 — finding 5: the two Low findings
**Skipped, and this is a positive finding, not a shrug.** Checked: `git log`
`worktree-9341e2eb` (6 commits, none referencing a critic Low), and
`docs/handoff/dispatch-9341e2eb/` — the directory contains `developer.*`, `review.diff`,
`e2e-gate.*`, `selfcheck.md`, `costs.yaml`, `architect-prepass.md`, and **no
`critic.*` file at all**. The critic's text is genuinely unrecoverable from this tree.
Per the mission: do not invent work. No change.

---

## 6. RISKS

| # | Risk | Mitigation |
|---|---|---|
| R1 | The C3 harness `unset` changes behaviour for all 10 existing cases | It only removes ambient env that no case relies on (every case that needs a value exports it via `extra_env`, applied *after* the unset). Run the full suite — all 10 must still pass. |
| R2 | C2's edit changes the function body, breaking Test 10's `sed` extraction | Extraction anchors on the opening and closing lines only; C2 touches neither. Test 10 self-reports extraction failure ("renamed/removed?") rather than silently passing, so a mistake here is loud. |
| R3 | C1 is a real behaviour change for anyone currently setting `EXCLUDE_DYNAMIC=2`/`true` | Gate has been default-OFF since `e908a5f` (one commit ago) and is opt-in; no caller in the repo sets it to a non-`0`/`1` value. Documented in C5. |
| R4 | rc `15` collides with a future rc assignment | Documented in the header comment at :384-385 as part of C2. |
| R5 | Concurrent access: two parallel spawns for the same role write the same `${HANDOFF_DIR}/mcp-role-<role>.resolved.json` | `$HANDOFF_DIR` is per-task, and within a task the same role does not spawn twice concurrently. If it ever did, the round-trip validation at :516 would catch a torn file and fail open. No lock needed; noted so a future fan-out change does not assume one exists. |
| R6 | Env-var naming drift (`LEADV2_*`) | Both vars already use the `LEADV2_SUBSESSION_` prefix; no new env var is introduced by this design. |
| R7 | `claude -p` flag hygiene | This design adds no `claude -p` invocation. The existing spawn at :555-567 carries `--max-turns`, `--output-format`, `--verbose`, `--permission-mode acceptEdits` (deliberately not `bypassPermissions` — pre-existing, unchanged, out of scope). |

---

## 7. NON-GOALS (explicit — implementer must not do these)

- Do **not** change `SLIM_MCP`'s gate expression at :404 — already strict.
- Do **not** flip either default back on, and do **not** re-run the probe.
- Do **not** restructure `resolve_role_mcp_config()` to run under `set +e` (§4b) —
  guard the one write, nothing more.
- Do **not** add the `context-diet` tag to the python heredoc's `WARN_SKIP` /
  `WARN_UNRESOLVED` lines (§4a) — behaviour change beyond the findings.
- Do **not** address the wrong-repo `repowise` resolution hole (§4c) — open-threads item.
- Do **not** touch `--permission-mode`, `--max-turns`, `build_cached_prefix()`,
  `PER_TASK_BOILERPLATE`, or `leadv2-context-diet-probe.sh`.
- Do **not** invent the two Low findings (§C6).
- No refactors, no renames, no reordering of `CLAUDE_ARGS`.

---

## 8. ACCEPTANCE

```yaml
acceptance:
  authored_at: 2026-08-23T20:40:00Z
  items:
    - id: A1
      surface: log_line
      observable: >
        Running the context-diet test suite prints "=== Results: N passed, 0 failed ===",
        and the printed run includes a line naming the default-unset case (CD-11) among
        the passing ones.
    - id: A2
      surface: log_line
      observable: >
        A worker spawned with neither context-diet variable set writes nothing containing
        the words "context-diet" to its stream file, and the recorded command line for
        that spawn shows none of the three diet flags.
    - id: A3
      surface: log_line
      observable: >
        With the per-role allowlist enabled and the task's handoff directory made
        unwritable, the spawn still happens and stderr shows exactly one line beginning
        "[claude-subsession] WARN context-diet:" naming the role and saying the worker is
        spawning with the full MCP set — no bare "No such file or directory" text.
    - id: A4
      surface: file_artifact
      observable: >
        docs/context-diet.md sections 1 and 2 read "default 0 (opt-in)" and carry one
        sentence naming the 2026-08-23 live probe and its near-zero result as the reason;
        docs/phases.md's worker-context-diet paragraph says both variables default to off.
    - id: A5
      surface: log_line
      observable: >
        A worker spawned with the exclude-dynamic variable set to 2 shows no
        exclude-dynamic flag on its recorded command line, same as when it is set to 0.
    - id: A6
      surface: file_artifact
      observable: >
        The worktree has one new commit whose message names 9341e2eb, and the working
        tree is clean afterwards.
```

LANE_WRITES: plugins/leadv2/scripts/claude-subsession.sh, plugins/leadv2/scripts/tests/test-subsession-context-diet.sh, plugins/leadv2/docs/context-diet.md, plugins/leadv2/docs/phases.md

DELIVERABLE_COMPLETE
