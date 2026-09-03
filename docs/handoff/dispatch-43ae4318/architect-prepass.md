# CODEX-LEAD-FULL-01 — architect prepass (mechanism-closed design)

TASK_ID: dispatch-43ae4318-architect · base eb39d6f · authored 2026-08-24T09:14:38Z

## 0. Where the mission's framing contradicts the tree — read this first

The mission specifies deliverable 2 as *"`lv2guard.sh` — bash **reimplementation** of the
CATASTROPHIC-tier deny-floor"*. **Design against the code: do not reimplement it.**

The deny floor is already a standalone, Claude-independent bash+python3 program:

- `plugins/leadv2/hooks/leadv2-deny-floor.sh` (136 lines) — the whole engine.
- `plugins/leadv2/config/leadv2-deny-patterns.yaml` (83 lines) — 9 rules, each with
  `regex` / `enabled` / `message` / `allow_inline_override`.
- `plugins/leadv2/tests/test-deny-floor.sh` — its existing suite.

Its only Claude-shaped surface is 12 lines: it reads a `{"tool_input":{"command":"…"}}` JSON
envelope from stdin (`leadv2-deny-floor.sh:31-39`) and exits 2 to signal a block. Nothing in it
needs a hook runtime. The patterns file is already parameterised by
`LEADV2_DENY_PATTERNS_FILE` (`leadv2-deny-floor.sh:27`).

A reimplementation would create a second copy of nine security regexes with no propagation
path between them. That is precisely the drift failure the global one-copy policy exists to
prevent, and here the drift is silent *and* security-relevant: a rule tightened in the yaml
after a near-miss would keep firing for the Claude lead and stop firing for the Codex lead,
with nothing on disk indicating the divergence.

**Design: `lv2guard` is an ADAPTER, not a reimplementation.** It synthesises the JSON envelope,
pipes it to the three existing hook programs, maps their exit codes, and `exec`s on allow. Same
inode, same regexes, same tests. The only genuinely new logic is the one rule the mission names
that no existing hook implements — `git worktree prune` vs. active lanes — which is *stateful*
(it must read the lane registry) and therefore cannot live in a regex yaml at all.

Two further corrections the mission's framing does not anticipate:

**(a) `active.yaml` is not at `docs/leadv2/active.yaml`.** The mission says lv2guard should
"check active.yaml". Repo-relative is the pre-`LEAD-CONTROL-PLANE-01` layout and is now wrong:
every lane runs in its own `git worktree add` checkout, so a repo-relative path gave each
session a private registry. The canonical path resolves through
`plugins/leadv2/scripts/leadv2-state-path.sh` to `~/.claude/leadv2-state/<repo-slug>/active.yaml`.
Probe:

```
$ ls -la ~/Projects/persona-engine/docs/leadv2/active.yaml
lrwxr-xr-x … -> /Users/kostiantyn.vlasenko/.claude/leadv2-state/persona-engine/active.yaml
```

**(b) The resolver keys off `PROJECT_ROOT`, not cwd — and gets it wrong silently.** Probe run
from inside persona-engine:

```
$ cd ~/Projects/persona-engine && PROJECT_ROOT=~/Projects/leadv2 \
    bash ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-state-path.sh active.yaml
/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/active.yaml
```

It returned the **leadv2** registry while standing in **persona-engine**, with exit 0 and no
warning. Since lv2guard ships in the leadv2 repo but *runs* from persona-engine, the naive
implementation (`PROJECT_ROOT=<dir of lv2guard>`) reads the wrong registry, sees zero lanes,
and permits the `git worktree prune` it exists to block. This is the `GATE-WRONG-ROOT-FALSE-DEAD-01`
defect class, and it is live here: persona-engine's registry currently holds a session row whose
`worktree:` is `/Users/kostiantyn.vlasenko/Projects/leadv2`. §3 R6 specifies the fail-closed
resolution order that avoids it.

---

## 1. CALLERS / CALLEES

`lv2guard.sh` is a new leaf entry point: **no in-repo caller.** Its callers are, by construction,
outside this repo — the Codex lead's shell, and the four prompt files (which are prose, not code).
Nothing in `plugins/leadv2/scripts/**` or `plugins/leadv2/hooks/**` may be edited to call it.
That asymmetry is the point: it is the Codex-side substitute for a hook runtime.

### 1a. Callees of `lv2guard.sh` — every program it invokes, with file:line

