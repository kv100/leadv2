# BROAD-STATUS-RELAY-SCOPE-01 — architect prepass (implementation design)

TASK_ID: dispatch-91f975bf-architect · ROLE: architect · repo: `~/Projects/leadv2` (plugin canonical)
No `context.yaml` existed for this task (only `architect.stream.jsonl` + `sessions.map`); mission text is
the sole binding input.

---

## 1. Ground truth found on disk (trace)

| Component | File | Role today |
|---|---|---|
| Beat composer (single, shared) | `plugins/leadv2/scripts/leadv2-broad-status.sh:74` | writes `founder-status.md`, emits ONE `[SUPERVISE-URGENT] BROAD_STATUS_READY at=… path=… rows=… dispatched=…` line into `supervise-loop.log` |
| Supervisor driver | `plugins/leadv2/scripts/leadv2-supervise-loop.sh:839-860` | beat branch: pump → composer; degraded emitter at `:397` |
| Single-lead driver | `plugins/leadv2/scripts/leadv2-pulse-beat.sh` | `--check/--now/--due`; throttle `LEADV2_SINGLE_LEAD_BEAT_S` (1800), skips when `.supervise-loop.json` pid is live |
| **Injector (the actual defect site)** | `plugins/leadv2/hooks/leadv2-single-lead-beat.sh:72-123` | DELIVER: tails the last READY/FAILED line, dedupes on `at=` (`.pulse-delivered`) + body hash (`.pulse-body-hash`), injects the raw ready-line as `additionalContext` — to **whichever session's hook fires first**, with no notion of who owns the beat |
| **Directive that turns the line into a 25-row dump** | `plugins/leadv2/hooks/leadv2-task-anchor.sh:221-229` **and** `:704-712` (two identical blocks) | "a `[BROAD_STATUS]` relay when the plugin emits `BROAD_STATUS_READY` (paste `founder-status.md` verbatim…)" — unconditional |
| Same wording, other surfaces (docs, not injectors) | `hooks/leadv2-supervisor-mode-reinject.sh:138-143`, `commands/leadv2.md:267`, `skills/leadv2-supervise/SKILL.md:139`, `docs/supervisor-role.md:99-179` | prose contract |

**So the founder's incident is two bugs, not one:**
1. The ready-line is delivered to any session that happens to fire a hook — delivery is not scoped.
2. The anchor directive says "paste verbatim" unconditionally — so a non-owning session that receives
   the line correctly obeys by dumping the whole ledger.

### Ownership signals that actually exist
- `.supervise-active` — control-plane JSON `{pid,pid_birth,started_at}`, written inside the
  `/leadv2 supervise` session (see `leadv2-supervisor-mode-reinject.sh:14-22`). **PID-based.**
- `.supervise-loop.json` — loop ownership sentinel, `{pid,…}`. PID-based.
- `active.yaml` `sessions[]` — `session_id` there is a **synthetic** `s-<utc>-<pid>-$$` registry id
  (`leadv2-active-registry.sh:532-572`), **not** the Claude hook `session_id` UUID. There is therefore
  **no existing mapping from a Claude session to an active lane.** This is the one place the mission's
  wording ("session owning active lanes") cannot be honoured literally today; see Risk R4.
- Claude hook `session_id` — available on hook stdin and already used ~20× in this hook tree
  (`leadv2-bg-ledger.sh:25`, `leadv2-auto-status.sh:162`, …).

---

## 2. Design — ownership resolved at DELIVER, two shapes of injected context

### 2.1 Data flow (numbered)

1. Any lead session's hook fires (`UserPromptSubmit` / `PostToolUse`) → `leadv2-single-lead-beat.sh`.
2. Hook parses `session_id` from stdin JSON (new; `cwd`/`hook_event_name` already parsed) and computes
   `SAFE_SID` (`[^A-Za-z0-9._-]` → `_`, truncate 64).
3. Hook sources the **new** resolver `scripts/leadv2-beat-owner.sh` → `leadv2_beat_role <safe_sid>`
   prints exactly one of `owner` / `guest` / `unresolved` (ladder in §2.2).
4. DELIVER dedupe becomes **per-session**: watermark `.pulse-delivered.<SAFE_SID>` and body hash
   `.pulse-body-hash.<SAFE_SID>` (legacy shared names kept as fallback when `session_id` is empty).
   Required — see Risk R1: today's shared watermark would let a non-owning session consume the beat and
   the owner would never receive it.
