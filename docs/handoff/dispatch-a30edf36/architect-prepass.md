# CODEX-QUOTA-GUARDRAILS-01 — fix round 1: scoped design

Worktree: `~/Projects/leadv2/.claude/worktrees/28e75319` (round-1 diff already present, uncommitted).
Scope: 4 files touched. No new files. No commit.

---

## 1. C1 — session-runner must DETECT the wall and OPEN the circuit

**File:** `plugins/leadv2/scripts/leadv2-codex-session-runner.sh`

**Defect (verified in tree):** line ~498-505 gates every spawn through `codex_spawn_gate`
(reads the circuit), but nothing in the loop ever *writes* it. The only writer is
`_codex_quota_watch_record` in `codex-task.sh`, which the runner never invokes — the runner
calls `codex exec` directly. A weekly usage wall therefore burns `MAX_ATTEMPTS` (default 6)
full `codex exec` attempts, then exits 3 "attempt budget exhausted", leaving the circuit
closed for every *other* arm too.

**Insertion point:** immediately AFTER the thread-id capture block (`_extract_thread_id`,
~line 517-524) and BEFORE `progress_after=…`. Rationale: `THREAD_ID` must be persisted to
`$THREAD_ID_FILE` first, so a post-circuit resume can continue the same Codex thread instead
of restarting blind (the runner already treats a missing thread id as fatal, exit 3).

**Detection window:** only the bytes this attempt appended. `log_size_before` is already
captured pre-spawn (line ~507) — reuse it, do not re-scan the whole log, or a stale wall
message from a previous attempt re-opens the circuit forever.

```
  _lim_new="$(tail -c "+$((log_size_before + 1))" "$LOGF" 2>/dev/null || true)"
  if printf '%s' "$_lim_new" | grep -qiE 'hit your usage limit|usage limit reached|rate limit exceeded'; then
    _lim_until=""
    if declare -F codex_circuit_parse_until >/dev/null 2>&1; then
      _lim_until="$(printf '%s' "$_lim_new" | codex_circuit_parse_until 2>/dev/null || true)"
    fi
    if declare -F codex_circuit_open >/dev/null 2>&1; then
      codex_circuit_open "$_lim_until" "session-runner"
    fi
    _append_receipt "quota_refused" "$rc" "$attempt"
    log_error "codex usage limit hit (until=${_lim_until:-default-24h}) — circuit opened, no further attempts"
    exit 2
  fi
```

Contract points:
- **Signature is verbatim identical** to `codex-task.sh:413` (`hit your usage limit|usage limit
  reached|rate limit exceeded`). One signature, two call sites — do not invent a third variant.
- `codex_circuit_parse_until` reads **stdin** (it is a `grep -oiE` with no file operand); it must
  be fed by pipe, not given a path. This is the wiring that retires M6 (dead code).
- Empty `_lim_until` is legal: `codex_circuit_open` maps empty → now+24h. Do not synthesise a
  fallback horizon at this call site.
- `declare -F` guards keep the runner's existing fail-open-on-missing-lib posture for the
  *writer* path (the *reader* path stays fail-closed at the gate, unchanged).
- Exit code **2** — same code the gate refusal already uses (line ~504), i.e. the router's
  "refused, try the next candidate" contract. Not 3 (budget exhausted) and not 1.
- **Stop retrying, unconditionally.** A wall does not yield to `RETRY_SLEEP_S`.

Ordering note: this sits *after* `_launcher_spawn_detected` (recursion, exit 5) — recursion is a
correctness violation and must keep priority over a quota refusal. It sits *before* the
`sentinel_present` check only in the sense of the retry decision; a completed task that also
printed a limit line still exits 0 via the sentinel check — so place the block after the
recursion guard and before `progress_after`, as specified.

---

## 2. C2 — Group F: session-runner ↔ gate integration tests

**File:** `plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh` (append new group before
the final tally at line 354). `RUNNER_SH` (line 14) is currently declared and never used; these
tests are what makes it live.

