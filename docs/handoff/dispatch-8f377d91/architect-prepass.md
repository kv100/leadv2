# architect prepass — V3-GLM-LADDER-01 ROUND 2 FINISHER (lane eb2d7143, on 389820a)

Scope: fix C1–C3, H1–H3, M1–M5 from `docs/handoff/dispatch-eb2d7143-review/critic.full.md`.
Design only — no implementation here.

Verified on disk (lane worktree `.claude/worktrees/eb2d7143`, HEAD `389820a`):
- `_glm_park_deferred` :736-816, `cmd_glm_deferred` :818-941, `_codex_credits_watch` :944-998,
  `_arm_exception_bump` :1000-1020, dead `_glm_deferred_is_retried` :710-733.
- park call site :4444 (case 7), Lever-3 bump site :4402-4412 (`candidate == sonnet`).
- the bench path that hides both: the ARM-LADDER-HAS-NO-QUOTA-PRECHECK-01 loop at
  :4205-4228 — `_provider_available` false → `quota_precheck_skip … reason=provider_quota_locked`
  and the arm is dropped from `candidate_arms` **before any attempt**, so `attempted[]` never
  gets a `glm_refused_*` entry.
- `lv2_lock_wait` exists: `plugins/leadv2/scripts/leadv2-portable-lock.sh:24`, sourced at
  `leadv2-dispatch-code.sh:314`; existing idiom at :2060, :2122, :2129, :2242.
- `.gitignore` hunk is present in the working tree but **not** in commit 389820a (4 files, none
  is `.gitignore`) — H1 confirmed.

---

## 1. Semantics decisions (locked — the implementer does not re-litigate these)

**D1 — the counter counts distinct sig8 per UTC day (M4).**
`docs/leadv2/.arm-exceptions-<YYYYMMDD>` grows from 2 lines to:
```
count=<distinct sig8 count>
last_reason=<actual glm_refused_* variant>
sig8=<s1>
sig8=<s2>
```
`count=` stays line 1 and stays the renderer's contract, so `leadv2-broad-status.sh` needs no
change for this field. A repeat bump for an already-present sig8 is a no-op (does not bump, does
not rewrite `last_reason`).

**D2 — "quota" means quota (M3).** Park **and** counter fire only for the quota family:
`glm_refused_quota_gate`, `glm_refused_postspawn_quota`, and the new
`glm_refused_quota_precheck` (D3). `glm_refused_lock_busy` and any other transient refusal park
nothing and bump nothing.

**D3 — the bench path is a first-class refusal (C1).** When the precheck loop drops `glm` because
its provider is quota-locked, that is the *same founder-visible event* as a live refusal and must
produce the same two artifacts. It gets its own reason token `glm_refused_quota_precheck` so the
founder line distinguishes "glm said no" from "glm was benched and never asked".

**D4 — the park queue owns its mission text (C2a).** At park time the mission is copied to
`docs/leadv2/glm-deferred.d/<sig8>.md` (park-owned, gitignored). The row's existing
`mission_path` key now points at that copy — the key name and the `--list`/`--json` output shape
are unchanged, so `leadv2-broad-status.sh` and any human muscle memory keep working. Pointing at
`docs/handoff/dispatch-<sig8>/lane-mission.md` is deleted; that artifact does not exist yet at
refusal time and for a non-product class never will.

**D5 — retry semantics (C2b). `--retry-all` never re-checks the old sig8 as a reason to skip
forever.** Per parked pending row, exactly one of four outcomes, each printed:

| Condition (checked in this order) | Printed | Row after |
|---|---|---|
| ledger has a terminal row for the parked sig8 (the sonnet fallback already did the work) | `reaped <sig8> fallback_landed` | **reaped** (marked `retried_at`, leaves the queue) |
| router-v2 resolve on chain `glm` does not return `eligible=glm` | `still_gated <sig8>` | pending |
| parked mission file missing/empty | `skipped_no_mission <sig8>` | pending |
| dispatch of the parked mission returns rc=0 | `retried <sig8> as=<new-sig8>` | reaped |
| dispatch returns rc≠0 | `retry_failed <sig8> rc=<rc> <last-line-of-child-stderr>` | pending |

