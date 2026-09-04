# CTX-COST-GUARDS-01B — architect prepass (mechanism-closed)

## 0. The mission's framing is stale — design is against the code

The mission says "**Nothing guards diff reading**" and asks for a new sub-guard. That was true at
authoring time; it is not true at HEAD. Verified in the tree, this worktree, base `4b51d96`:

- `plugins/leadv2/hooks/leadv2-warn-bash-diff-read.sh` **exists** (9803 bytes, 323 lines).
- It **is** wired: `plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh:66` (last MANIFEST row).
- Commit `4b51d96 feat: warn/deny sub-guard for Bash-side diff reads (CTX-COST-GUARDS-01)`.

So 01B is not "build the guard". It is **close the bypasses in the guard that shipped, and make it
actually run**. Everything below is derived from probing the shipped file, not from the brief.

**Headline finding — the guard is not live.** The runtime loads the plugin *cache*, which is a real
copy, not the one-inode symlink the rest of the plugin uses (CLAUDE.md, "Hooks are the exception to
one-inode"). Probe:

```
$ for f in .../cache/leadv2-local/leadv2/0.2.1/hooks .../0.2.2/hooks; do
    grep -c warn-bash-diff-read "$f/leadv2-bash-pre-dispatch.sh"; ls "$f/leadv2-warn-bash-diff-read.sh"; done
0
ls: .../0.2.1/hooks/leadv2-warn-bash-diff-read.sh: No such file or directory
0
ls: .../0.2.2/hooks/leadv2-warn-bash-diff-read.sh: No such file or directory
```

Both cached dispatchers still carry the pre-`4b51d96` manifest and neither has the sub-guard file.
CTX-COST-GUARDS-01 is committed and inert: on the running path, a Bash-side diff read is still
completely unguarded. Any acceptance for 01B that stops at "the repo file warns" repeats that miss.

---

## 1. CALLERS / CALLEES

### Callers of `leadv2-warn-bash-diff-read.sh`

| Caller | Where | Note |
|---|---|---|
| `leadv2-bash-pre-dispatch.sh` MANIFEST row | `plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh:66` | Trigger ERE: `\.(diff\|patch)([[:space:]]\|"\|'\|$)` **or** `(^\|[^A-Za-z0-9_-])git[[:space:]]+(diff\|show)([[:space:]]\|$)` |
| Actual exec | `leadv2-bash-pre-dispatch.sh:80` — `printf '%s' "$INPUT" \| "$SCRIPT_DIR/$SCRIPT"` | stdin = the full PreToolUse JSON, identical for every sub-guard |
| Registration (dispatcher, not the sub-guard) | `plugins/leadv2/hooks/hooks.json:176` — `PreToolUse:Bash` | `hooks.json` is **not** touched by 01B |
| **Independent copy nobody named** | `~/.claude/plugins/cache/leadv2-local/leadv2/{0.2.1,0.2.2}/hooks/` | real copies, both stale — see §0. This is the "different path" miss for this mechanism |

There is no second in-repo caller: the guard is invoked only through the dispatcher manifest loop.
`~/.claude/plugins/local/leadv2/.../leadv2-warn-bash-diff-read.sh` is inode `277828620` — the same
inode as the repo file, so the local-plugin view needs no propagation. Only the cache does.

### Callees of the guard

| Callee | Line | Failure behaviour |
|---|---|---|
| `cat` (stdin slurp) | `:19` | `\|\| true`, empty → `exit 0` |
| `python3` (classifier heredoc-less `-c`) | `:24-297` | `2>/dev/null \|\| true`; missing python3 → empty DECISION → `exit 0` |
| `python3` (allow-JSON emitter) | `:310-320` | on failure, ERR trap → `exit 0`, no stdout, dispatcher forwards nothing |
| `basename` (ERR trap message) | `:15` | stderr only; dispatcher **discards** sub-guard stderr unless rc==2 (`:83-86`) |

### Sibling sub-guards on the same path (must not regress)

`leadv2-deny-floor.sh` (ALWAYS), `leadv2-block-bash-heredoc.sh`, `leadv2-block-fg-dispatch.sh`,
`leadv2-codex-*`, `leadv2-close-ritual-guard.sh`, `leadv2-context-glossary-close.sh`,
`leadv2-bash-lint-pre-gate.sh`, `leadv2-env-audit-pre-gate.sh` (ALWAYS),
`leadv2-schema-audit-pre-gate.sh`. Ordering constraint already honoured: the diff guard is **last**,
so its allow-JSON can never pre-empt another guard's stdout (the dispatcher keeps only the first
valid JSON, `:87-117`). Probed end-to-end: `git diff` through the dispatcher returns the warn JSON
and `rc=0`; `bash <<'EOF' …` still exits 0 exactly as before (no heredoc-guard regression).

