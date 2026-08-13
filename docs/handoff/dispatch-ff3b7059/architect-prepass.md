# MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01 — architect prepass

Repo: `~/Projects/leadv2`. All work is inside `render_single_lead()`
(`plugins/leadv2/scripts/leadv2-status-surface.sh`, ~L2600–2928) plus its two fixture suites.
No legacy-mode code (L540–1800) is touched. No implementation here.

---

## 0. Evidence gathered (root causes, not theories)

| # | Symptom | Mechanical root cause | Evidence |
|---|---------|-----------------------|----------|
| A | Hash names (`81ec9717`) instead of `M1A-FACT-QUALITY-01` | Reservation rows populate the human name in **`lane_label`**, and leave `task_id` **empty**. Both name-resolution sites read only `task_id`/`founder_task_id` (L2846, L2872) → always fall through to sig8. | Live rows in `~/.claude/cache/dispatch-ledger/{leadv2,persona-engine}.jsonl`: `"task_id":"", … "lane_label":"MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01"` |
| B | Terminal cross-ref misses | `has_terminal` (L2850) tests `str(task_id) in terminal_task_ids`, but `task_id` at that point is still the **sig8** (because of A), while the terminal ledger stores the **human** name. Only the sig8 arm can ever fire. | L2846 `_res[1].get("task_id") or _res[1].get("founder_task_id")` — both `""` in every live reservation row |
| C | Even a matching lane stays on the list | `state = "closing" if has_terminal else "active"` (L2852). `closing` rows are still appended to `workers` and still counted in `active %d` (L2912/2916). Nothing ever drops them. | L2852, L2912, L2916 |
| D | Terminal authority can be truncated away | Both ledgers are read via `tail -n 400` (L2642). `~/.claude/cache/dispatch-ledger/persona-engine.jsonl` is already **415 lines**. Truncation on the *terminal* side silently manufactures false-actives. | `wc -l`: reservations 415, terminals 295 |
| E | **Lead session counted as a lane** | `codex_census()` (L2731–2765) labels **every** `docs/handoff/*/.session-runner.pid` as `arm: codex`. `leadv2-codex-lead.sh:367` writes that exact filename for the **lead's own** `TASK_ID`. So the lead's own pid file is enumerated as a worker. | `grep -rn "session-runner.pid"` → `leadv2-codex-lead.sh:367`, `leadv2-session-runner.sh:170`, `leadv2-session-spawner.sh:112` all write the same name |
| F | Per-repo blindness | `LEADV2_SL_RESERVATIONS="$LEDGER_FILE"` = `${LEDGER_DIR}/${REPO}.jsonl` and `LEADV2_SL_TERMINALS="${STATE_DIR}/dispatch-ledger.jsonl"` (L2608–2609). Both are scoped to the cwd's repo. | L2608–2609, L206, L48–54 |

There is **no lane journal** carrying `architect_prepass → worker_spawned → review_gate →
dispatch_terminal`. `grep -rn` over `plugins/leadv2/scripts/*.sh` finds none of those tokens as
emitted events, and `<STATE_DIR>/bus.jsonl` last wrote 2026-07-27. **Phase must therefore be
*derived* from artifacts the surface already reads** (§C4). This is stated up front so the
implementer does not go hunting for a file that does not exist.

---

## 1. Layers affected

| Layer | File | Change |
|-------|------|--------|
| Source-selection (bash) | `leadv2-status-surface.sh` `render_single_lead()` env block, L2600–2618 | build a multi-repo source list; pass it to python |
| Ledger read (python) | same heredoc, L2638–2802 | per-source read; terminal tail depth; terminal index on real keys |
| Census (python) | `codex_census()` L2731–2765 | argv corroboration → lead exclusion |
| Row assembly (python) | L2804–2884 | terminal wins; grace-window drop; name resolution; phase derivation |
| Render (python) | L2886–2921 | `<name> · <phase> · <arm> <age> [· <repo>]`; `closing` out of the active count |
| Tests | `tests/test-status-surface-single-lead.sh` | 5 new cases (§4) |
| Tests | `tests/test-status-surface-bash32.sh` | keep T4 green; add the bash-3.2 parse guard for the new code |

**Unchanged / out of scope:** `leadv2-status-surface.10s.sh` (no edit needed — it consumes the
`mode=single-lead` marker, which this design preserves byte-for-byte in position 1–3);
legacy-mode renderer; `leadv2-dispatch-code.sh`; `leadv2-dispatch-ledger.sh`;
`leadv2-codex-lead.sh` (the fix is reader-side by design — see §C3 risk R3); any ledger
*write*; `render_repo_facts()`; `--limits`.

---

## 2. Data flow (numbered)

