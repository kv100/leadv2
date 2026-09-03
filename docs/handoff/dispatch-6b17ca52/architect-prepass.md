# HOOK-INJECT-DEDUP-01 — fix round 1: mechanism-closed implementation design

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/7bdb16ee` @ `ea27378`
(branch `worktree-7bdb16ee`). All paths below are repo-relative inside that worktree.

Design only — no implementation performed.

---

## 0. Where the mission's framing and the code diverge

Three points where discovery contradicts the mission text. Design follows the code.

**0.1 — "Keep it cheap (grep+date math, no python startup if the file is absent)."**
There is no python *startup* to avoid. The entire gate already runs inside a single
`python3` heredoc opened at `plugins/leadv2/hooks/leadv2-task-anchor.sh:59` and closed at
`:831`. `_inject_dedup_gate()` (`:279`) is a function in that one interpreter. A shell
`grep`/`date` implementation would ADD a process, not remove one. The classification is
therefore designed as a pure-python helper called from inside the existing interpreter;
"cheap when the file is absent" reduces to one `os.path.exists()` and an early return.

**0.2 — Finding 5 ("add a single stderr WARN line") is a no-op as literally written.**
Line 59 is `OUT="$(python3 - "$TMPFILE" "$STATE_RESOLVER" <<'PYEOF' 2>/dev/null`. Every
byte the python block writes to stderr is discarded. Writing `[inject-dedup] fail-open:`
to `sys.stderr` without touching line 59 produces exactly the silence finding 5 exists to
end. The redirect must be removed as part of finding 5, or the finding is decorative in
the same way finding 1 says the urgency exception is. Safety analysis for removing it is
in §3.5 — it is safe because `main()` is already wrapped in
`try: main() except Exception: pass` (`:825-828`) and every `subprocess.run` in the block
(`:64`, `:148-153`, `:195-197`) uses `capture_output=True`, so no child stderr and no
traceback can reach fd 2 during normal operation.

**0.3 — Finding 1's premise is confirmed, but the fix as scoped does not deliver the
outcome the finding describes.** Confirmed by reading
`~/Projects/persona-engine/.claude/hooks/scheduled-decisions-nearest.sh:135-148`: the
renderer compares `nearest_id` against a per-session state file and `exit 0`s on a match,
classification-blind. So on a DUE TODAY → OVERDUE flip of the SAME row id, the renderer
prints nothing. Mixing `id:status` into the digest correctly forces a full re-inject —
but the body that gets re-injected **still contains no scheduled-decisions line at all**,
because the renderer was silent. The founder gets the open-threads block and the
DIRECTIVE re-grounded; they do not get the word OVERDUE. See §4 (counterexample) and §6
(non-goals) — I am designing exactly what the mission scoped and flagging the residual,
not silently widening it.

---

## 1. CALLERS / CALLEES

### 1.1 Functions this change touches

| Symbol | Defined | Called from | Calls |
|---|---|---|---|
| `_inject_dedup_gate(kind, session_id, body)` | `hooks/leadv2-task-anchor.sh:279` | **one** site: `:625` (thread-anchor branch, `if not task_id:`) | `os.makedirs`, `hashlib.sha256`, `glob.glob`, `os.replace`; **NEW** → `_nearest_decision_signature()` |
| `_nearest_decision_signature(root, leadv2_dir)` | **(to-create)**, beside `_inject_dedup_gate` | **one** site: inside `_inject_dedup_gate` | `os.path.exists`, `os.path.getsize`, `open().read()`, `re`, `datetime` |
| `build_thread_anchor(root, leadv2_dir, session_id)` | `:206` | **one** site: `:623` | `read_last_nonblank_lines` `:173`, `_filter_by_session` `:351`, `nearest_due_line` `:182` |
| `nearest_due_line(root)` | `:182` | **one** site: `:256` | `subprocess.run([<root>/.claude/hooks/scheduled-decisions-nearest.sh])`, `timeout=2` |
| `main()` | `:~520` | `:826` | all of the above; prints to stdout, which bash captures into `$OUT` and re-prints at `:832` |

