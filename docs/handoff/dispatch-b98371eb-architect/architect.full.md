# PANEL-TWO-IMPLEMENTATIONS-MERGE-01 — architect prepass

Repo: `~/Projects/leadv2`. Design only, no implementation.

Baseline verified on disk this pass (2026-08-05):
`tests/test-status-surface-single-lead.sh` **23 passed / 0 failed**,
`tests/test-status-surface-bash32.sh` **15 / 0 / 0 skipped**,
`tests/test-status-surface-fast-names.sh` **12 / 0**. All three green before any change.

---

## 1. What the two implementations actually are

| | lanes table (`--all`, default) | single-lead (`--single-lead`) |
|---|---|---|
| function | `_ss_lanes_py()` `:538–1765` (bash `_run_lanes_for_project` `:1766`) | `render_single_lead()` `:2633–3255` |
| worker discovery | `active.yaml` sessions + ledger rows + run dirs + `sig_process_alive`/`pid_argv_matches_sig` | `census_workers(ps_text)` + `codex_census` + reservation ledger |
| terminal source | ledger `state`/`terminal` folded into one row (`:1356`) | separate per-repo terminal index `term_by_sig`/`term_by_name` (`:2921–2967`) |
| class vocabulary | `cls ∈ {live, done, dead, queued}` (`add_row`, `:1440–1530`) | `state ∈ {active, closing}` + implicit `drop` (`_terminal_state`, `:3062`) |
| header | `lanes (N live, N dead, N done…, N queued)` `:1942` | `mode=single-lead active N <name20> <arm> <age>` `:3234` |
| consumed by | `.5s.sh` section 1 | `.5s.sh` section 6, title fields `$3..$6` (`:433–446`) |

**They do not read the same inputs.** `_ss_lanes_py` is driven by `active.yaml` + run dirs;
`render_single_lead` is driven by a `ps` snapshot + the reservation ledger. A literal
"move the census into the shared chain" is therefore not a move — it is a rewrite of both
discovery layers against a union input model, and that is the thing the previous worker
correctly refused.

### The merge that *is* correct and does fit

The drift that produced the founder's panel was never a census disagreement. It was a
**classification** disagreement: `_ss_lanes_py` learned (commit `89217a1`) that a
ledger-only pending/queued/reserved row with no pid and no exit code is `queued`, and
`render_single_lead` did not. So:

> Extract the classification **decision** — not the census — into one module that both
> heredocs load. Each renderer keeps its own discovery, projects what it found into a
> common `LaneFacts` record, and calls `classify()`. Neither renderer may branch on
> ledger state, pid liveness, exit code or terminal token on its own again.

That is one source of truth for *what a lane is*, it is implementable in this budget, and
it is exactly what the parity test can assert. The censuses stay separate and stay honest
about their own sources.

---

## 2. Design

### 2.1 The shared classifier — `plugins/leadv2/scripts/leadv2-lane-class.py` *(to-create)*

Plain python, no imports beyond stdlib, no I/O, no environment reads. Pure function.

**Input** — `LaneFacts`, a dict. Every field optional; absent means "this renderer has no
signal for it", which is different from "the signal says no".

| field | type | meaning |
|---|---|---|
| `kind` | `"worker"` \| `"lane"` | ledger-derived row vs `active.yaml` session |
| `pid_alive` | `True`/`False`/`None` | `None` = never had a pid |
| `argv_alive` | bool | argv identity-matched a live process |
| `close_alive` | bool | close-gate process alive |
| `exit_code` | int/`None` | |
| `ledger_state` | str | `pending`\|`queued`\|`reserved`\|`confirmed`\|`no_work`\|`landed`\|`dead`\|`parked`\|`refused`\|`""` |
| `terminal_token` | str | the write-terminal row's `terminal` field, `""` if none |
| `terminal_ts`, `reserved_ts`, `motion_mtime`, `now` | int | epochs, `0`/`None` = unknown |
| `outcome` | str | `completed`\|`died-with-work`\|`died-clean`\|`""` |
| `fresh_motion_s` | int | seconds since last motion, `None` if unknown |

**Output** — `LaneClass`:

```
{"cls": "live"|"queued"|"done"|"dead", "cause": "<text>", "live": bool, "terminal": bool}
```

