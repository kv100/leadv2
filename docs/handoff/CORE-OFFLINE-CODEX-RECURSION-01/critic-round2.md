# CORE-OFFLINE-CODEX-RECURSION-01 — critic round 2 (independent re-derivation)

Scope: `_launcher_spawn_detected` embedded Python parser in
`plugins/leadv2/scripts/leadv2-codex-session-runner.sh` (lines 195-417) and its tests in
`plugins/leadv2/scripts/tests/test-codex-session-runner.sh`, as changed by the uncommitted
working-tree diff. Codex authored both the round-2 fix and the review that motivated it
(`docs/handoff/CORE-OFFLINE-CODEX-RECURSION-01/{diagnosis.md,fix-round-2.md}`); nothing in
those files was trusted — every claim below was re-derived by extracting the exact embedded
Python verbatim (`sed -n '198,415p'` of the `.sh` file) and executing it against adversarial
input, then re-proved end-to-end through the real `leadv2-session-runner.sh` →
`leadv2-codex-session-runner.sh` call path using a patched copy of the shipped test harness.

**VERDICT: BLOCK.** One Critical finding, proven live in both directions the task explicitly
calls out as unacceptable (FALSE-KILL and FAIL-OPEN), rooted in the same 9-line `coproc` branch,
with zero test coverage for either direction despite a dedicated round-2 "coproc" test.

---

## CRITICAL — `coproc` NAME-vs-command disambiguation is backwards vs. real bash grammar

**File:** `plugins/leadv2/scripts/leadv2-codex-session-runner.sh:341-349`

```python
if t == "coproc":
    # `coproc [NAME] { ...; }` executes the group, not its NAME.
    j = i + 1
    if j + 1 < len(toks) and toks[j] != "{":
        j += 1
    if j < len(toks) and toks[j] == "{":
        return depth < 4 and eval_tokens(toks[j + 1:], depth + 1)
    i = j
    continue
```

The code decides "toks[j] is a skippable NAME" from **"is there some token after it, and is it
not literally `{`"**. Real bash's rule (confirmed against `man bash` §Coprocesses, verbatim
below, then confirmed by actually executing bash) is different and stricter:

> "If command is a compound command, NAME is optional... **If command is a simple command, NAME
> is not allowed; this is to avoid confusion between NAME and the first word of the simple
> command.**" (`man bash`, Coprocesses section, reproduced via `man bash | col -b`)