`_inject_dedup_gate` and `build_thread_anchor` each have exactly one caller. There is no
second copy of the gate in the plugin (`grep -rn "_inject_dedup_gate" plugins/` → two
hits, definition + call).

### 1.2 The independent copy nobody named — checked, and it is a *different* mechanism

`grep -rn "task-anchor-full" . --exclude-dir=.git` over the whole worktree:

```
plugins/leadv2/docs/context-diet.md:21          (prose)
plugins/leadv2/docs/context-diet.md:37          (prose)
plugins/leadv2/hooks/leadv2-task-anchor.sh:645  PRODUCER
plugins/leadv2/hooks/leadv2-pre-compact-checkpoint.sh:27  CONSUMER (rm -f)
plugins/leadv2/scripts/tests/test-inject-dedup.sh — no hit (this is finding 3's gap)
plugins/leadv2/scripts/tests/test-hook-token-mode-isolation.sh:22  existing coverage
```

This matters for finding 3. `/tmp/.leadv2-task-anchor-full-<sid>-<task>` is produced at
`:645` and written at `:814-820` on the **task-mode** path (`task_id` truthy), which is the
`return` at `:633`'s mutually exclusive sibling. It is NOT the thread-anchor hash file.
The two are unrelated gates that PreCompact happens to clear in the same `if` block
(`hooks/leadv2-pre-compact-checkpoint.sh:24-28`). A test in `test-inject-dedup.sh` that
asserts the glob is cleared must therefore **create the marker file itself** — the
thread-anchor fixture in that test never produces one, because `run_anchor()` builds a repo
with no `active.yaml` and no `tasks/*/STATE.md`, so `task_id` is always empty and `:645`
is never reached. A naive `[[ ! -f <glob> ]]` assertion would pass vacuously. This is the
single most likely way finding 3 gets "fixed" without testing anything.

Cross-repo: `scheduled-decisions-nearest.sh` lives only in persona-engine
(`~/Projects/persona-engine/.claude/hooks/`). The plugin tree has no copy — confirmed
`find . -name 'scheduled-decisions-nearest*'` in the worktree returns nothing. Read-only
reference; **out of scope, do not edit** (mission constraint, and it is another repo).

---

## 2. STATES AND RETURN CODES

### 2.1 `_inject_dedup_gate()` — returns the string `"full"` or `"marker"`

| State | Condition | rc | What the caller (`:626-632`) does | User-visible consequence |
|---|---|---|---|---|
| G0 | `LEADV2_INJECT_DEDUP=0` | `full` | `print(thread_out)` | Founder sees the whole thread anchor, every prompt. Kill-switch works. |
| G1 | session id empty / non-alnum-only | `full` | `print(thread_out)` | Same. Gate cannot key state, so it never suppresses. |
| G2 | no stored digest (first prompt this session) | `full` | `print(thread_out)` | Full block; digest written. |
| G3 | `stored == digest` | `marker` | prints the one-line `thread anchor unchanged …` | Founder sees one line instead of ~30. Intended saving. |
| G4 | body changed (open-threads edited) | `full` | `print(thread_out)` | Full re-inject. |
| G5 | UTC date rolled over | `full` | `print(thread_out)` | Full re-inject on the first prompt of a new day. |
| **G5b (NEW)** | `id:status` of the nearest scheduled decision changed | `full` | `print(thread_out)` | Full re-inject. **Note:** the re-injected body may not itself mention the decision — see §4. |
| G6 | any exception (unwritable state dir, corrupt state, oversize/unreadable ledger) | `full` | `print(thread_out)` | Full block + **NEW** one `[inject-dedup] fail-open: <err>` line on the hook's stderr. Hook still `exit 0`. |

