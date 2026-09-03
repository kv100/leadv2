# MERGED-BATCH-FIXROUND-01 — architect prepass (mechanism-closed implementation design)

Scope: the 6 High from `docs/handoff/dispatch-merged-batch/critic-lead.md` (H4 excluded — lead-owned),
plus the Medium/Low that are ≤5 lines inside a file the fix already touches.
Base: `b8ac631`. All code facts below were read from the live tree in this checkout, not from the
report; where the report's framing and the tree disagree, the tree wins and the disagreement is
stated.

**Contradiction with the mission's framing, stated up front (mission ¶H5):** the mission says the
fanout files are "currently UNCOMMITTED in the main checkout (a codex worker's aborted edits)".
They are not. `git log --oneline -1` → `b8ac631 fix(dispatch-fe034e50): fanout registry resolution
sibling-first, ladder test targets right artifact`; `git status --porcelain` lists only
`docs/leadv2/burn-deferred.d/`, `docs/leadv2/burn-deferred.jsonl`,
`plugins/leadv2/scripts/ZZ-pre-review-run.sh` — no fanout file. The sibling-first order is
**committed HEAD state**, and the worktree base is that commit. So H5 is a fix *on top of* b8ac631,
not a re-implementation "from origin state". This matters: implementing "from origin state" would
silently revert CORE-OFFLINE-WORKTREE-GAP-01 (the reason sibling-first landed), which is a
different regression. See §H5 for the reconciliation that keeps both invariants.

---

## Non-goals (explicit — do not do these)

- **H4** — regenerating `review.diff`. Lead-owned. Do not read or write `docs/handoff/dispatch-merged-batch/*`.
- **M1** (dual age floor). Deleting the hook-local newborn guard changes what H3's rewritten test
  asserts and re-opens SWEEP-KILLS-NEWBORN-LANE-01's merge seam. It is >5 lines, spans hook + lib +
  doc, and H3 explicitly says "re-run: if it goes red, the guard ordering (M1) is the real defect" —
  i.e. M1 is *diagnosed by* this round, not fixed in it. §H3 below specifies exactly what the
  rewritten test must do so M1's status becomes observable. Leave M1 open; name it in the summary.
- **M2** (install.sh sentinel-strip on upgrade) — a config-mutating change to `~/.codex/config.toml`
  on hosts that already installed. Out of scope for a fix-round; H6 only adds the *test* that makes
  the upgrade path visible. Do **not** add the strip logic without founder sign-off.
- **M4** (`PRE_HOOK` dual-pass measuring the wrong thing) — affects `test-worktree-lane-safety.sh`
  and the harness idiom shared by `test-merged-sweep-orchestration-dirt.sh`. Rewriting the dual-pass
  contract is its own task; H3 works *within* the existing `run_case` harness.
- **M6, M7, L3, L4, L5, L6, L7, L8** — none are ≤5 lines in a file this round touches
  (M7 is a 4-way exit-code split in the lib; L5/L6 are in suites not otherwise edited).
- **No refactor of `_MW_ORCH_RE`**, no extraction of shared helpers out of `leadv2-fanout.sh`,
  no touching `docs/leadv2/**` or `docs/handoff/**` as product output.
- **No new env vars.** Every knob below already exists (`LEADV2_SWEEP_MIN_AGE_S/_H`,
  `LEADV2_REPOWISE_MCP`, `LEADV2_STATE_ROOT`, `LEADV2_CANONICAL_ROOT`, `LEADV2_QUOTA_LIVE`) and all
  carry the `LEADV2_` prefix. No `LEAD_V2_*` drift is introduced.

---

## 1. CALLERS / CALLEES — per mechanism

### 1.1 H1 — the deny floor (`plugins/leadv2/codex-lead/deny-extra.yaml:55-59`)

Only one consumer parses this file, and it is not a function call — it is a file read:

| Site | file:line | Role |
|---|---|---|
| `lv2guard.sh` | `plugins/leadv2/codex-lead/lv2guard.sh:45` | `EXTRA_PATTERNS_FILE="$SCRIPT_DIR/deny-extra.yaml"` — the only resolver |
| `lv2guard.sh` | `:126` | readability precheck → `refuse extra_patterns_file_missing` |
| `lv2guard.sh` | `:184-266` (embedded python) | `parse_rules()` hand-parses the YAML line-by-line; matching is **`re.search(regex, cmd, re.IGNORECASE)`** at `:245` |
| `lv2guard.sh` | `:268` | zero-rule / unparseable → fail closed |

**Engine confirmed: python `re`, not `grep -E`.** Lookarounds are therefore legal. Probe:
`plugins/leadv2/codex-lead/lv2guard.sh:245` reads `if re.search(regex, cmd, re.IGNORECASE):`.

**Callers of `lv2guard.sh` itself** — both must be exercised by the new tests, because they feed the
matcher different strings:

| Caller | file:line | Form |
|---|---|---|
| Codex plugin PreToolUse hook | `plugins/leadv2/codex-lead/marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh` (133 lines) | delegates to canonical `lv2guard.sh` — it deliberately ships **no** copy of the yamls (`:106` comment: "plugin deliberately ships NO copy of lv2guard.sh or the yamls (one-copy…)"). **There is no second rule set to patch.** |
| Prose-mandated wrapper | `lv2guard.sh <command...>` argv form (`:27`) | argv joined |
| Adjudication | `lv2guard.sh --check -c '<string>'` (`:27`, `:66`, `:289`) | raw string, never execs |

**The independent copy nobody named:** there is none for the deny rules — I checked.
`find . -name deny-extra.yaml` returns exactly one path. The canonical
`plugins/leadv2/config/leadv2-deny-patterns.yaml` contains **no** `codex plugin` rule at all
(`grep 'plugin_uninstall_floor\|codex\\s+plugin'` → no match), so the Claude-side
`leadv2-deny-floor.sh` does not enforce this floor and is out of scope.

**Existing test coverage of this rule: zero.** `grep -rn "plugin remove|plugin uninstall|plugin_uninstall"`
over `plugins/leadv2/codex-lead/tests/` and `plugins/leadv2/tests/` returns nothing. The rule shipped
with no assertion of any kind.

