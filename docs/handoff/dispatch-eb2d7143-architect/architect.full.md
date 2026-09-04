# V3-GLM-LADDER-01 — architect prepass (design only, no implementation)

Task: dispatch-eb2d7143-architect · role: architect · repo: `~/Projects/leadv2` (plugin source)
`docs/handoff/dispatch-eb2d7143-architect/context.yaml` does not exist — no `decisions`/`off_limits`
beyond the ones stated in the mission text; those are treated as binding.

## 0. Discovery — what is actually on disk (verified this run)

All line numbers below are from the working tree at prepass time; they are anchors, not contracts.
The implementer must re-locate by the quoted marker string, not by number.

| Fact | Anchor (verified) |
|---|---|
| glm refusal sets `LAST_ARM_OUTCOME="glm_refused_${refusal}"` and `return 2` from `spawn_worker` | `leadv2-dispatch-code.sh:2552-2556` |
| candidate loop's refusal branch — `7)` arm, already special-cases `glm_refused_quota_gate` and re-resolves the chain | `leadv2-dispatch-code.sh:4093-4130` (`_reordered_after_quota_gate`) |
| route_headroom computation site A (initial) — emits `route_headroom_chosen … credits=${v2_credits}` | `leadv2-dispatch-code.sh:3980-3985` |
| route_headroom computation site B (after glm quota gate) — emits the same row with `credits=${_qg_credits}` | `leadv2-dispatch-code.sh:4128` |
| successful-launch branch (arm actually landed) — `emit decision "route_resolved …"` then `exit 0` | `leadv2-dispatch-code.sh:4068-4091` |
| subcommand dispatch `case` at file tail | `leadv2-dispatch-code.sh:4407-4416` |
| `queue_md` built deterministically in the renderer's python block | `leadv2-broad-status.sh:449-467` |
| `tail_facts` (incl. `repo_facts`) assembled and handed to a **Haiku** two-line writer | `leadv2-broad-status.sh:469-478`, `520-531` |
| `repo_facts` originates from a **per-repo override hook** `collect_repo_facts()` in `status-collector-facts.sh` | `leadv2-status-collector.sh:181-192` |
| SUITE_DEFS array + row format `"<name>\|\|\|bash $TEST_DIR/<script>"` | `tests/run-core-offline.sh:175-188, 227` |
| `.gitignore` already ignores `docs/leadv2/.pulse-*` and `docs/leadv2/.broad-status-prev.json` | `.gitignore:16-17` |

### D0 — mission correction, stated up front (architect self-check, item 5)

The mission says the credit watchdog should "surface it in the beat/founder-status facts
(repo_facts)". **`repo_facts` is the wrong surface** and this design deliberately does not use it,
for two independent reasons:

1. `repo_facts` is *repo-owned*, not plugin-owned: it is populated only if the host repo defines
   `collect_repo_facts()` in `.claude/leadv2-overrides/status-collector-facts.sh`
   (`leadv2-status-collector.sh:188`). Writing a plugin fact into it would make a plugin invariant
   depend on a per-repo override existing — the same class of defect as a plugin file being copied
   into a repo.
2. Everything in `tail_facts` reaches the founder **only through the Haiku two-line writer**
   (`leadv2-broad-status.sh:520-531`). That writer is not reliable: the beat published at
   `2026-08-19T22:43:42Z` — the one on screen for this very session — ends with
   `дельта недоступна в этом beat (Haiku-читалка не ответила)`. Routing a
   *degradation-visibility* signal through a component that is itself frequently degraded
   reproduces the exact incident this task exists to fix.

**Decision D0:** both the credit-watchdog line and the sonnet-exception counter render through the
**deterministic** `queue_md` block (`leadv2-broad-status.sh:449-467`), which is pasted verbatim into
`founder-status.md` and does not pass through any LLM. `tail_facts` gets the same values as a
*secondary*, machine-readable copy (new key `provider_health`), never as the only path.

## 1. Layers affected