Terminal tracing: there is no retry loop and no abort gate downstream. `main()` returns at
`:633`; bash prints `$OUT` at `:832` and `exit 0` at `:833`. **Every** rc terminates in
"text appears (or does not appear) above the founder's prompt." No rc can fail the prompt
submit — `set -euo pipefail` is neutralised for this path by `trap 'exit 0' ERR` (`:43`,
`:49`) and by `|| exit 0` on `:831`.

The one rc with a genuinely bad terminal outcome is **G3 reached when it should have been
G5b**: the founder's prompt carries a one-line marker, the OVERDUE decision is never
surfaced, and because the renderer's own state file also still holds that id, it will not
be surfaced on any later prompt of the session either. In plain words: *a decision that
went overdue today is not mentioned again for the rest of the session.* That is the defect
this change exists to close.

### 2.2 `_nearest_decision_signature()` — returns a short string, never raises

| State | Return | Effect on digest |
|---|---|---|
| ledger file absent | `""` | digest = `sha256(body + "\n" + today + "\n" + "")` — behaviourally identical to today |
| ledger present, no actionable row | `"none"` | stable; flips to `id:STATUS` when the first actionable row appears |
| ledger present, winner found | `"<row_id>:<STATUS>"` e.g. `SD-0412:OVERDUE` | flips on classification change ⇒ G5b |
| ledger over cap | `"oversize"` | stable constant; gate degrades to body+today, prompt still submits |
| read/parse error | `""` + one WARN line | fails open into today's behaviour |

`STATUS` ∈ `{OVERDUE, DUE_TODAY, CONDITION_BOUND}` — underscored so the token never
collides with the `:`/space-delimited signature format.

### 2.3 Hook process exit codes (unchanged by this work)

`leadv2-task-anchor.sh` exits `0` on every path: `:47` (`|| exit 0`), `:50`, `:831`, `:833`,
plus `trap 'exit 0' ERR`. Claude Code's `UserPromptSubmit` contract: stdout is prepended to
the founder's prompt as context; stderr on exit 0 is **not** injected into context (it goes
to the transcript/debug channel). This is why finding 5's WARN costs zero context tokens —
and also why it is invisible today behind `2>/dev/null`.

---

## 3. CONFIGURATION BOUNDARIES

### 3.1 `docs/leadv2/scheduled-decisions.md` (NEW input to the gate)

Resolved as `os.path.join(root, leadv2_dir, "scheduled-decisions.md")` — the same
expression already used at `:208`. Do **not** hardcode `docs/leadv2`; `leadv2_dir` comes
from `state-paths.yaml` and is already threaded into `build_thread_anchor`.

| Boundary | Observed / designed behaviour |
|---|---|
| **Absent** | `os.path.exists()` False → return `""` immediately. Zero read, zero regex. In this very worktree the file does not exist (`ls docs/leadv2/scheduled-decisions.md` → No such file), so this is the *default* path for the plugin repo itself — the tests must not assume otherwise. |
| **Empty (0 bytes)** | read → no `## ` headings → no candidates → `"none"`. |
| **Minimum** (one row, one `**Due**` field) | parsed; `"<id>:<STATUS>"`. |
| **Maximum / over-cap** | Live size in persona-engine is **307,743 bytes** (`ls -la ~/Projects/persona-engine/docs/leadv2/scheduled-decisions.md`). That is read + regex-scanned on **every founder prompt**. Cap at `LEADV2_SD_SCAN_MAX_BYTES` (default `8388608` = 8 MiB, ~27× current). Over cap → `"oversize"`, no read. Rationale: an unbounded read of a ledger that only grows means a pathological ledger stalls *every prompt in every session*, which is far more than the one operation it belongs to. |
| **Malformed date** (`2026-13-45`) | `datetime.date.fromisoformat` raises `ValueError` → that row is skipped (`due_date = None` ⇒ `status = None` ⇒ not a candidate). Identical to the sibling renderer's behaviour at its lines 87-89, so the two cannot disagree on a malformed row. |
| **Malformed structure** (heading with no `—`, unclosed table) | `re.match` at heading fails → section skipped. No raise. |
| **Non-UTF-8 bytes** | `open(..., encoding="utf-8")` raises `UnicodeDecodeError` → caught → `""` + WARN. Design note: pass `errors="replace"` instead, so one bad byte does not disable the whole mechanism. Recommended: `errors="replace"`. |
| **Unreadable (perm 000)** | `PermissionError` → `""` + WARN. Prompt unaffected. |
| **Concurrently rewritten mid-read** | Single `read()`; a torn read yields a different signature for one prompt ⇒ one spurious full re-inject. Benign (fails toward showing more, never less). No lock needed. |

