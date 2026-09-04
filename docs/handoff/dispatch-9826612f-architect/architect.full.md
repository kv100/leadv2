# CODEX-LEAD-FULL-01 — architect prepass (mechanism-closed design)

Scope: design only. No implementation. All new code lands under
`plugins/leadv2/codex-lead/`; two existing docs get additive edits.

## 0. Discovery notes that contradict or refine the mission framing

The mission is the reason to look; the tree is the arbiter. Three refinements, none of
which halts the work (per the mission's HARD RULE, they are recorded and the design
proceeds against the code):

1. **The mission calls its whole deny list "CATASTROPHIC-tier". The tree disagrees.**
   `plugins/leadv2/config/leadv2-deny-patterns.yaml` holds **9** rules, of which only
   **6** are catastrophic (`allow_inline_override: false`): `rm_rf_root` (:25),
   `rm_rf_home` (:31), `git_push_force_main` (:55), `mkfs` (:61), `dd_to_dev` (:67),
   `dev_redirect_overwrite` (:73), `chmod_r_777_root` (:79) — that is 7; the 3 SOFT
   rules (`allow_inline_override: true`) are `git_reset_hard` (:37), `git_clean_fdx`
   (:43), `git_stash` (:49). The mission names `git reset --hard/clean/stash` as
   catastrophic. **Design decision:** lv2guard keeps the yaml's own tiering rather than
   the mission's prose, because the yaml is the single source and the Claude-side hook
   already behaves that way; a Codex lead that experiences a *stricter* floor than the
   Claude lead makes the pilot's checklist non-comparable. lv2guard therefore honours
   `allow_inline_override` with the same `# deny-floor: allow` token.
2. **The mission's list contains 3 rules that do not exist anywhere in the tree**:
   `git worktree prune` while lanes are active, direct `codex exec`, heredoc >2KB.
   These are genuinely new and are **not** regex-only — two of them require context
   (active.yaml state; byte length). They ship in a codex-lead-owned extras file, never
   by editing canonical yaml.
3. **The canonical floor fails OPEN, the mission mandates lv2guard fail CLOSED.**
   `leadv2-deny-floor.sh:19-20` traps ERR and exits 0; `:29` exits 0 on a missing
   patterns file. lv2guard inverts this. Intentional and correct — a hook that fails
   open still leaves Claude's other 32 guards standing, whereas lv2guard is the *only*
   floor on the Codex side. Recorded here so review does not read it as a copy bug.

## 1. CALLERS / CALLEES

Everything under `codex-lead/` is new, so it has no in-tree callers. Its *callees* are
all existing and verified. Two of the three "callers" are humans/agents, which is the
whole risk surface (see §4).

### 1a. Callers of each new artifact

| New artifact | Caller | Path | Note |
|---|---|---|---|
| `prompts/leadv2.md` | Codex CLI slash-expansion | `~/.codex/prompts/leadv2.md` (installed copy) | Upgrade of the shim that exists today at that path. The repo copy is the source; the installed copy is a copy by necessity (Codex has no symlink-following guarantee, and `~/.codex/` is outside the repo). This is the one sanctioned copy; `install.sh` is the only writer. |
| `prompts/leadv2-{status,dispatch,review,close}.md` | Codex CLI | same | New. |
| `lv2guard.sh` | The Codex lead's own shell, by prose mandate in the AGENTS brief | invoked as `bash <repo>/plugins/leadv2/codex-lead/lv2guard.sh <cmd...>` or via a PATH shim | **No programmatic caller. Opt-in.** This is the central weakness — §4. |
| `leadv2-codex-status.sh` | `prompts/leadv2-status.md`; founder directly | — | |
| `install.sh` | founder, once per machine/repo | — | Runs from anywhere, writes only outside the repo. |
| `tests/test-lv2guard.sh`, `tests/test-codex-install.sh` | `bash <file>` by hand and by any suite runner | `plugins/leadv2/codex-lead/tests/` | |

### 1b. Callees — every external thing the new code invokes, verified