---

## 2. STATES AND RETURN CODES

### Guard states → rc → what the dispatcher does → what a human sees

| # | State | Guard rc / stdout | Dispatcher (`:80-124`) | User-visible consequence |
|---|---|---|---|---|
| 1 | `LEADV2_DIFF_READ_GUARD=0` | 0, empty | keeps looping, no stdout kept | command runs; nothing printed |
| 2 | stdin empty / not JSON | 0, empty | same | command runs; nothing printed |
| 3 | `agent_type` non-empty (subagent/worker) | 0, empty | same | reviewer worker reads its diff with no nag |
| 4 | no diff-shaped token in any clause | 0, empty | same | silent |
| 5 | diff-shaped **and** bounded ≤ MAX_LINES | 0, empty | same | silent |
| 6 | diff-shaped **and** (unbounded or window > MAX) | 0, allow-JSON | first-JSON kept, printed on stdout `:122-124`, dispatcher exits 0 | **command still runs**; the 3-line notice is injected as `additionalContext` above the output |
| 7 | state 6 **and** `LEADV2_DIFF_READ_DENY=1` | **2**, msg on stderr | `cat STDERR >&2; exit 2` `:83-86` | **Bash call is blocked**; the model sees the 3 lines and must pick another route |
| 8 | ERR trap fires (any internal error) | 0, empty, msg on stderr | stderr **discarded** (only echoed when rc==2) | silent fail-open; no diagnostic reaches anyone |
| 9 | emitter python3 dies after classify | 0, empty (trap) | same as 8 | warn silently lost — leak continues, nobody is told |

Terminal-outcome tracing, in plain words:

- **rc 0 + warn (state 6) is not enforcement.** The tokens are still paid on that turn and re-paid on
  every later turn. The only thing that changes is that the next decision is better informed. If the
  model ignores the notice, the invariant is violated with a warning attached.
- **rc 2 (state 7) is the only state that prevents payment**, and it is off by default. Deliberate:
  the same predicate fires on a reviewer worker doing its job, and state 3 is the only thing keeping
  that from breaking review. If state 3's predicate ever regresses **and** DENY is on, the visible
  result is "the review lane stops producing findings" — a review round that never renders a verdict,
  not an error message.
- **States 8/9 are indistinguishable from state 4 for a human.** Because the dispatcher throws away
  sub-guard stderr on non-block paths, a permanently broken guard looks exactly like a quiet one.
  This is how 01B's headline defect (§0) stayed invisible: an absent guard and a silent guard render
  identically. Mitigation in §5, M5.

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at each boundary. All rows probed unless marked *by inspection*.

### `LEADV2_DIFF_READ_GUARD` (`:17`)

| Boundary | Behaviour |
|---|---|
| absent / empty | guard active (warn mode) |
| `"0"` | full bypass, `exit 0` before reading stdin |
| any other value (`"false"`, `"no"`, `"1"`) | guard **active** — only the literal `0` disables *(by inspection)* |

### `LEADV2_DIFF_READ_DENY` (`:305`)

| Boundary | Behaviour |
|---|---|
| absent / empty / anything ≠ `1` | warn (allow-JSON) |
| `"1"` | block, rc 2 |

### `LEADV2_DIFF_READ_MAX_LINES` → `LV2_DIFF_READ_MAX_LINES` (`:22`, `env_int` `:27-39`)

| Boundary | Behaviour | Verdict |
|---|---|---|
| absent / empty | 200 | ok |
| `abc` (malformed) | falls back to 200 — probed: `LEADV2_DIFF_READ_MAX_LINES=abc … sed -n 1,340p x.diff` → warn JSON, rc 0 | ok, contained |
| negative | falls back to 200 | ok |
| `0` | every bounded read fires (`window > 0`); `head -1 x.diff` warns | noisy but contained to this guard |
| very large (`999999999`) | nothing bounded ever fires; unbounded reads still fire | **silent near-disable** — acceptable, it is an opt-out knob, but §5/M4 asks the test suite to pin it |

