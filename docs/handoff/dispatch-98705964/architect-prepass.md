# MENUBAR-PANEL-02 — architect prepass (attempt 2)

Repo: `~/Projects/leadv2`. Branch only. Design only — no implementation here.

---

## 1. Root cause, established from the code

The mission's framing ("the fix and the surface no longer meet") is correct but the
mechanism is more specific than "the `--all` payload path did not get the fix".

`leadv2-status-surface.sh` contains **two completely independent lane computations**:

| # | Producer | Lines | Consumers | Got the c1e8cbf fix? |
|---|----------|-------|-----------|----------------------|
| A | `_ss_lanes_py` → `LANE_ROWS` (9-col TSV) | 538–1737, 1748–1845 | `emit_lanes_table` (`--default`), `emit_oneline` | **yes** |
| B | `render_single_lead` (its own ~600-line python heredoc: ps census + per-repo reservation/terminal indices) | 2600–3222 | the `mode=single-lead` block of `--all` → the widget | **no** |

`--all` (line 3286) emits **both**: producer A's table first, then producer B's
`mode=single-lead` block. That is why the founder's forced live render showed a correct
table header and a wrong `mode=single-lead` list *in the same output*. Nothing about
`--all` is stale; `--all` simply also renders producer B, and the widget reads **only**
producer B (section 6 of the `---`-delimited payload, `.5s.sh:393`).

So this is not "one script, two outputs, one corrected". It is **two lane models in one
script**, and the widget consumes the un-fixed one.

### The `· · ·` defect is a parser bug, not a data-loss bug

`render_single_lead` emits (`leadv2-status-surface.sh:3208–3211`):

```
  <name> · <phase> · <arm> <age>              # single-repo
  <name> · <phase> · <arm> <age> · <repo>     # multi-repo
```

The widget's cached branch (`leadv2-status-surface.5s.sh:463–472`) re-parses that line by
**whitespace**:

```sh
_s_id="$(... awk '{print $1}')"   # b12e69cc
_s_arm="$(... awk '{print $2}')"  # ·          <- the separator
_s_age="$(... awk '{print $3}')"  # worker     <- the phase
printf '%s · %s · %s' "$_s_label" "$_s_arm" "$_s_age"
```

`b12e69cc · worker · glm 16m` therefore renders as `MENUBAR-PANEL-02 · · · worker`, and
then `_is_sig8 "$_s_id"` is true so the `sig b12e69cc` sub-row fires. **Both defect 1 and
defect 2 are this one call site.** The data was never missing — the widget reassembled a
`·`-delimited line as if it were whitespace-delimited.

### Repo attribution

`render_single_lead` derives repo from `_match_reservation()`; on a miss it falls back to
`repo = CUR_REPO` (`leadv2-status-surface.sh:~3104`). A `~/Projects/leadv2` lane rendered
under `persona-engine` is that fallback firing with `persona-engine` as cwd. Producer A
never has this problem: in multi-project mode it prepends the project slug from
`PROJ_SLUGS[]` (line 1810), i.e. attribution comes from **which ledger the row was read
from** — structurally correct.

Worse, wrong repo attribution also causes **defect 3**: `_terminal_hit(repo, …)` looks up
the terminal index of the *wrong* repo, misses, and the retired lane resurrects. Defects 2
and 3 share a root.

### Queued backlog rows (defect 4)

`SWIFTBAR-FAST-NAMES-01` etc. are ledger-only reservations with no live process. Producer B
has no notion of "not started" — every reservation without a terminal row becomes a
worker. `is_terminal()` deliberately treats `pending` as non-terminal (a stale pending is a
crashed dispatch and must stay visible), so these rows are load-bearing — they must be
*sectioned*, not dropped.

### Warnings (defect 6)

`warnings.append("%s terminals unreadable" % repo)` fires once per repo that has a
reservation ledger under `LEDGER_DIR` but no readable `STATE_ROOT/<repo>/dispatch-ledger.jsonl`
(`leadv2-status-surface.sh:~2917/2951`). `feeddark`, `replyaud`, `replyaud2`, `repro` have
ledger files and no state dir → four warnings for repos with zero lanes.

---

## 2. The design — one lane model, two projections

**Decision D1: producer A becomes the only lane computation. `render_single_lead` is
demoted to a projection of `LANE_ROWS`.**

Rejected alternative: a bash-level merge that appends producer B's census rows to
`LANE_ROWS`. It would have to re-implement terminal retirement, TTL age-out and repo
attribution outside `_ss_lanes_py` — i.e. it recreates a second walk, which is exactly the
drift this task exists to kill.