`cls` keeps `_ss_lanes_py`'s existing four-valued vocabulary **verbatim** — that path is
the one that was already fixed and whose 15+12+23 assertions encode its exact strings.
The classifier body is the branch chain currently at `:1440–1530` lifted unchanged
(live → close-alive → fresh-motion → gate → exit-code → no-process → **queued** →
stale → no-signal, then the `.outcome` overlay, then the `no_work` override, then the
terminal / stale→done reinterpretation). Lifted, not rewritten: byte-identical `cause`
strings are the contract that keeps the three existing suites green.

`live` is `cls == "live"`. `terminal` is today's `is_terminal(status, ledger_state)` plus
`terminal_token != ""`.

**Loading.** Bash resolves the absolute path once and exports
`LEADV2_LANE_CLASS_PY="$SCRIPT_DIR/leadv2-lane-class.py"`; each heredoc does
`exec(open(os.environ["LEADV2_LANE_CLASS_PY"]).read(), globals())` inside a `try`. On
failure: the lanes path raises into its existing loud-warning route, the single-lead path
calls `fail("lane classifier unloadable")` → `mode=single-lead active ⚠ …`. Never a
silent zero. One extra ~8 KB file read per tick; the tick already spawns 2–6 `tail`
subprocesses, so this is not a measurable cost on the 150 ms path.

> The file-header comment at `:582–587` says `_mini_yaml` was duplicated rather than
> sourced "because sharing a sourced .py would add a runtime artifact to this 150 ms read
> path". That reasoning stands for a 340-line YAML parser on a path that must survive a
> minimal `PATH`; it does not extend to a ~120-line pure-function module, and duplicating
> the classifier is precisely the drift this task exists to end. **Do not duplicate it.**

### 2.2 `render_single_lead` becomes a projection

Keep: `_parse_sources`, `tail_lines`, the per-repo terminal/reservation indices,
`census_workers`, `codex_census`, `_supervise_pid`, `_match_reservation`, `_terminal_hit`.
Those are discovery, and they read sources `_ss_lanes_py` does not.

Delete: `_terminal_state()` (`:3062–3071`) and every place the renderer decides liveness
itself — `state = "closing" if tstate == "closing" else "active"` (`:3154`, `:3190`) and
the `tstate == "drop"` `continue`s (`:3149`, `:3183`).

Replace with, per candidate lane (both branch (a) live-census and branch (b)
reservation-only):

```
facts = project(...)            # census + reservation row + terminal hit -> LaneFacts
lc    = classify(facts)
if not lc["live"]: continue     # founder rule: only running lanes appear
```

Consequences, all of them intended:

* `closing` disappears as a rendered state. A terminal lane is not live, so it is not
  listed and not counted — no grace window, no lingering row.
* A reservation-only `pending`/`queued`/`reserved` row classifies `queued` → not live →
  not listed and not counted. This is the same rule `89217a1` gave the lanes table; the
  two paths now get it from one place.
* The header count `N` is `len(live)`. Fields 1–6 of the header line stay positional and
  unchanged (`.5s.sh:433–446` splits on whitespace) — **nothing may be inserted before
  field 6**.

### 2.3 Defect 1 — an empty field never renders its separator

One helper, used by both renderers' detail-row emitters:

```python
def join_fields(parts, sep=" · "):
    return sep.join(p for p in (str(x).strip() if x is not None else "" for x in parts) if p)
```

`render_single_lead`'s two `print` calls at `:3243/:3245` collapse into one:

```
print("  " + join_fields([name, phase, join_fields([arm, age], " "), repo_or_None]))
```

`repo` is passed only when `multi_repo`. `arm`+`age` join with a space and, if `arm` is
empty (defect: a lane with a missing model field), the row reads `NAME · worker · 16m`
rather than `NAME · worker ·  16m`. The assertion the mission asks to keep: **no rendered
detail line may contain `· ·`, ` ·` at end-of-line, or a leading `· `.**

### 2.4 Defect 2 — the duplicated `sig <hex8>` sub-row

Located: it is **not** emitted by the renderer. It came from `.5s.sh`'s CACHED-mode
reformatter, which used to whitespace-split the `·`-delimited detail line and demote the
raw sig8 to a `sig …` sub-row. The comment at `.5s.sh:472–480` records that this was
already replaced by a `·`-safe parameter-expansion split, and the current code emits
exactly one line per detail row.

**Action: no code change. Add a regression assertion** to the parity suite — render the
widget in CACHED mode with a named lane and assert (a) the dropdown emits exactly one
line per renderer detail row, and (b) no dropdown line matches `^ *sig [0-9a-f]{8}`.
Reporting this as "already fixed, now locked" is the honest outcome; do not manufacture a
change to have something to point at.

### 2.5 Defect 3 — truncation that cannot be mistaken for another task id

