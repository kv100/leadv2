# SWIFTBAR-SINGLE-LEAD-01 — architect prepass

Scope: retune the SwiftBar menu-bar widget so it tells the truth in single-lead mode
(supervisor paused). Terse scoped design. No implementation here.

---

## 0. Ground truth found on disk (corrects three premises in the mission)

| Mission premise | Reality on disk | Consequence |
|---|---|---|
| "SwiftBar chain: collector → snapshot → render → surface → surface.10s" | **Two independent chains.** `collector.sh → docs/leadv2/status-snapshot.json → render.sh` feeds the lead's `[STATUS]` text pulse. `surface.10s.sh → surface.sh --all` is the SwiftBar chain and **never opens the snapshot** — it reads state dirs and ledgers directly. | `surface.sh` must gain a snapshot reader to satisfy req 2(b). This is the single largest new surface in the change. |
| "newest **non-terminal row** of `~/.claude/leadv2-state/<repo>/dispatch-ledger.jsonl`" | That file is the **terminal-only, write-once** ledger (`leadv2-dispatch-ledger.sh:19`). All 299 rows carry `terminal ∈ {landed,dead,parked,refused,no_work}`. A non-terminal row **does not exist** there. Fields are `sig8`-keyed; there is no `arm` and no `state`. | Req 2(a) as literally written is unsatisfiable. See §2 for the join that does deliver "task sig, arm, state, age". |
| (implicit) one ledger | Two: the **reservation** ledger `~/.claude/cache/dispatch-ledger/<repo>.jsonl` (`LEDGER_DIR`, surface.sh:55) carries `task_sig` (64-char), `arm`, `state`, `ts`, `handle`, `lane_label`; and the terminal ledger above. | "ACTIVE dispatch" = reservation with no terminal row. |

Verified sample (persona-engine): 390 reservation rows, `state` is `confirmed` for
100% of them (there is no other value in practice); 194 distinct terminal `sig8`s;
naive join leaves **220 "open"** reservations — nearly all abandoned. A design that
prints "the newest open reservation" with no recency bound would render an August-1st
corpse as 🛠 ACTIVE. That is the lying-green shape pointing the other way, and §2
bounds it.

Current machine state: **no `.supervise-active` exists anywhere** under
`~/.claude/leadv2-state/*/` — single-lead mode is the live case today, not a
hypothetical.

---

## 1. Mode detection (req 1)

`surface.sh` already computes `SUP_STATE ∈ {on,off,stale}` over the union of
enumerated projects (`SUP_DIRS`, surface.sh:266–450) and already flags an unreadable
`active.yaml` by rendering `lanes (⚠ …)`.

```
SINGLE_LEAD = 1  iff  SUP_STATE != "on"  OR  <sessions list in active.yaml is empty>
SINGLE_LEAD = 0  otherwise   → legacy lanes view, byte-identical to today
```

Emit `SINGLE_LEAD` as a global in `surface.sh` and **publish it on the wire** so the
badge does not re-derive it (the SWIFTBAR-LIVE-01 lesson at surface.10s.sh:133 —
"two derivations of one quantity always drift"): the new section 6 header line
carries `mode=single-lead|lanes` as its first field, and `surface.10s.sh` reads that
field, never `SUP_ON`.

Override for tests: `LEADV2_STATUS_SINGLE_LEAD=1|0` forces the branch.

---

## 2. ACTIVE dispatch derivation (req 2a)

Pure-python inside `surface.sh` (new `render_single_lead()`), reading two files:

1. `R` = rows of `${LEDGER_DIR}/<repo>.jsonl` (reservations), newest-first by `ts`.
2. `T` = set of `task_sig` values in `<STATE_DIR>/dispatch-ledger.jsonl` (terminal;
   these are `sig8`).
