Product implementation task dispatch-7f6f12e2. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# DISPATCH-FG-GUARD-01 — round 2 implementation design (architect prepass)

Lane: `.claude/worktrees/40241035`, branch `worktree-40241035`, HEAD `b40800f` (round 1).
Round 1 is **kept**. Round 2 is a rewrite of the hook's decision core plus test additions.

---

## 0. Base-update correction — READ FIRST (blocking-if-followed-literally)

The mission says: `git fetch && git merge --ff-only origin/main`.

**That command will fail.** The lane has diverged: `git rev-list --left-right --count main...worktree-40241035` = **9 / 1**. The lane holds one commit (`b40800f`) that `main` does not, so a fast-forward is impossible by definition. Round 1's "1628 phantom deletions" is exactly this divergence, not a broken diff.

Use instead, from inside the lane worktree:

```
git fetch origin
git rebase origin/main          # 1 commit to replay; round 1 touches 5 files, 4 of them new
```

If the rebase conflicts on `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (the only pre-existing file round 1 modified — `3398d11` and `feff89d` both touched dispatch), resolve keeping **both** sides: round 1's C3 enrichment is additive to the arm-registration changes. `hooks.json` may also conflict trivially (array append) — keep both entries.

Do not `git merge origin/main` without `--ff-only` as a silent substitute: a merge commit in a lane is acceptable but makes the reviewer's diff read as the whole of main again. Rebase gives the reviewer a 2-file diff.

---

## 1. Root cause, restated precisely

Both F1 and F2 are the same defect seen from two sides: **the hook evaluates every predicate against the whole command string, when the only thing that matters is the one shell segment that actually executes a launcher.**

- F1 (false negative): an exemption token anywhere in the string exempts a foreground dispatch that lives in a *different* segment.
- F2 (false positive): a launcher basename anywhere in the string triggers the guard even when no segment executes it.

So round 2 introduces exactly one new concept — **the launcher-execution segment** — and re-points every existing predicate at it. No predicate's own regex needs to change except where it is now anchored to a segment instead of the string.

---

## 2. Layers affected

| Layer | File | Change |
|---|---|---|
| Hook decision core | `plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh` | Rewrite lines 18–68: python3 pass now also lexes+segments; bash loops over launcher-exec segments |
| Hook refusal text | same file, lines 71–79 | Drop the now-false "if you were only reading the file" line |
| Regression suite | `plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh` | Fix test 21; add tests 22–29 |

**Unchanged, do not touch:** `hooks.json` (registration is correct), `leadv2-dispatch-code.sh` (C3 accepted as-is), `run-core-offline.sh` (suite already registered by round 1).

---

## 3. Data flow (numbered)

1. PreToolUse:Bash delivers the tool-call JSON on stdin.
2. Fail-open guard A: empty stdin → exit 0. (unchanged, line 13)
3. Env override `LEADV2_ALLOW_FG_DISPATCH=1` → exit 0. (unchanged, line 16)
4. **Single python3 pass** reads the JSON and emits a 3-field record on stdout:
   - line 1 — `RIB`: `"true"` / `"false"` / `""` (tri-state, unchanged semantics)
   - line 2 — `SEGS`: the launcher-execution segments, joined by `\x1f` (US, `chr(31)`), each with internal newlines collapsed to single spaces. **Empty line if none.**
   - line 3+ — `CMD`: the original command verbatim (may contain newlines; therefore must be last).
   On any exception the script writes nothing.
5. Fail-open guard B: `_PARSE_OUT` empty, or `CMD` empty after field split → exit 0. (python3 absent → empty → exit 0; degradation behaviour is preserved bit-for-bit)
6. Override comment `# fg-dispatch: allow` present anywhere in `CMD` → exit 0. (intentionally still whole-string: it is an author-intent marker, not a shape predicate)
7. **`SEGS` empty → exit 0.** This is the F2 fix: `cat …`, `git log -- …`, `grep -n foo …` produce no launcher-execution segment and are allowed with no override.
8. For each segment `S` in `SEGS`, evaluate the allow-tests **against `S` alone**. A segment is *allowed* if any of:
   - a. `RIB == "true"` (tool-level field, global by nature — applies to all segments)
   - b. `S` matches `--no-spawn|LEADV2_DISPATCH_SPAWN=0`
   - c. `S` matches `--help` or a whole-word `-h`
   - d. `S` matches whole-word `status` or `record-review`
   - e. `S` ends in a trailing `&` (`[[:space:]]&[[:space:]]*(#.*)?$`)
   - f. `S` contains `nohup.*&`
   - g. `S` contains `setsid`