| Callee | Path:line evidence | Called by | Contract used |
|---|---|---|---|
| deny patterns yaml | `plugins/leadv2/config/leadv2-deny-patterns.yaml:24-83` | `lv2guard.sh` | 9 rules, fields `name/regex/enabled/message/allow_inline_override`. Read, never written. |
| `leadv2-dispatch-code.sh` | `plugins/leadv2/scripts/leadv2-dispatch-code.sh`; burn-park `exit 6` at :1453; lock/prepass `exit 3` at :4907,:4947; duplicate `exit 2` at :2713,:2894; placement refusal `exit 5` at :741,:752,:763,:777,:784,:819; all-arms `exit 4` at :5209,:5219,:5291,:5322,:5339,:5367; usage `exit 1` at :4738,:4744,:4751,:5073,:5108 | `prompts/leadv2-dispatch.md` (prose instructs the lead to call it) | rc table §2b |
| `leadv2-review-run.sh` | `plugins/leadv2/scripts/leadv2-review-run.sh`; `exit 2`@:84,:1147 · `exit 6`@:1272,:1346 · `exit 7`@:1094,:1514 · `exit 8`@:1064,:1180 · `exit 9`@:1118,:1253 · `exit 0`@:1527 | `prompts/leadv2-review.md` | rc table §2c. Confirms the runbook's table byte-for-byte. |
| `leadv2-quota-live.sh` | `plugins/leadv2/scripts/leadv2-quota-live.sh:87-114`; modes `report\|json\|glm\|codex\|anthropic`, `--no-cache` | `leadv2-codex-status.sh`, `prompts/leadv2-status.md` | `json` mode. Live probe below. |
| `leadv2-status-surface.sh` | `plugins/leadv2/scripts/leadv2-status-surface.sh:28-30` (`--oneline`), read-only by contract (:16-18) | `leadv2-codex-status.sh` | `--oneline`. |
| `leadv2-broad-status.sh` → `docs/leadv2/founder-status.md` | renderer owned elsewhere; format contract `plugins/leadv2/docs/founder-status-format.md` | `prompts/leadv2-status.md` reads the artifact, never composes one | 3-column Russian table + ranked queue. |
| `docs/leadv2/active.yaml` (control-plane copy) | writer `plugins/leadv2/scripts/leadv2-active-registry.sh:163` — row keys `session_id, task_id, worktree, branch, started_at`; parsed with PyYAML at :97,:149 | `lv2guard.sh` (worktree-prune predicate), `leadv2-codex-status.sh` | **Read the control-plane path, not the repo path** — see §3 boundary CB-4. |
| `leadv2-state-path.sh --no-link root` | resolves to `~/.claude/leadv2-state/leadv2` (live probe below) | both new scripts | `--no-link` so rendering never mutates symlinks. |
| `codex-task.sh` | `plugins/leadv2/scripts/codex-task.sh:6-12` | named in the `codex_exec_direct` refusal message as the required door | — |

**Independent copies nobody named (the usual miss):** the quota reading has *two*
independent producers. The Claude statusline goes through `~/.claude/burn/statusline.sh:30`
→ `~/.claude/burn/quota-fragment.sh`, which is **user-local and outside this repo**;
`leadv2-quota-live.sh` is the in-plugin producer. They render the same three numbers by
different paths. **Decision: `leadv2-codex-status.sh` reads `leadv2-quota-live.sh json`
only.** Depending on `~/.claude/burn/quota-fragment.sh` would put a non-shippable
user-local file on the plugin's runtime path — exactly the drift class the global
shared-trees policy forbids. Consequence to state in the runbook: the Codex status line
and the Claude statusline can disagree transiently (different TTL caches: quota-live is
GLM 60s / Codex 120s / Anthropic 300s per its own report footer). That is acceptable and
must be documented, not hidden.

Live probe, quota-live report path (2026-08-24T09:36Z, this repo):

```
$ bash plugins/leadv2/scripts/leadv2-quota-live.sh report
=== leadv2 live quota (provider-owned numbers) ===
GLM (z.ai, pro):  5h=1% (resets 2026-08-24T12:10:06) | weekly=1% (...) | binding=weekly
Codex (plus):      3% used (97% remaining) | resets 2026-08-30T23:46:58 | credits: NONE (balance 0)
Anthropic (max_20x ACTIVE, ...): 5h=7.0% | weekly=68.0%
  (unknown = read failed; never reported as 0%. Per-bucket TTL cache: GLM 60s / Codex 120s / Anthropic 300s.)
```