Producer B owns one capability producer A lacks and that must not be lost: the **ps census**
(`census_workers` + `codex_census`), which finds a glm/kimi/codex/claude-subsession worker
that has no `active.yaml` row. That is the SWIFTBAR-ACTIVE-SOURCE-02 "idle while a worker
runs" fix. It moves *into* `_ss_lanes_py` as an additional row source, ahead of
classification — so census rows get terminal retirement, TTL and name resolution for free.

### 2.1 Data flow (after)

```
1. bash captures ONE ps snapshot            -> PS_SNAPSHOT            (unchanged)
2. per project P in PROJ_SLUGS[]:
     _run_lanes_for_project(P) -> _ss_lanes_py with
        LEADV2_SS_CENSUS_SCOPE=<slug of P>  (NEW)
     2a. active.yaml rows          (existing)
     2b. ledger-only rows          (existing)
     2c. census rows               (NEW — moved from render_single_lead)
         claimed by P only if P's reservation ledger holds the sig8,
         else by the repo whose worktree path contains the run-dir,
         else by CUR_REPO. A row is claimed by exactly one P.
     2d. merge 2a/2b/2c by sig8; terminal retirement, TTL age-out,
         lead-session exclusion, name resolution  (existing, now also
         applied to census rows)
     2e. classify -> cls in {live, queued(NEW), done, dead}
     -> 9-col TSV, prefixed with <slug>
3. LANE_ROWS  (the ONE list)   +  LIVE_N / QUEUED_N / DEAD_N / DONE_RECENT_N
4. projections:
     emit_lanes_table   (--default)      -- output byte-identical to today
     emit_oneline       (--oneline)      -- unchanged
     render_single_lead (--single-lead)  -- REWRITTEN as awk over LANE_ROWS
5. --all = emit_lanes_table + sections + render_single_lead   (unchanged shape)
6. widget .5s.sh reads section 6, resolves field 1 through labels.map, reprints
```

### 2.2 Interface contract — `LANE_ROWS` (unchanged schema, one new class)

| # | Field | Notes |
|---|-------|-------|
| 0 | `proj` | multi-project only; prepended slug. **Authoritative repo attribution.** |
| 1 | `name` | resolved human name, else `dispatch-<sig8>`, else sig8 |
| 2 | `kind` | `lane` / `warn` |
| 3 | `display` | phase / state text |
| 4 | `model` | arm |
| 5 | `age` | `now` / `14m` / `2h` |
| 6 | `cause` | unrendered by the table |
| 7 | `cls` | `live` \| **`queued`** \| `done` \| `dead` — new value is additive |
| 8 | `sig` | sig8 |
| 9 | `outcome` | |

`cls=queued` rule: a ledger-only reservation with **no live process, no journal activity,
and phase in {queued, pending, reserved}**. Everything that is `live` today stays `live` —
the 23-case suite's fixtures are unaffected because they carry either a live process or a
terminal row.

### 2.3 Interface contract — the `mode=single-lead` block (projection B)

Header (`.5s.sh:420–437` parses it, keep the token layout):

```
mode=single-lead active <LIVE_N> <name> <arm> <age>
```

`LIVE_N` counts `cls==live` **only**. `queued`, `dead`, `done` are excluded — this is
defects 3 and 4, fixed by construction rather than by a filter.

Detail lines, one per row, **absent fields emit no separator**:

```
  <name> · <phase> · <arm> <age> · <repo>
  <name> · <arm> <age>                       # phase unknown -> no ` · ` for it
  <name>                                     # nothing else known
```

Then, when `QUEUED_N > 0`, a clearly-labelled second section that does **not** share the
live number:

```
  queued (<QUEUED_N>)
    <name> · <repo>
```

Then exactly one warning line, or none:

```
  ⚠ <N> repos: terminals unreadable (<a>, <b>, <c>)
```

Suppression rule: a repo is included only if it contributed ≥1 reservation row. A repo with
a ledger file and zero lanes produces no warning at all.

Name clipping — replaces `name[:24]` / `name[:20]`:

```
clip(s, n):  len(s) <= n              -> s
             cut at last '-' at pos <= n-1, else hard cut at n-1
             ALWAYS append '…'
```

The `…` is the invariant: a truncated name can never be a syntactically valid task id, so
`VOICE-CUSTOMER-CONTROL-0` (mistakable for `-CONTROL-01`) becomes `VOICE-CUSTOMER…`.

### 2.4 Widget contract — `.5s.sh` cached branch

Today the widget **re-formats** the detail row. That is the bug. After this change it
**does not reassemble anything**:

```sh
# split off the FIRST ' · '-delimited field only
_s_first="${_s_trim%% · *}"
_s_rest="${_s_trim#* · }"          # equals _s_trim when there is no ' · '
_s_label="$(_lookup_label "$_s_first")"
if [ "$_s_rest" = "$_s_trim" ]; then printf '%s | …\n' "$_s_label"
else printf '%s · %s | …\n' "$_s_label" "$_s_rest"; fi
```