### 3.2 `LEADV2_INJECT_DEDUP`

Absent → `"1"` (default on). `"0"` → G0. Any other value (`"true"`, `""`, `"00"`) → treated
as ON, because the check is `== "0"`. Pre-existing semantics; **do not change** — the
existing G0 test at `test-inject-dedup.sh:108-115` pins it and the doc pins it.

### 3.3 `LEADV2_TASK_ANCHOR_STATE_DIR`

Absent → `~/.claude/state/leadv2`. Empty string → `or` short-circuits to the default (the
expression at `:288-289` is `os.environ.get(...) or os.path.expanduser(...)`, so `""`
correctly falls through). Unwritable → `os.makedirs` raises → G6. Pinned by
`test-inject-dedup.sh:126-142`.

### 3.4 `LEADV2_SD_SCAN_MAX_BYTES` (NEW)

Absent → `8388608`. Non-numeric → `int()` raises inside the helper's own `try` → `""` +
WARN (fail-open). `0` or negative → every ledger reads as over-cap → `"oversize"`, i.e. a
usable opt-out of the new scan without touching `LEADV2_INJECT_DEDUP`. **Naming check
(mandatory checklist item 1):** `LEADV2_*` prefix, matches `LEADV2_INJECT_DEDUP`,
`LEADV2_TASK_ANCHOR_STATE_DIR`, `LEADV2_TASK_ANCHOR_COMPACT_REPEAT` (`:643`). No
`LEAD_V2_*` variant exists anywhere (`grep -rn "LEAD_V2_" plugins/` → no hits).

### 3.5 The `2>/dev/null` at `hooks/leadv2-task-anchor.sh:59`

Must be **removed** for finding 5 to have any effect. Risk assessment:

- A raised exception inside `main()` is swallowed at `:825-828` — no traceback reaches fd 2.
- All three `subprocess.run` calls (`:64`, `:148-153`, `:195-197`) pass
  `capture_output=True`, so no child process stderr reaches fd 2.
- The only remaining source is a **parse-time** `SyntaxError` in the heredoc, which would
  print a traceback to the founder's terminal. That is caught by `bash -n` + the suite
  before commit, and a visible traceback is a strictly better failure mode than a hook that
  silently stops injecting the anchor.
- `$OUT` captures **stdout only**; stderr does not contaminate the injected block.

Rejected alternative: `exec 3>&2` + `os.write(3, ...)` to keep the redirect while letting
one line through. It works but is exotic, and it preserves exactly the silence that caused
this finding. Not worth the cleverness.

### 3.6 Concurrent access (mandatory checklist item 4)

- `<STATE_DIR>/.inject-hash.<sid>.thread-anchor` — written by the anchor hook, deleted by
  `leadv2-pre-compact-checkpoint.sh:26`. Different sessions use different `<sid>`, so no
  two writers share a path. Same-session PreCompact-vs-prompt is serialised by Claude Code
  (a `/compact` and a `UserPromptSubmit` do not interleave). Writes are already
  `tmp + os.replace` (`:325-328`) — atomic, keep it.