```python
def clip_name(s, n):
    if len(s) <= n: return s
    head = s[:n-1]
    cut  = max(head.rfind("-"), head.rfind("_"))
    if cut >= n // 2: head = head[:cut]     # prefer a separator boundary
    return head + "…"
```

Invariant, and this is the assertion: **any name the renderer shortened carries `…`.** A
rendered name that ends in a digit or letter is therefore always the complete task id.
`VOICE-CUSTOMER-CONTROL-01` at n=24 → `VOICE-CUSTOMER-CONTROL…`, never
`VOICE-CUSTOMER-CONTROL-0`.

Applied at both widths: the detail row (`n=24`, was `w["name"][:24]`) and the header /
menu-bar title name (`n=20`, was `newest["name"][:20]`). `…` is a single non-space
character, so the header's positional whitespace split is unaffected.

### 2.6 Defect 4 — delete the `terminals unreadable` family

The three `warnings.append("%s terminals unreadable" % repo)` sites (`:2957`, `:2967`,
`:3009`) and the `for w in warnings: print("  ⚠ %s" % w)` loops (`:3220`, `:3247`) are
removed. The `warnings` list itself goes.

**Rule U's behaviour is retained, only its panel line is deleted**: a repo whose
reservation or terminal ledger cannot be read still contributes **zero rows**
(`unverifiable_repos` / `continue` stay). Silently dropping a repo's rows is what the
founder asked for; silently *inventing* rows would not be. When
`LEADV2_STATUS_DEBUG=1` is set the reason goes to **stderr**, which the wrapper never
captures into the panel — that is the "belongs in a log" half of the instruction.

Untouched: the `fail()` route (`mode=single-lead active ⚠ ledger unreadable: …`). That is
a different, load-bearing warning — it fires when the renderer cannot produce a count at
all, and the wrapper keys `⚠️ ledger не прочитан` on it. Deleting it would reintroduce
confident-wrong zeros. **Only the per-repo `terminals unreadable` family goes.**

**This changes an existing assertion.** `tests/test-status-surface-single-lead.sh:416`
currently requires `⚠ repo-c terminals unreadable` to be present. It must be rewritten in
place — same test, inverted expectation — to: repo-c's rows are still absent **and** no
line matching `terminals unreadable` is emitted. The suite must stay at **23 passed / 0
failed**; do not delete the case to reach that number.
`tests/test-status-surface-bash32.sh:220` mentions the string only in a comment (its
`for _bad in …` list does not include it) — update the comment, no assertion change.

### 2.7 Only running lanes, and the empty case

Title and body both derive from the live-filtered set, so both obey the rule with no
separate title logic. When `workers` is empty after filtering:

```
mode=single-lead active 0
  нет активных lane
```

The existing stale-reservation diagnostic (`:3210–3217`,
`(last open <sig> <N>h ago, no terminal row)`) **replaces** that plain line when a genuine
unexpired open reservation with no terminal row exists. Judgment call, stated explicitly:
the founder's objection was to *dead lane rows padding the panel*, and this is a single
diagnostic line that names a lane the system believes is still open — the one case where
"nothing is running" would otherwise be a lie. Exactly one line is emitted either way.

### 2.8 `_ss_lanes_py` side

Minimal: `add_row`'s branch chain is replaced by `lc = classify(project_row(...))` and the
existing `cause`/`cls` locals are read back off `lc`. Everything downstream — the TTL
drop, `queued_n`, the `#LIVE/#DEAD/#DONE/#QUEUED` markers, the `display` composition — is
unchanged. `join_fields`/`clip_name` are adopted for its detail rows too, since both
defects are format-level and the table is the other renderer the parity test compares.

---

## 3. The parity test — `tests/test-status-surface-parity.sh` *(to-create)*

The two renderers cannot be fed one fixture (different sources), so parity is asserted on
the classification, three ways per shape:

1. **Classifier truth.** `python3 -c` loads `leadv2-lane-class.py`, feeds the shape's
   `LaneFacts` JSON, prints `cls`.
2. **Lanes-table projection.** Build the `active.yaml` / ledger / run-dir fixture encoding
   that shape, render `--all`, extract the row's class from the `#LIVE/#DEAD/#DONE/#QUEUED`
   markers and the row text.
3. **Single-lead projection.** Build the `ps`-stub / reservation-ledger / terminal-ledger
   fixture encoding the same shape, render `--single-lead`.