I.e. a NAME can only ever be parsed off when the token **after** the candidate is a compound
opener (`{`, and this codebase's parser only understands `{`). The shipped heuristic instead
fires whenever *anything at all* follows the candidate — which is every simple `coproc CMD arg`
invocation with 2+ words. This is wrong in **both** directions, and I reproduced both live.

### Direction A — FALSE-KILL: `coproc grep <bare-launcher-mention> <file>`

This is exactly the class of "operand to grep" input CODEX-LEAD-RECURSION-FALSEKILL-01 exists to
protect (the shipped negative fixture even tests the un-`coproc`-wrapped form of this same
string: `test-codex-session-runner.sh:61` `grep -n leadv2-supervise.sh docs/x.md`). Wrapping the
identical harmless grep in `coproc` flips the verdict to a kill.

**Real bash — launcher never runs, grep does (marker-file proof, not a guess):**
```
$ printf '#!/bin/bash\necho "SHOULD-NEVER-RUN" >> ./marker.txt\n' > leadv2-supervise.sh; chmod +x leadv2-supervise.sh
$ echo "haystack containing leadv2-supervise.sh as text" > somefile.txt
$ bash -c 'coproc grep leadv2-supervise.sh somefile.txt; wait $COPROC_PID 2>/dev/null; echo "exit: $?"'
exit: 0
$ cat marker.txt
cat: marker.txt: No such file or directory        # confirmed: launcher script never executed
```

**Parser (extracted verbatim, `python3 parser.py <log> 0`) on the same string:**
```
cmd = 'coproc grep leadv2-supervise.sh somefile.txt'
rc=0   (0 == DETECTED == "kill this session")
```

**Real end-to-end runner** (patched copy of the shipped test harness, same
`leadv2-session-runner.sh` entry point, same stub-Codex JSONL shape used by every other test in
this file):
```
[PROOF] FALSE-KILL CHECK (coproc grep LAUNCHER-NAME somefile.txt): rc=5 ...
[leadv2-codex-session-runner] ERROR: CODEX-LEAD RECURSION: Codex tried to spawn a leadv2
launcher/dispatcher from its already-running child session; stopping immediately
[PROOF] result: FALSE-KILL CONFIRMED
```
`rc=5` after exactly one attempt — the session is killed for a plain grep.

### Direction B — FAIL-OPEN: `coproc <launcher-path> --flag` (unnamed, no braces, one trailing arg)

**Real bash — the launcher genuinely executes (marker-file proof):**
```
$ bash -c 'coproc ./my-launcher.sh --flag; wait $COPROC_PID 2>/dev/null'
$ cat marker.txt
LAUNCHER-RAN args=[--flag]                         # confirmed: launcher DID execute
```

**Parser on `coproc .claude/scripts/leadv2-supervise.sh --flag`:** `rc=1` (NOT-DETECTED), no
crash, no stderr — a clean, silent miss.

**Real end-to-end runner** (same harness):
```
[PROOF] FAIL-OPEN CHECK (coproc LAUNCHER --flag, no name/braces): rc=4 ...
... attempt 0/6 .. attempt 5/6 (6 attempts burned) ...
ERROR: CODEX-LEAD RECURSION suspected: 6 consecutive turns changed no phase/git/handoff
evidence while this runner owns the flock — stopping early to prevent token-burning resumes
[PROOF] result: NOT DETECTED -- FAIL-OPEN CONFIRMED
```
The dedicated recursion guard never fires; the *unrelated* generic stall-detector eventually
catches it 6 attempts later. That is precisely the "6 wasted Codex turns" cost this task's own
brief names as the acceptance bar for a fail-open, reproduced exactly.

### Why the coincidental cases in the diff's own verdict table look right

`diagnosis.md:129` ("Fix round 2" verdict table) and `fix-round-2.md:34-36` only ever exercise
`coproc worker { <launcher>; }` — the one shape where "skip a word, then check for `{`" happens
to agree with real grammar (NAME really is optional before a *compound* command). The mission
brief that produced this diff (`fix-round-2.md:35`) literally says coproc "may be followed by an
optional NAME and then **a command** or a `{ … }` group" — acknowledging the bare-command form
exists — but neither the fix nor its self-verification table ever tests that form. Per `man bash`
that bare-command form is not a corner case, it's the *default* interpretation whenever there is
no `{`.

### Test gap (explicit answer to "are the new tests falsifiable?")

`plugins/leadv2/scripts/tests/test-codex-session-runner.sh:57-58` (stub) and the round-2 loop at
`:251-265` (`for shape in env-split env-split-long time coproc`) contain **exactly one** coproc
shape: `coproc worker { .claude/scripts/leadv2-supervise.sh; }`. The falsekill mega-fixture at
`:60-81` (20 negative strings) contains **zero** `coproc`-wrapped strings. I ran the shipped
suite unmodified — `16/16 PASS` — then added the two adversarial cases above as new `STUB_MODE`
branches + assertions in a scratch copy of the same file (not committed; deleted after the run)
and reproduced both bugs through the real runner. The green suite is real for the one shape it
tests and gives **no** evidence about either failure direction of the actual grammar mismatch —
this is "passes for the wrong reason" per the review brief.

### Required fix

Check whether the token **after** the candidate name is a compound opener before treating the
candidate as skippable; if it is not, the candidate itself is the program (matches
`_next_operand`'s existing pattern of "fall through, let the caller re-evaluate"):

```python
if t == "coproc":
    j = i + 1
    if j < len(toks) and toks[j] == "{":            # coproc { ...; }  (unnamed)
        return depth < 4 and eval_tokens(toks[j + 1:], depth + 1)
    if j + 1 < len(toks) and toks[j + 1] == "{":     # coproc NAME { ...; }
        return depth < 4 and eval_tokens(toks[j + 2:], depth + 1)
    i = j                                             # coproc CMD [args...] -- CMD is toks[j],
    continue                                          # NOT a name; let the outer loop see it.
```
Add both `coproc grep <launcher> f` (must NOT trip) and `coproc <launcher> --flag` / `coproc
<launcher>` (must trip) to the fixture, plus the already-shipped `coproc worker { <launcher>; }`
regression.

**Severity: Critical. Blocking.** Reachable with entirely ordinary shell constructs (any
coproc-wrapped grep/sed/cat mentioning a launcher name; any coproc-wrapped launcher call with one
flag) — not a contrived adversarial shape.

---

## Answers to the four specific checks

**1. Does `env -S` re-parse respect the existing `depth` guard? Can nesting blow the stack or loop forever?**
Verified safe, and consistent with the pre-existing convention — not a regression. Direct probe
(calling the extracted `scan_command`/`eval_tokens` with an explicit starting `depth`, bypassing
shell-quote-nesting mechanics entirely) shows `env -S`, `coproc`, and the pre-existing `eval` all
share the identical boundary: detection at starting depth 0-3, silently stops at depth ≥4 (one
more level than `eval` already tolerated). A 40-case fuzz batch (bare `coproc`/`env -S`/`exec`/
`time` with missing args, unbalanced braces, 200KB argument, 8 levels of `{ }` nesting, 6 levels
of nested `coproc`, null bytes) produced **0 crashes, 0 timeouts**, worst case 1.7s for a 200KB
garbage argument (pre-existing tokenizer cost, not introduced by this diff). Non-blocking.

**2. Does `coproc` group descent handle the unnamed form and a missing/unbalanced brace without an index error, and how are exceptions handled at the call site?**
No index errors found (Python's `and` short-circuit plus safe list slicing make the arithmetic in
:341-349 memory-safe even for `coproc`, `coproc {`, `coproc worker {`, unbalanced `coproc worker {
launcher` with no closing brace, etc. — all return cleanly, see fuzz results above). **However**:
at the call site (`:506`, `if _launcher_spawn_detected "$log_size_before"; then`), *any* uncaught
Python exception would exit 1 (Python's default traceback exit code) and the bash `if` would
silently treat that identically to "clean, not detected" — there is no distinction between "ran
cleanly, no launcher" and "crashed". I could not find an input that triggers this in the current
code, but the call site has no defence if a future change reintroduces one (e.g., the `python3`
heredoc's exit code is checked only 0-vs-nonzero, never inspected for "did stderr have a
traceback"). Recommend (Low, non-blocking, since not currently exploitable): distinguish a
traceback from a clean `SystemExit(1)` at the call site, or wrap the whole script body in a
top-level `try/except Exception` that logs and re-raises `SystemExit(1)` explicitly so a future
regression is at least loud in the log instead of silently indistinguishable from "safe".

**3. Any newly-reachable path where a launcher token that is NOT executed now reaches execution position?**
Yes — Direction A above (`coproc grep <launcher> <file>`) is exactly this: "leadv2-supervise.sh"
is grep's search-pattern operand, never executed, yet the parser evaluates it as `prog`. This is
the Critical finding, not a separate item.

**4. Are the new tests falsifiable, or do any pass for the wrong reason?**
The `coproc` test passes for the wrong reason (see Test gap above). The `env-split` /
`env-split-long` / `time` tests were separately spot-checked and are fine for their scope — those
constructs have no bash NAME-optional grammar quirk, so there is no analogous disambiguation bug,
and the fuzz batch found no crash/false-kill/fail-open on any of them.

---

## Low / non-blocking notes

- **`leadv2-codex-session-runner.sh:263`** — `ENV_ARG_OPTS = {"-u", "--unset", "-C", "--chdir",
  "-a", "--argv0"}`. `-a` is not a real GNU `env` short option (checked: this machine's
  `/usr/bin/env` is BSD env — `env: illegal option -- e`, `usage: env [-0iv] [-C workdir]
  [-P utilpath] [-S string]`, no `-a` at all; GNU coreutils only ever shipped `--argv0` as a
  long-only flag). Harmless as written (worst case: over-conservative skip of a flag nobody's
  `env` recognizes, still correctly skips the following operand), but the comment overclaims
  "GNU `env` options" for a flag that doesn't exist on either BSD or GNU `env`. Fix the comment or
  drop the bare `-a` from `ENV_ARG_OPTS` (keep `--argv0`).
- Shared `depth < 4` budget: `env -S`, `coproc`, `eval`, and interpreter `-c` bodies all draw from
  the same counter. Four unrelated wrapper layers (e.g. two `$(...)` substitutions + one `eval` +
  one `env -S`) exhaust the budget before a 5th, genuinely-nested launcher invocation would be
  reached. Pre-existing design, not introduced by this diff; flagging only so it isn't
  re-discovered as a "new" bug later.

---

## Raw evidence (commands run, verbatim)

Extracted the embedded parser byte-for-byte (`sed -n '198,415p' leadv2-codex-session-runner.sh`)
into a standalone `.py`, then drove it two ways: (a) directly via `python3 parser.py <logfile> 0`
against synthetic JSONL log lines shaped exactly like the real `command_execution` events this
function reads, and (b) end-to-end via a patched, uncommitted copy of
`test-codex-session-runner.sh` (two extra `STUB_MODE` branches + two assertions) run in place and
deleted immediately after, exercising the real `leadv2-session-runner.sh` entrypoint with the
project's own stub-Codex binary — not a re-implementation.

Shipped suite, unmodified, run from the worktree:
```
$ bash plugins/leadv2/scripts/tests/test-codex-session-runner.sh
...
[TEST] Results: PASS=16 FAIL=0
```

Adversarial batch against the real extracted parser (coproc forms):
```
[OK         ] A1-coproc-unnamed-braced                      rc=0 DETECTED  'coproc { .claude/scripts/leadv2-supervise.sh; }'
[OK         ] A2-coproc-unnamed-direct-noarg                rc=0 DETECTED  'coproc .claude/scripts/leadv2-supervise.sh'
[*** GAP ***] A3-coproc-unnamed-direct-WITH-ARG              rc=1 NOT-DETECTED  'coproc .claude/scripts/leadv2-supervise.sh --flag'
[OK         ] A6-coproc-named-braced (existing test)         rc=0 DETECTED  'coproc worker { .claude/scripts/leadv2-supervise.sh; }'
[OK         ] A8/A9/A10 (bare coproc / coproc {/ coproc worker) rc=1, no crash
[OK         ] A13-coproc-deep-nested-6                       rc=1 NOT-DETECTED (depth cap, expected, no hang, 0.129s)
```
Plus: `coproc grep leadv2-supervise.sh somefile.txt` → parser `rc=0` (DETECTED) vs. real bash
(marker-file test) → grep runs, launcher never executes → false-kill confirmed at the parser
level and then at the full end-to-end runner level (see Direction A above).

Fuzz batch (40 malformed `coproc`/`env`/`exec`/`time` inputs, 3s timeout each): 0 crashes, 0
timeouts; slowest case 1.696s (200KB `env -S` argument of garbage, pre-existing tokenizer cost).

Depth-boundary probe (direct `scan_command(text, depth=k)` calls, k=0..6, bypassing shell-quote
nesting): `env -S`, `coproc`, and `eval` all flip from `detected=True` to `detected=False`
exactly at starting depth 4 — identical, consistent, not a regression.

`man bash` §Coprocesses (`col -b`, verbatim, the load-bearing sentence):
```
If command is a simple command, NAME is not allowed; this is to avoid confusion between NAME
and the first word of the simple command.
```

No `mypy`/`tsc` run: this artifact is an embedded Python heredoc inside a `.sh` file in the
`leadv2` plugin repo, not a package under `platform/`/`agent/` or `web/`; there is no type-check
target for it. Runtime adversarial execution (above) is the applicable evidence standard here and
is what the task asked for explicitly.

DELIVERABLE_COMPLETE