### 1.2 H2 — `worktree remove --force` on unattended sweep paths

`plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh:189` is the site the report names. Its callees:

- `lv2_wt_protect_prime "${ROOT}"` — hook `:86` → lib `plugins/leadv2/scripts/lib/leadv2-worktree-protected.sh:118`
- `lv2_worktree_protected "${ROOT}" "${wt}"` — hook `:102` → lib `:249`
- fallback stubs when the lib is absent — hook `:76-77` (`prime` = no-op, `protected` = `return 5`)
- `git -C "${wt}" rev-list --count "${BASE}..HEAD"` — hook `:118`
- `git -C "${wt}" status --porcelain | grep -vE "${_MW_ORCH_RE}"` — hook `:171`
- `git worktree remove --force "${wt}"` — hook `:189`
- journal append via `${JOURNAL_BIN}` — hook `:195-197`

**The independent copies that nobody in the report named** — `grep -rn "worktree remove" plugins/leadv2`:

| file:line | Path | Protection-gated? | Verdict |
|---|---|---|---|
| `plugins/leadv2/scripts/leadv2-worktree-cleanup.sh:199` | `--sweep-dead`, "dead+empty" | yes — lib sourced at `:18-20` | **In the blast radius, out of this fix's scope.** It removes only lanes it has already proven *empty*, and it also `branch -D`s. Changing it is SWEEPER-LANE-SAFETY-01 territory, not this round. Name it in the summary. |
| `plugins/leadv2/scripts/leadv2-worktree-cleanup.sh:326` | `--sweep-merged` | yes | Its dirty check at `:319-324` is a **bare** `status --porcelain` with **no** orch-exclusion, so it already keeps any lane with an untracked handoff file. The `--force` here is a race-window belt-and-braces, not a deliverable-loss path. Leave. |
| `plugins/leadv2/scripts/leadv2-worktree-cleanup.sh:429` | explicit single-worktree removal | n/a | Operator-invoked with an explicit `--force` contract at `:420-426`. Correct as-is. |
| `plugins/leadv2/scripts/leadv2-codex-lead.sh:390`, `leadv2-red-first-gate.sh:155` | self-created scratch worktrees | n/a | The script created the tree in the same run. Not a lane. Leave. |

So H2's fix is **one call site** (`hooks/…:189`), and the design must say so explicitly rather than
sweeping `--force` out of the repo.

### 1.3 H3 — `case_newborn_kept`

`plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh`:

| Symbol | file:line | Note |
|---|---|---|
| `_mk` | `:76-101` | writes `$d/state/active.yaml` (`sessions: []`) at `:99`; back-dates lane meta at `:98` when `age=old` |
| `_backdate_lane_meta` | `:65-71` | `touch -t` on `<git-dir>/gitdir`, −1 h |
| `_swept` | `:103-109` | exports `LEADV2_STATE_ROOT="$repo/state"` **and** `LEADV2_SWEEP_MIN_AGE_H=0` |
| `case_orch_swept` / `case_real_work_kept` / `case_unmerged_kept` | `:112-131` | all go through `_swept` |
| **`case_newborn_kept`** | `:140-152` | **invokes the hook directly at `:144`** — no `LEADV2_STATE_ROOT`, no `LEADV2_SWEEP_MIN_AGE_H` |
| `case_no_regex_drift` | `:155-161` | reads the regex out of both files |
| `run_case` | `:163-176` | `pre_rc` from `git show HEAD:…` (M4 — the dual-pass caveat) |

Confirmed: `case_newborn_kept` is the **only** case that does not use `_swept`, which is precisely why
the fixture's `active.yaml` is never resolved and the run lands on rc 5.

**Cross-mechanism coupling the report understates:** `_swept` sets `LEADV2_SWEEP_MIN_AGE_H=0` but
**not** `_S`. The lib (`lib/leadv2-worktree-protected.sh:127-148`) prefers `_S` when numeric and
falls back to `_H`; with `_S` unset it uses `_H=0` → `LV2_WT_PROTECT_MIN_AGE_S=0` → probe D disabled
(`:279` `if (( LV2_WT_PROTECT_MIN_AGE_S > 0 ))`). The **hook-local** floor at `:145` reads only
`LEADV2_SWEEP_MIN_AGE_S`, unset → 1800 s, and the lane is back-dated 3600 s → passes. That is the
*only* configuration in which the hook-local newborn guard is reachable, and the suite is what
creates it. This is M1 restated as a mechanism fact: **the newborn guard is live-unreachable and
test-reachable.** The H3 rewrite must preserve that reachability or it will assert nothing again.

### 1.4 H5 — control-plane registry resolution

Two resolution chains, byte-identical in shape:

| Site | file:line | Chain (in order) |
|---|---|---|
| `leadv2-fanout.sh` | `:53-62` | sibling `${SCRIPT_DIR}` → vendored `${PROJECT_ROOT}/.claude/scripts` → `${LEADV2_CANONICAL_ROOT:-$HOME/Projects/leadv2}/plugins/leadv2/scripts` → `${HOME}/.claude/leadv2-shared/scripts`; then `source` at `:63` |
| `leadv2-fanout-lane-launcher.sh` | `:85-95` | identical four-step chain; then `source` at `:94`, plus `source "${SCRIPT_DIR}/leadv2-tasks-lib.sh"` at `:96` |

Callees after resolution: `leadv2-active-registry.sh` functions, plus (launcher only)
`_fanout_write_lane_terminal` — a **deliberately duplicated** copy of the fanout.sh helper, per the
comment at launcher `:99-108`. That duplication is documented and out of scope.

Callers of the launcher: `leadv2-fanout.sh` launch loop. Callers of `leadv2-fanout.sh`: the `/leadv2`
fanout entry and its suites.

**Property check on the live tree** — all three candidate copies are already state-path-aware:

```
plugins/leadv2/scripts/leadv2-active-registry.sh                    -> 2   (grep -c 'leadv2-state-path.sh')
/Users/…/.claude/leadv2-shared/scripts/leadv2-active-registry.sh    -> 2
.claude/scripts/leadv2-active-registry.sh                           -> 2
```