No configured value can take down anything beyond this one guard: every path ends `exit 0`, and the
dispatcher discards its stderr. Confirmed no over-cap/malformed input escalates past the operation
it belongs to.

### `agent_type` (`:271`)

| Boundary | Behaviour |
|---|---|
| absent (lead / main session) | guard applies |
| non-empty string (any subagent) | `exit 0` |
| present but `null` / `""` | `(data.get("agent_type") or "")` → falsy → guard applies |

Predicate matches `leadv2-lead-read-guard.sh:27` and `leadv2-read-gate.sh:147-148` exactly
(`.agent_type // empty`, non-empty ⇒ skip). Requirement "reuse the same predicate" is **already met**;
no change needed. Empirically established 2026-06-06 per `leadv2-lead-read-guard.sh:21-22`.

### `tool_input.command` (`:274-277`)

| Boundary | Behaviour |
|---|---|
| absent / empty / whitespace | `exit 0` |
| unparsable quoting | `tokenize` falls back to `seg.split()` (`:162-166`) — degrades, never raises |
| very long / many clauses | linear scan, no git call, no network; measured **~90 ms per invocation**, dominated by two `python3` starts. Mission's ~15 ms target is unreachable with a `python3` classifier; see §5/M6 |

---

## 4. CONFIRMED DEFECTS (probe table, run against the shipped guard)

`p(){ python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"; }`
then `p "<cmd>" | plugins/leadv2/hooks/leadv2-warn-bash-diff-read.sh`.

| input | actual | expected | verdict |
|---|---|---|---|
| `sed -n '1,340p' docs/handoff/x/review.diff` | FIRE | FIRE | ok |
| **`sed -n '1,340p' docs/handoff/x/review.diff 2>/dev/null`** | **silent** | FIRE | **D1 — bypass** |
| **`cat /tmp/r4-code.diff 2>/dev/null`** | **silent** | FIRE | **D1** |
| `git diff` | FIRE | FIRE | ok |
| `git diff --stat` | silent | silent | ok |
| `git show HEAD` | FIRE | FIRE | ok |
| **`git log -p -1`** | **silent** | FIRE | **D2 — uncovered patch reader** |
| **`git stash show -p`** | **silent** | FIRE | **D2** |
| `cat …/review.diff \| head -400` | FIRE | FIRE | ok |
| **`head -c 20000 x.diff`** | **silent** | FIRE | **D3 — byte cap read as `head -10`** |
| `sed -n '1,40p' …/review.diff` | silent | silent | ok |
| `wc -l x.diff` / `grep -c foo x.diff` | silent | silent | ok |
| `awk 'NR<50' x.diff` | FIRE | FIRE | ok (awk is unbounded by inspection) |
| `cat x.diff \| less` | FIRE | FIRE | ok |
| `for f in *.diff; do cat $f; done` | silent | FIRE | D4 — accepted, see §6 |
| `cat r.diff # >` | silent | FIRE | D5 — subsumed by D1 fix + comment strip |
| `git diff > /tmp/a.diff` | silent | silent | ok (writes to file, not transcript) |
| `agent_type=developer` + `cat x.diff` | silent | silent | ok |
| `echo 'not json' \| guard` | rc 0, no output | rc 0, no output | ok |

**D1 is the important one.** `has_redirect` (`:123-155`) treats *any* unquoted `>` in the clause as
"this stage writes to a file, so nothing enters the transcript". `2>/dev/null` is a `>`. It is also
the single most common suffix on exactly these commands. The shipped guard is one four-character
idiom away from doing nothing at all — and the model that is being nagged is the one that types it.

---

## 5. THE CHANGE

**M1 — `has_redirect` → stdout-only redirect detection.** Replace the "any `>`" scan with one that
recognises the redirect operator's fd prefix. Silencing operators: `>`, `>>`, `>|`, `1>`, `1>>`,
`&>`, `&>>`. **Not** silencing: `2>`, `2>>`, any `N>` with N≠1, and `>&2` (stdout to stderr still
reaches the transcript). Implement by scanning for `>` and looking back at the immediately preceding
unquoted, non-space characters: a run of digits ⇒ that fd; `&` ⇒ both; nothing ⇒ fd 1. `>&2`/`>&1` is
detected by looking *forward* past `&` to a digit.