1. bash resolves `LEDGER_DIR` (`~/.claude/cache/dispatch-ledger`) and `STATE_DIR`, as today.
2. bash derives `STATE_ROOT = ${LEADV2_STATUS_STATE_ROOT:-$(dirname "$STATE_DIR")}`.
3. bash builds a **source list**: the current `REPO` first, then — when
   `LEADV2_STATUS_AGGREGATE` ≠ `0` — every other `${LEDGER_DIR}/*.jsonl` basename.
4. For each repo `R`: `reservations = ${LEDGER_DIR}/R.jsonl`,
   `terminals = ${STATE_ROOT}/R/dispatch-ledger.jsonl`.
   If `terminals` does not exist → repo is marked **unverifiable** and contributes **no active
   rows**, only a warning line (§C1 rule U).
5. bash exports one newline-separated `LEADV2_SL_SOURCES` (`repo\tres_path\tterm_path\tverifiable`).
   `LEADV2_SL_RESERVATIONS` / `LEADV2_SL_TERMINALS` are retained and still describe the current
   repo (back-compat for the existing fixtures).
6. python parses each source: reservations `tail -n 400` (unchanged), terminals
   `tail -n 2000` (§C2 rule T).
7. python builds `term_by_sig`, `term_by_name` (§C2), `res_by_sig`, `res_by_name`.
8. python runs `census_workers(PS_SNAPSHOT)` (unchanged) and the **hardened** `codex_census()`
   (§C3), producing live lanes.
9. Rows are assembled: census lanes first, then unexpired uncovered reservations.
10. Each row gets `name` (§C4), `phase` (§C4), `repo`, `arm`, `age_s`, `state`.
11. Terminal verdict is applied **before** counting (§C2 rule R).
12. Render: header `mode=single-lead active <N> <name> <arm> <age>`, then one detail line per
    row, then any warning lines.

---

## 3. Changes

### C1 — Aggregate across repos, repo visible per row

- New env: `LEADV2_STATUS_AGGREGATE` (`1` default, `0` = current-repo only) and
  `LEADV2_STATUS_STATE_ROOT` (test seam; defaults to `dirname "$STATE_DIR"`).
  Both follow the existing `LEADV2_STATUS_*` convention — checklist item 1 verified against the
  other 12 `LEADV2_STATUS_*` vars in this file. No `LEAD_V2_*` drift.
- **Rule U (unverifiable source):** a repo whose terminal ledger is missing or unreadable
  contributes zero rows and instead emits `  ⚠ <repo> terminals unreadable` as a detail line.
  Rationale: without the terminal authority, that repo's reservations would resurrect closed
  lanes — exactly defect 1 in a new place. This is the direct extension of the "never a confident
  0" principle demanded by the mission. It is also why the current repo's own unreadable ledger
  must keep going through the existing `fail()` path.
- Row rendering carries the repo: `  <name> · <phase> · <arm> <age> · <repo>`.
  Emitted **only when the source list has >1 entry**, so single-repo output and every existing
  fixture assertion stay byte-identical.
- Live check: `~/.claude/cache/dispatch-ledger/` has 6 repos (`feeddark, leadv2, persona-engine,
  replyaud, replyaud2, repro`) but `~/.claude/leadv2-state/` has state dirs for only 2 of them —
  so rule U will fire for 4 repos today. That is correct behaviour and must be asserted in a test,
  not tuned away.

### C2 — Terminal rows are authoritative; finished lanes leave

- **Index (exact keys only, no substring matching):**
  - `term_by_sig[str(row["task_sig"])[:8]] = (ts, row)`
  - `term_by_name[n] = (ts, row)` for each non-empty `n` in
    `{row["task_id"], row["founder_task_id"]}` — whole-string keys, `dict` lookup only.
  - Most-recent `ts` wins per key. `ts` parsed with the existing `epoch()` helper.
- **Lookup for a lane** — try, in order, exact `dict` hits on: `sig8`, resolved `name`,
  reservation `lane_label`. First hit wins. No `in`-substring test anywhere; the mission
  forbids it and it would collide `M1A-FACT-QUALITY-01` with `M1A-FACT-QUALITY-01-FIX`.
- **Rule R (retention):** given a terminal hit at `term_ts`:
  - `now - term_ts <= LEADV2_SL_CLOSING_GRACE_S` (default `300`) → `state="closing"`, row is
    rendered but **excluded from the `active <N>` count**.
  - otherwise → row is **dropped entirely**.
  This is the whole of mission requirement 1: not-active, and eventually gone.
- **Rule T (tail depth):** terminals read at `tail -n 2000`, reservations stay at `400`.
  Asymmetric on purpose: losing an old *reservation* only hides a lane; losing an old *terminal*
  invents one. Documented inline at the `tail_lines` call site.