So the report's "the shared original still hardcodes `docs/leadv2/active.yaml`" is **stale as of this
checkout** — the shared copy carries the state-path call today. The invariant is nonetheless the
right one to enforce, because the drift guard (`leadv2-fanout.sh:85-105`) exists precisely because
these five copies do go stale independently. Enforce the *property*, do not re-order the chain.

**Existing test:** `test_5_registry_resolution_no_host_deps`,
`plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh:150-169`. It asserts only
`[[ "$out" == *"class=Standard"* ]]` (`:164`). It does not observe which copy was sourced, nor where
`active.yaml` was written.

### 1.5 H6 — untested live-path modules

| Module | file:line | Callers | Existing coverage |
|---|---|---|---|
| `repowise-launch.sh` (24 lines) | `plugins/leadv2/codex-lead/marketplace/plugins/leadv2/scripts/repowise-launch.sh` | `marketplace/plugins/leadv2/.mcp.json` `mcpServers.repowise.command = "./scripts/repowise-launch.sh"`, `cwd = "."` | `bash -n` only (test-lv2guard.sh, test-codex-plugin-manifest.sh) |
| callees | `:12-14` `exec bash "$LEADV2_REPOWISE_MCP"`; `:16-22` `$PWD`-upward walk → `exec bash "$DIR/.repowise/repowise-mcp.sh"`; `:24` `exit 0` | — | none |
| `install.sh` marketplace-add failure branch | `plugins/leadv2/codex-lead/install.sh:142-146` | operator | `test-codex-install.sh` virgin-`$FIX_HOME` only |
| `install.sh` fallback→plugin upgrade | `:165-200` (`USE_PLUGIN != 1` guard at `:177`) | operator | none |
| `cmd_verdict_provider` `limit_reached` | `plugins/leadv2/scripts/leadv2-burn-governor.sh:216-224` (embedded python) | dispatch table `:245-250` | tests 21–26 in `test-burn-governor.sh`, none feeding `limit_reached` |

`cmd_verdict_provider` callees: `config/leadv2-quota-ceilings.sh` → `leadv2_quota_ceiling` (`:195-200`),
`${LEADV2_QUOTA_LIVE:-${script_dir}/leadv2-quota-live.sh}` (`:205`), `python3` parser (`:207-232`).
**Its callers in product code: none** — that is M5, and it is why the new test is the only consumer.

---

## 2. STATES AND RETURN CODES

### 2.1 `lv2_worktree_protected` (lib `:249-304`) — consumed by both sweepers

| rc | `LV2_WT_PROTECT_REASON` | Set at | Merged-sweep hook does | User-visible consequence |
|---|---|---|---|---|
| 0 | `not-protected` | lib `:302` | falls through to ahead/newborn/dirt gates | lane may be swept |
| 1 | `active_yaml` | `:260` | log line to `/tmp/leadv2-sweep.log`, `continue` | lane kept, **nothing on stderr** (L1) |
| 2 | `arm_open` | `:266` | same | lane kept, silent |
| 3 | `live_pid` | `:275` | same | lane kept, silent |
| 4 | `young` | `:297` | same | lane kept, silent — and **not counted in `KEPT_YOUNG`** (hook `:114` `continue` precedes the counter at `:151`), so a pass that protects every lane prints nothing at all |
| 5 | `read-error:<err>` | `:253`, `:270`, `:292` | one stderr line per pass (`_PROTECT_ERR_SHOWN`), `continue` | **nothing is ever swept, on any lane, for as long as the control plane is unreadable.** Worktrees accumulate unbounded; the only symptom is disk. |

`LV2_WT_PROTECT_ERR` values that all collapse to rc 5 (M7, not fixed here):
`python3-absent` (`:151`), `state-path-resolver-absent` (`:157`), `state-path-resolver-failed` (`:162`),
`active-yaml-missing` (`:164`), `control-plane-unreadable` (`:171` — covers PyYAML absent, unopenable
file, non-dict YAML, malformed YAML, all four indistinguishable).

### 2.2 Merged-sweep hook terminal states (`hooks/leadv2-merged-worktree-sweep.sh`)

| State | Gate | Counter | Consequence |
|---|---|---|---|
| protected | `:102` | none (log file only) | lane survives this pass and every pass while protected |
| ahead>0 | `:118-121` | `KEPT_AHEAD` | "kept … with unmerged commits" on stderr |
| newborn | `:145-158` | `KEPT_YOUNG` | "N too young (<Ss)" — the `%s` prints `${min_age:-1800}`, a **loop-local from the last iteration** (L1), so it can report `1800` even when `_S` is set |
| real dirt | `:173-177` | `KEPT_DIRTY` | "kept … dirty" |
| removed | `:189` | `REMOVED` | worktree gone, branch retained (`:37`), journal note `worktree_swept … reason=merged-clean` |
| remove refused | `:199-201` | `KEPT_DIRTY` | reported as "dirty" even when the cause was something else (lock, permissions) |

The hook always `exit 0` (`:215`). It is a SessionStart hook: **a non-zero exit would not be
surfaced to anyone**, which is why every failure mode above is silent-by-construction and why H2's
data-loss window is invisible until a deliverable is missing.

**H2's precise state, in plain words:** a lane that is merged (ahead=0), unprotected, and whose only
uncommitted content is an untracked `docs/handoff/<id>/developer.full.md` is classified
`real_dirt == ""` by `:171` (the orch regex `^.. "?docs/handoff/` matches `?? docs/handoff/…`), reaches
`:189`, and is **deleted with the deliverable inside it**. Before the batch, plain `worktree remove`
refused on untracked files and the lane landed in `KEPT_DIRTY`. So: *a subagent's written analysis
disappears with no message anywhere, and the only trace is one `worktree_swept … reason=merged-clean`
line in the journal.*

### 2.3 `lv2guard.sh` rc contract (`:35`, `:66-90`, `:288-290`)