- `scheduled-decisions.md` — read-only here; every writer is elsewhere. §3.1 covers the
  torn-read case. **No lock required, and none should be added** — taking a lock on the
  prompt-submit path would let an unrelated writer stall every prompt.
- The GC glob at `:315` is scoped to `.inject-hash.*`. The comment at `:301-303` warns the
  state dir holds ~11.5k unrelated `.lead-streak` files. **Do not widen this glob.**

---

## 4. COUNTEREXAMPLE

*After every finding in this mission is fixed, what can still violate the invariant this
mechanism exists to protect?*

The invariant is: **the founder is never more than one prompt away from seeing current
thread state.** After these five fixes it is still violable, in one specific and likely
way. The gate will now correctly detect a DUE TODAY → OVERDUE flip and force a full
re-inject — but the body it re-injects is produced by `build_thread_anchor()`, whose
scheduled-decisions line comes from `nearest_due_line()` → the persona-engine renderer,
which is still id-keyed and still `exit 0`s silently because the id has not changed
(`scheduled-decisions-nearest.sh:143-145`). So the founder receives a full block that is
byte-identical to the one they already had: open threads, the DIRECTIVE, and **no mention
of the decision that just went overdue**. The gate's own knowledge of `OVERDUE` never
reaches the surface; it only reaches the hash. In other words this change converts a
silent-marker failure into a silent-full-block failure — strictly better for re-grounding
the DIRECTIVE, and strictly no better for the actual urgency signal that motivated
finding 1. A second, narrower hole survives too: the renderer's per-session state file
lives under `TMPDIR` keyed by `CLAUDE_SESSION_ID`, and `/compact` is cleared for the
plugin's own state (`leadv2-pre-compact-checkpoint.sh:26-27`) but **not** for the
renderer's `pe-nearest-due-<sid>` file, which is in another repo and outside this task's
scope — so post-compact the renderer stays silent about an already-shown id even though
the plugin has correctly forgotten everything.

What I checked to reach this: the renderer end-to-end (all 149 lines), `build_thread_anchor`
`:206-267`, `nearest_due_line` `:182-203`, the gate `:279-331`, the caller `:621-633`, the
PreCompact block `:24-28`, and every `task-anchor-full` reference in the tree.

**Recommendation to the lead (not designed here, not in LANE_WRITES):** the honest closure
is one extra line — when the in-gate classification differs from what the body carries and
the renderer produced nothing, append the in-gate-computed nearest line to the body before
hashing. That is ~6 lines in `build_thread_anchor`. It is beyond the mission's "mix
`id:status` into the hash input" wording, so I have scoped it out (§6) rather than widen a
fix round unilaterally. If the lead wants finding 1's *stated outcome* rather than its
*stated mechanism*, this is the delta to authorise.

---

## 5. CHANGES — exact files and edits

### 5.1 `plugins/leadv2/hooks/leadv2-task-anchor.sh`

**(a)** `:59` — drop `2>/dev/null` from the heredoc invocation. Add a one-line comment
naming HOOK-INJECT-DEDUP-01 §5 and stating that `main()` is exception-wrapped at `:825-828`
so no traceback can escape at runtime.

**(b)** New helper immediately above `_inject_dedup_gate` (i.e. after `:277`):

```
_SD_STATUS_TIERS: OVERDUE=0, DUE_TODAY=1, CONDITION_BOUND=2

def _nearest_decision_signature(root, leadv2_dir):
    """(id, status) of the nearest actionable scheduled decision, as "<id>:<STATUS>".
    Computed IN-GATE and independently of .claude/hooks/scheduled-decisions-nearest.sh,
    because that renderer's suppression is id-keyed and classification-blind: a
    DUE_TODAY -> OVERDUE flip of the same id renders nothing, so a body-only hash can
    never see it. Grammar mirrors that renderer (LEDGER-HOOK-PARSER-01 provenance);
    if the ledger format changes, both move together. Never raises."""
```