Live probe, json shape (truncated): `.glm.status`, `.glm.binding_window` (`"weekly"`),
`.glm.five_hour.pct`, `.glm.weekly.pct`, `.glm.weekly.reset_iso`. The implementer reads
`.codex` / `.anthropic` sibling keys from the same invocation; their leaf names are
`UNVERIFIED:` here (only `.glm` was printed within the read bound) and **must be read
from a live `leadv2-quota-live.sh json` run before the renderer is written** — not
guessed from the report text.

Live probes, other:

```
$ bash plugins/leadv2/scripts/leadv2-state-path.sh --no-link root
/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2
$ python3 -c "import yaml;print(yaml.__version__)"   → 6.0.3
$ command -v jq                                      → /usr/bin/jq
$ echo '{}' | bash ~/.claude/burn/statusline.sh
... | cc 32%·7d/4d12h · cx 97%·wk/6d14h · glm 99%·wk/6d16h
```

That last line is the exact shape `leadv2-codex-status.sh` mirrors.

### 1c. Internal call graph of `lv2guard.sh`

```
main(argv)
 ├─ parse_mode()            # argv-form vs `-c <string>` form
 ├─ build_match_string()    # shell-quote join + $HOME→~ normalisation   [CB-6]
 ├─ load_rules()            # canonical yaml (9) + deny-extra.yaml (3)   [CB-1,CB-2]
 ├─ match_regex_rules()     # python3 -c, re.search, IGNORECASE — mirrors deny-floor.sh:60-110
 ├─ match_predicate_rules()
 │    ├─ pred_worktree_prune()  → reads active.yaml sessions[]           [CB-4]
 │    ├─ pred_codex_exec()      → regex, but message names codex-task.sh
 │    └─ pred_heredoc_size()    → advisory only, never refuses           [CB-5]
 ├─ refuse(rule) → stderr banner, exit 97
 └─ exec "$@"   (argv form)  |  exec bash -c "$str"  (-c form)
```

## 2. STATES AND RETURN CODES

### 2a. `lv2guard.sh`