**M2 — comment strip.** In the same scan, stop at an unquoted `#` that begins a word (preceded by
start-of-clause or whitespace). Kills D5 and prevents a `#` comment from ever silencing the guard.

**M3 — cover the remaining patch readers.** In `is_git_diffshow_unsummarized` /
`classify`, add: `git log` when any of `-p`, `-u`, `--patch`, `--patch-with-stat` is present and no
summary flag is; `git stash show` with `-p`/`--patch`; `git format-patch` with `--stdout`.
Corresponding trigger-regex extension in the dispatcher manifest (`leadv2-bash-pre-dispatch.sh:66`),
otherwise the guard is never invoked for those commands at all:
add `|(^|[^A-Za-z0-9_-])git[[:space:]]+(log|stash|format-patch)([[:space:]]|$)`.
The existing `--stat`/`--name-only`/`--numstat`/`--shortstat`/`-s` exemption set (`:171`) already
covers the no-false-fire requirement and must keep covering `git log --stat`.

**M4 — byte caps.** In `bounded_window`, handle `head -c N` / `tail -c N` (and `--bytes=N`) by
converting to an approximate line count `N // 40` rather than falling through to the `-10` default.
Also make `head`/`tail` with **no** numeric flag return the real default (10) only when no `-c` was
seen — today any unrecognised flag silently yields 10, which is what makes D3 read as "bounded".

**M5 — a regression suite, which does not exist today.** New
`plugins/leadv2/scripts/tests/test-bash-diff-read-guard.sh`, shaped after
`plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh:1-20` (same `set -euo pipefail`,
`LEADV2_BURN_GOVERNOR=0`, `pass()`/`fail()` counters, `[TEST] PASS:` lines). It must pin:
every row of the §4 table; both env knobs at absent/`0`/`1`/malformed/huge; `agent_type` set and
unset; fail-open on empty and non-JSON stdin; `bash -n` on both files; one heredoc-guard case through
the dispatcher for no-regression; **and a cache-parity assertion** — that
`~/.claude/plugins/cache/leadv2-local/leadv2/*/hooks/leadv2-warn-bash-diff-read.sh` exists and its
dispatcher manifest names it, skipped with an explicit `[TEST] SKIP` line when no cache dir is
present (CI/foreign host) rather than silently passing.

**M6 — accept ~90 ms, state it.** Two `python3` starts cost ~45 ms each on this host; the mission's
~15 ms is not achievable without rewriting the classifier in awk/bash, which would trade a
well-tested lexer for a fragile one. Record the measured number in the file header instead of
implying a budget the code does not meet. No network, no git invocation — that part of the
requirement holds.

**M7 — operational, not a repo write: refresh the plugin cache.** After the change lands, copy the
dispatcher and the sub-guard into every
`~/.claude/plugins/cache/leadv2-local/leadv2/<version>/hooks/` and restart the session, or the fix
repeats CTX-COST-GUARDS-01's fate. Bumping the plugin version does not help by itself —
`claude plugin update` no-ops for directory-source marketplaces when content changed but the version
did not (CLAUDE.md). This is a lead action, not a lane write.

### Concurrent access

None. The guard is a read-only stdin→stdout filter; it opens no repo file, holds no lock, and two
concurrent Bash PreToolUse invocations share nothing but their `mktemp` files, which the dispatcher
already makes per-process (`leadv2-bash-pre-dispatch.sh:19-31`). No ordering constraint beyond
"stay last in the manifest".

### Env-var naming self-check

`LEADV2_DIFF_READ_GUARD`, `LEADV2_DIFF_READ_DENY`, `LEADV2_DIFF_READ_MAX_LINES` — all `LEADV2_*`,
consistent with `LEADV2_LEAD_GUARD`, `LEADV2_BURN_GOVERNOR`, `LEADV2_DISPATCH_TRACE`. The internal
`LV2_DIFF_READ_MAX_LINES` is a deliberate process-local alias for the python child and is not a
configuration surface; leave it, do not rename it into the `LEADV2_*` namespace where it would look
user-settable. No new env var is introduced by 01B.

