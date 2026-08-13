# MENUBAR-PANEL-02 — architect prepass

Repo: `~/Projects/leadv2`. Branch only. No commit to main, no push, no merge.

---

## 1. What is actually broken (verified on disk, not inferred)

The mission's three symptoms decompose into **five** independent defects across **two** files.
Two of them are not where the mission guessed. Read this section before writing code — the
"cached payload lost the fields" hypothesis in the mission is wrong, and fixing the payload
would not fix the empty separators.

### D1 — the widget parses ` · `-separated rows with a whitespace-field awk (WIDGET)

`leadv2-status-surface.5s.sh:444-452` (cached reformat branch):

```sh
_s_id="$(printf  '%s' "$_s_trim" | awk '{print $1}')"
_s_arm="$(printf '%s' "$_s_trim" | awk '{print $2}')"
_s_age="$(printf '%s' "$_s_trim" | awk '{print $3}')"
printf '%s · %s · %s | font=Menlo size=12\n' "$_s_label" "$_s_arm" "$_s_age"
```

The renderer emits (`leadv2-status-surface.sh:3207-3210`):

```
  4caee2e8 · worker · opus now · persona-engine        # multi_repo
  4caee2e8 · worker · opus now                         # single repo
```

awk's default FS is whitespace, so `$1=4caee2e8`, `$2=·`, `$3=worker`. The widget then
re-joins them with its own ` · `, producing exactly the founder's line:

```
4caee2e8 · · · worker
```

**The payload is intact. The fields were never lost — the widget threw them away.** The three
"empty" separators are the renderer's own `·` glyphs being re-printed as if they were data.
This is a pure widget-side parse bug and is fixable independently of everything else.

### D2 — two independent lane walks, separately evolved (RENDERER)

The renderer computes lanes **twice**, from different sources, under different invariants:

| | `_ss_lanes_py` (`:538-1745`) | `render_single_lead` (`:2600-3220`) |
|---|---|---|
| Consumed by | `emit_lanes_table` → `--all` §1, default mode, `--oneline` | `--all` §6, `--single-lead` |
| Source | `active.yaml` + ledger join | reservation ledger + **live `ps` census** |
| Terminal retirement | yes — `is_terminal()` + 7200 s age-out (`:1505-1520`) | partial — `_terminal_state()==drop` only |
| Repo attribution | per-project slug from `PROJ_SLUGS` walk (`:1776-1806`) | `_match_reservation()` else **`CUR_REPO` fallback** (`:3105`) |
| Lead exclusion | — | `SUPERVISE_PID` only (`:3084-3088`) |
| Fix lineage | STATUS-SURFACE-R5-01, SWIFTBAR-LIVE-01 | MENUBAR-SHOWS-DEAD-…-01 (`c1e8cbf`) |

The mission says "my tests exercised the table path, the widget consumes `--all`". More
precisely: **`--all` emits BOTH walks** — §1 from the table path (which does carry the fix)
and §6 from `render_single_lead` (which carries a different, older set of invariants). The
widget's single-lead branch reads **§6 only** and never looks at §1. So the fix and the
surface do not meet because the widget reads the walk that did not get it.

This is the drift that must be structurally closed, not patched.

### D3 — repo attribution falls back to the renderer's cwd (RENDERER)

`leadv2-status-surface.sh:3103-3105`:

```python
repo, res_entry = _match_reservation(sig8, census_task_id)
if repo is None:
    repo = CUR_REPO
```

A census-discovered worker with no matching reservation row inherits **whatever repo the
renderer was invoked in**. The refresher (`5s.sh:_kick_refresh`) runs `bash "$RENDERER" --all`
from SwiftBar's inherited cwd, so `CUR_REPO` in the cached payload is not the founder's shell
cwd. `4caee2e8` lives in `~/Projects/leadv2` and renders as `persona-engine` for exactly this
reason. The lane's true repo is recoverable and is being discarded: the census already holds
the worker's argv, which contains the worktree path.

### D4 — the lead is not excluded, and `arm` is not the way to exclude it (RENDERER)

`census_workers` matches `--task-id dispatch-<sig8> [--model <arm>]` and takes `arm` straight
from `--model`. The only identity filter is `SUPERVISE_PID`.

**Trap — do not filter on `arm == "opus"`.** The mission reasons "opus is the LEAD model, not
a worker arm", and that inference is correct about *these* rows but wrong as a *rule*: an
architect prepass is legitimately dispatched at opus (this very lane is one). Filtering by
model would hide real workers and would make the "lead appears in neither output" test pass
for the wrong reason — a lying-green fix.