- `if not workers:` branch (L2886) keeps its existing stale-reservation note and its
  `mode=single-lead active 0` — that path is already honest and T4-covered.

### C3 — The lead session is never a lane

`codex_census()` gains **argv corroboration** against the single `PS_SNAPSHOT` already in scope
(no new subprocess — the 10s tick budget is unchanged):

1. Build `pid -> argv` once from `PS_SNAPSHOT`.
2. For each `.session-runner.pid` found, after the existing `os.kill(pid, 0)` liveness check:
   - argv **not present** in the snapshot → **reject** (cannot prove worker-hood).
   - argv matches `leadv2-codex-lead.sh` → **reject** (this is the lead).
   - argv matches one of `leadv2-codex-session-runner.sh`, `leadv2-session-runner.sh`,
     `leadv2-session-spawner.sh`, or `codex exec` → **accept**.
   - anything else → **reject**.
3. Additionally reject any census pid equal to the pid parsed from
   `<STATE_DIR>/.supervise-active` (first int), for every census pattern, not just codex.

`EPERM` keeps its current presume-alive posture for the `kill` check; argv corroboration is
independent of it.

### C4 — Names and phase

**`lane_name(res_row, term_row, census_entry, sig8)`** — first non-empty of:
`res.task_id` → `res.founder_task_id` → **`res.lane_label`** → `term.task_id` →
`term.founder_task_id` → `census.task_id` (only when it is *not* 8-hex) → `sig8`.
`lane_label` is the field the writers actually populate; adding it is the single fix for defect 4.

**`lane_phase(...)`** — derived, in this precedence:

| Condition | phase |
|---|---|
| terminal hit within grace | `terminal` |
| `<HANDOFF>/dispatch-<sig8>-review/` exists | `review` |
| lane present in the live process census | `worker` |
| `<HANDOFF>/dispatch-<sig8>-architect/` exists | `architect` |
| otherwise (reservation only) | `queued` |

`HANDOFF` = `${LEADV2_SL_PROJECT_ROOT}/docs/handoff` (already exported at L2613); for aggregated
foreign repos `HANDOFF` is unknown → phase degrades to `worker`/`queued` only. That degradation
is honest and must be asserted, not hidden.

**Detail line:** `  <name[:24]> · <phase> · <arm> <age>[ · <repo>]`.
Truncation applies to `<name>` only — phase, arm, age and repo are never cut (mission rule).
Header stays `mode=single-lead active <N> <name[:20]> <arm> <age>` so the `.10s.sh` wrapper and
the badge parser need no change.

---

## 4. Tests (all in `tests/test-status-surface-single-lead.sh` unless noted)

The suite already sandboxes everything (`FIX` tmpdir, `PS_STUB`, `LEADV2_STATUS_*` overrides) —
new cases reuse `widget()`.

1. **T-term** — reservation for sig `aaaaaaaa` + terminal row `{"task_sig":"aaaaaaaa",
   "task_id":"M1A-FACT-QUALITY-01","terminal":"no_work"}` aged 10 min. Assert: no `active 1`,
   row absent from output entirely. Second variant aged 60 s → row present as `closing` and
   header still reads `active 0`.
2. **T-lead** — `PS_STUB` contains a pid whose argv is `leadv2-codex-lead.sh`, and a matching
   `docs/handoff/<id>/.session-runner.pid`. Assert: that id never appears in output.
   Companion positive case: same fixture with argv `leadv2-codex-session-runner.sh` → it *does*
   appear (proves the exclusion is targeted, not a blanket kill of codex lanes).
3. **T-multi** — two ledger files in `$LEDGERS` with two state dirs in `$STATE_ROOT`; a live
   reservation only in repo B. Assert: repo B's lane is visible and its line carries `· repo-b`.
4. **T-unverifiable** — repo C has a reservation ledger but no state dir. Assert: no lane from C
   is rendered as active, and `⚠ repo-c terminals unreadable` is present.
5. **T-name** — reservation with `task_id:""` + `lane_label:"M1A-FACT-QUALITY-01"` and an
   `dispatch-<sig8>-architect` handoff dir → line contains `M1A-FACT-QUALITY-01 · architect`.
   Sibling row with all name fields empty → falls back to the sig8.
6. **`tests/test-status-surface-bash32.sh`** — T4 (dead renderer → failure title, never a
   confident `0/0`) must stay green untouched; add `/bin/bash -n` over the modified surface and
   one `env -i` single-lead render to prove the new bash source-list loop parses and runs under
   the stripped SwiftBar environment.

