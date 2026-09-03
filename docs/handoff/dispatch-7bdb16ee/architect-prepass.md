# HOOK-INJECT-DEDUP-01 — architect prepass (mechanism-closed design)

Repo: `~/Projects/leadv2` @ baa430c. Role: architect prepass. No code written.

---

## 0. Discovery contradicts the mission's framing — read this first

The mission says: "the UserPromptSubmit injectors (`leadv2-task-anchor.sh` **and the sibling
injectors that emit open-threads / scheduled-decisions blocks** — enumerate them from hooks.json
UserPromptSubmit entries)". Enumerated from the tree, **those sibling injectors do not exist.**

`plugins/leadv2/hooks/hooks.json` `UserPromptSubmit` has exactly 7 entries:

| # | hook | emits a repeating per-turn block? | already gated? |
|---|------|-----------------------------------|----------------|
| 1 | `leadv2-task-anchor.sh` | **YES — thread mode** | task mode YES, **thread mode NO** ← the whole gap |
| 2 | `leadv2-user-prompt-context.sh` | no | §2 body dead behind `LEADV2_ANCHOR_OWNS_CONTEXT=1` (default); remainder is one-shot (drains + `rm` a warn file, or fires only when prev-turn tools > 30) |
| 3 | `leadv2-pulse-enforcer.sh` | no | fires only when last turn exceeded a word limit AND `LEADV2_LEAD_GUARD=1` |
| 4 | `leadv2-broken-signal-gate.sh` | no | fires only on a matched broken signal |
| 5 | `leadv2-compact-warn.sh` | no | tiered + `FIRED_FILE` watermark + `REWARN=40` |
| 6 | `leadv2-idle-notification-filter.sh` | no | stderr-only suppressor, injects nothing |
| 7 | `leadv2-single-lead-beat.sh` | no | **already content-hash deduped** (`BODY_HASH_FILE`) + `DELIVERED_FILE` watermark, `leadv2-single-lead-beat.sh:145-168` |

Consequences for the deliverable list:

- **Deliverable 1 collapses to ONE injector, ONE code path.** The research's four buckets
  (open-threads 121K, scheduled-decisions 115K, BROAD_STATUS 109K, task-anchor 107K) are *content
  categories inside injections*, not four hooks. open-threads + scheduled-decisions + the
  `<task-anchor>` framing are all produced by `build_thread_anchor()` in **one** hook,
  `leadv2-task-anchor.sh:206-267`. A "per-injector state file" design keyed by injector name is
  over-built for a population of one; keep the key shape anyway (see §3) so a second injector is a
  one-line addition, but do not create a shared library for it.
- **Deliverable 3 (never dedup BROAD_STATUS) is already satisfied and must be re-read as a
  prohibition, not a task.** `leadv2-single-lead-beat.sh` *already* dedups BROAD_STATUS by body
  hash — the mission's premise "each beat is new" is false against the code: an unchanged
  founder-status body is *already* suppressed today (`leadv2-single-lead-beat.sh:150-160`). The
  correct implementation action is **do not touch that file at all**; the founder's intent
  ("BROAD_STATUS is the pulse") is preserved by the existing `AT`-watermark logic, which is finer
  than what we would add. Adding a second gate there would double-suppress a beat.
- `leadv2-task-anchor.sh` **task mode** (active task present) is *already* deduped once-per-session
  by `/tmp/.leadv2-task-anchor-full-<sid>-<task>` (`leadv2-task-anchor.sh:570-587`). Do not
  re-gate it. It does, however, carry a live defect this task should close — see §4 R2.

**Net: the implementation is a ~40-line change inside one function of one file, plus one line in a
PreCompact hook, plus a test file.** Anyone planning a multi-hook sweep is planning against the
mission text, not against the tree.

---

## 1. CALLERS / CALLEES

### The function that changes