Pure `${var%%…}` / `${var#…}` — bash 3.2 safe, no arrays, no `read -a`, no process
substitution.

The `sig <hex>` sub-row is **deleted outright**. When the label resolved, it is duplication;
when it did not, field 1 already *is* the sig8. Either way it is never useful.

Consequence the mission asked for: cached and SYNC now render the same text, because the
widget stopped having its own opinion about the format.

### 2.5 Staleness

`_compute_age_suffix` (`.5s.sh:242–250`) already overrides the title at ≥600 s. Two gaps to
close:

1. `PAYLOAD_AGE` is 0 when `all.payload` is **missing**; a missing payload must be treated
   as maximally stale, not as fresh.
2. `_kick_refresh` returns silently when `LOCKDIR` is held and younger than 90 s
   (`.5s.sh:271–277`). If a refresher wedges, the payload ages while the title stays
   confident until the 600 s mark. Lower the confident window: when `ERRFILE` is non-empty
   **and** `PAYLOAD_AGE > 3 × TTL`, emit the `⚠️ кэш устарел` title immediately.

---

## 3. Files

| File | Change |
|------|--------|
| `plugins/leadv2/scripts/leadv2-status-surface.sh` | move ps census into `_ss_lanes_py`; add `LEADV2_SS_CENSUS_SCOPE`; add `cls=queued` + `QUEUED_N`; add `clip()`; rewrite `render_single_lead` as an awk projection over `LANE_ROWS`; collapse warnings |
| `plugins/leadv2/scripts/leadv2-status-surface.5s.sh` | cached detail-row branch: split on first ` · ` only, no reassembly; delete the `sig` sub-row; staleness hardening |
| `tests/test-status-surface-single-lead.sh` | keep all 23 cases green; add the new cases below |
| `tests/test-status-surface-bash32.sh` | keep 12 green; add the ` · `-split parameter-expansion case |
| `tests/test-status-surface-parity.sh` | **(to-create)** the regression that would have caught this drift |

Reads only, never written: `.env`, `~/.claude/cache/dispatch-ledger/*.jsonl`,
`~/.claude/cache/status-surface/*`.

No `claude -p` invocation is introduced (constraint-checklist item 3: N/A).
No env var outside the existing `LEADV2_*` convention is introduced; the one new name,
`LEADV2_SS_CENSUS_SCOPE`, matches the sibling `LEADV2_SS_*` block at
`leadv2-status-surface.sh:1750–1766` (item 1: pass).

---

## 4. Tests

`tests/test-status-surface-parity.sh` (new) — the missing regression:

1. **Same lane set.** One fixture; run `--default` and `--all`; extract the sig8 set from
   the table rows and from the `mode=single-lead` detail rows; assert the two sets are equal.
   This is the test whose absence let A and B drift.
2. **Lead is in neither.** Fixture with an `opus` lead session + one `sonnet` worker.
   Assert `opus` appears in neither output and the header count is 1.
3. **Second repo attributed correctly.** Fixture with a lane under `leadv2` and one under
   `persona-engine`; assert the `--all` detail row for the first ends `· leadv2`.
4. **No empty separators.** Assert `--all` output matches no `· *·` and no line ends `·`.
5. **Fields render when known.** Row with model `glm` and age `16m` → the detail line
   contains `glm 16m`.
6. **Terminal lane excluded.** Ledger row `terminal=dead cause=e2e_regression` → sig absent
   from the detail rows AND the header count does not include it.
7. **Queued not counted.** 1 live + 4 queued → header reads `active 1`; the queued names
   appear only under `queued (4)`.
8. **Truncation is unambiguous.** A 30-char name → output contains `…` and does not contain
   any 24-char prefix of it without `…`.
9. **Warnings collapse.** 5 unreadable repos → exactly one `⚠` line matching
   `⚠ 5 repos: terminals unreadable`; a 6th repo with no lanes adds no line.
10. **Stale cache.** `all.payload` mtime 700 s old → widget title is `⚠️ кэш устарел (11m)`.

Concurrent-access note (checklist item 4): `all.payload` is written by the detached
refresher and read by every 5 s tick. The existing `mv` from `${PAYLOAD}.tmp.$$` is atomic
within a filesystem and `LOCKDIR` serialises writers — no new race. `labels.map` is written
by `_build_labels_map` **after** the `mv`, so a tick between the two reads a fresh payload
against a stale map; today that renders a sig8 for one tick. Acceptable, unchanged, and the
sig8 is now the row's own first field rather than a duplicated sub-row. Recommend
`_build_labels_map` write to `${LABELS}.tmp.$$` and `mv` (it already does — keep it).