Run **only**: `tests/test-status-surface-single-lead.sh`, `tests/test-status-surface-bash32.sh`,
`plugins/leadv2/scripts/tests/test-status-surface.sh`, plus `bash -n` and `/bin/bash -n`.
**Do NOT run `run-core-offline.sh`** — ~10 min, budget-fatal.

---

## 5. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | bash 3.2: no associative arrays, no `mapfile`, no `${v,,}` | Source list is a single newline/tab-joined string built with `printf` in a `for` loop over `"$LEDGER_DIR"/*.jsonl`; all indexing happens in python. Guard with `/bin/bash -n` + the `env -i` case in T-bash32. |
| R2 | Aggregation resurrects ancient lanes from a repo with no terminal authority | Rule U: unverifiable repo contributes zero rows + a visible warning. |
| R3 | Reader-side lead exclusion is a heuristic on argv, and could be bypassed by a re-exec that drops the script name | Accepted deliberately: the writer-side alternative (renaming the lead's pid file in `leadv2-codex-lead.sh`) is outside the surface's blast radius and would break `leadv2-fanout.sh:1201` and `leadv2-progress-fingerprint.sh:77`, which both read that path. Mitigation: the rule **default-denies** — unknown argv rejects. A re-exec therefore hides a lane (recoverable, and the reservation branch still shows it) rather than inventing one. Flagged for the orchestrator: a follow-up task should give the lead a distinct sentinel name. |
| R4 | `tail -n 2000` on terminals raises per-tick cost | Terminal ledgers are 295 lines today; `tail` is one already-forked subprocess per source. Aggregation multiplies forks by repo count — capped by the source list being derived from an existing directory glob (6 today). Note the cost in the header comment; if it ever matters, the fix is one `tail` over concatenated paths. |
| R5 | Concurrent access: `dispatch-ledger.jsonl` is appended by `leadv2-dispatch-ledger.sh` under `dispatch-ledger.jsonl.lock` while the surface reads it | The surface is **read-only** and already tolerates a torn final line via the per-line `json.loads` in a `try` that calls `fail()`. Do **not** take the lock in the renderer — a 10s SwiftBar tick must never block a dispatch. A torn tail line must degrade to the existing `⚠ ledger unreadable` marker, never to a confident count. |
| R6 | Changing the detail-line format breaks a downstream parser | Header line format is preserved exactly (`mode=single-lead active <N> …`); only indented detail lines change. Verified: `.10s.sh` and the badge consume the `mode=` marker. |
| R7 | `LEADV2_STATUS_AGGREGATE` semantics colliding with an existing var | Checked: no other `AGGREGATE` env in the file or in `.claude/settings.json`. No contradiction. |

**Checklist item 3 (`claude -p` flags):** not applicable — this change introduces no `claude -p`
invocation.
**Checklist item 2 (paths):** every path referenced exists on disk today except
`${STATE_ROOT}/<repo>/dispatch-ledger.jsonl` for the 4 repos without state dirs, which is
precisely what rule U handles.

---

## 6. Explicit non-goals

- No legacy-mode (`LEGACY_MODE=1`) behaviour change; those fixtures must stay byte-identical.
- No edit to `leadv2-status-surface.10s.sh`.
- No edit to any dispatch/ledger writer, and no ledger writes of any kind.
- No new lane-journal file — phase is derived (§C4), not persisted.
- No `.env` writes; reads only.
- No commit to `main`, no push, no merge — lane branch only.
- No cross-repo *reconciliation* logic; the panel only reads and displays.

---

acceptance:
  - surface: rendered_line
    observable: "The SwiftBar panel's active count and its lane lines contain no lane whose ledger carries a terminal row older than five minutes; a lane closed within the last five minutes is shown marked closing and is not included in the count."
    authored_at: 2026-08-04T16:05:00Z
  - surface: rendered_line
    observable: "The lead's own session no longer appears among the panel's lanes; the panel shows only lanes that a worker process or a live reservation accounts for."
    authored_at: 2026-08-04T16:05:00Z
  - surface: rendered_line
    observable: "A worker running in a different repository than the one the panel was rendered from is visible in the panel, and its line shows that repository's name; a repository whose terminal ledger cannot be read shows a warning line instead of contributing lanes."
    authored_at: 2026-08-04T16:05:00Z
  - surface: rendered_line
    observable: "Each lane line reads as a human task name followed by its phase, arm and age (for example 'M1A-FACT-QUALITY-01 · architect · opus 12m') instead of an eight-character hash; a lane with no recorded name still shows its hash."
    authored_at: 2026-08-04T16:05:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-status-surface.sh, tests/test-status-surface-single-lead.sh, tests/test-status-surface-bash32.sh

DELIVERABLE_COMPLETE