5. Injected `additionalContext`, by role:
   - `owner` **or** `unresolved` → `"<ready-line>\nRELAY=full …"` (fail-open = today's behaviour).
   - `guest` → **exactly one line**, no ready-line body:
     `<at-stamp> [BROAD_STATUS] at=<at> path=docs/leadv2/founder-status.md — full status in owning session (RELAY=none); do not read or relay it.`
6. TRIGGER (unchanged order, still after DELIVER): hook exports
   `LEADV2_BEAT_OWNER_SESSION="$SAFE_SID"` and calls `leadv2-pulse-beat.sh --check`.
7. `leadv2-pulse-beat.sh`, **only when it actually proceeds past the liveness+throttle gate**, records
   the arming session atomically into `.pulse-beat-owner` (`<safe_sid> <epoch>`), then composes as
   today. The session that armed the beat is its owner.
8. `leadv2-task-anchor.sh` directive (both blocks) becomes conditional: relay verbatim **only** when the
   injected beat carries `RELAY=full`; when it carries `RELAY=none`, emit that single line and nothing
   else. No other wording changes.

### 2.2 `leadv2_beat_role` ladder (first match wins)

| # | Condition | Result |
|---|---|---|
| 0 | `LEADV2_BEAT_RELAY_SCOPE=0` (kill-switch) | `unresolved` (→ full relay everywhere = pre-change behaviour) |
| 1 | `LEADV2_BEAT_OWNER_OVERRIDE` set (test seam) | `owner` if `== safe_sid` else `guest` |
| 2 | `.supervise-active` pid alive **and** is an ancestor of this hook pid | `owner` |
| 3 | `.supervise-active` pid alive **and not** an ancestor | `guest` |
| 4 | `.pulse-beat-owner` fresh (age ≤ `2 × LEADV2_SINGLE_LEAD_BEAT_S`, floor 3600s) and names `safe_sid` | `owner` |
| 5 | `.pulse-beat-owner` fresh and names another session | `guest` |
| 6 | anything else (missing/stale/unparseable/no `session_id`/resolver absent) | `unresolved` |

Ancestor test: walk `ps -o ppid= -p <pid>` from `$PPID` upward, ≤ 12 hops, ≤ 1 `ps` call per hop, any
error → not-an-ancestor (never `owner` by accident, and rows 4-6 still apply).

### 2.3 Interface contracts

| Surface | Contract |
|---|---|
| `scripts/leadv2-beat-owner.sh` (new, sourced) | `leadv2_beat_role <safe_sid> <state_dir>` → stdout one of `owner\|guest\|unresolved`, rc always 0 |
| `.pulse-beat-owner` (new state file, `<state_dir>`) | single line `"<safe_sid> <epoch>"`, atomic `.tmp.$$` + `mv -f` |
| `.pulse-delivered.<safe_sid>` / `.pulse-body-hash.<safe_sid>` | same semantics as today's shared files, per-session; prune files matching the pattern with mtime > 7d on each fire (cheap `find -mtime +7 -delete`, errors ignored) |
| Injected context, owner | line 1 = verbatim ready-line (unchanged bytes), line 2 = `RELAY=full — paste docs/leadv2/founder-status.md verbatim; compare its line-1 stamp with at= first.` |
| Injected context, guest | one line, contains `RELAY=none` and `full status in owning session`, and **must not** contain `BROAD_STATUS_READY` (so the anchor's verbatim rule cannot latch) |
| Env vars (all `LEADV2_*`, checked against convention) | `LEADV2_BEAT_RELAY_SCOPE` (kill-switch, default 1), `LEADV2_BEAT_OWNER_OVERRIDE` (test seam), `LEADV2_BEAT_OWNER_SESSION` (hook→pulse-beat handoff). No `LEAD_V2_*` drift; no collision found with existing names. |

### 2.4 Files to change

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-beat-owner.sh` *(to-create)* | ownership resolver, §2.2 |
| `plugins/leadv2/hooks/leadv2-single-lead-beat.sh` | **HOOK** — parse `session_id`, per-session watermarks, role branch, two context shapes, export owner env into TRIGGER |
| `plugins/leadv2/scripts/leadv2-pulse-beat.sh` | write `.pulse-beat-owner` from `LEADV2_BEAT_OWNER_SESSION` after the due-gate, before `_run_beat` (both `--check`-spawned `--now` and direct `--now`) |
| `plugins/leadv2/hooks/leadv2-task-anchor.sh` | **HOOK** — both directive blocks (`:221-229`, `:704-712`) become `RELAY=full` / `RELAY=none` conditional |
| `plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh` *(to-create)* | red-first suite, §4 |

### 2.5 ⚠️ HOOK-CACHE WARNING (stated loudly, per mission)

**Two of the five files are hooks** (`leadv2-single-lead-beat.sh`, `leadv2-task-anchor.sh`). Hooks load
from the plugin **cache** copy; `claude plugin update` no-ops for a directory-source marketplace when
content changed but the version did not. **The fix does not go live until the changed hook files are
copied into the plugin cache AND the session is restarted.** Editing canonical only = a gate the
founder is told exists but which is not on the running path (the 2026-07-29 defect class). The
terminal artifact must state this explicitly and name the cache path used.

Also note: `LEADV2_LEAD_GUARD=1` blocks the `Edit` tool on canonical plugin `.sh` — implement via the
`/tmp` python patcher + `Bash` route (existing memory: `lead-edit-guard-canonical-edit`).

---

## 3. Risks & mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | **Shared watermark starves the owner.** `.pulse-delivered` / `.pulse-body-hash` live in the cross-worktree `STATE_DIR`, so today the first hook to fire consumes the beat. Scoping without fixing this converts "wrong session got the dump" into "nobody got the status". | CRITICAL | Per-session watermark files (§2.1 step 4). This is not optional polish — it is the load-bearing half of the fix. Must have its own test. |
| R2 | Race: two sessions' hooks concurrently read `.pulse-beat-owner` while `leadv2-pulse-beat.sh` rewrites it. | MEDIUM | Owner file is written atomically (`tmp+mv`); readers are read-only and a torn/absent read falls to `unresolved` → full relay. Concurrent write path is already serialised by `.pulse-beat.lock` (non-blocking flock) in `leadv2-pulse-beat.sh:143`. |
| R3 | Supervise loop composes the beat but never sets `LEADV2_BEAT_OWNER_SESSION` (loop has no Claude session id). | MEDIUM | Ladder rows 2-3 cover it via the live `.supervise-active` pid + ancestry, so a supervise session is `owner` and every other session is `guest` without touching `leadv2-supervise-loop.sh` at all. If `.supervise-active` is absent, row 6 → full relay everywhere (no silent drop). |
| R4 | "Session owning active lanes" cannot be resolved from `active.yaml` — its `session_id` is synthetic, not the Claude UUID. | MEDIUM | Documented limitation. In practice the lane-owning lead is the session whose hook cadence arms the beat, so row 4 covers it. Do **not** invent a mapping in this lane; if the founder wants it, it is a follow-up (`active.yaml` would need a `claude_session_id` field written by a hook). |
| R5 | Marker-file proliferation in `docs/leadv2/`. | LOW | 7-day mtime prune per fire; names are dot-prefixed and already gitignore-shaped (confirm `.pulse-*` is ignored, else add). |
| R6 | Fail-open inverted by a bug (guest computed on error) → beat silently dropped for everyone. | HIGH | Resolver rc is always 0 and returns `unresolved` on every error path; test T5 asserts unresolved→full. Never `set -e` inside the resolver. |
| R7 | Anchor wording change ripples into the other four prose surfaces, leaving contradictory instructions. | MEDIUM | In-scope wording edit is the anchor only, but its phrasing must be *additive* ("only when the injected beat says RELAY=full") so the prose surfaces stay true. `test-broad-status-duty.sh:384-387` asserts the anchor mentions `BROAD_STATUS_READY` exactly twice with `verbatim relay of a` — **the edit must keep both mentions and that phrase, or that existing suite goes red.** |
| R8 | Hook edited canonical-only → not live (§2.5). | CRITICAL | Cache copy + restart, stated in the terminal artifact. |

---

## 4. Test plan (red-first, pinned baseline)

New suite `plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh`, same harness style as
`test-single-lead-beat.sh` (temp `PROJECT_ROOT`, synthetic `supervise-loop.log` + `founder-status.md`,
hook driven by piping JSON to stdin, `LEADV2_BEAT_OWNER_OVERRIDE` as the seam so no real pids are needed).

| T | Scenario | Assertion |
|---|---|---|
| T1 | owner session, fresh beat | stdout `additionalContext` contains the verbatim ready-line **and** `RELAY=full` |
| T2 | guest session, same beat | stdout is exactly ONE line, contains `RELAY=none` + `full status in owning session`, does **not** contain `BROAD_STATUS_READY`, and does not contain any `founder-status.md` body row |
| T3 | **R1 regression:** guest fires first, then owner fires | owner still receives the full relay (per-session watermark) |
| T4 | owner fires twice, body unchanged | second fire injects nothing (idempotence preserved) |
| T5 | ownership unresolvable (no `.supervise-active`, no/stale `.pulse-beat-owner`) | full relay — fail-open, never empty |
| T6 | `LEADV2_BEAT_RELAY_SCOPE=0` | byte-identical behaviour to the pinned pre-change baseline |
| T7 | `PostToolUse` event, guest | flat `{"additionalContext":…}` shape (no `hookSpecificOutput`), still one line |
| T8 | anchor directive | both blocks mention `RELAY=full`; existing `test-broad-status-duty.sh` T8a/T8b still pass (2× `BROAD_STATUS_READY`, `verbatim relay of a` intact) |

Red-first: land T1-T3+T5 against the **unmodified** hook first and record the failures with a pinned
baseline commit (current `HEAD` = `85ae886`; pin by SHA, not by `merge-base` — see commit `8cc6bf8`'s
self-nullification lesson).

Gates: `bash -n` + `shellcheck` clean on all four touched/created shell files;
`plugins/leadv2/scripts/tests/run-core-offline.sh` unchanged pass rate — **the new suite is deliberately
NOT registered in `run-core-offline.sh`**, matching its siblings `test-single-lead-beat.sh` and
`test-broad-status-duty.sh` (neither is registered), so the offline count stays exactly as it is today.
Run both sibling suites too — they cover the same files.

---

## 5. Non-goals / out of scope (implementer: ignore these)

- `leadv2-dispatch-product-close.sh`, `leadv2-review-run.sh` — other lanes own them.
- `founder-status.md` **content**, row selection, or rendering (`leadv2-broad-status.sh` composer body).
- Beat **cadence** / throttle values (`LEADV2_SINGLE_LEAD_BEAT_S`, `LEADV2_SUPERVISE_BROAD_STATUS_S`).
- `leadv2-supervise-loop.sh` — not edited (R3 avoids it).
- Adding a real Claude-session ↔ lane mapping to `active.yaml` (R4 follow-up, needs founder call).
- The prose surfaces `commands/leadv2.md`, `skills/leadv2-supervise/SKILL.md`,
  `docs/supervisor-role.md`, `hooks/leadv2-supervisor-mode-reinject.sh` — the anchor phrasing is chosen
  to remain compatible with them; do not rewrite them in this lane.
- Any change to the ready-line **bytes** written by the composer (existing duty tests pin its shape:
  `test-broad-status-duty.sh:167`).

## 6. Rollback

Single `git revert` of the one commit, plus re-copy of the two hook files into the plugin cache and a
session restart. Runtime kill-switch without a revert: `LEADV2_BEAT_RELAY_SCOPE=0`.

## 7. Self-check (mandatory checklist)

1. **Env naming** — `LEADV2_BEAT_RELAY_SCOPE`, `LEADV2_BEAT_OWNER_OVERRIDE`, `LEADV2_BEAT_OWNER_SESSION`
   all `LEADV2_*`; no `LEAD_V2_*` form used; no existing usage of these three names found in the plugin
   tree (grep clean) → no contradiction.
2. **Paths** — every path in §2.4 verified on disk; the two new files are marked `(to-create)`.
3. **`claude -p`** — this lane introduces none. N/A.
4. **Concurrent access** — `.pulse-beat-owner` (written by `leadv2-pulse-beat.sh`, read by the hook in
   every session) and the per-session watermarks: race surface analysed in R1/R2; ordering constraint =
   DELIVER strictly before TRIGGER (already the case), atomic `tmp+mv` for every write, readers
   fail-open.
5. **Config contradiction** — the anchor's "paste verbatim" rule is echoed in four prose surfaces; the
   phrasing is additive so none of them becomes false (R7), and the existing duty-test assertions on the
   anchor text are called out as a hard constraint.

acceptance:
- surface: rendered_line
  observable: "In the session that armed/owns the beat, the chat shows the founder-status ledger relayed in full, headed by the beat timestamp. In every other live lead session at the same beat, the chat shows a single line naming the timestamp and docs/leadv2/founder-status.md and saying the full status is in the owning session — no ledger rows appear there."
  authored_at: 2026-08-19T00:00:00Z
- surface: rendered_line
  observable: "When no owning session can be determined, every live lead session shows the full ledger relay exactly as it does today — no session shows an empty or missing status beat."
  authored_at: 2026-08-19T00:00:00Z
- surface: file_artifact
  observable: "A reader opening docs/leadv2/founder-status.md sees the same content and the same stamp line as before the change."
  authored_at: 2026-08-19T00:00:00Z

LANE_WRITES: plugins/leadv2/hooks/leadv2-single-lead-beat.sh, plugins/leadv2/hooks/leadv2-task-anchor.sh, plugins/leadv2/scripts/leadv2-pulse-beat.sh, plugins/leadv2/scripts/leadv2-beat-owner.sh, plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh

DELIVERABLE_COMPLETE