Run `tests/test-status-surface-single-lead.sh`, `tests/test-status-surface-bash32.sh`,
`tests/test-status-surface-parity.sh`, `tests/test-status-surface-fast-names.sh`.
`bash -n` + `/bin/bash -n` on both scripts. **Do NOT run `run-core-offline.sh`.**

---

## 5. Risks

| Risk | Mitigation |
|------|------------|
| Moving ~250 lines of census python across a heredoc boundary breaks `_ss_lanes_py`'s existing 23-case behaviour | Census is an **additive row source** merged before classification; if the census set is empty the code path is identical to today. Run the single-lead suite before and after the move and diff `--default` output byte-for-byte on every fixture. |
| `render_single_lead`'s per-repo reservation/terminal indices are richer than `_ss_lanes_py`'s multi-project loop for *foreign* repos | `_ss_lanes_py` already receives each repo's ledger + state dir through `_run_lanes_for_project`. Verify with parity test 3 before deleting producer B's index code. |
| `cls=queued` changes `LIVE_N`, which `emit_lanes_table`'s header prints and the statusline parses | `emit_lanes_table` keeps printing the same header tokens; add `%d queued` only when `QUEUED_N > 0`, mirroring the existing `%d скрыто по возрасту` conditional. Assert the zero-queued header is byte-identical. |
| Widget's SYNC branch and CACHED branch converge → the fixture suite's `active`/`closing` greps may now match in both | Intended. Assert both branches produce the same detail text (parity test 1 covers it). |
| bash 3.2: `${var%% · *}` with a multibyte `·` | `·` is UTF-8 in the literal and pattern alike; byte-wise glob matching is safe. Covered by the new bash32 case. |
| Deleting the `sig` sub-row loses the only way to correlate a row to a run dir | The sig8 remains in the `--default` table's SIG column and in `--all`'s table section. Nothing is lost from the payload. |

---

## 6. Out of scope

- Reverting or altering `3afe03a`'s 5 s caching cadence — keep it.
- SwiftBar submenu / expandable warning UI. One collapsed line is the requirement; an
  expander is a follow-up.
- `plugins/leadv2/scripts/tests/` de-duplication (a separate open thread).
- Any change to `emit_oneline`'s format or to the statusline consumers.
- `.env` writes. `.env` is read-only here.
- `run-core-offline.sh`.

---

acceptance:
  - surface: rendered_line
    observable: "In the SwiftBar dropdown, the lane row for MENUBAR-PANEL-02 reads its name followed by its phase, model and age separated by single ' · ' marks — no run of empty separators, and no second 'sig <hex>' line beneath it."
    authored_at: 2026-08-04T20:40:00+03:00
  - surface: rendered_line
    observable: "The menu-bar title's lane count equals the number of rows listed under it that are actually running; a lane whose ledger says it is dead is absent from both the number and the list."
    authored_at: 2026-08-04T20:40:00+03:00
  - surface: rendered_line
    observable: "Backlog tasks appear under a separate 'queued (N)' heading in the dropdown and are not part of the running-lane number in the menu-bar title."
    authored_at: 2026-08-04T20:40:00+03:00
  - surface: rendered_line
    observable: "A lane living in ~/Projects/leadv2 shows 'leadv2' as its repo in the dropdown row, not 'persona-engine'."
    authored_at: 2026-08-04T20:40:00+03:00
  - surface: rendered_line
    observable: "A task name too long for the row ends with an ellipsis character, so it can never be read as a shorter, different task id."
    authored_at: 2026-08-04T20:40:00+03:00
  - surface: rendered_line
    observable: "The five separate '⚠ <repo> terminals' rows are replaced by a single line naming how many repos are affected, and repos with no lanes produce no warning line at all."
    authored_at: 2026-08-04T20:40:00+03:00
  - surface: rendered_line
    observable: "When the cached payload is more than ten minutes old the menu-bar title reads '⚠️ кэш устарел' with the age, instead of a confident lane count."
    authored_at: 2026-08-04T20:40:00+03:00
  - surface: file_artifact
    observable: "tests/test-status-surface-parity.sh exists and its run prints a pass line for the case asserting the table output and the --all output describe the same lane set."
    authored_at: 2026-08-04T20:40:00+03:00

LANE_WRITES: plugins/leadv2/scripts/leadv2-status-surface.sh, plugins/leadv2/scripts/leadv2-status-surface.5s.sh, tests/test-status-surface-single-lead.sh, tests/test-status-surface-bash32.sh, tests/test-status-surface-parity.sh

DELIVERABLE_COMPLETE