```
leadv2-dispatch-code.sh          (writer)   — parks refused glm tasks, counts sonnet exceptions,
                                              emits the deduped credit-empty journal line,
                                              owns the new `glm-deferred` subcommand
docs/leadv2/glm-deferred.jsonl   (state)    — append-only park file, plugin-owned runtime artifact
docs/leadv2/.arm-exceptions-<YYYYMMDD>      — daily counter file, plugin-owned runtime artifact
docs/leadv2/.codex-credits-empty.stamp      — 24h dedup stamp for the watchdog
leadv2-broad-status.sh           (reader)   — renders both into queue_md + tail_facts.provider_health
tests/test-glm-deferred-ladder.sh (new)     — red-first, rendered-probe based
tests/run-core-offline.sh         (+1 row)  — SUITE_DEFS registration
```

No change to routing order, ceilings, `feedback_quota_ceilings_per_provider`, or
`leadv2-router-v2.sh`. This task is observe-and-recover, not route-differently.

## 2. Data flow (numbered)

### Lever 1 — deferred-GLM park

1. `cmd_resolve` candidate loop calls `spawn_worker glm`; the glm launcher refuses on quota.
2. `spawn_worker` sets `LAST_ARM_OUTCOME="glm_refused_quota_gate"` and emits
   `arm_refused by=router model=glm task=<sig8> reason=glm_refused_quota_gate`
   (`leadv2-dispatch-code.sh:2552-2553`) — **unchanged**.
3. Control reaches the `7)` refusal branch (`:4093`). **New: immediately at the top of that branch**,
   before the existing `_reordered_after_quota_gate` re-resolve, call
   `_glm_park_deferred "${sig8}" "${LAST_ARM_OUTCOME}"`.
   *Ordering is load-bearing:* the park row must exist **before** the fall-through, so a crash
   between refusal and sonnet-spawn still leaves the task recoverable. The test asserts ordering by
   file mtime/content, not by "it happened somewhere".
4. `_glm_park_deferred` appends ONE JSON object to `docs/leadv2/glm-deferred.jsonl` **only when the
   task is glm-fitting** — see §4 gating.
5. Existing re-resolve → sonnet spawn proceeds untouched.

### Lever 2 — codex credit watchdog

1. At each of the two `route_headroom_chosen` emit sites (`:3984`, `:4128`) the credits JSON is
   already in hand (`${v2_credits}` / `${_qg_credits}`).
2. **New:** immediately after each emit, `_codex_credits_watch "<credits-json>"`.
3. The helper parses `.codex.has_credits` (falling back to `.codex.balance == "0"`); if truthy-empty
   it reads `docs/leadv2/.codex-credits-empty.stamp` (a single ISO-8601 `since=` line). If the stamp
   is absent → write it with `since=<now>` and emit `codex_credits_empty since=<now>`. If present and
   its `since` is < 24h old → **emit nothing** (dedup). If ≥ 24h old → re-emit and refresh the stamp.
   If `has_credits` is true → delete the stamp (so recovery re-arms the watchdog).
4. `leadv2-broad-status.sh` reads the stamp file directly (not the journal — journal parsing is not
   its job) and, when present, appends one deterministic line to `queue_md`.

### Lever 3 — loud sonnet exceptions

1. In the successful-launch branch (`:4068`, before `exit 0`), when
   `candidate == sonnet` **and** `attempted[]` contains any `glm_refused_*` entry, call
   `_arm_exception_bump "glm quota"`.
   *Why `attempted[]` and not `LAST_ARM_OUTCOME`:* by the time sonnet lands, `LAST_ARM_OUTCOME` has
   been overwritten by the sonnet spawn's own outcome (`:3082`). `attempted[]` is the durable record
   of what was refused earlier in the loop (`:4094`, `:4189`).
2. `_arm_exception_bump` rewrites `docs/leadv2/.arm-exceptions-$(date -u +%Y%m%d)` atomically
   (tmp + `mv`) with two lines: `count=<n>` and `last_reason=<reason>`. Read-modify-write under
   `flock` on the file itself — see risk R2.