`build_thread_anchor(root, leadv2_dir, session_id="")` — `plugins/leadv2/hooks/leadv2-task-anchor.sh:206`
(inside the embedded `python3` heredoc, `PYEOF` block spanning lines 59-758).

**Callers — exactly one, and it is the only reachable one:**

- `main()` at `leadv2-task-anchor.sh:559`:
  ```
  557    if not task_id:
  558        safe_capture(root, leadv2_dir, payload)
  559        thread_out = build_thread_anchor(root, leadv2_dir, payload.get("session_id"))
  560        if thread_out:
  561            print(thread_out)
  562        return
  ```
  Reached **only** when no active task resolved (neither `active.yaml` live-session match at
  `:490-528` nor recent-`STATE.md` fallback at `:530-556`). This is the "NO ACTIVE TASK — thread
  anchor" path; it is the path that fired for the session in the token-burn research.

  `print()` goes to the hook's stdout, captured into `$OUT` at `:59`, re-emitted verbatim at
  `:761` (`[[ -n "$OUT" ]] && printf -- '%s\n' "$OUT"`), `exit 0` at `:762`. Plain-text stdout on
  UserPromptSubmit is appended as context by the harness — this hook does **not** use the
  `hookSpecificOutput.additionalContext` JSON shape (unlike hooks 2,3,4,7). Keep it plain text.

**Callees of `build_thread_anchor` — all four, with what they cost us:**

| callee | file:line | role in the hash |
|---|---|---|
| `read_last_nonblank_lines(ot_path, THREAD_SCAN_MAX)` | `:173` | reads whole `docs/leadv2/open-threads.md`, returns last 2000 non-blank lines |
| `_filter_by_session(tail, session_id)` | `:287` | drops entries tagged `[s:<sid8>]` for other sessions; returns `(kept, hidden_count)`. **hidden_count is part of the rendered body** → must be inside the hash |
| `tail[-8:]` (inline, `:252`) | `:252` | the 8 visible lines |
| `nearest_due_line(root)` | `:182` | shells out to `<root>/.claude/hooks/scheduled-decisions-nearest.sh` (**project-local, lives in persona-engine, NOT in leadv2** — verified: `ls ~/Projects/leadv2/.claude/hooks/scheduled-decisions-nearest.sh` → absent; `~/Projects/persona-engine/.claude/hooks/scheduled-decisions-nearest.sh` → present, mode 755, 5002 bytes). Returns one line or `None`. 2s timeout, any failure → `None`. |

### Independent copies nobody named (the usual miss — checked)