Body, in order: `path` join → `os.path.exists` guard returning `""` → `os.path.getsize`
vs `LEADV2_SD_SCAN_MAX_BYTES` returning `"oversize"` → `open(..., encoding="utf-8",
errors="replace").read()` → the sibling's parse verbatim in structure (`CLOSED_TITLE_RE`,
`re.split(r"(?=^#{2,3} )", ...)`, the three field-regex passes, the `\b(\d{4}-\d{2}-\d{2})(?!\d)`
extraction, tier assignment, `active_tier` selection, `pool.sort(key=(sort_key, pos))`) →
return `f"{winner_id}:{STATUS}"` or `"none"`. Entire body inside one `try/except Exception`
that emits the WARN (see (d)) and returns `""`.

Two deliberate simplifications versus the renderer, both safe: the `detail` /
`GO:` / `Action:` text assembly is dropped (we need only id + status), and `sort_key` for
non-OVERDUE tiers stays `0` (identical to the renderer). Days-overdue is *not* mixed into
the signature — mixing it would force a full re-inject once per day per row, duplicating
G5 and making the marker nearly unreachable on a busy ledger.

**(c)** `:293` — digest input becomes three-part:

```
digest = sha256((body + "\n" + today + "\n" + sd_sig).encode("utf-8")).hexdigest()
```

with `sd_sig = _nearest_decision_signature(root, leadv2_dir)` computed just above. This
requires threading `root` and `leadv2_dir` into `_inject_dedup_gate` — signature becomes
`_inject_dedup_gate(kind, session_id, body, root=None, leadv2_dir=None)`, and the single
call site at `:625` passes them (both are already in scope there). Defaults keep the
function callable without them.

*Migration note:* the digest input changes shape, so every already-stored digest becomes a
mismatch. Consequence: the first prompt after this ships is one extra full re-inject per
live session. Acceptable (fails toward showing more), and worth one line in the commit
message.

**(d)** `:319-320` and `:330-331` — the two broad fail-open blocks. Add a module-level
helper so the text is written once:

```
def _inject_warn(err):
    try:
        sys.stderr.write("[inject-dedup] fail-open: %s: %s\n" % (type(err).__name__, err))
    except Exception:
        pass
```

Call it from `except Exception as exc:` at the GC-unlink block (`:319`), at the gate's
outer handler (`:330`), and at the new helper's handler. `exit 0` semantics and the
`return "full"` / `return ""` results are unchanged — the WARN is additive. Keep the
message on **one** line and never include the body or the ledger contents (a ledger row can
contain founder-private text; the exception string alone is bounded and safe).

### 5.2 `plugins/leadv2/scripts/tests/test-inject-dedup.sh`

Extend the existing file; do not restructure it. The fixture repo is built at `:22-37`.

**(a) Finding 2 — real scheduled-decisions fixture.** Add a helper that writes
`$REPO/docs/leadv2/scheduled-decisions.md` with one row whose Due date the test controls,
in the exact ledger grammar (`## SD-TEST-01 — Some decision` heading + a
`| **Due** | <date> |` table row). Then:

- write the row with `Due` = **today** (`date -u +%F`) → `run_anchor` → expect full;
- `run_anchor` again, unchanged → expect the `thread anchor unchanged` marker (test (a));
- rewrite **only** the Due date to `today - 3d`, leaving the id and every other byte
  identical → `run_anchor` → expect a **full** block, not the marker (test (b)).

Correctness requirement for test (b): the fixture's `open-threads.md` must not change
between the two fires, and the assertion must be that the output is full *while the body
is otherwise identical* — otherwise the test passes for the wrong reason (G4 rather than
G5b). Because the sandbox repo has no `.claude/hooks/scheduled-decisions-nearest.sh`,
`nearest_due_line()` returns `None` at `:192-193` and the body genuinely does not vary with
the Due date — which makes this test a *clean* isolation of G5b. State that in a comment;
it is the whole point.