Exclusion must be **identity-based**: a lane is the lead iff its pid is the lead's pid, its
pid is an ancestor of the renderer process, or it is the supervise sentinel. Model is a
symptom, never a predicate.

### D5 — the cached count is confident because it is produced under a different environment

Founder evidence: cached title `🛠 8: … (9s)` vs live `active 4`. The ` (9s)` suffix proves
the payload was **fresh** — so this is not a staleness-detection failure in the `≥600 s →
⚠️ кэш устарел` sense. The count differed because the refresher's `--all` ran under
SwiftBar's environment (different cwd → different `CUR_REPO`, different `STATE_DIR`,
different `LEDGER_DIR` discovery, minimal `PATH`) and produced a genuinely different lane
set from the same instant.

The existing staleness story (`5s.sh:243-249`) is correct for its own question ("how old is
this?") and needs no change to the threshold. What is missing is **provenance**: nothing in
the payload records which environment produced it, so a wrong-environment payload is
indistinguishable from a right one. The fix is to pin the refresher's environment and stamp
the payload, not to widen the age gate.

Once D2 collapses the two walks into one with D3+D4 applied, the 8-vs-4 gap closes on its
own; the provenance stamp is what keeps it *provably* closed.

### D0 — the drift was possible because nothing tests `--all`

`grep -n -- '--all' tests/test-status-surface-{single-lead,bash32,fast-names}.sh` returns one
hit, and it is a comment in a *fixture* (`fast-names.sh:93`) describing a hand-written payload.
**No test invokes the renderer with `--all`.** Every one of the 23 single-lead cases drives
`--single-lead` or the default table. That is the regression hole; closing it is the first
Done-means item and is more important than any individual defect above.

---

## 2. Design — one lane list, two projections

### 2.1 The shared function

Introduce a single lane computation inside the renderer whose output both `emit_lanes_table`
and `render_single_lead` consume as **projections**. Both existing walks are replaced by one.

Given the two walks read different sources (`active.yaml`+ledger vs ledger+`ps` census), the
merged walk must be the **union** of both discovery paths — dropping the `ps` census would
reintroduce the "idle while a worker runs" bug that census exists to fix, and dropping the
`active.yaml` path would lose lanes with no live process.

Recommended shape — **extend `_ss_lanes_py` to also run the census, and make
`render_single_lead` a formatter over `LANE_ROWS`**, rather than the reverse. Rationale:

- `_ss_lanes_py` already owns the harder invariants (terminal retention, age-out,
  `DONE_RECENT_N`/`AGED_OUT_N` accounting, multi-project slug walk). Porting those into the
  census walk is the larger and riskier move.
- `LANE_ROWS` is already a tab-separated record consumed by three renderers; it is the
  natural canonical form.
- `emit_lanes_table`'s output is byte-frozen by the 23-case suite. Keeping it as the primary
  producer means those 23 cases keep passing by construction, satisfying the mission's
  "must not be weakened" rule.

`LANE_ROWS` gains the fields §6 needs. Current column meaning (from
`leadv2-status-surface.sh:1929-1935`):

| col | single-repo | multi-project (slug prefixed at `:1806`) |
|---|---|---|
| 1 | NAME | PROJ |
| 2 | TYPE | NAME |
| 3 | PHASE/STATE | TYPE |
| 4 | MODEL | PHASE/STATE |
| 5 | AGE | MODEL |
| 6 | STATE | AGE |
| 7 | — | STATE |
| 8/9 | SIG | SIG |

The dual indexing (`$1..$8` vs `$1..$9`) is itself a hazard for a second consumer. **Normalise
`LANE_ROWS` to always carry the project slug in column 1**, single-repo included, and let
`emit_lanes_table` drop it when `MULTI_PROJECT=0`. One index map, one consumer contract.

### 2.2 Interface contract — canonical lane record

| # | field | type | rule |
|---|---|---|---|
| 1 | `proj` | slug | repo the lane's **ledger/worktree** is in — never the renderer's cwd (D3) |
| 2 | `name` | string ≤40 | `lane_label` > `task_id` > `founder_task_id` > mission H1 > `sig8` |
| 3 | `type` | enum | `worker`/`lead`/… — `lead` rows are filtered before projection (D4) |
| 4 | `phase` | string \| `""` | empty means unknown; consumers **must not** print a separator for it |
| 5 | `model` | string \| `""` | verbatim `--model` value; **never** used as an identity predicate |
| 6 | `age` | string | `now`/`Nm`/`Nh` |
| 7 | `state` | enum | `active`/`closing`/`done`/`dead` |
| 8 | `sig8` | 8-hex | always present |
| 9 | `origin` | enum | `census`/`reservation`/`active_yaml` — provenance, for debugging drift |

Empty fields are the empty string, and **rendering an empty field emits nothing — not a
separator**. This is the rule that kills D1 at the source in addition to the widget fix.

### 2.3 Projections

- **table** (`emit_lanes_table`) — unchanged output format; filters `state` per the existing
  retention window; drops col 1 when `MULTI_PROJECT=0`.
- **`--all` §6** (`render_single_lead`) — formats the **same** filtered list. Header count =
  rows with `state != closing`. Detail line built by joining only non-empty fields with ` · `.

Both must be derived from one in-memory list computed once per invocation. If a future
reviewer can point at two places that decide "is this a lane", the fix has not landed.

### 2.4 Widget changes (`leadv2-status-surface.5s.sh`)

1. **Split on ` · `, not whitespace** (D1). Replace the three `awk '{print $N}'` calls with a
   ` · `-aware split. bash 3.2, no `read -a` on a delimiter — use parameter expansion
   (`${line%% · *}` / `${line#* · }`) or `awk -F' · '`. Prefer the former; `awk -F' · '` on a
   multi-byte separator is portable but the parameter-expansion form has no subprocess cost
   on the 5 s render path.
2. **Do not emit empty segments.** Build the output line by appending only non-empty parts.
3. **Demote the `sig` sub-row only when it adds information** (mission ask). Current code
   (`:453-455`) prints `sig <hex>` whenever `_is_sig8 "$_s_id"` — including when
   `_lookup_label` returned the sig8 unchanged (resolver chain step 4 miss), which is pure
   duplication. Guard: emit the sub-row **iff `$_s_label != $_s_id`**.
4. **Provenance** (D5). `_kick_refresh` must pin the refresher's environment — `cd` to a
   determinate root and export the same `LEADV2_STATUS_*` scope the terminal path uses — and
   the payload gains a provenance line the widget can surface when it disagrees with the
   current environment.

### 2.5 Non-goals (implementer: ignore these)

- Reverting or weakening `3afe03a`'s caching. The 5 s cadence stays; the detached refresher,
  the mkdir lock, and the two-file render path all stay.
- Changing the `≥600 s → ⚠️ кэш устарел` threshold or the `(Ns)` age suffix. D5 is a
  provenance problem, not a threshold problem.
- Any change to `render_questions` / `render_limits` / `render_due` / `render_alarms` /
  `render_repo_facts`, or to the legacy/supervisor (non-single-lead) widget branch.
- Any change to `resolve_lane_label`'s four-step chain or to `labels.map`'s format.
- De-duplicating `.claude/scripts/leadv2-status-surface*.sh` or the stale
  `plugins/leadv2/scripts/tests/` tree — separate task, separate blast radius.
- Writing to `.env` (READS only).
- Running `run-core-offline.sh`.

---

## 3. Risks

| # | risk | mitigation |
|---|---|---|
| R1 | Merging the walks regresses one of the 23 frozen single-lead cases | Make `_ss_lanes_py` the producer and `render_single_lead` a pure formatter, so table bytes are unchanged by construction. Run the 23-case suite **before** touching §6. |
| R2 | Dropping the `ps` census while merging reintroduces "idle while a worker runs" | The merged walk is a **union** of census + reservation + `active.yaml`. Add a fixture with a live census-only worker and no reservation row; assert it appears in both outputs. |
| R3 | `arm == "opus"` used as the lead predicate — hides real opus workers, passes the test for the wrong reason | Identity-based exclusion only (pid / ancestor / supervise sentinel). Add a **negative** fixture: a legitimate opus *worker* that must still appear. This is the single most likely way this task lands a lying-green fix. |
| R4 | `LANE_ROWS` column renumbering silently breaks a third consumer | `emit_oneline` (`:1856-1867`) also indexes `$1..$7` with its own dual map. Renumbering is a 3-consumer change — grep every `-F '\t'` awk in the file before editing, and the bash-3.2 suite must cover `--oneline`. |
| R5 | bash 3.2: no `${var^^}`, no `read -a` with delimiter, no associative arrays, no `[[ ]]` | Already the house style in both files. `/bin/bash -n` (the real 3.2) in addition to `bash -n`, per mission. |
| R6 | Widget ` · ` split breaks when a lane label itself contains ` · ` | `resolve_lane_label` clips to 40 chars and strips `|` but **not** `·`. Strip/replace `·` in the label at resolve time, or split from the left with a fixed field count. |
| R7 | SwiftBar's minimal `PATH` means `python3` may be absent on the refresher path | Both files already handle this (`command -v python3` guards). Pinning the refresher env (D5/§2.4.4) must not *narrow* `PATH` further. |
| R8 | Concurrent access: `_kick_refresh` writes `all.payload`+`labels.map` while a 5 s tick reads them | Existing `mv` into place is atomic per-file, but payload and labels are **two** files — a tick between the two `mv`s reads a new payload against an old label map. Order: write `labels.map` first, then `mv` the payload (payload mtime is the freshness signal, so it must be promoted last). Note this explicitly in the implementation. |

---

## 4. Constraint checklist

1. **Env vars** — no new product env vars. Existing seams reused: `LEADV2_STATUS_SYNC`,
   `LEADV2_STATUS_RENDERER`, `LEADV2_STATUS_CACHE_DIR`, `LEADV2_STATUS_CACHE_TTL`,
   `LEADV2_STATUS_LEDGER_DIR`, `LEADV2_STATUS_STATE_ROOT`, `LEADV2_STATUS_AGGREGATE`,
   `LEADV2_STATUS_ACTIVE_YAML`, `LEADV2_STATUS_HANDOFF_DIR`. If lead-identity needs a test
   seam, name it **`LEADV2_STATUS_LEAD_PID`** — `LEADV2_*` prefix, no `LEAD_V2_*` drift.
2. **Paths** — every path in §5 exists on disk except the two marked `(to-create)`.
3. **`claude -p`** — not applicable; this task introduces no `claude -p` invocation.
4. **Concurrent access** — see R8; payload/labels promotion order is a real race, called out.
5. **Config contradiction** — none introduced. `LEADV2_STATUS_AGGREGATE` semantics
   (`!= "0"` → aggregate) must be preserved by the merged walk; it is currently read only in
   `render_single_lead` and must not be lost when that function becomes a formatter.

---

## 5. Files

**Modify**
- `plugins/leadv2/scripts/leadv2-status-surface.sh` — merge the two walks (D2), repo
  attribution from the lane's own ledger/worktree (D3), identity-based lead exclusion (D4),
  never emit a separator for an empty field, normalise `LANE_ROWS` col 1.
- `plugins/leadv2/scripts/leadv2-status-surface.5s.sh` — ` · ` split (D1), no empty segments,
  conditional `sig` sub-row, refresher env pinning + payload provenance (D5), labels-then-payload
  promotion order (R8).

**Tests — modify**
- `tests/test-status-surface-single-lead.sh` — add the `--all`-vs-table parity case, the
  lead-in-neither case, the second-repo attribution case, the no-empty-separator case, and
  R2/R3's negative fixtures. The existing 23 stay green and unmodified.
- `tests/test-status-surface-bash32.sh` — keep 12/12 green; extend for `--oneline` if
  `LANE_ROWS` is renumbered (R4).
- `tests/test-status-surface-fast-names.sh` — its hand-written `--all` fixture (`:93`) must be
  regenerated to the corrected §6 format, or it will encode the bug.

**Do not touch**
- `.claude/scripts/leadv2-status-surface*.sh`, `.claude/worktrees/**`,
  `plugins/leadv2/scripts/tests/**`, `.env`.

---

## 6. Acceptance

```
acceptance:
  - surface: rendered_line
    observable: >
      In the SwiftBar dropdown, each lane row reads as a name followed only by the
      fields that exist — e.g. "MENUBAR-PANEL-02 · worker · opus now · leadv2" — with
      no run of empty "·" separators anywhere in the row, and no second "sig <hex>"
      line under a row that already shows a human name.
    authored_at: 2026-08-04T00:00:00+03:00
  - surface: rendered_line
    observable: >
      The lane the founder is currently talking to the lead in does not appear as a
      row in the SwiftBar dropdown, and is not included in the count shown in the
      menu-bar title.
    authored_at: 2026-08-04T00:00:00+03:00
  - surface: rendered_line
    observable: >
      A lane whose work is happening in ~/Projects/leadv2 shows "leadv2" as its repo
      in the dropdown row, not "persona-engine".
    authored_at: 2026-08-04T00:00:00+03:00
  - surface: rendered_line
    observable: >
      The number in the menu-bar title equals the number of lane rows the founder can
      count in the dropdown beneath it, and both equal the number of lanes shown in
      the lanes table when the same surface is read in a terminal.
    authored_at: 2026-08-04T00:00:00+03:00
  - surface: file_artifact
    observable: >
      Both status-surface suites are pasted in full in the completion report, showing
      every case passing and zero failures, with the single-lead suite's original 23
      cases still present and unmodified.
    authored_at: 2026-08-04T00:00:00+03:00
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-status-surface.sh, plugins/leadv2/scripts/leadv2-status-surface.5s.sh, tests/test-status-surface-single-lead.sh, tests/test-status-surface-bash32.sh, tests/test-status-surface-fast-names.sh

DELIVERABLE_COMPLETE