The retry dispatches the **parked mission as a brand-new task** (`bash <self> "@<parked mission
file>"`), yielding a new sig8; the old sig8 is never re-dispatched. `already_terminal` as a
"skip and keep counting forever" branch is deleted — a terminal row now *reaps*, which is what
kills the permanent phantom in `отложено на GLM: N`.

**D6 — retire-only-on-success (H3).** `retried_at` is written and the success line printed **only**
after a dispatch returned 0 (or in the `reaped` case), and the append happens **inside** the same
`lv2_lock_wait` critical section as the read of the queue file. Child output is captured, not
discarded; its last line is echoed on the `retry_failed` line (this is the useful half of L4;
`--dry-run` is out of scope).

**D7 — no new env vars, no new flags.** `--retry-all` gains no `--force` / `--dry-run`. The four
outcomes above are enough to satisfy the review.

---

## 2. Changes, file by file

### 2.1 `plugins/leadv2/scripts/leadv2-dispatch-code.sh`

| # | Finding | Change |
|---|---|---|
| a | M1 | delete `_glm_deferred_is_retried` (:710-733) entirely — zero callers, logic already inline in 3 places. |
| b | D4/C2a | add helper `_leadv2_glm_deferred_mission_path() { printf '%s/docs/leadv2/glm-deferred.d/%s.md' "${PROJECT_ROOT}" "${1}"; }` next to the other 3 path helpers. |
| c | C2a | `_glm_park_deferred` takes a 3rd arg `mission_text`. It `mkdir -p`s `glm-deferred.d/`, writes the text to `<sig8>.md`, and sets the row's `mission_path` to that file. Empty text → file not written, `mission_path=""`. Delete the `docs/handoff/.../lane-mission.md` probe. |
| d | M3/D2 | park gate at :4444 narrows from `glm_refused_*` to the quota family only. |
| e | C1/D3 | in the precheck loop (:4210-4226), when the skipped arm is `glm`: set a `cmd_resolve`-scoped local `_glm_quota_benched=glm_refused_quota_precheck` and call `_glm_park_deferred "${sig8}" "glm_refused_quota_precheck" "${mission}" \|\| true`. Nothing else in that loop changes — the `quota_precheck_skip` emit, the all-locked rollback and `candidate_arms` filtering are untouched. |
| f | C1/M2/D1 | Lever-3 bump site (:4402-4412): fire when `attempted[]` holds a **quota-family** `glm_refused_*` entry **or** `_glm_quota_benched` is non-empty; pass the actual variant as the reason and the `sig8` as a new 2nd arg: `_arm_exception_bump "${_reason}" "${sig8}"`. |
| g | D1 | `_arm_exception_bump` takes `<reason> <sig8>`; reads the existing `sig8=` set, returns early if present, else appends and recomputes `count=` as the number of distinct `sig8=` lines. Atomic `.tmp` + `mv` as today. |
| h | C2b/H3/D5/D6 | rewrite the `retry-all` branch per the table in D5. |
| i | H2 | replace all four `flock 8` + `8>"…lock"` subshells (:773, :934, :971, :1007) with the repo primitive, copying the idiom already used at :2060/:2122/:2129/:2242: `lv2_lock_wait "${path}.lock" 10 \|\| return 0` (and its matching release), no fd-8 redirection. fd 9 stays untouched. |
| j | M5 | delete `local -a pending_sig8s pending_missions` (:874) and `local _line` (:905). |

**Off-limits invariants preserved:** no line inside the quota-gate/reorder block, `candidate_arms`
ordering, ladder, or ceiling changes; no new `LEADV2_*`/`PE_*` read; `spawn_product_close` call
signature untouched.

### 2.2 `plugins/leadv2/scripts/leadv2-broad-status.sh`
M4 — `glm_deferred_count` (:68-71) dedups by sig8, newest row wins, so a task parked twice counts
once. The `sonnet-фолбэков сегодня:` renderer is unchanged (it reads `count=`, D1 keeps that key).

