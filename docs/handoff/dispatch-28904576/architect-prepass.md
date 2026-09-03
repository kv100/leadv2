# GUARD-RESET-FLAG-GAP-01 — architect prepass (mechanism-closed)

Design only. No implementation. Base 8bd1758.

## 0. Prepass mismatches with the mission (HARD RULE: noted, not halted)

| # | Mission says | Tree says | Design decision |
|---|---|---|---|
| M1 | "plus a negative case (`echo \"git reset --hard\"` in prose args) asserting allowed **where the current suite asserts that shape**" | The current suite asserts no such shape, and the *current* regex already blocks `echo "git reset --hard"` (probe below, `prose-echo-old match=1`). Making it allowed is a **new hole**, not a regression fix. | Do NOT add an allow-assertion. Add a **block**-assertion pinning the deliberate over-block, with the `# deny-floor: allow` escape hatch named in the test comment. Rationale in §5 R3. |
| M2 | "push --force if present, …" — implies uncertainty | It is present (`git_push_force_main`) and has the same gap. | In scope, hardened. |
| M3 | "worktree prune/remove" | `worktree prune` exists (deny-extra, predicate rule). `worktree remove` has **no rule in either file**. | Out of scope — see §6 non-goals. Adding a rule is new floor policy, not a regex hardening. |
| M4 | "+ shared regex helper if one exists" | None exists. Neither parser supports anchors/includes; both are hand-rolled line parsers (`leadv2-deny-floor.sh:52-105`, `lv2guard.sh:162-241`) that read `regex:` as one literal line. | Inline the fragment in all 5 rules + add a **fragment-drift test** as the mechanical substitute for a helper (§4.3). |

## 1. CALLERS / CALLEES

The two yaml files are data. Everything that reads them:

### 1a. Readers of `plugins/leadv2/config/leadv2-deny-patterns.yaml`

| Reader | file:line | Path | Notes |
|---|---|---|---|
| `leadv2-deny-floor.sh` | `plugins/leadv2/hooks/leadv2-deny-floor.sh:26` resolves, `:52-105` matches | Claude-side `PreToolUse:Bash` | Fails **open** (exit 0) on any internal error; `LEADV2_DENY_FLOOR=0` kill-switch at `:21` |
| `lv2guard.sh` | `plugins/leadv2/codex-lead/lv2guard.sh:38` resolves, `:162-241` matches | Codex-side, opt-in by prose | Fails **closed** (rc 97) on missing/zero-rule file (`:104`, `:243-248`). Does NOT honor the kill-switch (CB-8) |
| `test-deny-floor.sh` | `plugins/leadv2/tests/test-deny-floor.sh:7` (via the hook) | test | 40 assertions today |
| `test-lv2guard.sh` | `plugins/leadv2/codex-lead/tests/test-lv2guard.sh:40` (copies it into a fixture repo) | test | **Copies** the yaml — a yaml edit is picked up automatically, no fixture update needed |

`leadv2-deny-floor.sh` is itself invoked by `plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh:52` (`MANIFEST='leadv2-deny-floor.sh|ALWAYS'`) — the deny-floor is not registered as a hook directly; it is dispatched by the pre-dispatch multiplexer. **Any change that broke the yaml parse would surface as a silently-open floor there, not as an error.**

### 1b. Readers of `plugins/leadv2/codex-lead/deny-extra.yaml`

| Reader | file:line | Notes |
|---|---|---|
| `lv2guard.sh` | `:39` resolves, `:105` fail-closed check, `:210-224` parse | ONLY reader. The Claude-side hook never reads this file — a rule that lives only here has **no Claude-side enforcement**, by design |
| `test-lv2guard.sh` | `:39` copies into fixture | — |

### 1c. Independent copies / different-path callers (the usual miss)