9. If **every** segment is allowed → exit 0. If **any** segment is not → emit the refusal on stderr and exit 2.
10. ERR trap → exit 0 (fail-open guard C, unchanged).

Note step 9's quantifier: any single unguarded foreground launcher segment denies the whole command, even if a sibling segment is exempt. That is the correct polarity — the guard exists to stop one process from being SIGTERM'd.

---

## 4. The lexer contract (python3, step 4)

This is the only genuinely new logic. Specify it tightly; the implementer should not improvise.

### 4.1 Segmentation

Split `cmd` on **unquoted** occurrences of, in this precedence order: `&&`, `||`, `;`, `|`, and a literal newline.

- Track single-quote and double-quote state while scanning; a separator inside quotes is not a separator.
- Track backslash escaping outside single quotes.
- **Do NOT split on a bare `&`.** It stays inside its segment so the trailing-`&` background test (step 8e) still sees it. `&&` must be consumed as one token before `&` is ever considered — a naive `|`-then-`||` or `&`-then-`&&` order silently breaks tests 16 and 2.
- Do not attempt to parse subshells `(...)`, `$(...)`, or heredocs. Out of scope; see §7.

### 4.2 Tokenising a segment

Prefer `shlex.split(seg)` inside `try/except ValueError`; on `ValueError` (unbalanced quote) fall back to `seg.split()`. Never let a lexing error propagate — it would take the whole hook to fail-open and silently disable the guard.

### 4.3 Execution-position test

Given tokens `t[0..n]` of a segment:

1. Drop leading `VAR=value` assignments — token matches `^[A-Za-z_][A-Za-z0-9_]*=`.
2. Drop leading wrapper commands: `nohup`, `setsid`, `env`, `command`, `exec`, `time`, `sudo`.
3. Let `head` = the first remaining token.
4. The segment is a **launcher-execution segment** iff either:
   - `basename(head)` ∈ GUARDED, or
   - `basename(head)` ∈ {`bash`, `sh`, `zsh`, `dash`, `source`, `.`} **and** some later token's `basename()` ∈ GUARDED.
5. `GUARDED = {leadv2-dispatch-code.sh, leadv2-codex-session-runner.sh, leadv2-fanout.sh, glm-coder.sh, omp-task.sh}` — one literal set, defined once. It currently appears once as a bash alternation regex (line 48); after this change it lives in the python block. Do not duplicate it in both places.

Why this subsumes the read-only allowlist the mission described: `cat`, `less`, `head`, `tail`, `grep`, `rg`, `git`, `ls`, `stat`, `wc`, `diff` all fail rule 4 at `head` — none is a launcher and none is an interpreter. An explicit read-only verb list would be redundant *and* would be a maintenance trap (the first verb someone forgets gets blocked again). **Recommend: do not add an allowlist.** State this in the commit message so the reviewer does not read its absence as an omission.

---

## 5. Interface contract — the parse record

| Field | Line | Type | Empty means |
|---|---|---|---|
| `RIB` | 1 | `true` \| `false` \| `""` | key absent from tool_input (tri-state; **not** false) |
| `SEGS` | 2 | `\x1f`-joined strings, newlines→spaces | no launcher-execution segment → allow |
| `CMD` | 3..∞ | verbatim command | parse failed → fail-open |

Bash-side split (order matters; `CMD` is the remainder, so it is extracted last):