3. `leadv2-broad-status.sh` reads today's file; when `count>0` it appends
   `sonnet-фолбэков сегодня: <N> (<last_reason>)` to `queue_md`.

## 3. Interface contracts

### 3a. `docs/leadv2/glm-deferred.jsonl` — one JSON object per line, append-only

| Field | Type | Meaning |
|---|---|---|
| `sig8` | string(8) | task signature, the join key to the dispatch ledger |
| `mission_path` | string | repo-relative path of the persisted lane mission, `""` if none |
| `founder_task_id` | string | `${founder_task_id}` or `""` |
| `refused_at` | string | ISO-8601 UTC, `%Y-%m-%dT%H:%M:%SZ` |
| `reason` | string | verbatim `LAST_ARM_OUTCOME` (e.g. `glm_refused_quota_gate`) |
| `quota_pct` | number\|null | glm headroom percent from `${v2_headroom}` if parseable, else `null` |
| `retried_at` | string\|null | set by `--retry-all` on the *replacement* row (see R4) |

Append is `printf '%s\n' "$json" >> file` under `flock` (single-line atomic append; the file is also
touched by the retry path, so the lock is required, not optional).

### 3b. `leadv2-dispatch-code.sh glm-deferred` subcommand

| Invocation | Behaviour | Exit |
|---|---|---|
| `glm-deferred` / `--list` | prints one human line per un-retried row: `<sig8> <refused_at> quota=<pct> <mission_path>`; prints `no deferred glm tasks` when empty | 0 |
| `glm-deferred --retry-all` | for each un-retried row: probe the quota gate; if the window is open, re-dispatch that sig8's mission and append a `retried_at`-stamped row; else leave it parked and print `still_gated <sig8>` | 0 |
| `glm-deferred --json` | machine-readable passthrough of the un-retried rows | 0 |
| unknown flag | usage to stderr | 2 |

Wired into the tail `case` (`:4407`) as `glm-deferred) shift; cmd_glm_deferred "$@" ;;` — placed
**before** the `*) cmd_resolve` catch-all. `usage()` gains one line.

**Gate probe for `--retry-all`:** reuse `leadv2-router-v2.sh resolve --chain glm --task-id <sig8>`
and read its `eligible=` / `headroom=` keys — the same resolver the refusal path already calls at
`:4105`. Do **not** invent a new quota API and do **not** call the glm launcher just to see if it
refuses (that burns a spawn).

### 3c. `docs/leadv2/.arm-exceptions-YYYYMMDD` (2 lines, `key=value`)

```
count=3
last_reason=glm quota
```

### 3d. `docs/leadv2/.codex-credits-empty.stamp` (1 line)

```
since=2026-08-19T22:11:04Z
```

### 3e. Renderer output contract (`queue_md` suffix, deterministic)

Appended after the existing queue body, each on its own line, only when non-zero/present:

```
sonnet-фолбэков сегодня: 3 (glm quota)
codex: кредиты на нуле с 2026-08-19T22:11:04Z
отложено на GLM: 5 задач (dispatch glm-deferred --list)
```

And in `tail_facts`, a new plugin-owned key (NOT inside `repo_facts`):

```json
"provider_health": {
  "sonnet_fallbacks_today": 3,
  "sonnet_fallback_last_reason": "glm quota",
  "codex_credits_empty_since": "2026-08-19T22:11:04Z",
  "glm_deferred_count": 5
}
```

## 4. Gating — what counts as "glm-fitting"

The mission says park "a task whose kind/classification is glm-fitting". The implementer must
**not** invent a new classifier. Constraint: park iff `glm` was present in `candidate_arms` at the
moment of refusal. That is already the router's own answer to "is this task glm-fitting" — glm only
appears in the chain when the classifier put it there. Anything else re-implements routing policy,
which the mission forbids.

## 5. DB / migrations

None. This subsystem is file-backed; Supabase is not involved.