**Shared harness (new, added to the stub block ~line 55):**

| Need | Approach |
|---|---|
| `flock` | present at `/opt/homebrew/bin/flock`; do **not** assume — add a `flock` stub to `$STUBBIN` that `exec "$@"`-style no-ops (`shift; exit 0`) only if `command -v flock` fails, else rely on the real one. Simpler and deterministic: always stub, since the test uses a private `TASK_DIR`. |
| `codex login status` | set `LEADV2_CODEX_SKIP_LOGIN_CHECK=1` (existing env hatch, line ~128). |
| control-plane resolution | set `LEADV2_CODEX_CIRCUIT_FILE`, `LEADV2_ARM_COOLDOWN_DIR`, and **`LEADV2_COMPLETION_RECEIPT`** explicitly. The last one matters: the unset default runs `leadv2-state-path.sh` inside a command substitution under `set -e`, which aborts the runner in a non-git temp root. |
| project root | `LEADV2_PROJECT_ROOT="$F_ROOT"` (fresh `mktemp -d` per test); runner creates `$F_ROOT/docs/handoff/$TASK_ID`. |
| attempts | `LEADV2_RUNNER_MAX_ATTEMPTS=1 LEADV2_RUNNER_RETRY_SLEEP_S=0`. |
| codex binary | `LEADV2_CODEX_BIN` → a per-test stub (see below); `PATH="$STUBBIN:$PATH"` for `flock`. |
| progress tool | `LEADV2_PROGRESS_FINGERPRINT` → stub printing a constant (avoids git). |

**f1 — pre-opened circuit ⇒ exit 2, zero codex invocations.**
Write `{"until":"<now+12h>",…}` to `$F1_CIRCUIT`. Stub `codex` = `echo "INVOKED $*" >> "$F1_ARGV"; exit 0`
(the login-status path is skipped, so any line in `$F1_ARGV` is a real spawn). Run the runner.
Assert: rc == 2 **and** `$F1_ARGV` does not exist / is empty **and** the runner log carries
`refused by quota gate`. The empty-argv assertion is the whole point — this is the test that
would have caught C1's sibling failure mode.

**f2 — stubbed codex emits the usage-limit line ⇒ circuit marker appears with the parsed horizon.**
Stub `codex` writes a JSON-ish log line to stdout (the runner redirects stdout+stderr into
`$LOGF`) containing both a `thread.started` event (so `THREAD_ID` capture succeeds and the run
does not exit 3 first) and the wall text:

```
{"type":"thread.started","thread_id":"th_f2"}
Codex error: You've hit your usage limit. Please try again at Aug 8th, 2026 08:49 AM
```
then `exit 1`. Circuit file starts absent. Assert, in the same shape as c3/c5:
- rc == 2;
- `$F2_CIRCUIT` exists and its `until` == `2026-08-08T08:49:00Z` (fixed date ⇒ exact equality, no ±window);
- captured runner stderr contains exactly one `codex_circuit_open until=2026-08-08T08:49:00Z` line;
- `$F2_ARGV` has exactly **1** spawn line (proves it stopped retrying rather than burning 6).

**f3 — fail-closed when the gate is unavailable ⇒ exit 2, no spawn.**
The runner sources the lib by absolute `$SCRIPT_DIR/lib/…` path, so it cannot be hidden by PATH.
Drive the branch the way the branch is actually written (`declare -F codex_spawn_gate` false):
copy the runner and its `lib/` into a scratch tree, delete `lib/leadv2-codex-quota-gate.sh`
there, and run the copy with `CODEX_SKIP_QUOTA_GATE=0`. Assert rc == 2 and log line
`quota gate unavailable`. (Copying is confined to `$BASE`; nothing under the repo is mutated.)
If the copy proves brittle, the accepted fallback is to run the runner with a `SCRIPT_DIR`-shadowing
scratch dir containing symlinks to every `scripts/` entry except the quota-gate lib — same assertion.