```
RIB="${_PARSE_OUT%%$'\n'*}"
_REST="${_PARSE_OUT#*$'\n'}"
SEGS_RAW="${_REST%%$'\n'*}"
CMD="${_REST#*$'\n'}"
```

Iterate segments with `IFS=$'\x1f' read -r -d '' -a SEGS < <(printf '%s\x1f' "$SEGS_RAW")` or the simpler `while IFS= read -r -d $'\x1f' seg` loop. Do **not** use unquoted word-splitting on `$SEGS_RAW` — segments contain spaces and glob metacharacters.

Why `\x1f` and not newline: `CMD` is already the multi-line remainder field, so a second newline-delimited variable-length field is unparseable by prefix/suffix expansion. `\x1f` cannot appear in a realistic shell command and needs no escaping.

---

## 6. Test plan

`plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh`. All 24 existing assertions must stay green; each of the following must fail against `b40800f` and pass after.

| # | Input command | Expect | Proves |
|---|---|---|---|
| 21 (**replace**) | `bash …/leadv2-dispatch-code.sh @m.md && bash leadv2-status-surface.sh` | DENY | old test 21 never reached the exemption regex; this one does. Relabel: "later segment named *status*-something does not exempt the dispatch segment" |
| 22 | `bash …/leadv2-dispatch-code.sh @m.md && git status` | DENY | F1, `&&` |
| 23 | `bash …/leadv2-dispatch-code.sh @m.md ; git status` | DENY | F1, `;` |
| 24 | `bash …/leadv2-dispatch-code.sh @m.md && echo done --help` | DENY | F1, `--help` has the same hole |
| 25 | `bash …/leadv2-dispatch-code.sh status` | ALLOW | real subcommand still exempt (no regression) |
| 26 | `bash …/leadv2-dispatch-code.sh @m.md --no-spawn` | ALLOW | real flag still exempt |
| 27 | `cat leadv2-dispatch-code.sh` | ALLOW, **no override token in input** | F2 |
| 28 | `git log -- plugins/leadv2/scripts/leadv2-dispatch-code.sh` | ALLOW | F2 |
| 29 | `bash …/leadv2-dispatch-code.sh @m.md &` | ALLOW | background test survives segmentation |

Recommended extras (cheap, guard the new lexer specifically — the segmenter is where a round-3 defect would live):

| # | Input | Expect | Proves |
|---|---|---|---|
| 30 | `echo "run leadv2-dispatch-code.sh status" && bash …/leadv2-dispatch-code.sh @m.md` | DENY | quoted separator/token not mistaken for structure |
| 31 | `bash …/leadv2-dispatch-code.sh @m.md \| tee /tmp/x.log` | DENY | `\|` splits, dispatch segment still foreground |
| 32 | `grep -rn "leadv2-fanout.sh" plugins/` | ALLOW | F2 for a second guarded launcher, launcher inside a quoted arg |

For 27/28/32 the assertion must additionally check that `/tmp/fg-guard-last-stderr` is empty — an "allow" that still printed the refusal would pass a naive exit-code-only check.

Update the trailing count comment/header if the suite advertises a case count anywhere, and confirm `run-core-offline.sh` still reports the suite (registration line added in round 1, unchanged).

---