- `_filter_by_session` / `_ENTRY_RE` are **duplicated verbatim** in
  `plugins/leadv2/hooks/pre-compact-task-freeze.sh` (the source comment at `:695-697` says so
  explicitly: "Both hooks carry this helper verbatim … keep the text identical so a diff between
  them makes drift visible"). **We are not editing that helper**, so no drift is introduced. If an
  implementer touches it, they must touch both.
- `leadv2-auto-status.sh` (PostToolUse, `.*`) also greps open-threads/scheduled-decisions. It is
  **out of scope**: PostToolUse, not UserPromptSubmit, and a different emission contract. Named
  here so it is not "discovered" in review as a missed sibling.
- `leadv2-merged-worktree-sweep.sh`, `leadv2-pending-questions-inject.sh` (SessionStart) also
  reference these files. SessionStart fires once per session — nothing to dedup. Out of scope.
- The worktree copies under `.claude/worktrees/*/plugins/leadv2/hooks/hooks.json` are per-lane
  checkouts of the same tracked file, not independent hooks. Ignore.

### New callee introduced

`_inject_dedup_gate(kind, session_id, body)` — new module-level function in the same heredoc,
called once, from `build_thread_anchor` (or from `main()` immediately around line 559-561 — see
§3 for why inside `build_thread_anchor` is wrong and the call belongs in `main()`).

---

## 2. STATES AND RETURN CODES

`build_thread_anchor` returns `str | None`; the *hook process* always `exit 0`. The user-visible
consequence is what a founder sees at the top of their next turn.

### 2a. Current states (before the change)

| # | state | returns | `main()` does | founder sees |
|---|---|---|---|---|
| S1 | neither open-threads.md nor scheduled-decisions.md exists | `None` | prints nothing | no anchor block at all |
| S2 | open-threads.md exists, all lines filtered out, no due line | header+footer only (~22 lines) | prints | a `<task-anchor>` with the DIRECTIVE and no content |
| S3 | normal: 1-8 thread lines (+hidden count) (+due line) | ~24-33 lines | prints | full thread anchor |
| S4 | content overflows the 40-line cap (`budget` at `:262`) | truncated to `budget` | prints | truncated anchor, no marker that it was truncated |
| S5 | any exception anywhere in `main()` | — | `except: pass` at `:757` → `$OUT` empty → nothing printed | no anchor (fail-open, silent) |

S2/S3/S4 are re-emitted **identically on every founder prompt**. That is the burn.

### 2b. States after the change (the gate)

Gate outcome vocabulary — this is what the implementer must make total:

| # | gate state | condition | emitted | founder-visible consequence |
|---|---|---|---|---|
| G0 | disabled | `LEADV2_INJECT_DEDUP=0` | full block, no state read/write | exactly today's behaviour |
| G1 | no session id | `payload.session_id` missing/empty after sanitisation | full block, no state write | exactly today's behaviour (cannot key state) — matches the existing precedent at `:572` and at `leadv2-single-lead-beat.sh:90-98` |
| G2 | first fire this session | hash file absent | full block; hash written | founder gets the whole thread anchor once |
| G3 | unchanged | stored hash == computed hash | **one line**: `<task-anchor>thread anchor unchanged — docs/leadv2/open-threads.md; the block above still governs.</task-anchor>` ; hash **not** rewritten (already equal) | founder still sees the anchor pointer every turn; the 25-line body is not re-paid |
| G4 | changed (bytes) | hashes differ | full block; hash overwritten | full re-inject |
| G5 | changed (date flip only) | body bytes identical, UTC date component differs | full block; hash overwritten | **the urgency exception**: a row that became DUE/OVERDUE purely by the clock re-injects |
| G6 | state dir unwritable / read fails / hash lib fails | any `OSError`/exception inside the gate | full block (fail-open), no state | exactly today's behaviour; never silence |
| G7 | post-compact | PreCompact cleared the hash file | → collapses to G2 on the next prompt | the founder's first post-compact turn re-grounds with the full anchor |

**Terminal-outcome trace, in plain words.** There is no retry loop and no abort gate downstream of
this hook — the hook's stdout is appended to the prompt and the turn proceeds either way. So the
only bad terminal outcome is **G3 firing when the founder actually needed the body**: the lead
begins a turn with no open-threads content in the live window and no way to recover it except by
reading `docs/leadv2/open-threads.md` itself. Two situations produce that, and both are closed
here: G7 (compaction drops the earlier full block — closed by the PreCompact clear, §4 R2) and a
stale hash file surviving a session-id reuse (closed by the 7-day GC, §3.4). A third — the founder
scrolled past it — is not a mechanism problem: the marker names the file path, which is the whole
reason task-anchor gets a marker line rather than silence.

`nearest_due_line` sub-process return codes, traced (this is the one place an rc crosses a process
boundary):

| renderer rc / condition | `nearest_due_line` returns | anchor content | consequence |
|---|---|---|---|
| renderer file absent or not executable (**true in the leadv2 repo itself**) | `None` (`:192-193`) | no due line | the due line simply never appears when leadv2 is the cwd repo; the dedup gate still works on the open-threads part alone |
| rc != 0 | `None` (`:200-201`) | no due line | a renderer that starts failing looks byte-identical to "nothing due" → G3 suppresses. Acceptable: the failure is already invisible today; we do not make it worse, and the date component still forces a daily re-inject |
| rc == 0, empty stdout ("already surfaced this session" — the renderer has its own dedup) | `None` (`:202-203`) | no due line | **note the interaction**: the renderer already suppresses per-session, so the due line is naturally present on fire #1 and absent on fire #2 → that is a *byte change* → G4 → a full re-inject on turn 2 even with our gate. See §4 R1; this is the single most likely "the gate didn't work" report |
| rc == 0, one line | the line | due line rendered | normal |
| timeout > 2s / OSError | `None` (`:198-199`) | no due line | same as rc != 0 |

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at every boundary. "Behaviour" is what the implementation must
guarantee; where today's code already guarantees it, that is stated.

### 3.1 `LEADV2_INJECT_DEDUP` (new env var)

| boundary | value | behaviour |
|---|---|---|
| absent | — | **ON** (dedup active). Mission deliverable 4. |
| empty string | `""` | ON. Treat only the exact string `0` as off — mirrors `LEADV2_TASK_ANCHOR_COMPACT_REPEAT` at `:572` (`!= "0"`) and `LEADV2_SINGLE_LEAD_BEAT` at `leadv2-single-lead-beat.sh:32` (`== "0"`). |
| `0` | off | G0: today's behaviour exactly, no state file created. |
| `1`, `true`, `yes`, garbage | — | ON. Do **not** add a parser; anything-but-`0` is ON. A stricter parser would make a typo (`LEADV2_INJECT_DEDUP=O`) silently disable the feature. |
| over-cap / malformed | n/a | not numeric, no cap surface. |

Naming check (mandatory checklist item 1): `LEADV2_` prefix, matches every sibling
(`LEADV2_COMPACT_WARN`, `LEADV2_BROKEN_GATE`, `LEADV2_IDLE_FILTER`, `LEADV2_SINGLE_LEAD_BEAT`).
No `LEAD_V2_*` variant exists in the tree. Grep for prior `LEADV2_INJECT_DEDUP` usage: **none** —
it is new, so no semantic contradiction is possible (checklist item 5 clears).

### 3.2 `LEADV2_TASK_ANCHOR_STATE_DIR` (new, test-only override)

| boundary | behaviour |
|---|---|
| absent | `$HOME/.claude/state/leadv2` — the established location (`leadv2-turncap-checkpoint-hook.sh:44`, `leadv2-single-lead-beat.sh` `STATE_DIR`) |
| set to a path | use it verbatim; `mkdir -p` best-effort |
| set to an unwritable path | G6 fail-open |
| set to a path containing spaces/quotes | must be quoted at every use; the value never reaches a shell (it is used from Python inside the heredoc), so no injection surface |

Rationale: the tests must not write to the founder's real state dir. `LEADV2_TURNCAP_STATE_DIR`
is the precedent for exactly this.

### 3.3 `session_id` (from the hook payload)

| boundary | behaviour |
|---|---|
| absent / `null` | G1 — full inject every turn, no state. Never crash. |
| empty after `re.sub(r"[^A-Za-z0-9._-]", "", …)` | G1 |
| normal UUID | key = the sanitised id (the existing code at `:570` and `:291` already sanitises; **reuse the same sanitisation**, do not write a second one) |
| adversarial (`../../etc/passwd`, 4KB long) | the existing sanitiser strips `/` and `.` survives — `..` is possible. **Therefore truncate to 64 chars AND reject a key that is all-dots.** The `/tmp` marker at `:574` has this same latent surface; do not copy it blindly. Concretely: `key = sanitised[:64]`; `if not key.strip("."): → G1`. |

### 3.4 The state file `<STATE_DIR>/.inject-hash.<sid>.thread-anchor`

| boundary | behaviour |
|---|---|
| dir absent | `os.makedirs(..., exist_ok=True)`; on failure → G6 |
| dir unwritable | G6 fail-open (**mission deliverable 5's fail-open test**) |
| file absent | G2 |
| file empty (0 bytes) | treat as "no stored hash" → G2. Never compare `"" == hash`. |
| file malformed (binary, 10MB, not hex) | it will simply not equal the computed hex digest → G4 full inject. **Bound the read: `f.read(256)`** so a pathological file cannot pull megabytes into the hook. |
| file is a directory / symlink to one | `OSError` → G6 |
| concurrent writers (two prompts racing, or the same session in two worktrees) | write via `<file>.tmp.<pid>` + `os.replace()` — atomic rename, the exact pattern at `leadv2-single-lead-beat.sh:160-166`. Worst case under a race: one extra full inject. Never a partial hash. |
| **population growth** | `~/.claude/state/leadv2` **already holds 11,505 files** (`ls … \| wc -l` → 11505, all `*.lead-streak`). Adding one file per session with no sweep makes this worse. **Required:** a once-per-day GC stamp (`.inject-gc-day`) driving `find <STATE_DIR> -maxdepth 1 -name '.inject-hash.*' -mtime +7 -delete`, copied from `leadv2-single-lead-beat.sh:99-112`. Note the existing sweep there covers only `.pulse-*` names — it will **not** clean ours. |

The over-cap rule from the mission ("an over-cap input that takes down more than the one operation
it belongs to is a defect") binds here: a huge or corrupt hash file must degrade to G4/G6 for this
one injection and never raise past `main()`'s `except: pass`.

### 3.5 `docs/leadv2/open-threads.md`

| boundary | behaviour (already true today; the gate must not change it) |
|---|---|
| absent | `has_ot=False`; if scheduled-decisions.md also absent → S1, gate never runs |
| empty (0 bytes) | `read_last_nonblank_lines` → `[]` → no "open threads" section; hashable body may be empty → **an empty body must still be hashed and gated**, otherwise S2 re-injects a bare 22-line DIRECTIVE forever |
| 1 line | normal |
| > 2000 non-blank lines | bounded by `THREAD_SCAN_MAX=2000` (`:283`); the visible block is capped at 8 (`:252`) |
| malformed / non-UTF8 | `read_last_nonblank_lines` catches and returns `[]` (`:178-179`) |
| pathologically large (100MB) | `THREAD_SCAN_MAX` bounds the *return*, not the *read* — the file is fully iterated at `:176`. Pre-existing; **out of scope**, flagged in §5 |

### 3.6 `docs/leadv2/scheduled-decisions.md` + the renderer

| boundary | behaviour |
|---|---|
| file absent | `has_sd=False` → no due line |
| present but renderer absent (**the leadv2 repo's own case**) | no due line, silently |
| renderer present, row newly DUE by clock only | **byte-identical output is possible** → the date component in the hash key is what forces re-injection (G5). This is the mission's urgency exception and it is why the date is in the key, not decoration. |
| renderer slow (>2s) | timeout → `None`; the gate sees a body without a due line → likely G4 one extra full inject, then steady state |

**Explicit design constraint the implementer must not violate:** the DUE/OVERDUE *classification*
is computed by `.claude/hooks/scheduled-decisions-nearest.sh`, which lives in **persona-engine, not
in this repo** (mission constraint: "never edit outside ~/Projects/leadv2"). We therefore **cannot**
key the hash on a classification we compute ourselves. The design substitutes the coarser but
sufficient key: `today's UTC date`. A date flip re-injects unconditionally; a same-day
classification change necessarily changed the renderer's bytes and is caught by G4. Do not attempt
to parse DUE/OVERDUE out of the renderer's line — that couples this repo to another repo's output
grammar, which is exactly what `LEDGER-NEAREST-DUE-01` (comment at `:183-190`) moved away from.

### 3.7 UTC date component

| boundary | behaviour |
|---|---|
| normal | `datetime.now(timezone.utc).strftime("%Y-%m-%d")` |
| clock skew backwards | date differs → one extra full inject. Harmless. |
| TZ env garbage | UTC is explicit; `TZ` cannot affect it |
| midnight crossing mid-session | intended G5 re-inject |

---

## 4. COUNTEREXAMPLE

*After every finding in this mission is fixed, what can still violate the invariant this mechanism
exists to protect?* The invariant is: **the lead always has the current open-threads / nearest-due
state in its live context when it answers a founder prompt.** Two things still violate it, and both
must be in the implementation or the invariant is not closed.

**R1 — the renderer's own per-session dedup makes turn 2 a byte change.**
`nearest_due_line` returns a line on the first call of a session and (per the renderer's documented
"or nothing if already surfaced this session" behaviour, `:188-189`) nothing afterwards. So body(turn 1)
≠ body(turn 2) *by construction*, and the gate produces a full inject on turn 2 before reaching steady
state from turn 3. This is not a bug — it is correct, the body genuinely changed — but it will be
reported as "the dedup doesn't work on the second turn". Mitigation: none needed in code; the test
for "unchanged content → marker on 2nd fire" must therefore control the due line (renderer absent,
which is the natural state in this repo) so it tests the gate rather than the renderer.

**R2 — compaction, and this is a real hole the mission does not mention.**
`/compact` discards the earlier turns, including the one full anchor. The session id is **unchanged**
across compaction, so the hash file survives, so the very next prompt hits G3 and the lead gets only
`[thread anchor unchanged]` with the body gone from its window. The founder's open threads silently
vanish for the rest of the session. The identical latent defect exists **today** in task mode: the
`/tmp/.leadv2-task-anchor-full-<sid>-<task>` marker at `:574` is never deleted by anything (verified:
`grep -rn "leadv2-task-anchor-full" plugins/leadv2/` → only the writer at `:574` and a test at
`test-hook-token-mode-isolation.sh:22`), and its source comment at `:576-577` — "post-compact
regrounding remains owned by the dedicated compact hooks" — asserts a delegation that no compact hook
actually performs. **Closure:** `leadv2-pre-compact-checkpoint.sh` (already registered on `PreCompact`)
must best-effort remove, for the compacting session id, both `<STATE_DIR>/.inject-hash.<sid>.*` and
`/tmp/.leadv2-task-anchor-full-<sid>-*`. One `rm -f` line, `|| true`, must never affect that hook's
exit code. Without this, the feature trades a token win for a correctness regression that only shows
up in exactly the long marathon sessions the feature exists to help.

Beyond R1 and R2 I could not construct a third violation. What I checked and found clean: the
`hidden` count line is inside the hashed body, so a foreign-session thread arriving does not silently
change the rendered text without changing the hash; the 40-line truncation happens *before* hashing
in the design (§3 requires hashing the **rendered body**, not the pre-truncation content) so two
different overflowing states that truncate to the same visible text correctly dedup to the same
thing; `safe_capture` runs on the same path and is untouched, so auto-capture of new founder asks
still happens on marker turns; every other UserPromptSubmit injector was enumerated in §0 and none
carries an ungated repeating block. I did not verify the harness's exact treatment of a hook that
prints one line vs many — that is uniform stdout append, and both shapes already occur in this hook
today (`:576-583` prints a 4-line block).

---

## 5. Out of scope — for the implementing agent to ignore

- **`leadv2-single-lead-beat.sh` — do not open the file.** BROAD_STATUS is excluded per deliverable
  3 and is already hash-deduped independently.
- `leadv2-user-prompt-context.sh`, `leadv2-pulse-enforcer.sh`, `leadv2-broken-signal-gate.sh`,
  `leadv2-compact-warn.sh`, `leadv2-idle-notification-filter.sh` — no repeating block; no change.
- `leadv2-auto-status.sh` (PostToolUse) and the SessionStart injectors — different event, out of
  scope.
- `_filter_by_session` / `_ENTRY_RE` and their verbatim twin in `pre-compact-task-freeze.sh` — not
  edited; do not "fix the duplication".
- The unbounded full-file read in `read_last_nonblank_lines` (§3.5) — pre-existing, not this task.
- The `~/.claude/state/leadv2` backlog of 11,505 `.lead-streak` files — our GC must not widen its
  glob to sweep another feature's files.
- No new shared library, no new hook file, no `hooks.json` change (the gate lives inside an
  already-registered hook).

## 6. Implementation shape (not code — the contract the implementer must hit)

1. In `leadv2-task-anchor.sh`, inside the `PYEOF` heredoc, add one module-level helper that takes
   `(kind, session_id, body)` and returns `("full"|"marker")`, wrapped so that **every** failure
   path returns `"full"`.
2. Call it in `main()` at the `if not task_id:` branch (`:557-562`), **after** `build_thread_anchor`
   has produced the final rendered string and **after** `safe_capture` — so capture is never gated,
   and so the hashed value is exactly the bytes that would have been printed.
   Do *not* put the gate inside `build_thread_anchor`; that function has no business knowing about
   session state and is the shape a future second caller would want unchanged.
3. Hash input: `sha256(body + "\n" + utc_date)`, hexdigest. `hashlib` only, stdlib.
4. On `"marker"`, print the single line described in G3 and return.
5. Add the `PreCompact` clear (§4 R2) to `leadv2-pre-compact-checkpoint.sh`.
6. Add the once-per-day GC (§3.4).
7. `bash -n` on both edited hooks; `python3 -c "compile(...)"` is not directly available for the
   heredoc — instead exercise it through the tests, which invoke the hook end-to-end with a crafted
   stdin payload (the pattern in `test-hook-token-mode-isolation.sh`).
8. New test file `plugins/leadv2/scripts/tests/test-inject-dedup.sh` covering G2→G3 (unchanged →
   marker on 2nd fire), G4 (changed → full), G5 (date flip → full; inject the date via a test hook
   or by writing a hash file whose date component is yesterday), G0 (`LEADV2_INJECT_DEDUP=0` →
   full both times), G6 (`LEADV2_TASK_ANCHOR_STATE_DIR` pointed at a `chmod 000` dir → full both
   times, exit 0), G1 (payload with no `session_id` → full both times), and R2 (hash file removed →
   full again). All under a temp `LEADV2_TASK_ANCHOR_STATE_DIR` and a temp git root; never the
   founder's real state dir.
9. Register the test in `plugins/leadv2/scripts/tests/run-core-offline.sh` (row format:
   `"per-turn injection dedup (HOOK-INJECT-DEDUP-01)|||bash $TEST_DIR/test-inject-dedup.sh"`).
10. Docs: a paragraph in `plugins/leadv2/docs/context-diet.md` (the existing home for context-cost
    mechanics) — what is gated, what is deliberately not (BROAD_STATUS, task-mode which is gated
    elsewhere), the kill-switch, and the post-compact clear.

## 7. Mandatory constraint checklist

1. **Env var naming** — `LEADV2_INJECT_DEDUP`, `LEADV2_TASK_ANCHOR_STATE_DIR`: `LEADV2_` prefix,
   consistent with every sibling. No `LEAD_V2_*` drift in the tree. **PASS**
2. **File paths** — all verified present: `plugins/leadv2/hooks/leadv2-task-anchor.sh`,
   `plugins/leadv2/hooks/leadv2-pre-compact-checkpoint.sh`,
   `plugins/leadv2/hooks/hooks.json`, `plugins/leadv2/scripts/tests/run-core-offline.sh`,
   `plugins/leadv2/docs/context-diet.md`. To-create: `plugins/leadv2/scripts/tests/test-inject-dedup.sh`
   *(to-create)*. Confirmed **absent** in this repo (by design, not an error):
   `.claude/hooks/scheduled-decisions-nearest.sh`. **PASS**
3. **`claude -p` commands** — the design introduces none. **N/A**
4. **Concurrent access** — the hash file is read+written by every prompt of a session, and the same
   session id can fire from two worktrees. Race surface named in §3.4; resolution is
   tmp-file + `os.replace()` (atomic), degrading to at most one redundant full inject. No lock
   needed — a lock here would add a blocking dependency to a hook that must never block a founder
   prompt. **PASS**
5. **Config contradiction** — `grep` for `LEADV2_INJECT_DEDUP` in the tree: no prior usage, no
   contradictory semantics. `LEADV2_TASK_ANCHOR_COMPACT_REPEAT` (existing, `:572`) governs a
   *different* gate (task mode); the two must remain independent and the new flag must not be read
   in the task-mode branch. **PASS, with that non-interference stated as a requirement.**

## 8. Risks

| # | risk | mitigation |
|---|---|---|
| 1 | Post-compact silence (§4 R2) | PreCompact clear — **mandatory, not optional** |
| 2 | Implementer widens scope to "all UserPromptSubmit injectors" per the mission text | §0 + §5: the population is one; touching `single-lead-beat` double-suppresses the founder's pulse |
| 3 | Marker so terse the lead ignores it | Marker names the file path so the lead can recover the body with one bounded Read |
| 4 | State-dir file growth on a dir already at 11.5k files | daily-stamped `-mtime +7` sweep scoped to `.inject-hash.*` only |
| 5 | Renderer-driven turn-2 re-inject read as a failure (§4 R1) | test controls the due line; documented in §4 |
| 6 | `session_id` path traversal via surviving dots | truncate to 64, reject all-dot keys (§3.3) |
| 7 | A future second injector copy-pastes the gate | `(kind, …)` key shape is already generic; the file name carries `.thread-anchor` as the kind |

acceptance:
  - surface: rendered_line
    observable: "On the founder's second and later prompts in the same session, the block at the top of the turn is the single line reading `thread anchor unchanged — docs/leadv2/open-threads.md; the block above still governs.` instead of the twenty-odd lines of open threads and DIRECTIVE text that appeared on the first prompt."
    authored_at: 2026-08-23T22:17:29Z
  - surface: rendered_line
    observable: "After a line is added to docs/leadv2/open-threads.md, the very next founder prompt shows the full thread-anchor block again, with the new line visible in it."
    authored_at: 2026-08-23T22:17:29Z
  - surface: rendered_line
    observable: "On the first founder prompt after midnight UTC in a session that has been running since the previous day, the full thread-anchor block reappears even though nobody edited open-threads.md or scheduled-decisions.md."
    authored_at: 2026-08-23T22:17:29Z
  - surface: rendered_line
    observable: "On the first founder prompt after a /compact, the full thread-anchor block is present again rather than the unchanged-marker line."
    authored_at: 2026-08-23T22:17:29Z
  - surface: rendered_line
    observable: "With LEADV2_INJECT_DEDUP=0 set for the session, every founder prompt shows the full thread-anchor block, exactly as before this change."
    authored_at: 2026-08-23T22:17:29Z
  - surface: file_artifact
    observable: "A file named .inject-hash.<session-id>.thread-anchor appears in ~/.claude/state/leadv2/ after the first prompt of a session, containing a single 64-character hex string, and no such file remains for sessions older than seven days."
    authored_at: 2026-08-23T22:17:29Z

LANE_WRITES: plugins/leadv2/hooks/leadv2-task-anchor.sh, plugins/leadv2/hooks/leadv2-pre-compact-checkpoint.sh, plugins/leadv2/scripts/tests/test-inject-dedup.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/docs/context-diet.md

DELIVERABLE_COMPLETE