### 2.3 `.gitignore` (H1)
Commit the three existing working-tree lines **in this lane's commit**, plus:
```
docs/leadv2/glm-deferred.d/
docs/leadv2/*.lock
```
`docs/leadv2/*.lock` covers `glm-deferred.jsonl.lock`, `.codex-credits-empty.stamp.lock`,
`.arm-exceptions-*.lock` in one rule. After the commit, a probe run must leave the tree clean.

### 2.4 `plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh`
**Harness fix first (C1, the lying-green part):** delete the per-run `LEADV2_DISPATCH_CACHE_DIR`
workaround in `run_c` (:201-219) and its 8-line comment; all `run_c` calls share one cache dir.
Leg (c) (credit watchdog) must stay green — it asserts journal lines emitted in `cmd_resolve`
independently of which arm wins — and if it does not, that is a real finding, not a reason to
restore the workaround.

New legs, each proven red against `git show 389820a:` versions of the two production scripts by
the same scratch-dir method the round-1 suite already documents:

- **(e) shared-cache double refusal.** Two dispatches, ONE `LEADV2_DISPATCH_CACHE_DIR`, refusing
  glm stub. Assert: `.arm-exceptions-<day>` has `count=2`; `glm-deferred.jsonl` holds **2 rows,
  one per distinct sig8**; run 2's row carries `reason":"glm_refused_quota_precheck"`. (Semantics
  chosen and asserted, per acceptance: 2 rows, not 1-row-plus-dedup.)
- **(e2) same-sig8 idempotence.** A second bump for a sig8 already in the file leaves `count`
  unchanged.
- **(f) real retry-all.** Park a row with a real parked mission under `glm-deferred.d/`, no ledger
  terminal row, router-v2 stub returning `eligible=glm`, fixture launcher that touches a marker
  file. Assert: marker exists (a NEW dispatch happened), output matches `retried <sig8> as=`, and
  `glm-deferred --list` no longer shows the sig8.
- **(g) reap.** Park a row whose sig8 has a `landed` terminal row. Assert `reaped <sig8>` and the
  row is gone from `--list`.
- **(h) no-mission negative.** Park a row with `mission_path:""`. Assert `skipped_no_mission` and
  the row is **still** in `--list` (the H3 data-loss case).
- **(i) failed dispatch negative.** Fixture launcher exits 1. Assert `retry_failed` and the row is
  still pending.

The `--retry-all` invocations must carry the same hermetic env as the dispatch legs
(`LEADV2_DISPATCH_GLM_BIN`, `LEADV2_DISPATCH_SUBSESSION_BIN`, `LEADV2_ROUTER_V2_BIN`,
`LEADV2_JOURNAL_BIN`, `LEADV2_DISPATCH_CACHE_DIR`) — the child dispatch inherits them — and the
existing poison fence must stay armed across every new leg.

---

## 3. Data flow (numbered)

1. `cmd_resolve` builds `candidate_arms`.
2. Precheck loop: glm's provider quota-locked → `quota_precheck_skip` emitted, glm dropped,
   **`_glm_quota_benched` set + park row + mission copy written** (new, D3/C1).
3. Otherwise glm is attempted; case 7 refusal → `attempted[]` gains `glm_refused_<variant>`;
   quota-family variant → park row + mission copy (existing site, narrowed by D2).
4. Ladder falls through to sonnet; on the sonnet-landed branch the counter bumps once per
   distinct sig8 with the real variant (D1/M2/C1).
5. `leadv2-broad-status.sh` renders `sonnet-фолбэков сегодня: <count> (<last_reason>)` and
   `отложено на GLM: <distinct pending sig8s>`.
6. Human runs `dispatch glm-deferred --retry-all` → per row, one of the five D5 outcomes; reaped
   rows disappear from step 5's count permanently.