3. A reservation `r` is **open** iff `r.task_sig[:8] ∉ T`.
4. Bound it: only rows with `now - r.created_epoch <= ACTIVE_TTL` are eligible.
   `ACTIVE_TTL = ${LEADV2_STATUS_ACTIVE_TTL_S:-7200}` (2h).
5. ACTIVE = the newest eligible open row. Render
   `active <sig8> arm=<arm> state=<state> age=<Nm>`.
6. No eligible row → `active none`. If an open row exists but is older than the TTL,
   render `active none (last open <sig8> <Nh> ago, no terminal row)` — visible, but
   never counted as active. Silence there would be the false-idle failure.
7. Either file unreadable/corrupt → `active ⚠ ledger unreadable: <reason>` and the
   badge raises ⚠ (req 4).

`repo` slug resolution reuses `LEADV2_STATUS_REPO` (already defined, surface.sh:32).

---

## 3. repo_facts on the SwiftBar path (req 2b)

`surface.sh` gains a snapshot reader used **only** for repo_facts:

- Path: `${LEADV2_STATUS_SNAPSHOT:-<PROJECT_ROOT>/docs/leadv2/status-snapshot.json}`,
  `PROJECT_ROOT` from git toplevel as elsewhere in the file.
- Render **every** key of `sections.repo_facts.data` generically as `key: value`
  (JSON-dumped scalar), mirroring `render.sh:133-145`. **Zero repo-specific logic in
  the plugin** — this is the hard constraint; the repo's
  `.claude/leadv2-overrides/status-collector-facts.sh` owns content.
- `sections.repo_facts.ok == false` → `repo facts: не удалось измерить`.
- Snapshot missing → emit nothing (a repo with no facts hook is not an error).
- Snapshot present but unparseable → `repo facts: ⚠ snapshot corrupt` **and** the ⚠
  title path (req 4). Missing ≠ corrupt; collapsing them is the bug this whole task
  exists to stop.