| State | rc | What the caller (the Codex lead's shell, and the founder reading it) does | User-visible consequence traced to the end |
|---|---|---|---|
| No rule matched, argv form | *(command's own rc)* | `exec` replaces the process; the lead sees the real command's output and code verbatim | Guard is invisible. |
| No rule matched, `-c` form | *(command's own rc)* | same, via `bash -c` | Same. |
| CATASTROPHIC rule matched | **97** | Lead must not retry; must change premise or raise via founder | The destructive command never runs; founder sees a loud banner naming the rule. |
| SOFT rule matched, no inline token | **97** | Lead may re-issue once with `# deny-floor: allow` appended (`-c` form only — see CB-6) | Same as above until the token is added. |
| SOFT rule matched **with** `# deny-floor: allow` | *(command's own rc)* | executes | Matches Claude-side behaviour exactly. |
| Predicate `worktree_prune_active_lanes` fires | **97** | Lead must close/unregister lanes first | No worktree belonging to a live lane is pruned; a lane's diff cannot be silently destroyed mid-flight. |
| Predicate `codex_exec_direct` fires | **97** | Lead must re-issue through `codex-task.sh` | No Codex job is launched outside the wrapper, so tiering/`--reason`/journalling still apply. |
| Advisory `heredoc_oversize` fires | *(command's own rc)* | stderr warning only, command still runs | Founder sees a warning line; nothing is blocked. |
| **No args at all** | **2** | usage error printed | Distinguishable from a refusal. |
| Patterns file missing / unreadable / zero rules parsed | **97** | fail-CLOSED; lead must fix the install | **Every** guarded command stops until the plugin path is correct. Loud, not silent. |
| `python3` absent | **97** | fail-CLOSED | Same. |
| `active.yaml` unreadable/malformed **and** the command is a worktree-prune | **97** | fail-CLOSED for that one rule only | A prune is refused when lane state cannot be proven; other commands are unaffected. |
| Command not found after all checks pass | **127** | `exec`'s own code | Ordinary shell behaviour. |

**97 is reserved.** The runbook must say: `97` from a guarded invocation always means
"refused by lv2guard", never the wrapped command. Risk R-3 covers the collision case.

### 2b. `leadv2-dispatch-code.sh` rc → what `prompts/leadv2-dispatch.md` instructs

Verified against the script (line refs in §1b). Identical to the runbook table, so the
prompt restates rather than redefines.

| rc | Meaning | Prompt-mandated action | Consequence in plain words if the lead gets it wrong |
|---|---|---|---|
| 0 | launched / resolve-only | record handle, wait for evidence | — |
| 1 | usage/internal | fix invocation; never retry verbatim | A verbatim retry burns a turn and produces the same error. |
| 2 | duplicate signature | **never relaunch** | Relaunching double-spends: two workers write the same lane, one silently loses its diff. |
| 3 | lock unavailable / architect prepass parked | surface the decision; terminal until answered | Polling here spins forever; the task does not start today. |
| 4 | all arms refused/unavailable | terminal for today; do not poll | No worker exists for this task today; the founder gets nothing on it. |
| 5 | lane worktree placement refused | create the named worktree or pick a valid ref, then retry | — |
| 6 | burn cap parked | record the park; stop dispatching; **never raise the cap** | Correct stop. Raising the cap converts a budget guard into an overspend. |

**Terminal trace:** rc 3, 4 and 6 all reach a caller (the Codex lead) that has no retry
loop. The user-visible consequence of all three is the same sentence and the prompt must
say it: *"this task produces no work today; tell the founder in one line and move to the
next named task."* The failure mode the prompt exists to prevent is a lead that treats
rc=4 or rc=6 as transient and re-dispatches.

### 2c. `leadv2-review-run.sh` rc → what `prompts/leadv2-review.md` instructs

Verified in-code (§1b). Round cap is now engine-side (`exit 8` at :1064/:1180), so the
prompt must **not** carry its own round counter.

| rc | Meaning | Prompt-mandated action | Consequence in plain words |
|---|---|---|---|
| 0 | pass | only now may the diff proceed | — |
| 2 | missing/bad flags | fix the call; no merge | — |
| 6 | blocked: lost/empty review body | retry once with a different arm; a second block parks | — |
| 7 | fail | exactly one bounded fix round against the named findings, then re-review | `do_not_merge=1` is absolute: merging anyway ships unreviewed code. |
| 8 | round or spawn cap | escalate or park; **never loop** | The lane is out of review budget; looping burns quota and lands nothing. |
| 9 | unreviewed: no arm available | not a pass; park or escalate | Merging on rc=9 is a pre-registered FAIL condition of the pilot. |

The prompt must restate the runbook's hardest line: **a `review-gate.md` file is not a
verdict — read `status:`; only rc=0 *and* `status: pass` permit progress.**

### 2d. `install.sh`

| State | rc | Consequence |
|---|---|---|
| All targets already correct | 0 | prints `unchanged` per item; no `.bak` written. This is the idempotency observable. |
| Prompts copied / updated (existing differing file backed up) | 0 | prints `updated <file> (backup: <file>.bak)`. |
| repowise MCP block absent → appended between sentinels | 0 | prints `config.toml: repowise block added`; a `.bak` of the 101 KB file is written first. |
| `[mcp_servers.repowise]` exists **outside** our sentinels | 0 | prints `config.toml: repowise already configured by hand — left untouched`. **Never edits.** |
| `~/.codex/` absent | 0 | creates `~/.codex/prompts/` and proceeds. |
| Target repo path missing | 3 | prints the path; nothing written anywhere. |
| AGENTS.md `@import` line missing in target repo | 0 with a loud `ACTION REQUIRED:` line | **Verifies, never writes** — the runbook is explicit that persona-engine's `AGENTS.md` must not be overwritten. |
| `~/.codex/config.toml` unwritable | 4 | prompts already installed are kept; the failure is named. |

`install.sh` writes **nothing** inside `~/Projects/leadv2`. It ships here and runs
elsewhere.

### 2e. `leadv2-codex-status.sh`

Fail-open by mission constraint. One line on stdout, always rc 0 unless argv is wrong.

| State | rc | Rendered |
|---|---|---|
| All three buckets read | 0 | `cc <n>%·<win>/<reset> · cx <n>%·… · glm <n>%·… \| lanes <k> \| task <id>` |
| A bucket read fails | 0 | `?` for that bucket — **never `0%`** (quota-live's own contract). |
| `active.yaml` absent/empty | 0 | `lanes 0 \| task —` |
| `leadv2-status-surface.sh` slow/absent | 0 | lane segment degrades to `lanes ?`; the quota segment still renders. |
| Bad flag | 2 | usage. |

## 3. CONFIGURATION BOUNDARIES

| # | Input | Absent | Empty | Minimum | Maximum / over-cap | Malformed |
|---|---|---|---|---|---|---|
| CB-1 | `config/leadv2-deny-patterns.yaml` | **refuse, rc 97** (canonical hook exits 0 here — deliberate inversion, §0.3) | 0 rules parsed → refuse 97 | 1 enabled rule → normal | no cap; ~10² rules is a few ms of `re.search` | a single bad `regex:` is **skipped** (`re.error` → `continue`, mirroring deny-floor.sh:108-109), the rest still enforced. A file that parses to zero rules → refuse. |
| CB-2 | `codex-lead/deny-extra.yaml` | refuse 97 (it ships beside the guard; absence means a broken install) | refuse 97 | — | — | unknown `kind:` → **skip that rule with a stderr warning**, do not refuse the whole guard |
| CB-3 | the guarded command (argv or `-c` string) | no args → rc 2 usage | empty string in `-c` → rc 2 | — | **length cap 64 KiB for matching.** Over-cap: match the first 64 KiB, warn, and still exec. Refusing a long-but-legitimate command would take down work unrelated to the rule. | non-UTF-8 bytes → decode with `errors='replace'` before matching; never crash |
| CB-4 | control-plane `active.yaml` | prune predicate only: **refuse 97**; every other command unaffected | `sessions: []` → prune **allowed** (this is today's live state) | 1 session → prune refused | `sessions` with N rows → refused, message names the first 3 `task_id`s | YAML parse error → refuse 97 **for the prune rule only**. Bounded blast radius: an unparseable active.yaml must not stop `git status`. |
| CB-5 | heredoc-size advisory threshold `LEADV2_CODEX_HEREDOC_WARN_BYTES` | default 2048 | empty → default | `1` → warns on everything (operator's choice) | any value; non-numeric → default + warning | never refuses, so no malformed value can block work |
| CB-6 | `# deny-floor: allow` token | not present → SOFT rules refuse | — | — | — | **Only reachable in `-c` form.** In argv form the token would be a literal argument passed to the command. The AGENTS brief must state: overrides require `lv2guard -c '<cmd> # deny-floor: allow'`. |
| CB-7 | `$HOME` | unset → skip the `$HOME`→`~` normalisation, regexes still match literal `~` | — | — | — | — |
| CB-8 | `LEADV2_DENY_FLOOR=0` | default `1` → enforced | — | — | — | **lv2guard deliberately does NOT honour this kill-switch.** The Claude-side hook has 32 sibling guards; lv2guard is the only floor on the Codex side, and a lead that can disable its own floor with one env var has no floor. Documented divergence; the pilot's checklist depends on it. |
| CB-9 | `~/.codex/config.toml` (install) | created with just the sentinel block | zero-byte → sentinel block appended | — | 101 KB today; no cap — append only, `.bak` first | TOML that fails a parse check → **do not write**, rc 4, name the file. Never append to a file we cannot prove we understand. |
| CB-10 | `~/.codex/prompts/<name>.md` (install) | copied | copied | — | — | byte-differs from ours → `.bak` then overwrite; byte-identical → `unchanged`, no `.bak` |

Two boundary decisions that are load-bearing and easy to get wrong:

- **CB-3 over-cap must not refuse.** A 200 KB command string is weird but not
  destructive; refusing it takes down more than the operation it belongs to.
- **CB-4 malformed must refuse, but only the prune.** The inverse — a global refuse on
  an unparseable active.yaml — would brick every guarded command in the session.

## 4. COUNTEREXAMPLE

*After every finding in this mission is fixed, what can still violate the invariant this
mechanism exists to protect ("no irreversible operation reaches a shared tree")?*

Quite a lot, and the design must say so rather than let the pilot believe otherwise.
lv2guard is **advisory by construction**: nothing in Codex forces a command through it.
The AGENTS brief mandates it in prose, and prose is exactly what the pilot is measuring
compliance with — so a lead that forgets, or that reasons its way around the rule,
executes `rm -rf` with no floor in the way. Four concrete bypasses survive a perfect
implementation: (a) simply not typing `lv2guard`; (b) `lv2guard bash -c 'rm -rf ~'` —
the guard matches the *outer* string, and the inner one is reconstructed differently, so
tightening the regex helps only until the next nesting form (`env`, `sh -c`, `xargs`,
`find -exec`, a shell function, a `Makefile` target); (c) compound commands, since in
argv form `lv2guard git status && rm -rf ~` gives the guard only `git status` — the
`&&` belongs to the outer shell; (d) anything a *worker* does, since dispatched
Claude/GLM lanes never see lv2guard at all. What I checked to say this: the canonical
hook is a `PreToolUse` interceptor (`leadv2-deny-floor.sh:2`) that the Claude runtime
calls for *every* Bash tool use with no opt-out short of `LEADV2_DENY_FLOOR=0`; there is
no equivalent interception point in Codex — the runbook's own premise is "Codex has no
PreToolUse/blocking hooks", and I found no hook, wrapper, or plugin surface in
`~/.codex/config.toml`'s structure that would provide one. The honest conclusion: **the
real enforcement floor on the Codex side is the sandbox flag** (`-s workspace-write`,
runbook §Install), not lv2guard. lv2guard's genuine value is (i) catching the *honest
mistake*, which is the common case, and (ii) producing a transcript-auditable record for
the pilot's checklist. Two mitigations belong in the design and neither should be
oversold: **M-1** ship an optional `codex-lead/shim/` directory (`rm`, `git`, `codex`
wrappers that re-exec through lv2guard) which the founder can prepend to `PATH` — this
closes (a) and (c) for the named binaries and is the only structural fix available;
ship it **documented and off by default**, because a PATH shim that misbehaves breaks
every shell on the machine. **M-2** the runbook's transcript checklist stays the
measuring instrument, and its "deny floor" row must be reworded from "no destructive
command ran" to "every side-effecting command went through lv2guard", since only the
latter is observable in a transcript.

## 5. Files — exact list

| Path | New/edit | Purpose |
|---|---|---|
| `plugins/leadv2/codex-lead/lv2guard.sh` | new | the guard (§1c, §2a) |
| `plugins/leadv2/codex-lead/deny-extra.yaml` | new | 3 codex-lead-only rules: `worktree_prune_active_lanes`, `codex_exec_direct`, `heredoc_oversize` |
| `plugins/leadv2/codex-lead/leadv2-codex-status.sh` | new | one-line status (§2e) |
| `plugins/leadv2/codex-lead/install.sh` | new | idempotent installer (§2d) |
| `plugins/leadv2/codex-lead/prompts/leadv2.md` | new | upgrade of the `~/.codex/prompts/leadv2.md` shim |
| `plugins/leadv2/codex-lead/prompts/leadv2-status.md` | new | founder status, one compact Russian table per `founder-status-format.md` |
| `plugins/leadv2/codex-lead/prompts/leadv2-dispatch.md` | new | premise-check → dispatch via lv2guard; rc table §2b |
| `plugins/leadv2/codex-lead/prompts/leadv2-review.md` | new | review-run + verdict reading; rc table §2c |
| `plugins/leadv2/codex-lead/prompts/leadv2-close.md` | new | evidence-based close, journal append, ledger row, worktree left on disk |
| `plugins/leadv2/codex-lead/shim/{rm,git,codex}` | new | M-1, off by default |
| `plugins/leadv2/codex-lead/tests/test-lv2guard.sh` | new | deny/allow fixtures, no real destruction (§6) |
| `plugins/leadv2/codex-lead/tests/test-codex-install.sh` | new | idempotency: run twice → no dupes, no second `.bak` |
| `plugins/leadv2/docs/codex-lead-AGENTS-pilot.md` | edit | + lv2guard mandate, + prompt-pack map; **≤150 lines total** (74 today → ~40 lines of headroom) |
| `plugins/leadv2/docs/codex-lead-pilot-runbook.md` | edit | §Install gets the `install.sh` one-liner; §Transcript checklist "deny floor" row reworded per M-2 |

Non-goals, explicit — the implementing agent ignores all of these: no edit to
`leadv2-deny-floor.sh`, `leadv2-deny-patterns.yaml`, `hooks.json`, or any script under
`plugins/leadv2/scripts/`; no new Claude-side hook; no change to dispatch/review rc
semantics; no supervisor/fanout mode; no Codex-FULL or session-runner recursion; no MCP
tooling beyond the repowise block the installer ensures; no `~/.claude/burn/` dependency;
no writes to `docs/leadv2/` or `docs/handoff/` from any shipped script.

## 6. Test design (fixtures only — nothing real is destroyed)

`test-lv2guard.sh` — every case runs the guard with `LEADV2_CODEX_GUARD_EXEC=echo`
(a test seam that prints instead of exec'ing), inside a `mktemp -d` fixture:

- allow: `git status`, `ls`, `git clean -n`, `git stash list`, `rm -rf ./build` inside the fixture
- refuse 97: `rm -rf /`, `rm -rf ~`, `rm -rf $HOME/x`, `git push --force origin main`, `mkfs.ext4 /dev/x`, `dd of=/dev/sda`, `chmod -R 777 /`
- refuse 97 then allow with token: `git reset --hard`, `git clean -fd`, `git stash`
- predicate: `git worktree prune` with a fixture `active.yaml` holding one session → 97; with `sessions: []` → allow; with malformed yaml → 97; with malformed yaml + `git status` → allow (CB-4 blast-radius test)
- predicate: `codex exec 'x'` → 97 naming `codex-task.sh`; `codex-task.sh task 'x'` → allow
- advisory: 3 KB `-c` string → warning on stderr **and** rc 0
- fail-closed: patterns file pointed at a nonexistent path → 97 on `ls`
- CB-8: `LEADV2_DENY_FLOOR=0 lv2guard rm -rf /` → still 97

`test-codex-install.sh` — `HOME` redirected to a fixture; run twice; assert prompt count
unchanged, exactly one repowise sentinel block, no `.bak` from the second run, and the
`ACTION REQUIRED` line when the fixture repo's `AGENTS.md` lacks the `@import`.

Plus `bash -n` over every shipped `.sh` and every `shim/*`.

## 7. Risks

| # | Risk | Mitigation |
|---|---|---|
| R-1 | lv2guard is opt-in → the invariant is not closed | §4; ship M-1 shim off-by-default; reword the checklist row (M-2). Do not claim enforcement in any doc. |
| R-2 | `$HOME` is expanded by the shell before the guard sees it, so `rm_rf_home`'s `(~\|\$HOME)` regex never matches in argv form | CB-6/CB-7: normalise the match string `$HOME`→`~` **before** matching. Test asserts `rm -rf /Users/<me>` is refused. |
| R-3 | rc 97 collides with a wrapped command that genuinely exits 97 | Document 97 as reserved; the refusal always prints a `[lv2guard] REFUSED` banner to stderr, so the two are distinguishable by a human and by grep. |
| R-4 | `install.sh` corrupts a 101 KB hand-tuned `config.toml` | `.bak` first; TOML parse-check before and after; refuse to touch a hand-written `[mcp_servers.repowise]` (CB-9). |
| R-5 | The installed prompt copies drift from the repo source (the one sanctioned copy) | `install.sh` reports `unchanged`/`updated` per file, and `prompts/leadv2-status.md` instructs the lead to re-run `install.sh` at session start. Accepted, documented drift. |
| R-6 | AGENTS brief exceeds 150 lines | Budget: 74 today, cap 150. Guard mandate + prompt map must fit in ~40 lines; the rest of the headroom stays free. A test could assert `wc -l ≤ 150`. |
| R-7 | Two parallel readers of `active.yaml` (lv2guard predicate + status renderer) while the registry writes it | Both are read-only and the registry writes atomically under `fcntl` (`leadv2-active-registry.sh:95`, `:149`). No lock needed on the read side; a torn read surfaces as a YAML error, which CB-4 already handles by refusing the prune. |
| R-8 | Codex status and Claude statusline disagree | Different TTL caches (§1b). Documented in the runbook; not a defect. |

## Mandatory constraint checklist

1. **Env var naming** — all new vars use `LEADV2_*`: `LEADV2_CODEX_HEREDOC_WARN_BYTES`,
   `LEADV2_CODEX_GUARD_EXEC`, `LEADV2_DENY_PATTERNS_FILE` (reused from
   `leadv2-deny-floor.sh:27`). No `LEAD_V2_*` form introduced. PASS.
2. **File paths** — every path in §5 either exists (verified by `ls` this session) or is
   marked new. `plugins/leadv2/codex-lead/` does not exist yet (verified: absent). PASS.
3. **`claude -p` commands** — this design introduces none; the prompt pack routes all
   worker launches through `leadv2-dispatch-code.sh`, and the runbook already forbids
   hand-written `claude -p`. N/A, and the implementer must keep it N/A.
4. **Concurrent access** — R-7 covers the only shared file. `~/.codex/prompts/` is
   single-writer (`install.sh`, run by hand). No lock required.
5. **Config contradiction** — `LEADV2_DENY_FLOOR=0` has a *different* meaning on the two
   sides (honoured by the hook, ignored by lv2guard). Flagged as a deliberate divergence
   in CB-8 and it must be stated in the AGENTS brief; leaving it implicit would be the
   contradiction. Recorded rather than silently skipped.

## Acceptance

```yaml
acceptance:
  - surface: log_line
    observable: >
      Running the guard against a home-directory wipe prints a loud refusal banner
      naming the rule, and the home directory is still there afterwards.
    authored_at: 2026-08-24T09:45:00Z
  - surface: log_line
    observable: >
      Asking to prune worktrees while a lane is registered as active is refused with a
      message naming that lane's task; with no lanes registered, the same request goes
      through.
    authored_at: 2026-08-24T09:45:00Z
  - surface: file_artifact
    observable: >
      Installing twice in a row leaves exactly one copy of each prompt in the Codex
      prompts directory and exactly one repowise section in the Codex config, and the
      second run reports every item as unchanged with no new backup files.
    authored_at: 2026-08-24T09:45:00Z
  - surface: rendered_line
    observable: >
      The Codex status command prints one line showing the three quota percentages, the
      number of live lanes, and the active task — and when a provider cannot be read it
      shows a question mark for that provider rather than zero percent.
    authored_at: 2026-08-24T09:45:00Z
  - surface: rendered_line
    observable: >
      In a Codex session, the status prompt produces the founder's status as one compact
      Russian table with the three agreed columns, and the dispatch prompt refuses to
      re-dispatch a task the dispatcher reported as already running.
    authored_at: 2026-08-24T09:45:00Z
  - surface: file_artifact
    observable: >
      The pilot brief still fits inside its 150-line budget after the guard mandate and
      the prompt map are added.
    authored_at: 2026-08-24T09:45:00Z
```

LANE_WRITES: plugins/leadv2/codex-lead/lv2guard.sh, plugins/leadv2/codex-lead/deny-extra.yaml, plugins/leadv2/codex-lead/leadv2-codex-status.sh, plugins/leadv2/codex-lead/install.sh, plugins/leadv2/codex-lead/prompts/*.md, plugins/leadv2/codex-lead/shim/*, plugins/leadv2/codex-lead/tests/*.sh, plugins/leadv2/docs/codex-lead-AGENTS-pilot.md, plugins/leadv2/docs/codex-lead-pilot-runbook.md

DELIVERABLE_COMPLETE