## 6. Risk list

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Park file grows unbounded** — every quota-gated day appends rows forever, and `--list` gets slower and noisier until it is ignored (the failure mode of every unbounded log). | Cap at 500 rows: `_glm_park_deferred` truncates to the newest 500 on append. Rows older than 7 days are dropped by the same pass. State the cap in the file's first-write comment; `--list` prints `(truncated, oldest dropped)` when it fires — never silently. |
| R2 | **Concurrent counter clobber.** Multiple lanes dispatch in parallel; `.arm-exceptions-*` is read-modify-write, so two simultaneous sonnet fallbacks lose one increment. | `flock` on a sidecar `.lock` fd for the whole read-modify-write, `tmp+mv` for the write. Same for the park file's truncating append. Do **not** reuse fd 9 — `leadv2-dispatch-code.sh` already flocks fd 9 for the dispatch lock (`:335`) and the spawn path deliberately closes it (`9>&-`, `:2546`); pick fd 8. |
| R3 | **Fd 9 inheritance into the detached worker.** Any new lock taken near the spawn site could be inherited by the `setsid`+`disown` worker and held for its lifetime — the exact bug FIX PASS 4 fixed. | All three helpers must complete their `flock` scope **before** any `spawn_worker` call and must never wrap one. Park write happens in the `7)` branch (post-refusal, pre-respawn) and the exception bump happens in the `0)` branch (post-spawn) — neither encloses a spawn. Verify with `shellcheck` + a grep assertion in the test that no `flock` scope contains `spawn_worker`. |
| R4 | **`--retry-all` double-dispatch.** Re-dispatching a sig8 that already landed on sonnet creates a duplicate lane. | Two guards: (a) before re-dispatch, consult the dispatch ledger for a terminal row for that sig8 and skip if present; (b) never rewrite the original row in place — append a new row with `retried_at` set, and treat a sig8 as "un-retried" only if no later row for it carries `retried_at`. Append-only preserves the incident audit trail. |
| R5 | **Renderer coupling to a missing file.** `leadv2-broad-status.sh` runs in repos where these files never existed. | Every read is `[[ -r ... ]]`-guarded and yields the empty/zero case; a malformed file yields zero, never an exception. A renderer traceback degrades the whole beat (`:505-510`) — that is a strictly worse outcome than a missing line. |
| R6 | **Date rollover at UTC midnight** — a lane that refuses at 23:59:59 and lands at 00:00:01 bumps tomorrow's counter while the founder reads today's. | Accepted, documented in a code comment. Compute the date **once** per `cmd_resolve` invocation (`_LEADV2_EXC_DAY`), not once per helper call, so a single dispatch never straddles two files. |
| R7 | **Credit-parse drift.** The `credits=` payload shape (`{"balance":"0","has_credits":false}`) is a *provider-side* contract. | UNVERIFIED: the exact credits JSON shape is taken from the incident text quoted in the mission, not from a live probe in this prepass. The implementer must confirm it against a real `leadv2-router-v2.sh resolve` run and paste that output in the lane deliverable before relying on the key names. Parse defensively: a missing/unparseable `codex` key means "unknown", which emits nothing (never a false alarm). |
| R8 | **Emitting the watchdog line from inside a `python3 -c` failure path.** Sites `:3982-3984` already tolerate python failure via `|| printf`. | The watchdog helper must be independently guarded — its failure must never abort `cmd_resolve`. Trailing `|| true` on the call site. |

## 7. Mandatory constraint checklist

1. **Env vars:** none added — the mission forbids it and this design adds none. Existing
   `LEADV2_ROUTER_V2_ON_QUOTA_GATE` / `LEADV2_ROUTER_V2_BIN` are read, not modified. Test-only path
   overrides, if the implementer needs them, must use the `LEADV2_` prefix and be documented as
   test-only. ✅
2. **File paths:** every path in §1 verified to exist except the four marked `(to-create)`:
   `docs/leadv2/glm-deferred.jsonl`, `docs/leadv2/.arm-exceptions-YYYYMMDD`,
   `docs/leadv2/.codex-credits-empty.stamp`, `tests/test-glm-deferred-ladder.sh`. ✅