## 7. Risks and mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Operator-precedence bug in the segmenter: matching `&` before `&&`, or `\|` before `\|\|`, breaks existing tests 2 and 16 | **High** — silently re-opens the guard | Consume two-char operators first; test 16 (`&& echo done` → DENY) and test 2 (trailing `&` → ALLOW) are the canaries and already exist |
| R2 | A lexing exception escapes and trips the ERR trap → hook exits 0 for *every* command, guard silently dead | **High** | `try/except Exception` around the whole python body (already the round-1 shape); `shlex` call individually wrapped; test 14 (malformed JSON) covers the outer path — add no new uncaught call sites |
| R3 | Subshell / `$( )` / heredoc bodies are not parsed; `$(bash dispatch.sh @m.md)` is not recognised as an execution segment | Medium | **Accept and document.** Correct handling needs a real shell parser. Note it in the hook header comment as a known residual; the override + `run_in_background` paths make it recoverable, and the failure mode is a false *negative* on an exotic shape, matching the guard's fail-open philosophy |
| R4 | `xargs bash leadv2-dispatch-code.sh`, `find … -exec bash …`, `ssh host 'bash …'` are not execution-position matches | Low | Accept; same rationale as R3. Do not chase by adding `xargs`/`find` to the wrapper-strip list — stripping `xargs` would make `xargs grep leadv2-dispatch-code.sh` a false positive again |
| R5 | GUARDED set duplicated in both python and the old bash regex, drifting apart | Medium | Delete the bash regex at line 48 entirely; the set lives in exactly one place. Grep the final file for `leadv2-codex-session-runner` — exactly one occurrence expected |
| R6 | Rebase onto `origin/main` conflicts in `leadv2-dispatch-code.sh` (touched by `3398d11`, `feff89d`) | Medium | Keep both sides — C3 enrichment is additive. Re-run the full core-offline suite after the rebase, not only this suite |
| R7 | Deny-message line "If you were only reading the file (grep/cat/echo), append `# fg-dispatch: allow`" becomes false advice | Low | Delete that line; reads no longer trigger the hook. Test 1 asserts on four other strings, so it will not break — verify before editing |
| R8 | Bash iteration over `$SEGS_RAW` via unquoted expansion glob-expands a segment containing `*` | Medium | Use the `IFS=$'\x1f'` read-loop form given in §5; never bare `for s in $SEGS_RAW` |

### Mandatory constraint checklist

1. **Env var naming** — `LEADV2_ALLOW_FG_DISPATCH`, `LEADV2_DISPATCH_SPAWN`: both `LEADV2_*`, consistent with round 1 and with `leadv2-block-fg-agent.sh`'s `LEADV2_ALLOW_FG`. No new env vars introduced. PASS.
2. **File paths** — both write-set paths exist on disk in the lane worktree (`.claude/worktrees/40241035`). Neither exists on `main` yet for the two new files; that is expected pre-merge. PASS.
3. **`claude -p` commands** — none introduced by this change. N/A.
4. **Concurrent access** — the hook is stateless and read-only; the test suite writes `/tmp/fg-guard-last-stderr` and `/tmp/fg-guard-stderr.$$`. The `$$`-suffixed temp is per-process but `/tmp/fg-guard-last-stderr` is **not** — two concurrent runs of this suite would clobber each other. Pre-existing in round 1, low impact (core-offline runs suites serially). Optional cleanup: suffix it with `$$` too. Not required for PASS.
5. **Config contradiction check** — no env-var semantics changed. PASS.

---

## 8. Out of scope (implementer: ignore these)

- `leadv2-dispatch-code.sh` C3 enrichment — reviewed clean, do not re-touch.
- `hooks.json` — registration correct, do not re-touch.
- The internal-subprocess deadlock question — review confirmed non-reproducible.
- python3-absent degradation — already correct via fail-open; do not add a fallback path.
- argv-replay `%q` quoting — reviewed clean.
- Widening the GUARDED launcher set.
- Any shell-parser dependency (`bashlex` etc.) — no new dependencies; python3 stdlib only.
- The `.claude/scripts/tests/` stale-copy tree — separate open thread, not this lane.

---

## 9. Non-goals

- Not a full shell grammar. R3/R4 shapes stay unhandled, by decision.
- Not adding a read-only-verb allowlist (§4.3 rationale).
- Not changing deny polarity, exit codes, or the override tokens.

---

acceptance:
- surface: rendered_line
  observable: A lead runs the dispatch launcher chained with a second command (`… leadv2-dispatch-code.sh @mission.md && git status`) and the terminal shows the "[leadv2-block-fg-dispatch] BLOCKED" refusal with the `… &` re-run suggestion, instead of the command running and the dispatch dying silently at the 2-minute mark.
  authored_at: 2026-08-05T00:00:00+03:00