| Callee | file:line | Envelope lv2guard must build | Consumes |
| --- | --- | --- | --- |
| `leadv2-deny-floor.sh` | `plugins/leadv2/hooks/leadv2-deny-floor.sh:31-39` | `{"tool_input":{"command":"<cmd>"}}` on stdin | 9 yaml rules |
| `leadv2-block-bash-heredoc.sh` | `plugins/leadv2/hooks/leadv2-block-bash-heredoc.sh` | same envelope | heredoc detection |
| `leadv2-codex-direct-exec-guard.sh` | `plugins/leadv2/hooks/leadv2-codex-direct-exec-guard.sh:20-45` | same envelope | `codex exec` deny + launcher allowlist |
| `leadv2-state-path.sh` | `plugins/leadv2/scripts/leadv2-state-path.sh` | `PROJECT_ROOT=<root>` env + `active.yaml` argv | git-common-dir |
| `python3` | — | inline, for JSON build + yaml lane count | stdlib only |
| the guarded command itself | — | `exec "$@"` | — |

The three hook programs are invoked **unmodified and unread-into-lv2guard**. lv2guard contains
zero copies of their regexes.

### 1b. Callees of `leadv2-codex-status.sh`

| Callee | file:line | Why |
| --- | --- | --- |
| `leadv2-quota-live.sh json` | `plugins/leadv2/scripts/leadv2-quota-live.sh:17` | the three-bucket percentages; documented to fail **open to `unknown`, never 0%** (`:4-5`) |
| `leadv2-state-path.sh` | `plugins/leadv2/scripts/leadv2-state-path.sh` | canonical `active.yaml` |
| `python3` | — | yaml read (no PyYAML — line-parse, matching deny-floor's precedent at `leadv2-deny-floor.sh:53-56`) |

**Do NOT call `~/.claude/burn/quota-fragment.sh`.** It renders exactly the target format —

```
$ bash ~/.claude/burn/quota-fragment.sh
 | cc 32%·7d/4d13h · cx 98%·wk/6d15h · glm 99%·wk/6d17h
```

— but it lives outside `~/Projects/leadv2` and is therefore not shippable, not installable, and
not editable under this task's constraint. Reproduce the *format* from `quota-live.sh json`;
take no dependency on that file. If a future task wants it shared, it moves into the plugin repo
first.

### 1c. The independent-copy check (the usual miss)

Searched for a second deny-floor implementation before designing: `grep -rln CATASTROPHIC
plugins/leadv2/` returns exactly four paths — the engine, the yaml, its test, and one handoff
note. There is **one** implementation today. The design's whole purpose is to keep that number
at one; a reimplementation would make it two, on two different runtimes, which is the miss this
section exists to catch.

Also note `plugins/leadv2/scripts/ZZ-pre-review-run.sh` is untracked in the working tree
(`??` in git status). It is not on any path this design touches; flagged only so the implementer
does not assume a clean tree.

---

## 2. STATES AND RETURN CODES

### 2a. `lv2guard <command...>` — every state and rc

| rc | State | What the caller (Codex lead) does | Terminal user-visible consequence |
| --- | --- | --- | --- |
| 0 | No rule matched | Nothing — the guarded command ran; **rc 0 is the command's own rc, passed through by `exec`** | The command's normal effect. |
| *(passthrough)* | Command ran and failed on its own merits | Reads the command's own error | Whatever that command normally does on failure. lv2guard is transparent. |
| 97 | A deny rule fired | Must not retry verbatim; changes premise or raises via ask-lead | The destructive command **did not run**. Nothing on disk changed. Loud reason on stderr naming the rule. |
| 98 | Usage error — `lv2guard` called with no command | Fix the invocation | Nothing ran; one usage line printed. |
| 99 | Guard could not evaluate (hook program missing, python3 absent, registry unreadable **and** the command is prune-class) | **Stop.** Do not run the command unguarded | Nothing ran. This is the fail-CLOSED arm the mission mandates. |

`exec` on the allow path is load-bearing: it means lv2guard adds no wrapper process, forwards
signals, preserves stdin/stdout/stderr and the exit code exactly. A lead cannot tell a guarded
command from an unguarded one except when it is blocked. That is what makes the AGENTS prose
rule ("every side-effecting command through lv2guard") cheap enough to actually be followed.

### 2b. Mapping the callee hooks' rc → lv2guard rc

| Hook rc | Hook meaning | lv2guard does |
| --- | --- | --- |
| 0 | allow | continue to next rule; after the last, `exec` |
| 2 | block | print the hook's stderr verbatim, exit **97** |
| other non-zero | hook-internal error | hooks are written fail-open (`trap … exit 0`, `leadv2-deny-floor.sh:19`); treat an unexpected non-zero as **99** rather than inheriting fail-open, because lv2guard's contract is fail-CLOSED |

**This is a deliberate divergence and must be stated in the implementation's comments.** The
hooks fail *open* because a broken hook must never wedge an interactive Claude session — the
session has 32 other guards. lv2guard fails *closed* because it is the Codex lead's **only**
floor: an open failure there is an ungated destructive command. The regexes are shared; the
failure posture is not, and inverting it is the entire reason lv2guard is a wrapper rather than
a symlink.

### 2c. Terminal outcomes traced to the end

- **rc 97 on `git worktree prune`** → the lead does not prune → a live lane's worktree stays on
  disk → that lane's build completes and its diff is reviewable. Without the rule: the prune
  removes the administrative files of a worktree whose lane is mid-build; the lane's later
  `git` calls fail in a checkout git no longer knows about, and *the founder is told a lane is
  running when its work can no longer be committed*.
- **rc 99 with an unreadable registry** → the lead cannot prune at all today, and must resolve
  the registry path before doing so. Chosen over fail-open because the mission says
  "fail-CLOSED in lv2guard on its deny rules", and because §0(b) shows the *silent-wrong-answer*
  case is real: a fail-open here does not look like a failure, it looks like "zero lanes".
- **rc 97 on `codex exec`** → no direct Codex invocation → no XHIGH-default run that bypasses
  the router's quota gate → the codex bucket reading in the pilot's measurement protocol stays
  attributable. Note the pilot runbook says `codex-direct-exec-guard` "does not transfer"
  because that guard stops a *Claude* lead from calling Codex. The mission overrides this for
  lv2guard, and correctly: the reason to keep it is no longer "the lead must not be Codex" but
  "Codex sub-invocations must stay on the metered path". §5 requires the runbook line to be
  corrected rather than left contradicting the shipped guard.
- **rc 0 (passthrough) on `rm -rf ~/.claude/leadv2-shared/…`** → **the command RUNS.** See §4.

### 2d. `leadv2-codex-status.sh` — states

| rc | State | Rendered line |
| --- | --- | --- |
| 0 | all sources read | `cc 32%·7d/4d13h · cx 98%·wk · glm 99%·wk │ lanes 1/5 │ task dispatch-c8474002` |
| 0 | a quota bucket failed | that bucket renders `unknown`, never `0%` — the others still render |
| 0 | registry absent/empty | `lanes 0/?` and `task —`; **still rc 0** |
| 2 | usage error only | one usage line |

Status is **fail-open by mandate** ("fail-open on missing telemetry") — the inverse of lv2guard,
in the same deliverable set. A status line that refuses to render because one endpoint is down
is worse than a partial one.

---

## 3. CONFIGURATION BOUNDARIES

Every input, at absent / empty / minimum / over-cap / malformed.

| # | Input | Absent | Empty | Minimum | Over-cap / max | Malformed |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | `lv2guard` argv | rc 98 usage | `lv2guard ""` → rc 98 (empty argv[1] is not a command) | one word (`lv2guard ls`) → evaluated, exec'd | argv beyond `ARG_MAX` → the kernel rejects at `exec`; lv2guard must **not** pre-join argv into one giant string for its own use beyond the JSON build | argv containing NUL is impossible via execve; quotes/newlines/`$`/backticks must survive to the hook **as data** — build the envelope with `python3 json.dumps(sys.argv[1:])`, never string concatenation |
| R2 | `leadv2-deny-patterns.yaml` | rc 99 (fail-closed: no floor = no guard) | zero rules → deny-floor exits 0 at `:47`; lv2guard **must** treat an empty rules list as rc 99, not allow | 1 rule → normal | 1000 rules → `re.search` per rule, ~ms; no cap needed | a rule with a bad regex is skipped by `re.error` at `leadv2-deny-floor.sh:104-105`. **This is a silent partial floor.** lv2guard must not paper over it; §6 requires the yaml to be regex-compiled in the test suite so a typo fails CI rather than disarming one rule in production |
| R3 | `LEADV2_DENY_FLOOR` | default `1` = enabled | `""` → `${…:-1}` yields `""`, which is `!= "0"`, so enabled. Correct | `0` → **the entire floor is bypassed**, catastrophic rules included (`leadv2-deny-floor.sh:22-24`) | — | any other value = enabled (fail-safe) |
| R4 | `LEADV2_DENY_FLOOR=0` **through lv2guard** | — | — | — | — | **Decision: lv2guard does NOT honour it.** It must `unset`/force `LEADV2_DENY_FLOOR=1` for its own hook call. A kill-switch is appropriate for a session with 32 other guards and an interactive human at the keyboard; it is not appropriate for a wrapper whose sole purpose is to be the floor. The escape hatch for a genuine false positive is a yaml edit reviewed as a diff, not an env var set in a prompt. |
| R5 | `LEADV2_ALLOW_DIRECT_CODEX` | direct `codex exec` denied | `""` → denied | `1` → allowed, logged to stderr (`leadv2-codex-direct-exec-guard.sh:41-43`) | — | Same decision as R4: forced off inside lv2guard |
| R6 | `PROJECT_ROOT` for the registry | **The trap of §0(b).** Resolution order, fail-closed: (1) `LEADV2_PROJECT_ROOT` if set; (2) `git -C "$PWD" rev-parse --show-toplevel`; (3) **rc 99** — never the directory lv2guard itself lives in | `""` → treat as absent | — | — | points at a non-git dir → resolver's git call fails → **rc 99**, not a repo-relative fallback |
| R7 | `active.yaml` | file missing → for prune-class commands **rc 99**; for all others, irrelevant (not read) | `sessions: []` → zero lanes → prune **allowed** | 1 session row → prune denied | `hard_limit: 3` in leadv2 vs `5` in persona-engine — lv2guard reads `sessions:`, never `meta.hard_limit`; the cap is a dispatch concern | not valid yaml → **rc 99**. Line-parse `sessions:` per the deny-floor precedent; a PyYAML import is not available and must not be added |
| R8 | `active.yaml` **lock** | — | — | — | — | lv2guard is a **reader**. It must take no lock and must not write. A torn read is possible; the mitigation is that any parse ambiguity is rc 99 (deny), which is the safe direction for a prune |
| R9 | heredoc size | no heredoc → allow | — | — | **>2KB is ADVISORY per the mission** — warn on stderr, rc 0, command proceeds. Do not silently promote it to a deny; the Claude-side hook blocks heredocs outright and that difference must be a deliberate, documented one, not an accident |
| R10 | `~/.codex/prompts/` (installer) | create it | — | — | — | exists as a **file** not a dir → installer exits non-zero with the reason |
| R11 | `~/.codex/config.toml` | create with just the MCP block | 0 bytes → append block | — | **100974 bytes today** (`ls -la` probe). Never rewrite it wholesale; append-only, and `.bak` first | not valid TOML → **do not attempt a fix.** Back up, warn, skip the MCP edit, continue with prompts. An installer that mangles a 100KB user config is worse than one that skips a step |
| R12 | installer repo-path arg | default `~/Projects/persona-engine` | `""` → use default | — | — | path not a git repo → warn + skip the AGENTS.md verification; still install prompts |
| R13 | AGENTS.md `@import` line | absent → **report, do not add** | — | — | — | The runbook (`codex-lead-pilot-runbook.md:23-26`) already carries an `UNVERIFIED:` on import resolution and an explicit "do not overwrite AGENTS.md". Deliverable 4 says "**verifies** the line exists" — verify is the whole verb. Print the exact line to append; let the founder append it |
| R14 | quota bucket JSON | `unknown` | `unknown` | — | — | `unknown` — `leadv2-quota-live.sh:4-5` guarantees never-0%; the status renderer must not coerce `unknown`→`0` |

### R11 detail — the idempotency contract

"Ensures the repowise MCP block, don't duplicate" needs a *stable identity*, or run #2 appends a
near-identical block. Delimit with literal marker comments:

```
# >>> leadv2-codex-lead: repowise mcp (managed) >>>
…
# <<< leadv2-codex-lead: repowise mcp (managed) <<<
```

Idempotency = "markers present" (skip), not "content resembles". If markers are present but the
enclosed content differs from what would be written, the block was hand-edited: back up to
`.bak`, replace between the markers, and **say so in the printed summary**. "Never overwrites
user customizations silently" is satisfied by the report, not by refusing to act.

---

## 4. COUNTEREXAMPLE — what still violates the invariant after every mission finding is fixed

The invariant lv2guard exists to protect: *the Codex lead cannot irreversibly destroy work
outside the lane it is allowed to touch.* After all seven deliverables ship exactly as specified,
here is what still breaks it.

**The largest hole is that the mission's own rule text is wider than the yaml that implements
it, and the adapter design inherits the yaml.** The mission asks lv2guard to refuse "`rm -rf` on
`$HOME`/**shared trees**" and "`git reset --hard`/`clean`/`stash` in `~/Projects/*` **shared
checkouts**". Neither of those path predicates exists. `rm_rf_home` matches `~` or `$HOME` only
as a *terminal* token — `rm -rf ~/.claude/leadv2-shared/scripts` does not match it and **will
run**, deleting the shared tree that this repo's global policy names as the single source. And
`git_reset_hard` / `git_clean_fdx` / `git_stash` are `allow_inline_override: true`, i.e. SOFT:
appending `# deny-floor: allow` bypasses them anywhere, including in `~/Projects/persona-engine`.
So the three commands the mission calls out by name are, in the shipped floor, *path-blind and
overridable* — a lead that has read the block message once knows the bypass, because the message
itself prints it (`leadv2-deny-floor.sh:130`). Closing this means adding path-scoped
CATASTROPHIC rules to the yaml, which changes behaviour for the **Claude** lead too and is
therefore a founder decision, not an implementer's. §5/D1 raises it; the honest statement for
this design is: **lv2guard as specified does not stop `rm -rf ~/.claude/leadv2-shared/…`.**

Second, and structurally unfixable inside this task: lv2guard is enforced by **prose**. The
mission says so — "the AGENTS brief must mandate … (prose rule — the pilot measures compliance)".
Codex has no PreToolUse interception, so an unguarded `rm -rf` typed directly is not blocked, it
is merely *later observable* in the transcript checklist. Every guarantee above is conditional
on the lead choosing to type `lv2guard` first. The `exec`-transparency in §2a is the mitigation
that makes the choice cheap, and the transcript checklist
(`codex-lead-pilot-runbook.md:118-134`) is the detection. Neither is prevention. The pilot's
PASS criteria should count *unguarded side-effecting commands* as a measured quantity; right now
they do not.

Third: a rule can be disarmed silently. A regex typo makes `re.error` skip that rule
(`leadv2-deny-floor.sh:104-105`) with no output — the floor keeps working, one rule short. §6's
compile-check test is the only thing standing between that and a production hole.

Fourth: `LEADV2_DENY_FLOOR=0` remains a real global bypass for anything that calls the hook
*directly*. R4 removes it inside lv2guard, but the env var is exported in a shell, and a lead
that sets it disarms the Claude-side floor for every tool in that session.

What I checked and found clean: there is exactly one deny-floor implementation
(`grep -rln CATASTROPHIC`, four hits, one of them the engine); the patterns file is already
env-parameterised so the adapter needs no edit to it; `quota-live.sh` genuinely fails to
`unknown` rather than `0%` per its header contract and the live `report` probe in §1b.

---

## 5. Decisions requiring founder/orchestrator sign-off

| # | Decision | Recommendation |
| --- | --- | --- |
| D1 | §4's first paragraph: add path-scoped CATASTROPHIC rules for shared-tree `rm -rf` and `~/Projects/*` reset/clean/stash? It changes the **Claude** lead's behaviour too | Do it, as a **separate** task with its own review — a false positive here wedges every session. Not in this lane |
| D2 | R4/R5: lv2guard forcibly ignores both kill-switches | Recommended as designed; it is what "fail-CLOSED" means |
| D3 | `codex-direct-exec-guard` transfers, contradicting `codex-lead-pilot-runbook.md:135-137` and `codex-lead-AGENTS-pilot.md:73-75` | Ship the guard **and** correct both prose lines in this lane (they are in §7's write list). Shipping a guard whose own runbook says it doesn't apply guarantees a confused bypass |

---

## 6. Tests (deliverable 6)

`plugins/leadv2/tests/test-lv2guard.sh` — mirror `test-deny-floor.sh`'s harness shape
(`run <expected_exit> <cmd>`), asserting **97** where it asserts 2:

1. deny: `rm -rf /`, `rm -rf $HOME`, `mkfs.ext4 /dev/sda1`, `dd of=/dev/sda`,
   `git push --force origin main` → 97.
2. deny: `codex exec "hi"` → 97; allow: `codex-task.sh task "hi"` → passthrough.
3. deny: `git worktree prune` with a fixture registry holding one session → 97;
   allow with `sessions: []` → passthrough.
4. fail-closed: prune with the registry **absent** → 99; with malformed yaml → 99.
5. R4: `LEADV2_DENY_FLOOR=0 lv2guard rm -rf /` → still **97**.
6. R1 quoting: a command containing `"`, `'`, `$X`, a newline, and a backtick reaches the hook
   as data and is neither expanded nor truncated.
7. advisory: a 3KB heredoc → stderr warning **and rc 0**.
8. transparency: `lv2guard sh -c 'exit 42'` → 42; `lv2guard echo hi` → stdout exactly `hi`.
9. **R2 integrity:** every `regex:` in `leadv2-deny-patterns.yaml` compiles under `re.compile`
   — the §4-third-hole guard.

`plugins/leadv2/tests/test-codex-lead-install.sh`:

10. run installer twice against `HOME=$(mktemp -d)` → prompts identical, **exactly one** marker
    pair in `config.toml`, no `.bak` on run 2.
11. pre-existing hand-edited managed block → replaced, `.bak` created, replacement **reported**.
12. `config.toml` malformed → `.bak` created, MCP step skipped with a warning, prompts still
    installed, rc non-zero.
13. `~/.codex/prompts` exists as a file → non-zero, nothing written.

All fixtures under `mktemp -d`; **no test may reference a real path under `$HOME` or
`~/Projects`.** `bash -n` over every shipped `.sh` is step 0 of both suites.

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >
      A lead that runs the guard on a command to delete the shared tree root sees a
      loud refusal naming the rule that stopped it, and the directory it named is
      still on disk afterwards.
    authored_at: 2026-08-24T09:14:38Z
  - surface: log_line
    observable: >
      With one lane recorded as active, an attempt to prune worktrees is refused and
      says which task is still running; with no lane active the same attempt goes
      through and prunes normally.
    authored_at: 2026-08-24T09:14:38Z
  - surface: rendered_line
    observable: >
      The status command prints one line showing all three provider percentages, the
      lane count, and the active task id; when a provider endpoint is unreachable
      that provider reads "unknown" and the other two still show their numbers.
    authored_at: 2026-08-24T09:14:38Z
  - surface: file_artifact
    observable: >
      After running the installer twice from a clean home, the Codex prompts
      directory holds the five prompt files and the Codex config contains exactly one
      managed repowise section; the second run reports that it changed nothing.
    authored_at: 2026-08-24T09:14:38Z
  - surface: log_line
    observable: >
      A guarded command that is not on any deny rule produces exactly the output and
      exit status it would have produced unguarded — the founder cannot tell the
      wrapper is there.
    authored_at: 2026-08-24T09:14:38Z
```

## 7. Out of scope (implementer: ignore)

- Editing `leadv2-deny-floor.sh`, `leadv2-deny-patterns.yaml`, `leadv2-block-bash-heredoc.sh`,
  `leadv2-codex-direct-exec-guard.sh`, or `hooks.json`. **Reuse only.** D1 is a separate task.
- Any new deny regex. The one new rule (prune-vs-lanes) is stateful bash, not a pattern.
- Editing `~/.claude/burn/quota-fragment.sh` or anything outside `~/Projects/leadv2`.
- Appending the `@import` line to persona-engine's `AGENTS.md` (R13 — verify and report only).
- Writing to `active.yaml`, or taking its lock (R8).
- Supervisor/fanout mode, Kimi/ladder-spill, model-pinning — explicitly excluded by
  `codex-lead-pilot-runbook.md:151-156`.
- Making lv2guard mandatory by any mechanism other than prose. Codex has no interception point;
  §4 paragraph 2 is a measured limitation, not a bug to solve here.

LANE_WRITES: plugins/leadv2/codex-lead/lv2guard.sh, plugins/leadv2/codex-lead/leadv2-codex-status.sh, plugins/leadv2/codex-lead/install.sh, plugins/leadv2/codex-lead/prompts/leadv2.md, plugins/leadv2/codex-lead/prompts/leadv2-status.md, plugins/leadv2/codex-lead/prompts/leadv2-dispatch.md, plugins/leadv2/codex-lead/prompts/leadv2-review.md, plugins/leadv2/codex-lead/prompts/leadv2-close.md, plugins/leadv2/tests/test-lv2guard.sh, plugins/leadv2/tests/test-codex-lead-install.sh, plugins/leadv2/docs/codex-lead-AGENTS-pilot.md, plugins/leadv2/docs/codex-lead-pilot-runbook.md

DELIVERABLE_COMPLETE