Assert per shape: **lanes-table class == classifier `cls`**, and **the lane appears in the
single-lead body and header count iff `cls == "live"`**. That equivalence is the bridge
between the two vocabularies and is what makes future drift a test failure.

| # | shape | expected `cls` | in single-lead? |
|---|---|---|---|
| 1 | live worker, pid alive | `live` | yes |
| 2 | live worker, no pid, argv identity match | `live` | yes |
| 3 | terminal `landed` | `done` | no |
| 4 | terminal `dead` (exit≠0) | `dead` | no |
| 5 | terminal `no_work` | `dead` (`no-work(...)`) | no |
| 6 | ledger-only `queued`, no pid, no exit | `queued` | no |
| 7 | `reserved`, no pid | `queued` | no |
| 8 | `pending`, no pid | `queued` | no |
| 9 | repo whose terminal ledger is unreadable | — (repo suppressed) | no; **and no `terminals unreadable` line** |
| 10 | lane with no `arm`/model field | `live` | yes; row has **no `· ·`** |
| 11 | name longer than the column (`VOICE-CUSTOMER-CONTROL-01`) | `live` | yes; rendered name **ends in `…`**, and `VOICE-CUSTOMER-CONTROL-0` appears nowhere |
| 12 | live lane + finished lane together (mixed) | `live`,`done` | only the live one, count `active 1` |
| 13 | all lanes finished | `done` | body is exactly one plain line, zero lane rows |

Shapes 9–13 are the four defects and the founder's two new requirements, each with its own
assertion as the mission requires. 13 shapes ≥ the required 10.

Harness: copy the sandboxing preamble of `tests/test-status-surface-single-lead.sh`
(`mktemp -d`, `LEADV2_STATUS_*` pinned, `PS_STUB`) verbatim — nothing may read the
operator's live state.

---

## 4. Files

| file | change |
|---|---|
| `plugins/leadv2/scripts/leadv2-lane-class.py` *(to-create)* | shared `classify()` + `join_fields()` + `clip_name()`; pure functions, no I/O |
| `plugins/leadv2/scripts/leadv2-status-surface.sh` | export `LEADV2_LANE_CLASS_PY`; both heredocs load it; `add_row` delegates; `render_single_lead` becomes a live-only projection; `_terminal_state` deleted; `terminals unreadable` family deleted; `join_fields`/`clip_name` adopted |
| `tests/test-status-surface-parity.sh` *(to-create)* | the 13 shapes above |
| `tests/test-status-surface-single-lead.sh` | `:416` assertion inverted in place; add only-running-lanes cases if the count can grow past 23 without deleting a case |
| `tests/test-status-surface-bash32.sh` | comment at `:220` only |

`plugins/leadv2/scripts/leadv2-status-surface.5s.sh` is **not** modified — §2.2 preserves
its positional header contract and §2.4 confirms its CACHED reformatter is already correct.

Suites to run, and only these:
`tests/test-status-surface-parity.sh`, `tests/test-status-surface-single-lead.sh` (23/0),
`tests/test-status-surface-bash32.sh` (15/0), `tests/test-status-surface-fast-names.sh`
(12/0), plus `bash -n` and `/bin/bash` (3.2) `-n` on the changed shell script.
**Do NOT run `run-core-offline.sh`.** No commit, no push.

---

## 5. Risks

| id | risk | mitigation |
|---|---|---|
| R-1 | Lifting the `add_row` chain into a module changes a `cause` string by one character → the 23/15/12 assertions break in ways that look like real regressions | lift verbatim; run the three suites *before* touching `render_single_lead`, so a break is attributable to the lift alone |
| R-2 | `exec(open(...))` fails under SwiftBar's minimal `PATH`/sandbox (the exact failure class as the PyYAML bug) | path is absolute and bash-resolved, not `PATH`-relative; `bash32` suite already renders under `env -i PATH=/usr/bin:/bin` and will catch it; load failure routes to the loud `⚠`, never a zero |
| R-3 | Dropping `closing` removes a row a founder was using to see a just-finished lane | that is the explicit founder instruction of 2026-08-04 21:31; the lanes table still shows `done в последний час` |
| R-4 | Deleting the warning hides a genuinely broken repo ledger | behaviour unchanged (rows suppressed, never invented); reason available on stderr under `LEADV2_STATUS_DEBUG=1`; the `fail()` ⚠ route survives untouched |
| R-5 | `…` (U+2026) in a name breaks the wrapper's `awk` positional split or SwiftBar rendering | single non-space char; `bash32` T8c already covers the field split; add one assertion that header field 4 survives an ellipsised name |
| R-6 | `queued` lanes vanishing from single-lead makes the founder think dispatch is dead | the lanes table's `, N queued` clause (`89217a1`) is the surface for backlog; single-lead is by definition the *running* view |
| R-7 | Two renderers still have two censuses → a future drift in *discovery* is not covered by this test | stated limitation, not hidden: the parity test covers classification only. A discovery-parity test needs a union input model and is a separate task |