3. **`claude -p` commands:** this design introduces none. ✅
4. **Concurrent access:** R2/R3/R4 above. ✅
5. **Config contradiction:** no env var introduced → nothing to contradict. The one semantic
   contradiction found is D0 (`repo_facts` misuse) and it is resolved by not using it. ✅

## 8. `.gitignore`

`glm-deferred.jsonl` is operational state, not source. Add alongside the existing entries
(`.gitignore:16-17`):

```
docs/leadv2/glm-deferred.jsonl
docs/leadv2/.arm-exceptions-*
docs/leadv2/.codex-credits-empty.stamp
```

## 9. Tests — `tests/test-glm-deferred-ladder.sh` (red-first)

Follow the content-probe baseline pattern of `test-review-gate-scope-evidence.sh`. Four legs, each
of which must be demonstrated RED against the pre-change tree before the fix lands:

| Leg | Asserts | Probe surface |
|---|---|---|
| (a) | a quota-refused glm-fitting dispatch writes a park row, and the row's mtime precedes the sonnet worker's spawn record | the park file's contents + ordering |
| (b) | `leadv2-dispatch-code.sh glm-deferred --list` prints the parked sig8 | the subcommand's **stdout** |
| (c) | two credit-empty computations within 24h produce exactly ONE `codex_credits_empty` journal line; a third after a back-dated stamp produces a second | journal line count |
| (d) | after one fallback, the **rendered** `founder-status.md` contains `sonnet-фолбэков сегодня: 1` | **rendered artifact**, not a source grep |

Leg (d) is the CLAIM-EVIDENCE lesson made executable: it must run the real renderer and grep its
output file. A grep of `leadv2-broad-status.sh` source for the Russian string is a fake green and
will be treated as a BLOCKING review finding.

Registration: one row appended to `SUITE_DEFS` (`tests/run-core-offline.sh:175-188`), format
`"deferred-GLM ladder (V3-GLM-LADDER-01)|||bash $TEST_DIR/test-glm-deferred-ladder.sh"`.
Nothing else in that file changes.

## 10. Out of scope (implementer: ignore these)

- Changing routing order, ceilings, or `feedback_quota_ceilings_per_provider`.
- Any change to `leadv2-router-v2.sh`, `leadv2-dispatch-product-close.sh`, `supervise*`.
- Auto-retry of parked tasks (cron/daemon). `--retry-all` is **manual-only** in this task; an
  automatic retrier is a separate lane with its own double-dispatch blast radius.
- Notifying the founder proactively (Telegram/push). The beat is the channel.
- Kimi's symmetric refusal path. It has the same shape and deserves the same treatment, but
  widening the diff widens the review surface; propose as a follow-up, do not implement.
- Backfilling historical refusals from existing journals.

## acceptance:

```yaml
acceptance:
  - surface: rendered_line
    observable: >
      The founder-status message published by the beat contains a line reading
      "sonnet-фолбэков сегодня: 1 (glm quota)" on a day when exactly one dispatch fell
      from glm to sonnet after a quota refusal, and contains no such line on a day with none.
    authored_at: 2026-08-20T00:00:00Z
  - surface: file_artifact
    observable: >
      docs/leadv2/glm-deferred.jsonl holds one JSON line per quota-refused glm-fitting task,
      each showing that task's 8-character signature, the time it was refused, and the glm
      quota percentage at refusal.
    authored_at: 2026-08-20T00:00:00Z
  - surface: log_line
    observable: >
      The dispatch decision journal shows exactly one "codex_credits_empty since=<timestamp>"
      entry across a 24-hour stretch in which codex reported an empty balance many times,
      and a second entry once that stretch exceeds 24 hours.
    authored_at: 2026-08-20T00:00:00Z
  - surface: rendered_line
    observable: >
      Running the dispatcher's glm-deferred listing prints, for each parked task, its signature,
      refusal time and mission path; with nothing parked it prints "no deferred glm tasks".
    authored_at: 2026-08-20T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-broad-status.sh, plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, .gitignore

DELIVERABLE_COMPLETE