## 4. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Parking at bench time also parks tasks that then hit `dispatch_rolled_back` (all arms locked) — nothing ran. | Correct by design: those are exactly the tasks worth retrying. `--retry-all` finds no terminal row → real re-dispatch. |
| Retry re-runs work a sonnet fallback already completed. | The terminal-row reap (D5 row 1) is checked **first**, so a landed fallback is never re-dispatched. |
| Concurrent lanes (3–4 in flight) racing `glm-deferred.jsonl` / `.arm-exceptions-*` read-modify-write. | H2's `lv2_lock_wait … 10` on every one of the four sections, plus the existing `os.replace`. The 10 s bounded wait also removes the indefinite-hang contradiction with the diff's own ":702 never abort cmd_resolve" comment. |
| `glm-deferred.d/` mission files accumulate. | Bounded by the existing 500-row / 7-day truncation *only if* the truncation also unlinks the dropped rows' mission files — implementer must extend the truncation python to do so. |
| Changing the `.arm-exceptions` file format breaks the renderer. | `count=` stays line 1, key unchanged (D1); the (d) rendered-artifact leg re-proves it. |
| Removing the `run_c` cache workaround turns leg (c) red for an unrelated reason. | Leg (c) asserts journal lines from `_codex_credits_watch`, which runs before arm selection; if it still goes red, report it rather than re-adding the workaround. |

## 5. Out of scope / non-goals
- L1 (writer/reader `PROJECT_ROOT` env-precedence asymmetry), L2 (`_truncated` sentinel
  accumulation), L3 (weak (d)-negative leg), and the `--dry-run` half of L4 — all optional, all
  deferred.
- Routing order, ladder, ceilings, `candidate_arms` composition — untouched by construction.
- `leadv2-dispatch-product-close.sh`, `supervise*` — off limits.
- No new env vars, no new subcommand flags.
- Anything under `docs/leadv2/` or `docs/handoff/` as a *tracked* artifact.

## 6. Self-check (mandatory checklist)
1. **Env var naming** — no new env var introduced; every var read is pre-existing `LEADV2_*`. PASS.
2. **File paths** — all cited paths verified on the lane worktree; `docs/leadv2/glm-deferred.d/`
   is `(to-create)` at runtime. PASS.
3. **`claude -p`** — none introduced. N/A.
4. **Concurrent access** — the park file, the mission dir and the daily counter are written by
   parallel lanes; addressed by H2's `lv2_lock_wait` on all four sections (risk table). PASS.
5. **Config contradiction** — `.gitignore` is the only config touched; the added rules are
   additive and cover the `.lock` files no rule matched. PASS.

## acceptance:
```yaml
acceptance:
  - surface: file_artifact
    observable: >
      After two glm-quota-refused dispatches that share one dispatch cache directory,
      docs/leadv2/.arm-exceptions-<UTC-day> opens with "count=2" and lists two different
      eight-character sig8 lines, and docs/leadv2/glm-deferred.jsonl holds one park row per
      those two sig8s.
    authored_at: 2026-08-20T00:55:00Z
  - surface: rendered_line
    observable: >
      docs/leadv2/founder-status.md shows the sonnet-fallback line reading
      "sonnet-фолбэков сегодня: 2 (glm_refused_quota_precheck)" for that same day —
      the real refusal variant, not the hardcoded "glm quota".
    authored_at: 2026-08-20T00:55:00Z
  - surface: file_artifact
    observable: >
      docs/leadv2/glm-deferred.d/<sig8>.md exists at park time and contains the founder's
      mission text verbatim; the park row's mission_path names that file instead of an
      empty string.
    authored_at: 2026-08-20T00:55:00Z
  - surface: log_line
    observable: >
      "dispatch glm-deferred --retry-all" on a parked row with a usable mission and an open
      quota window prints "retried <old-sig8> as=<new-sig8>", a fresh lane dispatch is
      observable for the new sig8, and a following "glm-deferred --list" no longer shows the
      old sig8. On a row whose fallback already landed it prints "reaped <sig8> fallback_landed"
      and the row likewise disappears. On a row with no mission it prints
      "skipped_no_mission <sig8>" and "--list" still shows that row.
    authored_at: 2026-08-20T00:55:00Z
  - surface: log_line
    observable: >
      The glm-deferred-ladder suite ends with "glm-deferred-ladder suite: FAIL=0" including the
      new shared-cache and retry-all legs, the lane-placement-pin suite reports 24 passed / 0
      failed, and shellcheck at -S warning reports no SC2034 on the changed scripts.
    authored_at: 2026-08-20T00:55:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-broad-status.sh, plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh, .gitignore

DELIVERABLE_COMPLETE