| rc | Meaning | Caller behaviour |
|---|---|---|
| 0 | allowed (`--check`: always 0 when allowed; wrapper: command's own 0) | Codex proceeds |
| 97 | refused by a deny rule | PreToolUse hook denies the tool call; the agent sees `message` |
| other | wrapped command's own exit code | passthrough |

For H1 the only rc that matters is 97-vs-0 on four command shapes. `--check` never execs (`:39`,
`:289`) so the tests are side-effect free.

### 2.4 `cmd_verdict_provider` (`leadv2-burn-governor.sh:187-243`)

| Input state | Output line | Consumer consequence |
|---|---|---|
| provider ∉ {glm,codex,claude} | `verdict=ok … reason=bad_provider` | **a typo'd provider reads as "quota fine"** |
| ceilings file unsourceable / `leadv2_quota_ceiling` absent | `verdict=ok … reason=no_telemetry` | dispatch proceeds |
| ceiling non-numeric | `verdict=ok … reason=no_telemetry` | dispatch proceeds |
| live probe unparseable / non-`ok` status | `verdict=ok … soft=S hard=C reason=no_telemetry` | dispatch proceeds |
| codex `limit_reached: true` (top-level **or** binding window) | parser prints `100` → `used=100 ≥ ceiling` → `verdict=hard reason=over_hard` | **the caller must refuse the dispatch** — this is the branch H6 says is unverified |
| `used ≥ ceiling` | `verdict=hard reason=over_hard` | refuse |
| `soft ≤ used < ceiling` | `verdict=soft reason=over_soft` | degrade/warn |
| `used < soft` | `verdict=ok reason=under_soft` | proceed |
| **`--providr` / any unknown flag** | dispatch table `*) cmd_verdict` (`:249`) → prints a **24 h token-burn** verdict | a caller cannot distinguish "provider quota fine" from "wrong gate answered" (M5, second half) |

Since `--provider` has **zero product callers**, every rc above terminates in a test or a human's
terminal today. Stated plainly: **the codex `limit_reached` saturation sentinel has never protected
a real dispatch, and if it were wired up tomorrow nothing would have proven it fires.**

### 2.5 `repowise-launch.sh`

| State | Line | rc | Consequence |
|---|---|---|---|
| `LEADV2_REPOWISE_MCP` set and file exists | `:12-13` | `exec` — becomes the server | repowise available |
| set but file missing | `:12` (guard `-f` fails) | falls through to the walk | **the override is silently ignored** |
| walk finds `$DIR/.repowise/repowise-mcp.sh` | `:18-19` | `exec` | repowise available |
| walk reaches `/` | `:17` loop exit | `exit 0` at `:24` | **MCP server starts and immediately exits; Codex reports no error; repowise is absent for the whole session and nothing anywhere says so** |
| `$PWD` deleted / unreadable | `:16` | `$PWD` is a shell variable, not a syscall — the loop still terminates at `/` | same silent `exit 0` |

### 2.6 `install.sh` plugin path

| State | Line | Printed | Consequence |
|---|---|---|---|
| marketplace registered at a different root | `:134-136` | `ACTION REQUIRED: … not re-pointed silently` | `MARKETPLACE_OK=0` → plugin install skipped → prompt-pack fallback |
| marketplace already at this root | `:137-139` | `marketplace …: unchanged` | `MARKETPLACE_OK=1` |
| `codex plugin marketplace add` succeeds | `:141-143` | `marketplace …: added` | `MARKETPLACE_OK=1` |
| **add fails** | `:144-146` | `ACTION REQUIRED: … failed` | falls through to fallback — **branch never exercised**, because `STUB_NOPLUG` fails `plugin --help` earlier |
| plugin already in config.toml | `:151-153` | `plugin: unchanged` | `USE_PLUGIN=1` |
| `plugin add` succeeds and registers | `:154-157` | `plugin: installed` | `USE_PLUGIN=1` |
| `plugin add` did not register | `:158-159` | `ACTION REQUIRED` | fallback |
| `USE_PLUGIN=1` | `:177` | repowise TOML block **skipped** | on a host that ran the pre-plugin installer, the old sentinel block stays → two servers named `repowise` (M2, not fixed) |

---

## 3. CONFIGURATION BOUNDARIES

### 3.1 `LEADV2_SWEEP_MIN_AGE_S` / `LEADV2_SWEEP_MIN_AGE_H`

| Input | Lib (`:127-148`) | Hook-local (`:145`) |
|---|---|---|
| both absent | 48 h | 1800 s |
| `_S=""` | falls to `_H` branch → 48 h | `${…:-1800}` → **`""`** (set-but-empty defeats `:-`) → `(( age < ))` on empty → bash 3.2 evaluates empty as 0 → **guard disabled** |
| `_S=0` | probe D disabled (`:279`) | `age < 0` never true → disabled |
| `_S=1` | 1 s | 1 s |
| `_S=2147483648` or larger | malformed branch → warns, falls to `_H`/48 h | `(( age < 2147483648 ))` — fine, everything is "young", **guard protects everything forever** |
| `_S="abc"` | one stderr warning, falls back — **never aborts the pass** (`:132`) | `(( age < abc ))` → bash treats an unset-name as 0 → guard disabled. Under `set -u`? The hook does **not** set `-u` (checked), so no abort. |
| `_H=0`, `_S` unset | probe D disabled | unaffected — **the documented kill switch does not reach the hook-local floor** (M1) |

Assessment against the mission's rule "an over-cap or malformed input that takes down more than the
one operation it belongs to is a defect": the **lib** is correct — malformed input warns and degrades
to the default, blast radius one probe. The **hook-local** floor silently mis-parses empty and
malformed values into "disabled". That is a defect, but it is M1's defect and M1 is a non-goal; the
H3 rewrite makes it *observable* rather than fixing it.

### 3.2 `LEADV2_STATE_ROOT` (via `leadv2-state-path.sh --no-link`)

| Input | Behaviour |
|---|---|
| absent | resolver's default root; in a fixture repo with no state that means `active.yaml` missing → `LV2_WT_PROTECT_ERR=active-yaml-missing` → **rc 5 on every lane** — exactly the H3 short-circuit |
| points at a dir with `active.yaml` = `sessions: []` | prime succeeds, zero sessions, probes A/C never fire |
| points at a dir with **no** `active.yaml` | `:163-165` → rc 5 fail-closed |
| `active.yaml` empty or comment-only | `yaml.safe_load` → `None` → `not isinstance(data, dict)` → `sys.exit(3)` → `control-plane-unreadable` → rc 5 |
| `active.yaml` malformed | same rc 5, same indistinguishable reason (M7) |
| `active.yaml` 10 MB | read once per **pass** (`prime`), not per worktree — bounded by design (lib `:19-21`) |
| PyYAML absent on the host | `:70-72` `sys.exit(3)` → rc 5 → **both sweepers permanently disabled, one opaque warning** |

### 3.3 Registry-resolution inputs (H5)

| Input | fanout `:53-62` / launcher `:85-95` |
|---|---|
| sibling exists, non-empty | chosen |
| sibling exists but **zero bytes** | `[[ -s ]]` false → next candidate. Correct. |
| sibling exists, non-empty, **not state-path-aware** | **chosen today, silently.** This is the hole H5 names. |
| `LEADV2_CANONICAL_ROOT` absent | defaults to `${HOME}/Projects/leadv2` |
| `LEADV2_CANONICAL_ROOT=""` | `${…:-}` on an empty-but-set var → falls back to the default. Verified idiom `${LEADV2_CANONICAL_ROOT:-${HOME}/Projects/leadv2}` uses `:-`, so empty → default. Correct. |
| `HOME` unset | `set -u` is on in fanout.sh (`:39`) → **`${HOME}` would abort**. In practice `HOME` is always set; `test_5` sets it to an empty dir. Not worsened by this change. |
| all four absent | `[[ ! -s ]]` → error line + `exit 1` — fail-closed, correct |

### 3.4 `LEADV2_REPOWISE_MCP`

| Input | `repowise-launch.sh:12` |
|---|---|
| absent / empty | walk |
| set, file exists | `exec` it |
| set, file missing | **falls through to the walk silently** — the override's failure is unobservable |
| set to a directory | `-f` false → walk |
| set to a non-executable file | `exec bash "$f"` — bash reads it, execute bit irrelevant. Fine. |

### 3.5 `.mcp.json` `cwd`

`cwd: "."` (`marketplace/plugins/leadv2/.mcp.json:6`) alongside the plugin-relative `command`. If `.`
resolves plugin-relative, `$PWD` at spawn is the plugin cache dir, the walk finds nothing, and the
launcher `exit 0`s silently (§2.5). **UNVERIFIED:** I have no probe artifact for how the Codex plugin
runtime resolves `cwd` in `.mcp.json` — the report says the same (M3: "the one wire-contract claim in
CODEX-LEAD-PLUGIN-01 with no probe artifact"). The design below therefore makes the launcher
*announce* its starting directory instead of asserting a resolution semantics we cannot prove.

### 3.6 `deny-extra.yaml` as an input to lv2guard's hand-parser

| Input | `parse_rules` (`:184-232`) |
|---|---|
| file absent/unreadable | `:126` and `:268` → refuse, fail closed |
| zero rules parsed | `__FAILCLOSED__extra` → refuse |
| a rule with an **invalid** regex | `re.error` → `continue` (`:250`) — **that one rule is silently skipped, the rest still enforce.** A malformed new rule therefore reopens the floor with no message. This is the single most important boundary for H1: the new regex must be validated by a test, not by eye. |
| regex value containing a single quote | the parser strips matching outer quotes only (`:203-205`); an inner `'` in a single-quoted YAML scalar would need `''` and the hand-parser does not un-escape it. **Avoid quotes inside the regex entirely.** |
| regex value containing `:` | `split(':', 1)` splits on the *first* colon only, so `regex:` values with colons survive. |
| rule with unknown `kind` | warned + skipped (`:239-242`) |

---

## 4. THE DESIGN — per finding

### H1 — close the plugin-removal floor

**File:** `plugins/leadv2/codex-lead/deny-extra.yaml` (replace the single rule at `:55-59`).

Use **three explicit rules**, not one lookahead regex. Rationale: the parser silently drops a rule
whose regex fails to compile (`:250`), so a single clever regex is a single point of silent failure
covering all four shapes; three simple regexes fail independently and each is directly asserted.
Also, `re.IGNORECASE` is already applied, so `--Provider`-style case variants are covered for free.

| Rule name | regex (single-quoted, no inner quotes) | Covers |
|---|---|---|
| `plugin_uninstall_floor` | `codex\s+plugin\s+(remove\|uninstall)\b.*\bleadv2\b` | unchanged — `codex plugin remove leadv2@leadv2-local`, `codex plugin uninstall leadv2` |
| `plugin_marketplace_remove_floor` | `codex\s+plugin\s+marketplace\s+(remove\|rm)\b.*\bleadv2\b` | `codex plugin marketplace remove leadv2-local` |
| `plugin_disable_floor` | `codex\s+plugin\s+disable\b.*\bleadv2\b` | `codex plugin disable leadv2` |

All three: `kind: regex`, `enabled: true`, `allow_inline_override: false`, each with its own
`message` naming what is being removed and that the founder runs it by hand.

`\bleadv2\b` matches inside `leadv2-local` (the `-` is a word boundary) and inside
`leadv2@leadv2-local` — no widening needed.

**Tests** — `plugins/leadv2/codex-lead/tests/test-lv2guard.sh`, as `assert_rc` rows next to the
existing `--check` block (harness at `:20-21`, existing rows from `:50`):

| Expect | Command |
|---|---|
| 97 | `codex plugin remove leadv2@leadv2-local` |
| 97 | `codex plugin uninstall leadv2` |
| 97 | `codex plugin marketplace remove leadv2-local` |
| 97 | `codex plugin disable leadv2` |
| 97 | `codex plugin marketplace rm leadv2-local` |
| 0 | `codex plugin remove someother@other-market` — no `leadv2`, must stay allowed |
| 0 | `codex plugin list` |

Plus one **compile guard**: a case that runs the same `re.compile` over every `regex:` in
`deny-extra.yaml` and fails if any raises `re.error` — this is what makes the `:250` silent-skip
boundary (§3.6) impossible to reopen. ~6 lines of python in the suite.

**Boundary to check before committing:** `plugins/leadv2/tests/test-deny-floor.sh` asserts
"every git rule in deny-extra.yaml carries GITGLOBAL". The three new rules are `codex plugin` rules,
not git rules; confirm the drift check's selector does not match them (it keys on git patterns) —
run `test-deny-floor.sh` as part of the round regardless.

### H2 — drop `--force` from the merged-sweep path

**File:** `plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh`.

Adopt the report's option (a) — decide first, then discard only what the decision proved
discardable, then plain remove:

1. Keep `:171`'s decision (`real_dirt` computed from `status --porcelain` minus `_MW_ORCH_RE`) exactly
   as-is. The ordering fix from the batch is correct and stays.
2. After the decision says "removable", re-run `git -C "${wt}" status --porcelain -uall`, keep only
   lines matching `_MW_ORCH_RE`, strip the 3-char porcelain prefix and the optional surrounding
   quotes, and `rm -rf` **only those paths**, each resolved under `${wt}` and rejected if the
   resolved path escapes `${wt}` (defensive: a quoted porcelain path with `..`).
3. `git worktree remove "${wt}"` — **no `--force`**.
4. On refusal → `KEPT_DIRTY` as today. The tree is not gutted, because step 2 removed only paths the
   decision already classified as regenerated bookkeeping, and step 3 refusing means something else
   appeared (a race) — which is exactly the case that must be kept.

`-uall` matters: default `status --porcelain` reports an untracked *directory* as one entry
(`?? docs/handoff/`), and the existing `_MW_ORCH_RE` anchors on `^.. "?docs/handoff/` which still
matches — but `-uall` makes the removal list file-granular and the assertion legible.

Update `plugins/leadv2/docs/worktree-sweepers.md` "Deliberate boundaries" to say the sweeper
force-discards nothing and a removal refusal keeps the lane (≤5 lines, file already in the batch).

**Tests** — `plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh`, new case
`case_untracked_handoff_deliverable_survives`: merged lane, unprotected, whose only dirt is an
**untracked** `docs/handoff/lane/deliverable.md` containing a known sentinel string. Assert the
sentinel is still readable somewhere on disk after the pass. Given the design above (the file matches
`_MW_ORCH_RE`, so it is classified as bookkeeping and *is* removed with the tree), the honest
assertion is the stricter one: **the lane is kept and the file survives at its original path.** To
get that, step 2's removal list must exclude `docs/handoff/` when the entry is untracked. Concretely:
`_MW_ORCH_RE` stays the *classification* regex; the *removal* list is `_MW_ORCH_RE` **minus** any
untracked (`^??`) `docs/handoff/` entry, and an untracked handoff entry additionally forces
`real_dirt` non-empty so the lane lands in `KEPT_DIRTY`. That is the only shape in which a deliverable
cannot be lost by construction rather than by ordering luck.

This is a deliberate divergence from the report, which offered (a) or (b); (a) as written still
deletes the deliverable because `docs/handoff/` is inside the orch set. Say so in the commit message.

### H3 — make `case_newborn_kept` reach the newborn guard

**File:** `plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh:140-152`.

1. Line `:144` — add the same environment `_swept` uses: `LEADV2_STATE_ROOT="$repo/state"` **and**
   `LEADV2_SWEEP_MIN_AGE_H=0`. The `_H=0` disables the lib's probe D (§1.3) so the lane reaches the
   hook-local guard; `LEADV2_STATE_ROOT` makes prime succeed so rc 5 cannot satisfy the assertion.
   Keep the direct invocation (the case needs stderr, which `_swept` discards) rather than reusing
   `_swept`.
2. Tighten `:149` from `grep -qiE "young|protect"` to `grep -q "young"`.
3. Add a **negative control** in the same case: assert the output does **not** contain
   `read-error` — so a future regression that reintroduces the fail-closed path is red, not green.

Expected outcome: the case exercises hook `:145-158` with `min_age=1800` and a 0-second-old lane →
`KEPT_YOUNG`, stderr `… 1 too young (<1800s): lane (young 0s)`. If it goes red instead, M1's ordering
is the real defect and that must be written into the summary — **not** worked around by loosening the
assertion again.

### H5 — enforce the property, keep sibling-first

**Files:** `plugins/leadv2/scripts/leadv2-fanout.sh:53-62`,
`plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh:85-95`.

Do **not** reverse the chain — sibling-first is what CORE-OFFLINE-WORKTREE-GAP-01 needs (a lane
worktree has no vendored `.claude/scripts/`; a fixture `$HOME` has no shared tree). Instead make each
candidate's acceptance conditional on the property:

- Replace each `[[ -s "$cand" ]]` acceptance with `[[ -s "$cand" ]] && grep -q 'leadv2-state-path.sh' "$cand"`.
  A candidate that is present but not state-path-aware is **skipped**, and the chain continues to the
  next copy.
- If no candidate satisfies the property, the existing fail-closed branch fires with a message that
  names the property, not just the paths: `leadv2-active-registry.sh not found, or every copy found
  (sibling/vendored/canonical/shared) predates the control-plane state-path resolution — refusing to
  launch`.
- Restore the removed rationale comment, corrected: the invariant is *"the resolved copy routes
  active.yaml through leadv2-state-path.sh"*, and sibling-first is an availability ordering, not the
  invariant.

Implement as a small local helper in each file (they cannot share one — the launcher's comment at
`:99-108` documents why fanout.sh is not a library). ~8 lines each, identical text.

**Tests** — `plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh`:

- Strengthen `test_5` (`:150-169`): after the dry run, assert that
  `${sandbox}/state/active.yaml` exists (or was the path written) **and** that
  `${sandbox}/proj/docs/leadv2/active.yaml` does **not** exist. That is the property the report asks
  for — the run's registry writes landed under `LEADV2_STATE_ROOT`.
- New `test_6_registry_property_rejects_stale_copy`: sandbox where the sibling `SCRIPT_DIR` copy is
  replaced by a stub with no `leadv2-state-path.sh` reference and a valid vendored copy exists →
  assert the run still succeeds (skipped to vendored). Then a second sandbox where **every** copy is
  stale → assert exit 1 and the refusal message.

### H6 — behavioural tests for the untested live-path modules

**New file:** `plugins/leadv2/codex-lead/tests/test-repowise-launch.sh` (harness idiom copied from
`test-lv2guard.sh`). Cases, all hermetic under `mktemp -d`, all invoking the launcher with a stub
`repowise-mcp.sh` that prints a sentinel and exits 0:

| Case | Setup | Assert |
|---|---|---|
| override honoured | `LEADV2_REPOWISE_MCP=<stub>` | stub sentinel on stdout |
| override missing-file falls back | `LEADV2_REPOWISE_MCP=/nonexistent` + a walkable repo | walk sentinel on stdout **and** a stderr line naming the ignored override (new behaviour, see below) |
| walk finds it at cwd | `$PWD/.repowise/repowise-mcp.sh` | stub sentinel |
| walk finds it 3 levels up | stub at the sandbox root, cwd 3 dirs deep | stub sentinel |
| not found | no `.repowise` anywhere up to `/` | rc 0, empty stdout, **one stderr line naming the directory the walk started from** |
| args passthrough | stub echoes `$@` | args reach the server verbatim |

**Behaviour change in the module** (M3's second half, ≤5 lines, in a file this round already
touches): before `exit 0` at `:24`, print one stderr line —
`[repowise-launch] no .repowise/repowise-mcp.sh found walking up from <start-dir> — repowise MCP unavailable for this session`;
and when `LEADV2_REPOWISE_MCP` is set but not a file, print one stderr line saying so. This converts
§2.5's silent absence into an observable one. Capture `START_DIR="$PWD"` before the loop mutates
`DIR`.

**Do not** drop `cwd` from `.mcp.json` — that is an unprobed wire-contract change (§3.5). The stderr
line makes the actual resolution observable the next time a Codex session starts, which is the probe.

**`plugins/leadv2/codex-lead/tests/test-codex-install.sh`** — add two cases:
- *marketplace-add failure*: a codex stub whose `plugin --help` succeeds (so the plugin path is
  entered) but whose `plugin marketplace add` exits non-zero → assert `ACTION REQUIRED` on stdout and
  that the prompt-pack fallback was installed.
- *fallback→plugin upgrade*: run the installer once with `STUB_NOPLUG` (writes the sentinel block to
  `$FIX_HOME/.codex/config.toml`), then again with the plugin-capable stub → assert the config still
  contains exactly one `[mcp_servers.repowise]` **or**, if two, that the test records the M2 defect
  explicitly. Since M2 is a non-goal, this case is written as a **characterisation test** that asserts
  today's behaviour and carries a `# lean: characterises M2, not a fix` comment. Do not make it pass
  by changing install.sh.

**`plugins/leadv2/scripts/tests/test-burn-governor.sh`** — add two rows:
- codex `limit_reached: true` at the **top level** with `used_percent: 4` in the binding window →
  assert `verdict=hard`, `used_pct=100`, `reason=over_hard`.
- codex `limit_reached: true` on the **binding window** only → same assertion (the parser's `or`
  branch at `:222`).

Both via a `LEADV2_QUOTA_LIVE` stub emitting the fixture JSON — the env var already exists (`:205`).

### Medium/Low taken opportunistically (≤5 lines, files already touched)

| id | File | Change |
|---|---|---|
| L1a | `hooks/leadv2-merged-worktree-sweep.sh:151` | count lib-`young` (rc 4) keeps into `KEPT_YOUNG` so an all-protected pass is not silent |
| L1b | `hooks/leadv2-merged-worktree-sweep.sh:209` | print the resolved floor, not the loop-local `${min_age:-1800}` — hoist `min_age` out of the loop |
| L2 | `hooks/leadv2-merged-worktree-sweep.sh:108` | `${TMPDIR:-/tmp}/leadv2-sweep.$(id -u).log`, and refuse to write through a symlink |
| M5b | `scripts/leadv2-burn-governor.sh:249` | insert `-*) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;` before the catch-all |
| M3b | `marketplace/…/scripts/repowise-launch.sh:24` | the two stderr lines described above |

Everything else from the report stays untouched: **M1, M2, M4, M6, M7, L3, L4, L5, L6, L7, L8** —
list them verbatim in the summary as deliberately deferred.

---

## 5. COUNTEREXAMPLE — what still violates the invariants after all six are fixed

The invariant this cluster protects is *"no unattended automation destroys work a human or an agent
has not yet handed off, and no floor the guarded agent stands on can be removed by the guarded
agent."* After all six fixes, three things still violate it.

**(1) The floor is only as strong as its file's readability, and the guard's own bypass surface is
wider than `codex plugin`.** H1 closes four command shapes on one rule set. It does not close
`rm ~/.codex/plugins/…`, editing `~/.codex/config.toml` to drop the `[plugins."leadv2@leadv2-local"]`
block, `mv`ing `deny-extra.yaml`, or running `codex --dangerously-bypass-hook-trust`. The
fail-closed reads at `lv2guard.sh:126/268` catch a *missing* file at match time, but nothing prevents
the removal itself, and nothing at all guards the config-file edit. More narrowly: a rule whose regex
fails to compile is silently skipped at `:250`, so a future well-meaning edit to any of the three new
regexes reopens the floor with zero signal — which is exactly why the compile-guard test in §H1 is
part of the fix rather than a nicety. **(2) The deliverable-loss window is narrowed, not closed.**
After H2 the sweeper keeps a lane whose handoff dir is untracked, but a lane whose deliverable was
`git add`ed and not committed is still classified by `_MW_ORCH_RE` as bookkeeping (the regex keys on
the path, not the porcelain status), and the merged+unprotected+staged-handoff-only lane is still
removed. Worse, the whole protection layer collapses to rc 5 on a host without PyYAML — and rc 5 is
*safe* for the sweeper but means every lane is kept forever, so the operator's incentive is to
"fix" it by disabling the gate, at which point every gate above is bypassed at once with one env var.
**(3) H5 enforces a proxy, not the property.** `grep -q 'leadv2-state-path.sh'` proves the string
appears in the file, not that the resolution path actually routes through it — a copy that contains
the string in a comment, or calls it on one branch and hardcodes `docs/leadv2/active.yaml` on
another, passes. The five-copy drift problem the guard at `leadv2-fanout.sh:85-105` exists for is
unchanged by this round; H5 only ensures the *chosen* copy has the right shape, and the drift guard
can still be bypassed wholesale with `LEADV2_SKIP_DRIFT_GUARD=1`. Finally, the newborn guard remains
live-unreachable (M1): after H3 the suite proves the guard *works* in a configuration only the suite
creates, and in default config `lv2_worktree_protected`'s 48 h `young` probe answers first — so the
code H3 now genuinely tests is code that never runs in production.

What I checked and found *not* to be a counterexample: the marketplace PreToolUse hook ships no
second copy of the deny rules (`lv2guard-pretooluse.sh:106`, 133 lines total, delegates to canonical),
so H1 has no sibling to patch; `leadv2-worktree-cleanup.sh:326`'s `--force` is preceded by a bare
`status --porcelain` dirty check with no orch exclusion, so it cannot lose an untracked deliverable;
and `leadv2-worktree-cleanup.sh:429` is operator-invoked behind an explicit `--force` contract.

---

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| The three new deny regexes over-block a legitimate `codex plugin remove <other>` | explicit rc-0 rows in the suite for a non-leadv2 removal and for `codex plugin list` |
| A new regex fails to compile → rule silently skipped (`lv2guard.sh:250`) | the compile-guard test case in §H1 — mandatory, not optional |
| H2's removal-list step deletes something outside the worktree via a crafted porcelain path | resolve each path under `${wt}` and skip anything that escapes; `-uall` for file granularity |
| H3 goes red because M1's ordering makes the guard unreachable | that is the designed outcome — record it in the summary as M1 confirmed; do **not** loosen the assertion |
| H5's `grep -q` makes fanout refuse to launch on a host whose copies are all stale | all three copies on this checkout already satisfy the property (probed, §1.4); the refusal message names the remedy |
| `test-repowise-launch.sh` walks up to `/` and finds a real `.repowise` on the dev machine | run every case with `cd` into a `mktemp -d` under `${TMPDIR}`, and assert on the sentinel, not on absence alone; if `${TMPDIR}` itself is inside a repowise repo the not-found case must use a `HOME`- and `PWD`-isolated dir under `/tmp` |
| Two parallel steps touching `hooks/leadv2-merged-worktree-sweep.sh` (H2 + L1 + L2) | single-agent, sequential — commit H2 first, then the L1/L2 one-liners, so a bisect separates the data-loss fix from cosmetics |
| Concurrent access: the merged-sweep hook runs at **every** SessionStart, including inside the lane doing this work | the lane's own worktree is protected by probe A/B while the arm is open; do not run the hook manually in this worktree |

## 7. Suites to run

```
bash plugins/leadv2/codex-lead/tests/test-lv2guard.sh
bash plugins/leadv2/codex-lead/tests/test-repowise-launch.sh        # new
bash plugins/leadv2/codex-lead/tests/test-codex-install.sh
bash plugins/leadv2/codex-lead/tests/test-codex-plugin-manifest.sh
bash plugins/leadv2/tests/test-deny-floor.sh
bash plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh
bash plugins/leadv2/scripts/tests/test-worktree-lane-safety.sh
bash plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh
bash plugins/leadv2/scripts/tests/test-burn-governor.sh
```

bash 3.2 throughout: no associative arrays, no `${var,,}`, no `mapfile`, `stat -f`/`stat -c` both
guarded, no `readarray`. No credentials logged.

---

acceptance:
  - surface: log_line
    observable: "On a SessionStart pass over a merged, unprotected lane whose only uncommitted content is an untracked docs/handoff/<id>/deliverable file, the sweeper's stderr names that lane as kept-dirty, and the deliverable file is still readable at its original path inside the worktree afterwards."
    authored_at: 2026-08-24T17:11:10Z
  - surface: log_line
    observable: "A Codex agent that types the plugin-removal command printed in the runbook's own Rollback section sees the guard's refusal message about the leadv2 deny floor instead of the plugin being removed; the same is true for the disable form and the marketplace-remove form."
    authored_at: 2026-08-24T17:11:10Z
  - surface: file_artifact
    observable: "After a fanout dry run in an isolated sandbox, the session registry file exists under the configured state root and no registry file has appeared at <project>/docs/leadv2/active.yaml."
    authored_at: 2026-08-24T17:11:10Z
  - surface: log_line
    observable: "A Codex session started in a directory with no repowise repo above it prints one line naming the directory the search started from and stating that repowise is unavailable, instead of repowise being silently absent with no message anywhere."
    authored_at: 2026-08-24T17:11:10Z
  - surface: log_line
    observable: "The newborn-lane case in the merged-sweep suite reports the lane as kept for being too young, and the run output contains no read-error text."
    authored_at: 2026-08-24T17:11:10Z

LANE_WRITES: plugins/leadv2/codex-lead/deny-extra.yaml, plugins/leadv2/codex-lead/tests/test-lv2guard.sh, plugins/leadv2/codex-lead/tests/test-repowise-launch.sh, plugins/leadv2/codex-lead/tests/test-codex-install.sh, plugins/leadv2/codex-lead/marketplace/plugins/leadv2/scripts/repowise-launch.sh, plugins/leadv2/hooks/leadv2-merged-worktree-sweep.sh, plugins/leadv2/scripts/tests/test-merged-sweep-orchestration-dirt.sh, plugins/leadv2/scripts/leadv2-fanout.sh, plugins/leadv2/scripts/leadv2-fanout-lane-launcher.sh, plugins/leadv2/scripts/tests/test-fanout-classify-guard.sh, plugins/leadv2/scripts/leadv2-burn-governor.sh, plugins/leadv2/scripts/tests/test-burn-governor.sh, plugins/leadv2/docs/worktree-sweepers.md

DELIVERABLE_COMPLETE