### Constraint checklist

1. **Env vars** — new: `LEADV2_LANE_CLASS_PY` (internal, bash→python), `LEADV2_STATUS_DEBUG`.
   Both use the `LEADV2_*` prefix; `LEADV2_STATUS_*` matches the file's existing
   `LEADV2_STATUS_ACTIVE_TTL_S`/`LEADV2_STATUS_STATE_DIR` convention. No `LEAD_V2_*` drift.
   Retired: `LEADV2_STATUS_SL_CLOSING_GRACE_S` (grace no longer exists) — grep before
   removing; if any test pins it, keep it parsed and ignored rather than erroring.
2. **Paths** — all read paths verified this pass:
   `plugins/leadv2/scripts/leadv2-status-surface.sh` (3337 lines),
   `plugins/leadv2/scripts/leadv2-status-surface.5s.sh` (573),
   `tests/test-status-surface-{single-lead,bash32,fast-names}.sh` (452/324/193).
   To-create: `plugins/leadv2/scripts/leadv2-lane-class.py`,
   `tests/test-status-surface-parity.sh`.
3. **`claude -p`** — n/a, this change spawns no Claude session.
4. **Concurrent access** — read-only against ledgers that dispatch appends under `flock`;
   the surface does not take the lock (a 5 s render must never block a dispatch). The
   existing torn-final-line tolerance is unchanged.
5. **Config contradiction** — `LEADV2_SS_*` (lanes heredoc) and `LEADV2_SL_*` (single-lead
   heredoc) prefixes stay disjoint; the shared module reads **no** environment at all, so
   it cannot import either renderer's config semantics into the other.

## 6. Out of scope

* Merging the two **censuses**. Explicitly deferred, with R-7 as the stated gap.
* Any ledger *writer* (`leadv2-dispatch-ledger.sh`, `leadv2-dispatch-code.sh`).
* `leadv2-status-surface.5s.sh` (contract preserved by design).
* The legacy/supervisor render mode (`.5s.sh:516+`).
* `render_questions`' duplicated `_mini_yaml` — same class of duplication, different
  blast radius, separate task.
* `run-core-offline.sh` and every suite outside the four named in §4.
* Commit, push, merge.

acceptance:
- surface: rendered_line
  observable: "In the menu-bar dropdown, every lane row reads as a complete
    dot-separated line with no gap between two dots and no dot hanging at the end, even
    when the lane has no recorded model."
  authored_at: 2026-08-05T00:00:00Z
- surface: rendered_line
  observable: "No row anywhere in the panel says a repo's terminals are unreadable; that
    wording is gone from the menu entirely."
  authored_at: 2026-08-05T00:00:00Z
- surface: rendered_line
  observable: "The dropdown lists only lanes that are actually running right now — a lane
    that has finished is absent from the list and is not counted in the header, and the
    menu-bar title no longer carries a finished lane's name."
  authored_at: 2026-08-05T00:00:00Z
- surface: rendered_line
  observable: "When nothing is running, the panel shows one plain line saying so instead
    of a list of finished lanes."
  authored_at: 2026-08-05T00:00:00Z
- surface: rendered_line
  observable: "A lane whose name is too wide for the column is shown ending in an ellipsis,
    so a shortened name can never be read as a different task id such as
    VOICE-CUSTOMER-CONTROL-0."
  authored_at: 2026-08-05T00:00:00Z
- surface: rendered_line
  observable: "A named lane occupies exactly one row in the dropdown — there is no second
    row underneath it repeating its 8-character id."
  authored_at: 2026-08-05T00:00:00Z
- surface: file_artifact
  observable: "Running the four status-surface test scripts prints passing summaries with
    no FAIL lines: the new parity suite covering at least ten lane shapes, plus
    single-lead 23 passed 0 failed, bash32 15 passed 0 failed, fast-names 12 passed 0
    failed."
  authored_at: 2026-08-05T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-class.py, plugins/leadv2/scripts/leadv2-status-surface.sh, tests/test-status-surface-parity.sh, tests/test-status-surface-single-lead.sh, tests/test-status-surface-bash32.sh

DELIVERABLE_COMPLETE