Portability: `date -u -v-3d +%F` is BSD-only. Use `python3 -c "import time; print(time.strftime('%Y-%m-%d', time.gmtime(time.time()-3*86400)))"` — the file already uses this
idiom at `:90`.

**(b) Finding 3 — R2 must cover the `/tmp` glob.** Because the sandbox never has an active
task, `:645` never runs and the marker is never created (§1.2). The test must create it
explicitly before the PreCompact fire:

```
tmp_marker="/tmp/.leadv2-task-anchor-full-${SESSION_ID}-covertask"
: > "$tmp_marker"
```
add `rm -f "$tmp_marker"` to `cleanup()` at `:16`, then after the existing PreCompact
invocation at `:158` assert `[[ ! -f "$tmp_marker" ]]`. Guard the whole sub-test on
`SESSION_ID` being `$$`-suffixed (it is, `:24`) so parallel suite runs cannot collide on
`/tmp`.

**(c) Finding 5 — assert the WARN is reachable.** Reuse the existing G6 unwritable-state-dir
case at `:126-142`, which already forces a real `PermissionError` inside the gate — no
test-only error-injection backdoor is needed or wanted. Capture stderr
(`g6_err="$(... 2>&1 >/dev/null)"`) and assert it contains `[inject-dedup] fail-open:`.
Keep the existing stdout assertions on the same fires.

### 5.3 `plugins/leadv2/docs/context-diet.md`

**Finding 4 — correct the overclaim.** The current text at lines 14-17 says the digest is
`sha256(body + "\n" + utc_date)` and that "any real content change … forces a full
re-inject". Replace with the three-part digest and add a short paragraph stating: the
scheduled-decisions classification is computed **in-gate**, independently of the
project-local `scheduled-decisions-nearest.sh` renderer, precisely because that renderer's
own suppression is **id-keyed** — the same row flipping DUE TODAY → OVERDUE renders
nothing, so a body-only digest is blind to it. Also state the residual honestly (§4): the
re-inject fires, but the re-injected body may not itself name the overdue row. Document
`LEADV2_SD_SCAN_MAX_BYTES` next to the existing `LEADV2_INJECT_DEDUP` kill-switch note.

### 5.4 Checklist items 2, 3, 5 (mandatory)

- **Paths (item 2):** `plugins/leadv2/hooks/leadv2-task-anchor.sh` ✓ exists;
  `plugins/leadv2/hooks/leadv2-pre-compact-checkpoint.sh` ✓ exists (read-only here);
  `plugins/leadv2/scripts/tests/test-inject-dedup.sh` ✓ exists;
  `plugins/leadv2/docs/context-diet.md` ✓ exists (mission says `docs/context-diet.md` — the
  real path is under `plugins/leadv2/`);
  `~/Projects/persona-engine/.claude/hooks/scheduled-decisions-nearest.sh` ✓ exists,
  **read-only reference, other repo, off-limits**;
  `docs/leadv2/scheduled-decisions.md` — **absent in this worktree** (to-create only inside
  the test sandbox, never in the repo).
- **`claude -p` (item 3):** this change introduces none. N/A.
- **Config contradiction (item 5):** `grep -rn "LEADV2_INJECT_DEDUP\|LEADV2_TASK_ANCHOR_STATE_DIR" plugins/`
  → hook, pre-compact hook, test, doc; semantics consistent. `LEADV2_SD_SCAN_MAX_BYTES` is
  new — zero pre-existing hits, no contradiction possible.

---

## 6. NON-GOALS — explicitly out of scope for the implementing agent

1. **Editing `~/Projects/persona-engine/.claude/hooks/scheduled-decisions-nearest.sh`.**
   Another repo, mission-excluded. Read for grammar reference only.