New pass count: **+3** (f1, f2, f3), plus the d2 rewrite (§3) and the c2 rewrite (§5) which stay
at 1 assertion each. Expected total after the round: **19** (was 16).

---

## 3. H3 — remove the unreachable `LEADV2_CODEX_SANCTIONED` hatch

**File:** `plugins/leadv2/hooks/leadv2-codex-direct-exec-guard.sh`

Delete **line 12** (`#   - LEADV2_CODEX_SANCTIONED=1 env (set by the runner scripts themselves)`)
and **line 41** (`[[ "${LEADV2_CODEX_SANCTIONED:-}" == "1" ]] && exit 0`).

Why it is structurally dead, not merely unused: a `PreToolUse:Bash` hook is a fresh process
spawned by the Claude host, not a child of the runner script. An `export` inside
`leadv2-codex-session-runner.sh` is invisible to it, and no caller sets it in the host's own
environment (`grep -rn LEADV2_CODEX_SANCTIONED plugins/` returns only the hook + its test).
`LEADV2_ALLOW_DIRECT_CODEX` is genuinely different — a human exports it in the shell the host
inherits — and **stays**.

After removal, the name-substring allowlist (line 35-38) is the sole runner-recognition
mechanism, which is correct: it inspects the *command text* the hook actually receives.

**Post-removal check:** line 41 currently ends a `[[ … ]] && exit 0` one-liner. It is the last
statement before an `if`; deleting it does not change `set -u`/`trap ERR` semantics. Verify the
remaining `# Env overrides.` comment (line 40) still reads correctly — reword to
`# Escape hatch (human-set in the invoking shell).`

**Test d2 (lines 281-289) is inverted, not deleted.** It manufactured false confidence; deleting
it would silently permit the hatch's reintroduction. New d2:

```
# d2: LEADV2_CODEX_SANCTIONED is NOT an escape hatch (removed — hook procs never
# see a sibling's exports). Must still block.
```
`LEADV2_CODEX_SANCTIONED=1 bash "$HOOK_SH"` on a `codex exec` payload ⇒ **rc 2** + `BLOCKED`.

**Exec bit:** the file is untracked (`??`). Run `chmod +x` on it and confirm
`git add --chmod=+x` is unnecessary because git records the on-disk mode for a new file —
verify with `git ls-files -s` after a dry `git add -n`, or simply assert `[[ -x ]]` before
handing off. Do not commit.

---

## 4. M4 — codex-task.sh calls `codex_spawn_gate` instead of the hand-copied block

**File:** `plugins/leadv2/scripts/codex-task.sh`

1. After line 104 (`source …/lib/leadv2-codex-circuit.sh`), add, in the same unguarded style:
   ```
   # CODEX-QUOTA-GUARDRAILS-01 — shared spawn gate (cooldown + circuit).
   source "${_CODEX_SCRIPT_DIR}/lib/leadv2-codex-quota-gate.sh"
   ```
   Unguarded (no `|| true`) matching the two sources above it: a missing lib is a hard failure,
   not a silent ungated spawn. The lib's own internal sources are already idempotent
   (`command -v arm_cooldown_state` guard), so double-sourcing `leadv2-arm-cooldown.sh` /
   `leadv2-codex-circuit.sh` is a no-op.

2. In `_codex_quota_gate` (line 270), **keep** the `CODEX_SKIP_QUOTA_GATE` short-circuit and the
   `case "$SUB"` dispatch (the lib has no concept of subcommands), and **replace lines ~278-309**
   — the cooldown `case` and the circuit `case`, both of them — with:
   ```
   codex_spawn_gate "$SUB" || exit "$?"
   ```
   `exit "$?"` (not a literal `exit 2`) preserves whatever refusal code the lib returns, per the
   mission wording. The lib prints the identical two stderr lines the deleted block printed
   (`[codex-task] CODEX_REFUSED_QUOTA reason=… ` + `LEADV2_DISPATCH_REFUSED: quota_gate`) — the
   marker text was copied from here, so no observable output changes and e1/e2 stay green.