- Staleness: if `collected_at` is older than
  `${LEADV2_STATUS_SNAPSHOT_MAX_AGE_S:-900}`, prefix the block with
  `repo facts ⚠ stale Nm` — a stale fact shown as current is worse than no fact
  (render.sh's own stated rule).

---

## 4. Wire contract — the `--all` positional trap

`surface.10s.sh` slices `--all` output by **ordinal** (`_sec N`, surface.10s.sh:108).
Sections 1..5 are lanes / questions / limits / due / alarms. Inserting anywhere but
the end silently reassigns every downstream section and breaks the existing tests.

**Decision: append only.**

```
--all emits (unchanged order 1-5):
  1 lanes  ---  2 questions  ---  3 limits  ---  4 due  ---  5 alarms
  ---  6 single_lead   (NEW)
  ---  7 repo_facts    (NEW)
```

Dropdown order in `surface.10s.sh` is a *print-time* reordering of these blocks and
is independent of emit order. Required dropdown order (req 2):

```
ACTIVE dispatch (sec 6) → repo facts (sec 7) → SD due (sec 4)
  → limits (sec 3) → questions (sec 5→ existing Q_BLOCK, sec 2) → Refresh
```

(Note: mission lists "(d) provider limits" and "(e) pending questions"; sections 3
and 2 respectively. Alarms/sec-5 stay at the tail as today.)

Section 6 line format (single, parse-stable, label-position-anchored like the lanes
header parse):

```
mode=single-lead active <sig8> arm=<arm> state=<state> age=<Nm>
mode=single-lead active none
mode=single-lead active ⚠ <reason>
mode=lanes
```

New standalone modes `--single-lead` and `--repo-facts` are added to the `case` at
surface.sh:186 and the dispatch at :2413 so each block is testable in isolation
without slicing `--all`.

---

## 5. Title priority (req 3) — `surface.10s.sh`

Applies **only** when section 6 says `mode=single-lead`; the `mode=lanes` branch runs
today's code path untouched.

| # | Condition | Title |
|---|---|---|
| 1 | section 6 = `active ⚠ …` **or** section 7 = `⚠ snapshot corrupt` **or** `--all` rc≠0 / empty | `⚠️ <what> не прочитан` |
| 2 | `Q_N > 0` | `❓N` |
| 3 | any repo_facts key matching `*_alarm` with a truthy value (not `false`/`null`/`0`/`""`/`[]`/`{}`) | `🔴 N` |
| 4 | section 6 has an active dispatch | `🛠 <sig8> <arm> <age>` |
| 5 | else | `⚪ idle` |

Priority 1 is unconditional and pre-empts everything: an unreadable input must never
render as ⚪ idle. ⚪ idle is a **claim** — it may only be printed when both the
reservation ledger and the terminal ledger were read successfully. If the snapshot is
merely *absent* (no facts hook), that is a known-empty, not a failure, and ⚪ is
honest.

The `⚪ sup OFF · ` prefix (surface.10s.sh:169) is **dropped** in single-lead mode —
"sup OFF" is the normal state now, not news. The prefix logic stays intact on the
`mode=lanes` branch (existing regression contract).

---

## 6. Collector change (req 5) — `leadv2-status-collector.sh`

Add one section via the **existing** `_sc_run_section` isolation helper (that helper
is exactly the required guard; do not hand-roll a new one):

```
_sc_single_lead_section()  →  _sc_run_section "single_lead" _sc_single_lead_section
```

Emits one JSON object:

```json
{
  "supervise_active": true|false,
  "supervise_active_path": "<path or null>",
  "ledger_tail": [ {"task_sig","arm","state","ts","lane_label"}, ... ],   // last 20
  "ledger_path": "<path>",
  "ledger_ok": true|false
}
```

This feeds `render.sh`'s text `[STATUS]` pulse. It is **not** on the SwiftBar path —
`surface.sh` derives its own active-dispatch from the ledgers directly (§2), because
the badge refreshes every 10s and the collector runs on a multi-minute timer; sourcing
the badge from a 15-minute-old snapshot would reintroduce staleness at the exact
surface this task is fixing. Two consumers, one file each, no shared staleness.

`render.sh` is **not** in the write set, so it will not render `single_lead` yet — the
section lands in the snapshot for the follow-up. Flagged in §9.

---

## 7. Files and what changes in each

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-status-surface.sh` | `SINGLE_LEAD` detection; `render_single_lead()`; `render_repo_facts()`; snapshot reader; `--single-lead`/`--repo-facts` modes; append sections 6+7 to `--all` |
| `plugins/leadv2/scripts/leadv2-status-surface.10s.sh` | `_sec 6`/`_sec 7`; mode branch; single-lead title ladder; dropdown reorder; legacy branch untouched |
| `plugins/leadv2/scripts/leadv2-status-collector.sh` | `single_lead` section via `_sc_run_section` |
| `plugins/leadv2/scripts/leadv2-status-render.sh` | Touched only if needed for `bash -n` parity; **no behaviour change required by this task** (see §9) |

House rules that bind the implementer (both surface files state them in-file):
POSIX `[ ]` tests only, no `[[ ]]`; `printf '%s'` only, never `printf "$var"`
(repo_facts values are hook-authored and may contain `%` and `|`); strip `|` from
every value printed into a SwiftBar row.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| Ordinal `--all` contract breaks | Append-only (§4); existing sections 1–5 keep their indices; run the existing `plugins/leadv2/tests/` surface tests |
| 220 stale open reservations render as ACTIVE | `ACTIVE_TTL` bound + explicit "last open … no terminal row" line (§2) |
| `state` is always `confirmed` → the field is decoration | Render it anyway (mission asks), but never *branch* on it; branch on the terminal-join + TTL |
| Two ledgers with different sig widths (64 vs 8) | Join on `task_sig[:8]`; verified against live data |
| repo_facts value contains `\|` or `%` | `tr -d '\|'` + `printf '%s'`; no `printf "$var"` |
| Snapshot absent conflated with corrupt | Distinct branches, distinct titles (§3, §5) |
| `surface.sh` is multi-project; snapshot is single-repo | Snapshot read is scoped to `PROJECT_ROOT`/`LEADV2_STATUS_SNAPSHOT` only, and only reached in single-lead mode where one repo is in play |
| Collector's new section slows the timer | It is two file reads + a tail; `_sc_run_section` already isolates failure and timeout risk is nil |
| Concurrent access: collector `mv`s the snapshot while `surface.sh` reads it | Collector writes tmp+`mv` (atomic rename) — reader either sees old or new, never a torn file. No lock needed. Documented, not changed. |

Env-var check: all new knobs use the `LEADV2_*` prefix
(`LEADV2_STATUS_ACTIVE_TTL_S`, `LEADV2_STATUS_SNAPSHOT`,
`LEADV2_STATUS_SNAPSHOT_MAX_AGE_S`, `LEADV2_STATUS_SINGLE_LEAD`) — consistent with the
existing `LEADV2_STATUS_*` family; no `LEAD_V2_*` form introduced. No `claude -p`
invocation in this change.

---

## 9. Non-goals / out of scope

- No repo-specific facts **content** — the plugin stays generic; content is the
  repo's `status-collector-facts.sh` hook.
- No `leadv2-reply-router.sh` change; copy-reply rows keep their
  clipboard-only safety property.
- No launchd/cron/timer changes.
- No change to the legacy `mode=lanes` rendering path.
- `render.sh` does **not** learn to display the new `single_lead` snapshot section in
  this task (write-set constraint). Follow-up.
- **No persistent regression test file.** The write set forbids new files, so the
  fixture test runs from `/tmp`. The repo has `plugins/leadv2/tests/` and every prior
  surface round left a test behind; not doing so here means the single-lead title
  ladder has no standing guard. Recommend a follow-up to land
  `plugins/leadv2/tests/test-swiftbar-single-lead.sh`.

---

## 10. Acceptance

```yaml
acceptance:
  authored_at: 2026-08-02T18:05:00Z
  - surface: rendered_line
    observable: >
      With no .supervise-active on the machine and no open dispatch reservation
      inside the TTL, the SwiftBar menu-bar title reads "⚪ idle" and the dropdown's
      first block reads "active none" — the words "sup OFF" and the 🟢/🔴 lane
      counters are absent from the title.
  - surface: rendered_line
    observable: >
      With a reservation row written seconds ago and no matching terminal row, the
      menu-bar title reads "🛠" followed by the 8-character task signature, the arm
      name, and an age in minutes; the dropdown's first block shows that same
      signature with "arm=" and "state=" on one line.
  - surface: rendered_line
    observable: >
      With one pending founder question outstanding, the title reads "❓1" and it
      wins over the 🛠 an active dispatch would otherwise show.
  - surface: rendered_line
    observable: >
      With the reservation ledger replaced by unparseable bytes, the title begins
      with the ⚠ warning glyph and names what could not be read; neither "⚪ idle"
      nor a green/red count appears anywhere in the title.
  - surface: rendered_line
    observable: >
      With a repo_facts key whose name ends in "_alarm" set to a truthy value in the
      snapshot, the title reads "🔴" with a count, and the dropdown's repo-facts
      block lists that key and its value verbatim alongside every other repo_facts
      key the snapshot carries.
  - surface: file_artifact
    observable: >
      After the collector runs, docs/leadv2/status-snapshot.json contains a
      "single_lead" entry under "sections" holding a supervise_active flag and a
      ledger tail, and every previously present section is still there.
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-status-surface.10s.sh, plugins/leadv2/scripts/leadv2-status-surface.sh, plugins/leadv2/scripts/leadv2-status-render.sh, plugins/leadv2/scripts/leadv2-status-collector.sh

DELIVERABLE_COMPLETE