---

## 6. COUNTEREXAMPLE — what still violates the invariant after every fix above

The invariant is "a whole diff never enters the transcript un-summarised". After D1–D3 and M1–M7,
this mechanism still cannot enforce it, and the honest reason is structural, not a missing regex.
Four residuals I checked and could not close: (a) **the default is advisory** — state 6 prints a
notice and then runs the command, so the tokens are paid anyway; only `LEADV2_DIFF_READ_DENY=1`
actually prevents payment, and it is off by design because the same predicate fires on reviewer
workers, so the guard's normal mode is a nag, not a gate. (b) **The diff-shaped predicate is a
filename suffix plus a git subcommand.** A patch written to `build-attempt-1.log`, `review.txt`,
`r4-code.out`, or piped from a non-git tool is invisible to it — and the measured worst offender in
the 01 brief, `build-attempt-1.diff`, only had the right suffix by luck. (c) **Any indirection wins**:
`python3 -c 'print(open("x.diff").read())'`, `xargs cat < list`, `cat $F` where `F` was set in an
earlier clause, and the `for f in *.diff` loop from §4/D4 all classify silent, because the classifier
resolves neither variables nor globs, and making it try would be a strictly worse trade. (d) **The
cache copy drifts again on the very next edit** — M7 is a manual step with no enforcement, and the
one thing that would make it self-detecting is the cache-parity assertion in M5, which only fails
when someone runs the suite. So: not "nothing I can find". The mechanism reduces the accidental case
— the lead reflexively typing `sed -n '1,340p' review.diff` — and it does not touch the deliberate or
the indirect case at all. That is the correct scope for a PreToolUse warn, and 01B should not try to
grow it into a gate.

---

## 7. OUT OF SCOPE (implementing agent: ignore these)

- `plugins/leadv2/hooks/hooks.json` — dispatcher already registered, do not touch.
- The other ten sub-guards, and their manifest rows other than the one regex extension in M3.
- The Read side (`leadv2-read-gate.sh`, `leadv2-lead-read-guard.sh`, `leadv2-bash-output-cap.sh`).
- Changing the default from warn to deny.
- Variable/glob resolution, `.log`/`.txt` patch detection, interpreter-level reads (§6 b–c).
- Rewriting the classifier out of python3 for speed (M6).
- Any consuming repo. Plugin repo only; never create a copy of a plugin file in persona-engine.

---

## 8. Acceptance

```yaml
acceptance:
  - surface: rendered_line
    observable: >
      In a live lead session (not a subagent), running
      `sed -n '1,340p' docs/handoff/<id>/review.diff 2>/dev/null` shows, above the command's
      output, the three-line notice beginning "[leadv2-warn-bash-diff-read] this pulls a whole
      diff into the conversation" — the `2>/dev/null` suffix no longer suppresses it.
    authored_at: 2026-08-25T15:27:56Z
  - surface: rendered_line
    observable: >
      In the same session, `git diff --stat` and `sed -n '1,40p' docs/handoff/<id>/review.diff`
      show their normal output with no notice above it, and a reviewer worker running
      `cat review.diff` sees no notice either.
    authored_at: 2026-08-25T15:27:56Z
  - surface: file_artifact
    observable: >
      Every `~/.claude/plugins/cache/leadv2-local/leadv2/<version>/hooks/` directory contains
      `leadv2-warn-bash-diff-read.sh`, and the dispatcher beside it lists that filename in its
      manifest — i.e. the copy the runtime actually loads carries the guard.
    authored_at: 2026-08-25T15:27:56Z
  - surface: log_line
    observable: >
      `plugins/leadv2/scripts/tests/test-bash-diff-read-guard.sh` ends with a "[TEST] FAIL: 0"
      summary line, with a PASS line present for each of the `2>/dev/null`, `git log -p`,
      `head -c`, subagent-skip and malformed-stdin cases.
    authored_at: 2026-08-25T15:27:56Z
```

LANE_WRITES: plugins/leadv2/hooks/leadv2-warn-bash-diff-read.sh, plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh, plugins/leadv2/scripts/tests/test-bash-diff-read-guard.sh

DELIVERABLE_COMPLETE