3. The threshold check (lines ~311-323) is **unchanged** and stays in `codex-task.sh` — it needs
   `_codex_quota_routing_yaml` / `_codex_quota_read`, which are not in the lib. Note it consumes
   `"$@"`; `codex_spawn_gate "$SUB"` does its own `shift`, on its *own* positional list, so the
   caller's `"$@"` is untouched.

Behavioural delta to watch: the deleted block used `arm_cooldown_state codex` with no `2>/dev/null`,
the lib uses `2>/dev/null || true`. Strictly more forgiving; no gate weakening (an errored
cooldown read was never a refusal in either version).

---

## 5. M5 — c2 must prove the 24h default through real code

**File:** `plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh`, lines 188-211.

Current c2 pipes `rate limit exceeded` into `codex_circuit_open`, which reads no stdin — the pipe
is decorative and the test proves only "open with an empty first arg defaults to 24h", never that
the *real* unparseable path yields an empty first arg.

Replacement drives the same two-step the runner now performs (§1), against a fixture log:

```
C2_LOG="$BASE/c2-fixture.log"
printf '%s\n' \
  '{"type":"thread.started","thread_id":"th_c2"}' \
  "Codex error: rate limit exceeded, retry soon" > "$C2_LOG"
# step 1 — real parser on real unparseable provider text ⇒ rc 1, empty stdout
C2_UNTIL="$(cat "$C2_LOG" | bash -c "source '$CIRCUIT_LIB'; codex_circuit_parse_until" 2>/dev/null || true)"
# step 2 — feed that empty result to the real opener
LEADV2_CODEX_CIRCUIT_FILE="$C2_CIRCUIT" \
  bash -c "source '$CIRCUIT_LIB'; codex_circuit_open '$C2_UNTIL' 'test'" 2>"$C2_JOURNAL"
```
Assert **both**: `[[ -z "$C2_UNTIL" ]]` (the parser genuinely declined) **and** the existing
±120s now+24h window on `codex_circuit_state`. One `pass`/`fail` call as today — the two
conditions are `&&`-joined so the count stays at 1.

---

## 6. LOW — unused `sub` in `codex_spawn_gate`

`plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh:30` — `local sub="${1:-}"` is assigned and
never read. **Drop the assignment, keep `shift || true`** so the signature `codex_spawn_gate <sub>
[args…]` is preserved for callers (§4 passes `"$SUB"`; the runner passes `exec`).

Do *not* interpolate `sub` into the refusal lines: `LEADV2_DISPATCH_REFUSED: quota_gate` and
`reason=circuit` are grepped by c3/e1 and by the live router's fallback chain; changing the line
shape is out of scope for a LOW.

---

## 7. Files written

| File | Findings addressed |
|---|---|
| `plugins/leadv2/scripts/leadv2-codex-session-runner.sh` | C1, M6 (wires dead parser) |
| `plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh` | C2 (Group F), H3 (d2 inversion), M5 (c2 rewrite) |
| `plugins/leadv2/hooks/leadv2-codex-direct-exec-guard.sh` | H3 |
| `plugins/leadv2/scripts/codex-task.sh` | M4 |
| `plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh` | LOW |

`plugins/leadv2/scripts/lib/leadv2-codex-circuit.sh`, `leadv2-codex-planner.sh`,
`hooks/hooks.json`, `tests/run-core-offline.sh` are **untouched** — the suite is already
registered at `run-core-offline.sh:78`.

---

## 8. Non-goals (implementing agent: ignore)

- Do **not** add new env vars. Every knob used here already exists
  (`LEADV2_CODEX_CIRCUIT_FILE`, `LEADV2_ARM_COOLDOWN_DIR`, `LEADV2_COMPLETION_RECEIPT`,
  `LEADV2_CODEX_SKIP_LOGIN_CHECK`, `LEADV2_RUNNER_MAX_ATTEMPTS`, `CODEX_SKIP_QUOTA_GATE`) and
  all carry the `LEADV2_*` / `CODEX_*` prefixes already in `.claude/settings.json`.