- surface: rendered_line
  observable: A lead runs `cat plugins/leadv2/scripts/leadv2-dispatch-code.sh` or `git log -- plugins/leadv2/scripts/leadv2-dispatch-code.sh` and sees the file contents / commit list, with no refusal text and without having appended any override comment.
  authored_at: 2026-08-05T00:00:00+03:00
- surface: log_line
  observable: The core-offline suite run prints a PASS line for the fg-dispatch-guard suite with FAIL=0, at a case count higher than 24, and the overall run reports 0 failed and 0 missing suites.
  authored_at: 2026-08-05T00:00:00+03:00

LANE_WRITES: plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh, plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# DISPATCH-FG-GUARD-01 — fix round 2 (plugin repo ~/Projects/leadv2)

Round 1 (commit `b40800f`) was reviewed and BLOCKED. Continue from your existing edits in this
lane — do not start over, do not revert round 1. Full review:
`~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/fgguard-review.md`.

## F1 — CRITICAL, blocking. The exemption defeats the guard.
`plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh:56-58` greps the WHOLE command string for the
`status` / `record-review` / `--help` / `-h` / `--no-spawn` exemptions, instead of the launcher's
own argv. So this is silently ALLOWED and the dispatch still dies to SIGTERM:

    bash .../leadv2-dispatch-code.sh @m.md && git status
    bash .../leadv2-dispatch-code.sh @m.md ; git status

Reproduced live against this worktree.

Fix: split the command on `&&`, `||`, `;` and `|` FIRST, find the segment that contains the matched
launcher basename, and evaluate every exemption against that segment alone. Apply the same scoping
to all four exemptions, not only `status` — `--help` and `--no-spawn` have the identical shape and
the identical hole.

## F2 — HIGH, non-blocking but fix it now. Read-only commands are blocked.
The target match (around :48) is a bare grep for the launcher basename with no verb check, so
`cat leadv2-dispatch-code.sh`, `git log -- leadv2-dispatch-code.sh`, `grep -n foo
leadv2-dispatch-code.sh` are all denied. These are exactly the files a lead reads while working on
this subsystem, so it will fire constantly. Require that the launcher appear in an EXECUTION
position — first word of the segment, or the argument to `bash`/`sh`/`zsh`/`source`/`.` — and let
read-only verbs (`cat`, `less`, `head`, `tail`, `grep`, `rg`, `git`, `ls`, `stat`, `wc`, `diff`)
through without needing the override.

## F3 — the test suite passes 24/24 and covers NEITHER bug.
Test 21, "status subcommand does not match path fragment", is mislabeled: its input
(`leadv2-status-surface.sh`) fails the basename target-match before it ever reaches the exemption
regex it claims to exercise. It proves nothing.

Add tests that FAIL against round 1's code and pass after the fix:
- `bash .../leadv2-dispatch-code.sh @m.md && git status` → DENIED
- `bash .../leadv2-dispatch-code.sh @m.md ; git status` → DENIED
- `bash .../leadv2-dispatch-code.sh @m.md && echo done --help` → DENIED
- `bash .../leadv2-dispatch-code.sh status` → ALLOWED (real subcommand, unchanged)
- `bash .../leadv2-dispatch-code.sh @m.md --no-spawn` → ALLOWED
- `cat leadv2-dispatch-code.sh` → ALLOWED, no override needed
- `git log -- plugins/leadv2/scripts/leadv2-dispatch-code.sh` → ALLOWED
- `bash .../leadv2-dispatch-code.sh @m.md &` → ALLOWED
Fix test 21's label, or delete it and replace it with one that actually reaches the exemption path.

## Unchanged and confirmed clean by review — do not touch
Internal-subprocess deadlock, python3-absent degradation, argv-replay quoting, fail-open discipline.
The C3 message change is accepted as-is.

## Write set
Same as round 1. Do not widen it.

## Acceptance
All new tests above green, the existing 24 still green, from a base that is up to date with
`origin/main` (`git fetch && git merge --ff-only origin/main` first — round 1 branched from a stale
base and its diff read as 1628 phantom deletions).

## Return
`PASS|FAIL|BLOCKED` + changed paths + commit + raw test output.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-7f6f12e2" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.