2. **Making the renderer's suppression classification-aware.** That is the sibling-repo fix
   (critic's option A) that this task deliberately declines.
3. **Surfacing the in-gate-computed OVERDUE line in the injected body.** The honest closure
   of §4, but wider than "mix `id:status` into the hash input". Lead's call, not the
   implementer's.
4. **Clearing the renderer's `${TMPDIR}/pe-nearest-due-<sid>` state on PreCompact.**
   Cross-repo, same reason.
5. **`leadv2-single-lead-beat.sh`'s BROAD_STATUS gate** — already documented as out of scope
   in `context-diet.md:19-20`. Untouched.
6. **The task-mode anchor path** (`task_id` truthy, `:635-833`) — only finding 3's *test*
   touches its `/tmp` marker; the production code path is not modified.
7. **Any change to `LEADV2_INJECT_DEDUP` semantics**, the GC glob scope, or the
   `tmp + os.replace` write pattern.
8. **Adding a lock around the ledger read.** Explicitly rejected in §3.6.
9. **Refactoring the parse into a shared module** between the plugin and the renderer. They
   are separate processes in separate repos; the duplication is deliberate and commented.

---

## 7. Acceptance

```yaml
acceptance:
  - surface: rendered_line
    observable: >-
      On a second founder prompt in the same session with nothing changed, the text above
      the prompt is the single line "thread anchor unchanged — docs/leadv2/open-threads.md;
      the block above still governs." instead of the multi-line thread-anchor block.
    authored_at: 2026-08-24T00:00:00Z
  - surface: rendered_line
    observable: >-
      After the nearest scheduled decision goes from due-today to overdue — with the open
      threads text otherwise untouched — the next founder prompt shows the full multi-line
      thread-anchor block again, not the one-line "unchanged" marker.
    authored_at: 2026-08-24T00:00:00Z
  - surface: rendered_line
    observable: >-
      On the first founder prompt after a /compact in the same session, the full multi-line
      thread-anchor block is shown, not the one-line "unchanged" marker.
    authored_at: 2026-08-24T00:00:00Z
  - surface: log_line
    observable: >-
      When the anchor hook's state directory cannot be written, a line reading
      "[inject-dedup] fail-open:" followed by the error appears on the hook's stderr, and
      the founder still sees the full thread-anchor block above their prompt.
    authored_at: 2026-08-24T00:00:00Z
  - surface: file_artifact
    observable: >-
      plugins/leadv2/docs/context-diet.md describes a three-part digest and states that the
      due/overdue classification is computed inside the gate because the project-local
      renderer's own suppression is keyed on row id alone.
    authored_at: 2026-08-24T00:00:00Z
  - surface: log_line
    observable: >-
      The test suite's final line reads "[TEST] Results: PASS=<n> FAIL=0" with n greater
      than the pre-change pass count, and the run includes passing cases named for the
      scheduled-decisions fixture and for the /tmp full-marker clearing.
    authored_at: 2026-08-24T00:00:00Z
```

---

## 8. Implementation order

1. `_nearest_decision_signature` + `_inject_warn` + three-part digest + `:59` redirect
   removal (one commit-shaped unit — the WARN is untestable without the redirect change).
2. `bash -n plugins/leadv2/hooks/leadv2-task-anchor.sh` and
   `bash -n plugins/leadv2/hooks/leadv2-pre-compact-checkpoint.sh`.
3. Test additions (2a, 2b, 2c) — expect 2a's second case to FAIL before step 1 is in and
   PASS after; if it passes before step 1, the test is wrong (it is measuring G4).
4. `bash plugins/leadv2/scripts/tests/test-inject-dedup.sh` → `FAIL=0`.
5. `context-diet.md` correction.
6. Commit in the worktree, message naming `7bdb16ee` and `HOOK-INJECT-DEDUP-01`, noting the
   one-time extra re-inject from the digest-shape migration (§5.1c).

LANE_WRITES: plugins/leadv2/hooks/leadv2-task-anchor.sh, plugins/leadv2/scripts/tests/test-inject-dedup.sh, plugins/leadv2/docs/context-diet.md

DELIVERABLE_COMPLETE