- Do **not** unify the two usage-limit signature strings into a shared constant — that is a
  cross-file refactor beyond the 5 touched files.
- Do **not** move the threshold check into the gate lib.
- Do **not** touch `codex-task.sh`'s `_codex_quota_watch_record` / `_codex_reap`.
- Do **not** write into `~/.claude/plugins` cache. Do **not** commit. Do **not** touch the main
  checkout.
- Do **not** register a new suite in `run-core-offline.sh`.
- No changes to `hooks.json` (the hook is already wired there in round 1).

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| f2's stub must produce a `thread.started` line or the runner exits 3 before reaching the new block | fixture line specified in §2; assert rc==2 not rc==3 to catch it |
| `LEADV2_COMPLETION_RECEIPT` unset ⇒ `leadv2-state-path.sh` under `set -e` kills the runner in a temp root before any assertion | set it explicitly in every Group F test |
| Re-scanning the whole `$LOGF` would re-open the circuit off a stale message | detection window pinned to `tail -c "+$((log_size_before+1))"` |
| `codex_circuit_parse_until` given a path instead of stdin returns nothing ⇒ silent 24h default masking a parseable horizon | f2 asserts the **exact** `2026-08-08T08:49:00Z`, so a stdin/argv mistake fails the test |
| M4 changes stderr wording ⇒ router fallback chain / e1 regress | lib text is a verbatim copy of the deleted block; e1 (`circuit-unknown`) and c3 (`reason=circuit`) are the regression guard |
| Group F leaves a stray flock / lock file | each test uses a fresh `mktemp -d` under `$BASE`, removed by the existing `trap … EXIT` |
| Hook exec bit lost when the untracked file is later staged | assert `[[ -x hooks/leadv2-codex-direct-exec-guard.sh ]]` before handing off; `chmod +x` if not |
| `bash 3.2` (macOS `/bin/bash`) rejects a construct | `bash -n` under both `/bin/bash` and `/opt/homebrew/bin/bash` on all 5 touched files; avoid `${var^^}`, `declare -A`, `&>>` |

---

acceptance:
  - surface: log_line
    observable: "When Codex replies with a usage-limit refusal, the session-runner log shows
      one `codex_circuit_open until=<timestamp>` line followed by
      `codex usage limit hit … circuit opened, no further attempts`, and no further
      `attempt N/6: codex …` lines appear after it."
    authored_at: 2026-08-04T00:00:00Z
  - surface: file_artifact
    observable: "The control-plane file `codex-circuit.json` exists after that refusal and its
      `until` field reads the timestamp Codex named in its `try again at …` message (not a
      generic 24-hour placeholder)."
    authored_at: 2026-08-04T00:00:00Z
  - surface: log_line
    observable: "`test-codex-quota-guardrails.sh` finishes with
      `[CODEX-QUOTA-GUARDRAILS] pass=19 fail=0`, and its output lists PASS lines named f1, f2 and
      f3 for the session-runner gate integration."
    authored_at: 2026-08-04T00:00:00Z
  - surface: log_line
    observable: "`run-core-offline.sh` finishes reporting the same number of passing checks as
      this worktree's pre-change baseline (30) with zero failures."
    authored_at: 2026-08-04T00:00:00Z
  - surface: log_line
    observable: "A shell that exports LEADV2_CODEX_SANCTIONED=1 and asks Claude to run
      `codex exec …` still sees the `[leadv2-codex-direct-exec] BLOCKED direct 'codex exec'`
      message — the variable no longer opens the guard."
    authored_at: 2026-08-04T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-codex-session-runner.sh, plugins/leadv2/scripts/codex-task.sh, plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh, plugins/leadv2/scripts/tests/test-codex-quota-guardrails.sh, plugins/leadv2/hooks/leadv2-codex-direct-exec-guard.sh

DELIVERABLE_COMPLETE
