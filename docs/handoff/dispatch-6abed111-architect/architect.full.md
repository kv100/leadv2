# BROAD-STATUS-RELAY-SCOPE-01 — ROUND 3 FINISHER — architect prepass

TASK_ID: dispatch-6abed111-architect · lane: 91f975bf · authored_at: 2026-08-19T12:14:22Z
Lane worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/91f975bf` (branch `worktree-91f975bf`, at `85ae886`).
All r1+r2 work is **uncommitted** in that worktree. r3 = 2 surgical items + commit.

---

## 0. Verified state (facts, not assumptions)

| Claim | Verification |
|---|---|
| `CLAUDE_SESSION_ID` does not exist in a Claude Code Bash subprocess | `env \| grep -iE '^CLAUDE'` in this subsession: **no** `CLAUDE_SESSION_ID`; **`CLAUDE_CODE_SESSION_ID=f5096a7e-4c5…`** present (36-char uuid). Mission item 1 is **CONFIRMED real**. |
| Where the bad read lives | worktree `plugins/leadv2/scripts/leadv2-dispatch-code.sh`, inside `_dispatch_register_arm()` — diff hunk `@@ -519`, the line `lead_session="$(printf '%s' "${CLAUDE_SESSION_ID:-}" \| tr -c 'A-Za-z0-9._-' '_')"`. (Mission's ":405" is the pre-r1 line number; the function is the anchor, not the number.) |
| Consumer chain | `_dispatch_register_arm` → `docs/handoff/<task_id>/arm-registered` line field `LEAD_SESSION=` → `leadv2_session_has_live_lane()` (`leadv2-beat-owner.sh`, python3 block, compares `sanitize(LEAD_SESSION)` to `safe_sid`) → gate for both (a) the **write** of `.pulse-beat-owner` in `leadv2-pulse-beat.sh` and (b) ladder step 4 in `leadv2_beat_role`. Empty `LEAD_SESSION=` ⇒ never matches ⇒ owner file never written ⇒ every session `unresolved` ⇒ **full 25-row relay everywhere** = the original incident. |
| Hook side is already correct | `leadv2-single-lead-beat.sh` takes `session_id` from **hook JSON stdin**, not env, then `SAFE_SID = tr -c 'A-Za-z0-9._-' '_' | cut 64`. So only the writer is broken; sanitization on both sides is already symmetric. |
| Test seam for the write target exists | `_dispatch_arm_registered_file()` honours `LEADV2_DISPATCH_ARM_REGISTERED_FILE` — the new test needs no fake repo tree. |
| Suite size | `test-broad-status-relay-scope.sh` currently has **19** asserted cases (T1–T19; `grep -c 'pass "T'` = 19). See §5 Risk R5 re: the mission's "22+". |

---

## 1. Layers affected

```
plugins/leadv2/scripts/leadv2-dispatch-code.sh      (write side — 1 expression)
plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh  (+T20, +T21)
docs/handoff/<lane>/developer.full.md               (deliverable, not a lane write)
```
No change to: routing, dedup, ledger, the resolver ladder, the hook, pulse-beat, run-core-offline (already registered in r1), `.gitignore`.

---

## 2. Data flow after the fix (numbered)

1. Lead session `S` (hook-visible `session_id` = uuid `U`) dispatches a lane.
2. `_dispatch_register_arm` resolves `lead_session` from **`CLAUDE_CODE_SESSION_ID`**, falling back to `CLAUDE_SESSION_ID` (forward/backward compat), sanitizes with the existing `tr -c 'A-Za-z0-9._-' '_'` + `:0:64`, and appends `LEAD_SESSION=<sanitized U>` as the **last** field of the arm line (field order unchanged; pre-upgrade readers unaffected).
3. Hook fires in `S`; `SAFE_SID = sanitize(U)` — string-equal to step 2's value because both sanitizers are identical and a uuid contains only safe chars (`sanitize(U) == U`).
4. `leadv2-pulse-beat.sh --check` receives `LEADV2_BEAT_OWNER_SESSION=SAFE_SID`, calls `leadv2_session_has_live_lane` → now **matches** → writes `docs/leadv2/.pulse-beat-owner` = `"<SAFE_SID> <epoch>"`.
5. Next hook fire: `leadv2_beat_role` ladder passes steps 2/3/4 → `S` = `owner` (full relay), every other live session = `guest` (one `RELAY=none` line).

The only edge in the chain that changes is step 2. Everything downstream was already proven by r1/r2 tests T9–T18.

---

## 3. Interface contract (the one change)

| Item | Before | After |
|---|---|---|
| env read in `_dispatch_register_arm` | `${CLAUDE_SESSION_ID:-}` | `${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}` |
| `arm-registered` line grammar | `arm=<a> handle=<h> epoch=<n> LEAD_SESSION=<s>` | unchanged (`<s>` now non-empty in prod) |
| Sanitizer | `tr -c 'A-Za-z0-9._-' '_'`, `:0:64` | unchanged — do **not** touch, symmetry with the hook is load-bearing |

Exact replacement (one line, plus a 2-line comment amendment naming `CLAUDE_CODE_SESSION_ID` as the real var and `CLAUDE_SESSION_ID` as legacy fallback):

```bash
lead_session="$(printf '%s' "${CLAUDE_CODE_SESSION_ID:-${CLAUDE_SESSION_ID:-}}" | tr -c 'A-Za-z0-9._-' '_')"
```

**No new env var.** `LEADV2_DISPATCH_LEAD_SESSION`-style override is explicitly a non-goal (§6) — it would need a `usage()` entry and widens the write-set.

---

## 4. Test design — T20 (red-first) + T21 (fallback guard)

Both go at the end of `test-broad-status-relay-scope.sh`, before the `── Summary` block. They exercise the **real** function text from the real script — no reimplementation (a copy-pasted stub would pass while prod stayed broken, which is exactly the class of defect this lane exists to kill).

**Mechanism** (there is no existing sourcing idiom for this script — it has no `sourced` guard and running it top-level parses args, so extraction is the correct approach):

1. Resolve the real script from the test's own location — reuse the same `_LV2_D`-style resolution the file already uses for `HOOK_SH` (`$(cd "$(dirname "$0")/../.." && pwd)/scripts/leadv2-dispatch-code.sh`). Do **not** point at `$REPO` (that is the synthetic fixture repo).
2. Extract both functions into a driver script (a real file, not an inline `bash -c` string — keeps quoting shellcheck-clean):
   ```
   sed -n '/^_dispatch_arm_registered_file() {/,/^}/p;/^_dispatch_register_arm() {/,/^}/p' "$DISPATCH_SH" > "$TMP/t20-driver.sh"
   ```
3. **Extraction guard (mandatory):** assert the driver contains both `_dispatch_arm_registered_file()` and `_dispatch_register_arm()`; if not → `fail "T20: extraction failed — function renamed in leadv2-dispatch-code.sh"`. Without this, a rename turns the test silently green.
4. Append `set -uo pipefail`-compatible header + the call: `_dispatch_register_arm deadbeef claude "PID=1"`.
5. Run it with a scrubbed env:
   ```
   env -u CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID="f5096a7e-4c5b-4a1e-9d33-000000000001" \
       PROJECT_ROOT="$TMP" LEADV2_DISPATCH_ARM_REGISTERED_FILE="$ARMF" \
       bash "$TMP/t20-driver.sh"
   ```
   `env -u` is the load-bearing part: `CLAUDE_SESSION_ID` must be *absent*, not empty-string, to model prod.

**T20 assertions** (this is the red-first one — on current code `LEAD_SESSION=` is empty and both fail):
- the single line in `$ARMF` matches `LEAD_SESSION=f5096a7e-4c5b-4a1e-9d33-000000000001` exactly (uuid is sanitizer-invariant), and
- the field is non-empty: `grep -qE 'LEAD_SESSION=[A-Za-z0-9._-]+$'`.

**T21** (not red — a fallback regression guard, so the fix is a *fallback* and not a *replacement*): same driver, `env -u CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID="legacy-sid-1"` → `LEAD_SESSION=legacy-sid-1`.

**Red-first evidence to capture raw:** run the suite on the *unfixed* dispatch script and on the fixed one; paste both raw tails (`N passed, M failed` + the T20 failure text). Order: write T20/T21 → run RED → apply the one-line fix → run GREEN. Do not reorder.

**Prod probe (acceptance surface, not a test):** in the lane worktree, with `LEADV2_STATE_ROOT` pointed at a scratch state dir, write a fresh `arm-registered` via the fixed function with only `CLAUDE_CODE_SESSION_ID` set, stub one `running` lane for that task_id, run `leadv2-pulse-beat.sh --check` with `LEADV2_BEAT_OWNER_SESSION=<same sid>`, then **open `.pulse-beat-owner`** — a human sees `<sid> <epoch>` where before the file did not exist.

---

## 5. Risks & mitigations

| # | Risk | Sev | Mitigation |
|---|---|---|---|
| R1 | **Child-session attribution.** If the dispatch script runs inside a *subagent* subprocess, `CLAUDE_CODE_SESSION_ID` is the **child** session id (this subsession has `CLAUDE_CODE_CHILD_SESSION=1` and its own uuid), which no hook-firing session will ever match. | MED | Fails **open**: no match → owner file unwritten → `unresolved` → full relay = today's behaviour, never a wrong-session grant. Document as a known limitation in the deliverable; fixing it (explicit override plumbed from the lead) is a follow-up, not this lane. |
| R2 | Extraction-based test drifts if the function is renamed/reformatted | MED | The §4.3 extraction guard fails loudly. Also require `^_dispatch_register_arm() {` to stay at column 0 (it is). |
| R3 | `tr -c` behaviour on empty input | LOW | Already exercised today (empty is the current prod value); unchanged. |
| R4 | Sanitizer divergence between writer and hook | HIGH if touched | Do not touch either `tr` set. Any change must land in **both** plus the python `sanitize()` in `leadv2-beat-owner.sh` — three sites. Out of scope. |
| R5 | **Mission acceptance says "22+ cases"; the suite has 19 (T1–T19), 21 after T20/T21.** | LOW | Report the **actual** `N passed` line. Do **not** invent filler cases to hit 22 — that is padding, not coverage. Flag the number discrepancy in the deliverable. |
| R6 | Commit picks up unrelated/runtime files | MED | Explicit `git add` of the 9 paths in §7; never `git add -A`/`-u`. Re-`git diff <file>` immediately before each `git add` (a parallel session in this repo can revert an edit). |
| R7 | **Cache-copy: the ship note is incomplete if it names only the 3 hooks.** Verified: `CLAUDE_PLUGIN_ROOT=~/.claude/plugins/local/leadv2/plugins/leadv2` is a **symlink → `~/Projects/leadv2/plugins/leadv2`** (so canonical edits are live on that path), **but** `~/.claude/plugins/cache/leadv2-local/leadv2/{0.1.0,0.2.0,0.2.1,0.2.2,0.3.0}/` are **real copies**, last synced Aug 13 — stale. `hooks.json` invokes `"${CLAUDE_PLUGIN_ROOT}/hooks/…"`, and the hook then sources `"${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-beat-owner.sh"` and runs `"${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-pulse-beat.sh"`. So any session whose plugin root resolves to a cache version needs **5** files, not 3. | HIGH (for the doc) | Ship note lists the 3 hooks *as mandated* **plus** `scripts/leadv2-beat-owner.sh` (new file — a cache tree without it makes the hook print the `beat-owner resolver missing` stderr line and fall back to full relay) and `scripts/leadv2-pulse-beat.sh`. Note that `claude plugin update` no-ops for a directory-source marketplace when content changed but the version did not → copy into the active cache version dir and **restart the session**. |
| R8 | Stale round-1/round-2 prose ("deliberately not registered", "find on every fire") contradicts shipped code — the suite **is** registered in `run-core-offline.sh:131`, and the `find -delete` sweep **is** day-gated behind `.pulse-gc-day` (M5). | MED | Remove/replace both claims in the deliverable; state the current behaviour with the file:line evidence above. |

---

## 6. Non-goals (implementer: ignore these)

- Any change to routing, dedup, ledger, TTLs, or the `leadv2_beat_role` ladder.
- Any new env var (incl. a lead-session override for R1) or `usage()` edit.
- Changing the sanitizer on either side; changing `arm-registered` field order.
- Touching `run-core-offline.sh` (already registered), `.gitignore`, the hooks, `leadv2-pulse-beat.sh`, or `leadv2-beat-owner.sh` code.
- Actually performing the cache-copy / session restart — the deliverable **documents** the step; executing it is the founder's/lead's action.
- Committing `docs/leadv2/founder-status.md`, `docs/leadv2/status-snapshot.json`, `docs/leadv2/tasks/dispatch-567ba028/journal.md`, `docs/leadv2/tasks/dispatch-59ae8b51/journal.md`, `.claude/cache/`, `docs/handoff/**`, `docs/leadv2/tasks/backlog-pump/`.
- Merging to `main` or pushing.

---

## 7. Commit plan (in the lane worktree, branch `worktree-91f975bf`)

Stage exactly these 9 paths, each re-diffed immediately before `git add`:

```
.gitignore
plugins/leadv2/hooks/leadv2-single-lead-beat.sh
plugins/leadv2/hooks/leadv2-supervisor-mode-reinject.sh
plugins/leadv2/hooks/leadv2-task-anchor.sh
plugins/leadv2/scripts/leadv2-beat-owner.sh          (new)
plugins/leadv2/scripts/leadv2-dispatch-code.sh
plugins/leadv2/scripts/leadv2-pulse-beat.sh
plugins/leadv2/scripts/tests/run-core-offline.sh
plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh   (new)
```

Then verify with `git status --porcelain` that the 4 excluded paths from §6 are still unstaged/untracked, and `git diff --cached --stat` shows exactly 9 files. Gates before commit: `bash -n` on both touched files + `shellcheck` on both.

---

## 8. Constraint checklist

1. **Env naming** — no new `LEADV2_*` var introduced; `CLAUDE_CODE_SESSION_ID` is a Claude Code platform var, verified present in-process. No `LEAD_V2_*`/`LEADV2_*` drift.
2. **Paths** — all paths in §7 verified present in the worktree (`git status --porcelain`); the 2 new files marked `(new)`. `docs/handoff/dispatch-91f975bf/` exists (contains `arm-registered`, `lane-mission.md`, …).
3. **`claude -p`** — this lane invokes none. N/A.
4. **Concurrent access** — `arm-registered` is append-only (`>>`, every failure `|| true`), one writer per spawn; the reader tolerates extra fields and caps at 12 files. `.pulse-beat-owner` and `.pulse-session.*` are written `tmp.$$` + `mv -f` (atomic rename). No new lock needed. The one real race surface is **this repo vs. a parallel `claude` session** → R6's re-diff-before-add rule.
5. **Config contradiction** — `CLAUDE_SESSION_ID` is still read by 6 other plugin scripts (`codex-task.sh:1150`, `glm-coder.sh`, `kimi-coder.sh`, `leadv2-ask.sh:176`, `leadv2-reply-router.sh:52`, `leadv2-token-budget-warn.sh:30`), all of which therefore also degrade to their `nosession`/empty defaults today. **Not this lane's write-set** — record as a follow-up thread (`SESSION-ID-ENV-WRONG-EVERYWHERE-01`), do not fix here. No contradiction introduced by this change (fallback preserves the legacy var's semantics).

---

## acceptance:

```yaml
acceptance:
  - surface: file_artifact
    observable: >
      Opening docs/handoff/<task_id>/arm-registered after a dispatch, the last field of the
      arm line reads LEAD_SESSION=<36-character session id> instead of LEAD_SESSION= with
      nothing after the equals sign.
    authored_at: 2026-08-19T12:14:22Z
  - surface: file_artifact
    observable: >
      docs/leadv2/.pulse-beat-owner exists after a beat fired by a session that has a live
      lane, and its single line shows that session's id followed by an epoch — where before
      the file was absent entirely.
    authored_at: 2026-08-19T12:14:22Z
  - surface: rendered_line
    observable: >
      In a second, non-owning live session, the [BROAD_STATUS] block injected at the next
      prompt is one line ending "RELAY=none ... do not read founder-status.md" instead of the
      full 25-row founder-status.md dump.
    authored_at: 2026-08-19T12:14:22Z
  - surface: file_artifact
    observable: >
      docs/handoff/dispatch-91f975bf/developer.full.md names leadv2-single-lead-beat.sh,
      leadv2-task-anchor.sh and leadv2-supervisor-mode-reinject.sh (plus leadv2-beat-owner.sh
      and leadv2-pulse-beat.sh) under a cache-copy + session-restart ship step, and contains
      no "deliberately not registered" or "find on every fire" sentence.
    authored_at: 2026-08-19T12:14:22Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh

DELIVERABLE_COMPLETE