1. **`plugins/leadv2/codex-lead/shim/git`** (`shim/git:9`) — `exec bash "$GUARD" "$REAL_GIT" "$@"`. The guard therefore matches against **`/usr/bin/git -C /p reset --hard`**, an absolute path, not the bare word `git`. Verified: the new fragment still matches this form (`probe-regex.py`, `/usr/bin/git -C /p reset --hard → new=1`). Any design that anchored the rule with `^git` or a command-position anchor would **silently break the shim path**. This is the concrete reason §5 R1 rejects anchoring.
2. **`lv2guard.sh` argv form vs `-c` form** (`:69-73`) — argv joins with `$*`; `-c` uses the raw string. Both feed the same `MATCH_STRING`. The inline `# deny-floor: allow` token is honored **only in `-c` form** (`:93`, CB-6). So `lv2guard.sh git -C x reset --hard` (argv) is unoverridable; the `-c` equivalent is overridable. Tests must cover both forms for the new cases.
3. **`$HOME` normalisation** (`lv2guard.sh:77-79`) runs *before* matching. The live-incident command used `~/Projects/leadv2`; if a caller passes the expanded `/Users/…`, lv2guard folds it back to `~` first. Irrelevant to the git rules (they don't match on the path) but relevant to the `-C <path>` token consumed by the fragment: `-C ~/Projects/leadv2` and `-C /Users/…` both match (`\S+`).
4. **`.claude/worktrees/*/plugins/leadv2/config/leadv2-deny-patterns.yaml`** — 4+ stale worktree copies exist. They are **not** callers of the live floor (each worktree's guard reads its own copy). Do not edit them; they are garbage-collected worktrees. Named here only so a reviewer does not flag them as missed sites.
5. **Plugin-cache copy: does not exist.** `CLAUDE_PLUGIN_ROOT` = `~/.claude/plugins/local/leadv2`; `~/.claude/plugins/local/leadv2/plugins/leadv2/config/leadv2-deny-patterns.yaml` and `~/Projects/leadv2/plugins/leadv2/config/leadv2-deny-patterns.yaml` are **inode 19871800 — the same file**, and no `~/.claude/plugins/cache/leadv2-local/leadv2/*/plugins/leadv2/config/` copy exists in any cached version. **Consequence: the yaml edit is live the moment it is saved; no cache copy, no session restart.** (Probe: `ls -li` on both paths → identical inode; `for d in cache/*/ … ls` → no matches.) This contradicts the global "hooks are the exception, copy into the cache" rule — that rule is about hook `.sh` under a *cached* marketplace, not this local one.

### 1d. Callees of the changed code

None — the change is data. The functions that consume it (`re.search` in both parsers, `worktree_prune_active_lanes()` at `lv2guard.sh:109`, `heredoc_oversize()` at `:150`) are untouched.

## 2. STATES AND RETURN CODES

### 2a. `leadv2-deny-floor.sh` (Claude side)

| State | rc | What the caller (pre-dispatch hook → Claude) does | User-visible consequence |
|---|---|---|---|
| Kill-switch `LEADV2_DENY_FLOOR=0` (`:21`) | 0 | tool call proceeds | Every rule bypassed, including catastrophic ones. `git -C x reset --hard` executes. |
| Empty stdin / unparseable JSON / empty command (`:29,:40`) | 0 | proceeds | Fail-open: no floor. |
| Patterns file absent (`:47`) | 0 | proceeds | **No floor at all, silently.** Contrast lv2guard, which fails closed. |
| Any internal error (ERR trap `:18`) | 0 | proceeds | Fail-open. A malformed regex added by this change would land here — but `re.error` is caught per-rule (`:103`) so one bad regex skips only that rule and the rest still apply. |
| No rule matched | 0 | proceeds | Normal work unaffected. |
| Rule matched, `allow_inline_override: true`, `# deny-floor: allow` present (`:117`) | 0 | proceeds | Operator's explicit one-off escape hatch. |
| Rule matched, no valid override | **2** | Claude Code refuses the Bash tool call and returns the stderr block to the model | The command **never runs**; the model sees `[leadv2-deny-floor] BLOCKED: command matches deny-floor rule '<name>'` plus the rule message and the two escape hatches. **No retry loop** — the model must change the command or use `ask-lead.sh`. Live probe artifact: this architect's own analysis heredoc was refused with exactly `rule 'git_reset_hard'` at 2026-08-24, confirming the hook is armed on this session's Bash path. |

### 2b. `lv2guard.sh` (Codex side)

| State | rc | Caller behaviour | User-visible consequence |
|---|---|---|---|
| no args (`:53`) | 2 | shell reports usage error | Usage text on stderr. |
| `-c` with empty string (`:62`) | 2 | same | Usage text. |
| `python3` not on PATH (`:103`) | **97** | refuse | **Every** guarded command refused, including `ls`. Deliberate (no sibling guards). |
| canonical or extra patterns file unreadable / zero rules (`:104-105`, `:243-248`) | **97** | refuse | Same total refusal. **A yaml edit that breaks the line parser turns the Codex lead into a brick that cannot run `ls`** — this is the highest-blast-radius failure mode of this change (§3, §5 R2). |
| regex rule matched, no override | **97** | refuse | `[lv2guard] REFUSED: command matches rule '<name>'` on stderr; command not executed. rc 97 is reserved and never the wrapped command's own code. |
| regex rule matched, `-c` form + inline token + SOFT rule (`:259`) | passthrough | executes | Operator escape hatch. |
| predicate `worktree_prune_active_lanes`, 0 sessions (`:143`) | passthrough | executes | prune runs. |
| predicate, ≥1 session or malformed `active.yaml` (`:138-145`) | **97** | refuse | Only the prune is refused; unrelated commands unaffected (CB-4 blast radius, asserted at `test-lv2guard.sh:90`). |
| predicate `heredoc_oversize` over threshold (`:153`) | passthrough | executes | stderr advisory only. |
| unknown predicate name (`:256`) | passthrough | executes | stderr warning, **rule silently does not enforce**. |
| unknown `kind:` in deny-extra (`:221-223`) | rule skipped | — | stderr warning; the rest of the rule set still applies. |
| no match | passthrough / 127 | exec's the real command | Normal. |

**Terminal trace for the incident command, post-fix.** `git -C ~/Projects/leadv2 reset --hard HEAD` issued as a Claude Bash tool call → deny-floor rc 2 → the tool call is refused, the shared tree keeps its uncommitted files, and the model is told which rule fired. Issued through `lv2guard.sh -c` on the Codex side → rc 97, same outcome. Issued through `shim/git` → argv form → rc 97, **and not overridable** (CB-6).

## 3. CONFIGURATION BOUNDARIES

Inputs the mechanism reads, and the behaviour at each boundary.

| Input | Absent | Empty | Minimum | Maximum / over-cap | Malformed |
|---|---|---|---|---|---|
| `leadv2-deny-patterns.yaml` | hook: rc 0, **no floor**, silent (`:47`). lv2guard: rc 97, everything refused (`:104`) | 0 rules → hook allows all; lv2guard rc 97 (`:206-208`) | 1 parseable rule is enough for both | no rule-count cap; parse is O(lines) | line parser cannot fail — it silently produces a rule with no `regex`, which is **skipped** (`:96`, `:229`). **A quoting mistake in this change degrades to a silently-absent rule on the Claude side.** This is why §4.3's drift test is required. |
| `deny-extra.yaml` | lv2guard rc 97 (`:105`); Claude hook unaffected (never reads it) | 0 rules → lv2guard rc 97 (`:211-213`) | 1 rule | — | unknown `kind:` → that rule skipped with a warning (`:221`) |
| a single `regex:` value | rule skipped | rule skipped | — | no length cap in either parser; the ~250-char hardened regexes are fine. **Constraint: the value MUST stay on one physical line** — both parsers key off `stripped.startswith('regex:')` and take `split(':',1)[1]`; a YAML folded/block scalar (`>-`, `\|`) yields the literal `>-` as the pattern and the rule matches nothing. | `re.error` → that rule skipped, others still evaluated (`:103`, `:238`). Fail-soft per rule, not per file. |
| `LEADV2_DENY_FLOOR` | default `1` = enabled | `""` ≠ `"0"` → enabled | `0` disables everything (hook only) | — | any other value → enabled |
| `LEADV2_DENY_PATTERNS_FILE` | defaults to the in-repo path | empty → `${VAR:-default}` falls back to default | — | — | nonexistent path → hook fails open, lv2guard rc 97 (asserted `test-lv2guard.sh:110`) |
| `MATCH_CAP_BYTES` (lv2guard `:42`, hard-coded 65536) | n/a | n/a | — | **command >64KB: only the first 64KB is matched, the full command still runs** (CB-3). A destructive `git -C … reset --hard` past byte 65536 of a mega-command is NOT caught. Pre-existing; unchanged by this design; listed in §5 R4. | n/a |
| `LEADV2_CODEX_HEREDOC_WARN_BYTES` | 2048 | falls back to 2048 | 0 → warns on every heredoc | large → never warns | non-numeric → warning + 2048 (`:97-100`) |
| command string itself | empty → hook rc 0 | — | — | see MATCH_CAP | binary/NUL bytes: passed to `re.search` as a Python str; undecodable input would raise inside the parser → hook rc 0 (fail-open), lv2guard rc 97 |

**No boundary in this change takes down more than the operation it belongs to, except one:** a yaml file that fails to parse to ≥1 rule bricks the entire Codex lead (rc 97 on `ls`). Mitigation is §4.3's drift test, which parses both files with the *same* line parser and fails the suite if any rule loses its regex.

## 4. THE DESIGN

### 4.1 The fragment

One literal, reused verbatim in all 5 git rules. Name it `GITGLOBAL` in comments only — there is no interpolation mechanism (§0 M4).

```
(?:\s+(?:-[cC]\s*\S+|--(?:git-dir|work-tree|namespace|exec-path|super-prefix|attr-source|config-env)(?:=\S*|\s+\S+)|-{1,2}[A-Za-z][A-Za-z0-9-]*(?:=\S*)?))*
```

Three alternatives, ordered — first match wins per token:
1. `-[cC]\s*\S+` — `-C <path>`, `-C/path`, `-c k=v`, `-ck=v`. The two value-taking short flags.
2. the nine long global flags that accept a **separate** value (`--git-dir /p/.git` as well as `--git-dir=/p/.git`).
3. `-{1,2}[A-Za-z][A-Za-z0-9-]*(?:=\S*)?` — any other flag token: booleans (`-p`, `-P`, `--no-pager`, `--bare`, `--literal-pathspecs`) and any attached-value long flag (`--future-flag=1`), including ones git has not shipped yet.

It substitutes for the leading `git\s+` only: `git\s+X` → `git<GITGLOBAL>\s+X`. The rest of every rule is byte-identical to today.

### 4.2 The five rules (exact new values, single-quoted, one line each)

| File | Rule | New regex |
|---|---|---|
| `config/leadv2-deny-patterns.yaml` | `git_reset_hard` | `git<GG>\s+reset\s+.*--hard` |
| " | `git_clean_fdx` | `git<GG>\s+clean\b` + the three existing lookarounds, unchanged |
| " | `git_stash` | `git<GG>\s+stash(?!\s+(list\|show\|pop\|apply\|branch)\b)(\s\|$)` |
| " | `git_push_force_main` | both alternation branches get `<GG>`: `git<GG>\s+push\s+.*(--force\|-f)\b.*(origin\s+)?(main\|master)\b\|git<GG>\s+push\s+.*(main\|master)\b.*(--force\|-f)\b` |
| `codex-lead/deny-extra.yaml` | `worktree_prune_active_lanes` | `git<GG>\s+worktree\s+prune\b` |

Non-git rules (`rm_rf_root`, `rm_rf_home`, `mkfs`, `dd_to_dev`, `dev_redirect_overwrite`, `chmod_r_777_root`) and non-git extra rules (`codex_exec_direct`, `heredoc_oversize`) are **not touched** — census done, no git-global-flag surface in any of them.

Also add, above `rules:` in each file, a short comment block: the fragment verbatim, one sentence on why it exists (GUARD-RESET-FLAG-GAP-01), and the instruction that **any new rule beginning with `git` must include it** — the human-readable half of the drift test.

**Empirical validation of the fragment** (`docs/handoff/dispatch-28904576-architect/probe-regex.py`, run at 2026-08-24):

```
=== BLOCK cases (new must be 1) ===   22/22 OK
  old=0 new=1  [reset] git -C ~/Projects/leadv2 reset --hard HEAD     <- the live incident
  old=0 new=1  [reset] git -c core.pager=cat reset --hard
  old=0 new=1  [reset] git -c a=b -C /p --no-pager reset --hard
  old=0 new=1  [reset] git -P reset --hard
  old=0 new=1  [reset] /usr/bin/git -C /p reset --hard                 <- shim/git path
  old=0 new=1  [reset] git -C/p reset --hard                           <- attached value
  old=0 new=1  [clean] git -C /p clean -x -f -d
  old=0 new=1  [stash] git -c a=b stash drop
  old=0 new=1  [stash] git -C /p stash clear
  old=0 new=1  [push]  git -c a=b push --force origin main
  old=0 new=1  [push]  git -C /p push origin main --force
  old=0 new=1  [prune] git -C /p worktree prune
  (+10 already-covered adjacent forms, old=1 new=1 — no regression)
=== ALLOW cases (new must be 0) ===   13/13 OK, zero false positives
  git reset HEAD~1 · git -C /p log --oneline · git -C /p clean -n
  git -C /p commit -m "clean -fd is scary" · git -C /p stash pop
  git -C /p push origin feature · git -C /p worktree add /tmp/wt · …
```

### 4.3 Tests

**A. `plugins/leadv2/tests/test-deny-floor.sh`** — reuse the existing `run <expected_exit> <cmd>` helper. Add, grouped under a `# --- flag-interspersed git forms (GUARD-RESET-FLAG-GAP-01) ---` header:

| Case | Expect | Why |
|---|---|---|
| `git -C /tmp/x reset --hard HEAD` | 2 | the live incident |
| `git -c core.pager=cat reset --hard` | 2 | `-c k=v` |
| `git --git-dir=/tmp/x/.git reset --hard` | 2 | attached long value |
| `git -C /tmp/x --no-pager reset --hard` | 2 | multiple globals |
| `git --git-dir=/tmp/x/.git clean -fd` | 2 | mission case |
| `git -C /tmp/x clean -x -f -d` | 2 | separated flags + global |
| `git -c a=b stash drop` | 2 | mission case |
| `git -C /tmp/x stash clear` | 2 | — |
| `git -c a=b push --force origin main` | 2 | census |
| `git -C /tmp/x reset --hard HEAD # deny-floor: allow` | 0 | SOFT tier still overridable through the fragment |
| `git -C /tmp/x reset HEAD~1` | 0 | negative — global flag + non-hard reset |
| `git -C /tmp/x clean -n` | 0 | negative — dry-run survives the fragment |
| `git -C /tmp/x stash pop` | 0 | negative — read-only stash form survives |
| `git -C /tmp/x push origin feature-branch` | 0 | negative — non-force push |
| `git -C /tmp/x log --oneline` | 0 | negative — unrelated subcommand after globals |
| `git -C /tmp/x commit -m "clean -fd is scary"` | 0 | negative — **prose inside a different subcommand's args does not fire** (this is the real "prose" guarantee the mission asked for; see §0 M1) |
| `echo "git reset --hard"` | **2** | pins the deliberate over-block. Comment must say: *this shape is refused today and stays refused; the floor cannot distinguish quoting, and `# deny-floor: allow` is the escape hatch. Do not "fix" this into a 0 — that reopens GUARD-RESET-FLAG-GAP-01's sibling hole.* |

**B. Fragment-drift check, appended to `test-deny-floor.sh`.** Reads both yaml files with the same line parse the hook uses; for every rule, strip the substring `--git-dir` from the regex, then for every remaining occurrence of the literal `git` assert it is immediately followed by the exact `GITGLOBAL` literal. Fails with the offending rule name. This is the mechanical replacement for a shared helper: a sixth git rule authored without the fragment fails the suite instead of shipping a hole.

**C. `plugins/leadv2/codex-lead/tests/test-lv2guard.sh`** — the fixture already copies the live yamls (`:39-40`), so no fixture change. Add with `assert_rc`:

| Case | Form | Expect |
|---|---|---|
| `git -C /p reset --hard` | `-c` | 97 |
| `git -C /p reset --hard # deny-floor: allow` | `-c` | 0 |
| `git -C /p reset --hard` | **argv** (`-- git -C /p reset --hard`) | 97 — argv form, CB-6: no token possible |
| `/usr/bin/git -C /p reset --hard` | argv | 97 — the `shim/git` shape (§1c-1) |
| `git --git-dir=/p/.git clean -fd` | `-c` | 97 |
| `git -c a=b stash drop` | `-c` | 97 |
| `git -c a=b push --force origin main` | `-c` | 97 |
| `git -C /p worktree prune` with 1 active session in fixture `active.yaml` | `-c` | 97 — predicate reached **through** the fragment |
| `git -C /p worktree prune` with `sessions: []` | `-c` | 0 — predicate still allows |
| `git -C /p log --oneline`, `git -C /p clean -n`, `git -C /p stash list` | `-c` | 0 each |

The existing `bash -n` sweep at `:122-129` already covers every `codex-lead/*.sh`; `bash -n` on the two edited test files is the deliverable-4 check.

### 4.4 Sequencing

Additive and order-independent — both files are read fresh on every invocation, there is no cache and no restart (§1c-5). Recommended order: yaml edits → run both suites → tests. Rollback is `git checkout` of the two yamls (a single revert restores the previous, weaker floor; no state migration).

## 5. RISKS

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Anchoring the rules to command position** (`^git`, `(?:^\|[;&\|])\s*git`) to kill prose false-positives would silently un-guard `shim/git`'s absolute-path form `/usr/bin/git …` (§1c-1) and every `cd x && git …`, `$(git …)`, `xargs git …` shape (probe: all currently match). | **Do not anchor.** The asymmetry decides it: a false negative wiped a shared tree today; a false positive costs one `# deny-floor: allow`. Design keeps the unanchored `git` prefix. |
| R2 | A quoting/parse mistake in the long regex line yields a rule with **no** regex → Claude side silently loses that rule (fail-open), Codex side may hit rc 97 and refuse `ls`. | §4.3-B drift test parses both files with the production parser and asserts every git rule carries the fragment; the existing suites assert each rule still blocks its canonical case. |
| R3 | Adding the mission's literal negative case (`echo "git reset --hard"` → allowed) would require anchoring or a quote-stripping pre-pass, i.e. R1. | Rejected; pinned as a block-assertion with an explicit "do not flip this" comment (§0 M1). The *useful* prose guarantee — `git -C x commit -m "…clean -fd…"` stays allowed — is tested and holds. |
| R4 | `MATCH_CAP_BYTES=65536`: a destructive git form past byte 65536 of a mega-command is never matched (lv2guard only). | Pre-existing, deliberate (CB-3), out of scope. Named in §7. |
| R5 | Regex cost: the fragment is a bounded `(?:…)*` over `\S+` tokens; combined with `git_clean_fdx`'s three lookarounds it could be quadratic on a pathological 64KB input. | Each alternative is anchored to `\s+-`, so the star can only iterate over flag-shaped tokens; measured over the 35 probe cases with no observable cost. Recommend the implementer spot-check the 64KB path once and note the timing in the diff. |
| R6 | Four stale `.claude/worktrees/*/` copies of the yaml exist and will not receive the fix. | They are per-worktree and GC'd; not live callers (§1c-4). Explicitly out of scope — do not edit them. |

## 6. NON-GOALS (implementer: ignore these)

- No new deny rules. `git worktree remove --force`, `git branch -D`, `git filter-branch`, `git update-ref -d`, `git reflog expire` are all unguarded today and stay that way — new floor policy is a founder decision, not a regex fix (§0 M3).
- No fix for `rm --recursive --force /` (long-flag form; probe `rm-longflags match=0` — a real pre-existing hole in `rm_rf_root`, **non-git**, therefore outside "audit ALL git rules"). Report it; do not fix it here.
- No change to either parser, to `lv2guard.sh`, to `leadv2-deny-floor.sh`, to `leadv2-bash-pre-dispatch.sh`, or to the shims.
- No shared-regex-helper mechanism (yaml anchors, includes, a Python fragment module) — §0 M4.
- No change to tier assignments (`allow_inline_override`), messages, or the kill-switch.
- No edits under `.claude/worktrees/`, `~/.claude/plugins/cache/`, or `docs/leadv2/`.

## 7. COUNTEREXAMPLE — what still violates the invariant after every finding is fixed

The invariant: *no irreversible git operation reaches a shared working tree without an explicit operator override.* After this change, five holes remain, and I can name each.

**(a) An unknown separate-value global flag.** The fragment enumerates nine long flags that take a detached value; alternative 3 consumes only *attached*-value and boolean flags. A future or forgotten `git --future-flag val reset --hard` slips through — verified, `probe-edge.py: unknown-sepval match=0`. The attached form `--future-flag=1 reset --hard` is caught. This is the deliberate price of not over-consuming tokens (which is what would produce false positives on `git commit -m "…"`); it is a strictly smaller hole than today's, not a closed one.

**(b) The Codex side is opt-in prose, not runtime enforcement.** `lv2guard.sh:5-6` says it plainly: Codex has no blocking hooks, so a Codex lead that simply does not call `lv2guard` is unguarded by every rule in both files. The shims (`shim/git`, `shim/rm`) close this for two binaries only, are off by default, and are defeated by `bash -c`, a nested shell, or a worker lane with its own PATH.

**(c) Everything that is not the Bash tool.** The Claude-side floor is a `PreToolUse:Bash` hook. A `git reset --hard` issued from a Python `subprocess`, a Makefile target, a `.sh` file the model writes and then runs (`bash build.sh` matches nothing), an MCP server, or `codex exec` inside an unguarded lane never reaches the regex. This is the largest remaining surface and no regex change touches it.

**(d) `LEADV2_DENY_FLOOR=0` and the >64KB match cap.** The kill-switch bypasses every Claude-side rule including catastrophic ones (`:21`); the 64KB cap (R4) hides anything past the cap on the Codex side.

**(e) Aliases and indirection.** `alias g=git; g -C /p reset --hard` matches nothing — the string never contains `git`. Same for `$GIT_BIN`, a function named `deploy` that wraps the reset, or `git` invoked via `env -i`.

What I checked to make these claims: both yaml files in full; both parsers (`leadv2-deny-floor.sh:52-105`, `lv2guard.sh:162-241`); both dispatch paths (`leadv2-bash-pre-dispatch.sh:52` manifest, `lv2guard.sh:268-278` exec); both shims; both test suites in full; inode identity of the plugin-root and repo yaml plus the absence of any cache copy; and 35 regex cases across two probe scripts kept at `docs/handoff/dispatch-28904576-architect/probe-regex.py` and `probe-edge.py`. Holes (a)–(e) are the honest residual; (b) and (c) are architectural and belong in a separate task, not this one.

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >-
      A Bash tool call that puts a global flag in front of the subcommand —
      "git -C <path> reset --hard HEAD" — is refused before it runs, and the
      transcript shows the deny-floor block message naming the rule
      git_reset_hard, exactly as the flag-less form already does today.
    authored_at: 2026-08-24T11:40:00Z
  - surface: file_artifact
    observable: >-
      An uncommitted scratch file in the shared tree is still present, with its
      contents unchanged, after that refused attempt.
    authored_at: 2026-08-24T11:40:00Z
  - surface: log_line
    observable: >-
      On the Codex side the same command through the guard prints
      "[lv2guard] REFUSED: command matches rule 'git_reset_hard'" and the
      wrapped command produces no output of its own.
    authored_at: 2026-08-24T11:40:00Z
  - surface: log_line
    observable: >-
      A reviewer reading the two suites' printed summaries sees zero failures on
      both, with the new flag-interspersed cases listed as passing among them.
    authored_at: 2026-08-24T11:40:00Z
  - surface: rendered_line
    observable: >-
      Ordinary flagged work is unaffected: a "git -C <path>" invocation of log,
      status, commit, clean -n, stash pop, or a non-force push completes and
      prints its normal output with no deny-floor message anywhere.
    authored_at: 2026-08-24T11:40:00Z
```

LANE_WRITES: plugins/leadv2/config/leadv2-deny-patterns.yaml, plugins/leadv2/codex-lead/deny-extra.yaml, plugins/leadv2/tests/test-deny-floor.sh, plugins/leadv2/codex-lead/tests/test-lv2guard.sh

DELIVERABLE_COMPLETE
