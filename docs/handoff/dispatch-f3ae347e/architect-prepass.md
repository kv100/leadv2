# architect prepass — CLAUDE-PROFILE-SELECT-FINISH-01 (dispatch-f3ae347e)

Base: `main` @ 36e7080, read from the tree at `/Users/kostiantyn.vlasenko/Projects/leadv2`.
Authority: the LEAD RULING of 2026-08-25 adopts `docs/handoff/dispatch-16fbe872/architect-prepass.md`
with the C3-lean / I5-dropped amendment. This document is that design **re-verified against the
live tree**, plus the mechanism closure the earlier prepass did not do. Where the two differ, the
difference is called out under §0 and this document governs, because the difference is a fact read
out of the tree, not a re-litigation of the ruling.

---

## 0. What re-reading the tree changed (three corrections, all mechanical)

The ruling's substance stands untouched. Three statements in the adopted prepass are refuted by the
files as they exist at 36e7080; all three are in the *test/doc* layer, which is exactly the
"independent copy nobody named" the closure protocol exists to catch.

**X1 — appending `cred=` to the pick line is NOT backward-compatible with the test suite.**
The adopted prepass argued (line 78-80) that appending keeps consumers valid. True for
`claude-subsession.sh:605` (front-anchored `re_sel`) and for the `candidates=` sed scrape. **False
for `tests/test-claude-profile-select.sh`**, whose selector-stdout assertions are `$`-anchored on
`candidates=N`:

| test | line | pattern | breaks? |
|---|---|---|---|
| T4 | 105 | `^profile=alpha config_dir=.*/dir-alpha score=20 source=live reason=worst_window candidates=2$` | **yes** |
| T5 | 113 | `^profile=beta .*score=80 source=live reason=worst_window candidates=2$` | **yes** |
| T6 | 122 | `^profile=dead .*score=101 source=unknown reason=all_unknown candidates=2$` | **yes** |
| T7 | 136 | `^profile=alpha .*candidates=2$` | **yes** |
| T9a | 154 | `config_dir=.*/dir-` | no |
| T10 | 163 | `^profile=tie-a ` | no |
| T2/T3/T8 | — | `^profile=- reason=single_profile$` | no (fail-open line gains no `cred=`) |

C1 therefore *requires* updating T4/T5/T6/T7 in the same commit. Shipping C1 without it is a red
suite, not a review finding.

**X2 — the same anchoring breaks the subsession's own assertions, and the new-case ids collide.**
`I2b` (line 195) asserts `^\[claude-profile\] selected=alpha score=20 source=live candidates=2$` and
`I4` (line 199) asserts the ISO-prefixed handoff variant of that same `$`-anchored line. Extending
`line_log` with ` cred_kind=…` (C2) breaks both. Separately, the adopted prepass proposed new cases
numbered **I2..I6**, but `test-claude-profile-select.sh` **already uses I1..I9** for entirely
different assertions (I5 there is the handoff-log leak scan). The new cases must be numbered
**I10..I13** or the file gets two `I5`s and the ruling's "drop I5" instruction becomes ambiguous
against an existing, unrelated, passing test.

**X3 — `docs/model-routing.md` already has the section C5 asks to create.**
`docs/model-routing.md:112` is `## Claude multi-profile selection (CLAUDE-MULTIPROFILE-QUOTA-02,
opt-in)`. C5 amends that section; it does not add a second one.

Everything else in the adopted prepass — P1 (no cherry-pick; both commits are already ancestors of
`main`, and all three files are `git ls-files`-tracked at 36e7080), P2 (no
`CLAUDE_CODE_CREDENTIALS_SERVICE` export), C1, C2, C4-minus-I5, C6, and every Non-goal — is
confirmed against the tree and carried forward unchanged.

---

## 1. CALLERS / CALLEES

### 1a. `leadv2-claude-profile-select.sh`
- **Callers (complete, whole repo excluding `.claude/worktrees/`):**
  - `plugins/leadv2/scripts/claude-subsession.sh:569` binds the path, `:591` runs it, `:622` invokes
    the wrapper. **This is the only production caller.**
  - `plugins/leadv2/scripts/tests/test-claude-profile-select.sh:16` (`SELECT_BIN`), driven by
    `run_select()` at `:66`.
  - `plugins/leadv2/scripts/tests/run-core-offline.sh:334` registers the suite.
  - No other script, workflow, hook, or skill references it. `codex-task.sh` and
    `leadv2-codex-session-runner.sh` are on the **codex** path and never touch it — the C6 bonus is
    the only thing this lane changes on that path.
- **Callees:** `python3 $PROBE` (`:150`, `:153` — default `leadv2-quota-read.py`, overridable);
  `python3 $PICK` (`:179` — `lib/leadv2-claude-profile-pick.py`); `mktemp`, `date`, `base64`,
  `kill`, `wait`.

### 1b. `lib/leadv2-claude-profile-pick.py`
- **Callers:** `leadv2-claude-profile-select.sh:179` (production) and
  `tests/test-claude-profile-select.sh:17` (`PICK_BIN`, unit-driven). Nothing else.
- **Callees:** stdlib only (`base64`, `json`, `sys`). No env, no fs, no network — this is what makes
  T10 hermetic and must stay true.

### 1c. `claude-subsession.sh :: leadv2_select_claude_profile`
- **Caller:** `claude-subsession.sh:622`, one unconditional call at file scope, deliberately placed
  **before** the `CLAUDE_ARGS` build at `:625` so both launch sites (the `--wait` foreground `claude`
  and the `setsid` background arm) inherit the exported env. Confirmed by comment `:560-561`.
- **Callees:** `bash $_CLAUDE_PROFILE_SELECT` (`:591`), `mktemp`, `head -1`, `sed`, `date`.
- **Downstream of the export:** everything in the spawned `claude` process tree. That includes any
  in-lane `leadv2-quota-read.py` / `leadv2-provider-quota-gate.sh anthropic` run, which is the
  consumer that makes the new `LEADV2_ANTHROPIC_ACTIVE_SERVICE` export meaningful (see 1d).

### 1d. `LEADV2_ANTHROPIC_ACTIVE_SERVICE` — who reads it (this is the whole justification for C2)
- `leadv2-quota-read.py:413-414` (`resolve_active_account`): `requested = os.environ.get(
  "LEADV2_ANTHROPIC_ACTIVE_SERVICE") or os.environ.get("CLAUDE_CODE_CREDENTIALS_SERVICE")` — picks
  the matching account and returns provenance `session_credential`.
- `leadv2-quota-read.py:444-451` (`read_anthropic`): when set and no `--credential-file`, the source
  list collapses to **that one service** instead of enumerating every `Claude Code-credentials*`
  entry (`:453`).
- `leadv2-claude-profile-select.sh:149` already sets it per-probe.
- **Nothing else in the repo reads it.** Note that `:414` treats
  `CLAUDE_CODE_CREDENTIALS_SERVICE` purely as an alias *we* accept — it is not evidence the CLI
  emits it. P2 stands.

### 1e. `lib/leadv2-codex-quota-gate.sh :: codex_spawn_gate` (C6 bonus)
- **Callers:** `leadv2-codex-session-runner.sh:502` (`if ! codex_spawn_gate exec >> "$LOGF" 2>&1`),
  `codex-task.sh:346` (`codex_spawn_gate "$SUB" || exit "$?"`). Both call it in a
  `set -e`-suspending context (`if !` / `||`), so the bare child invocation at `:78` cannot abort a
  caller — worth stating because the WARN branch must not change that.
- **Callee under discussion:** `${_CODEX_QG_DIR}/../leadv2-provider-quota-gate.sh codex <purpose>`
  at `:78`, exec'd **directly**, so the exec bit is load-bearing (comment `:75-77`).
- **Tests:** `tests/test-codex-quota-guardrails.sh:129,144,159,280,295,395` and
  `tests/test-codex-quota-gate.sh` drive it. `a4c` (`guardrails:151-161`) asserts rc 2 +
  `reason=threshold` on stderr; **no test asserts stderr is empty**, so adding a WARN line to
  non-{0,1} rcs cannot break an existing case. Verified by grep for empty-stderr assertions across
  both suites: none.

---

## 2. STATES AND RETURN CODES

### 2a. `leadv2-claude-profile-select.sh` — every terminal state (rc is always 0)
The script's rc carries no information; the **stdout line** is the channel. Consequence column is
what a human ends up experiencing.

| # | state | site | stdout | consumer action | user-visible consequence |
|---|---|---|---|---|---|
| S1 | flag unset / ≠1 | `:48` | *(nothing)* | wrapper already returned at `:575` | lane spawns on the inherited account exactly as pre-feature; no `[claude-profile]` line anywhere |
| S2 | registry unreadable/absent | `:68` | `profile=- reason=single_profile` | `re_sel` fails → `:617` | stderr `[claude-profile] single-profile fallback`; lane uses inherited account |
| S3 | line malformed (label charset, missing/relative/unreadable config_dir, bad cred) | `:74-100` | line skipped, run continues | — | one `WARN: registry line N skipped: …` per bad line on the **selector's** stderr, which `:591` discards in production; only tests see it |
| S4 | duplicate label | `:101-108` | first wins | — | same as S3 |
| S5 | < 2 valid entries | `:115` | `single_profile` | `:617` | fallback line; lane unchanged |
| S6 | probe or pick script unreadable | `:116-117` | `single_profile` | `:617` | fallback line |
| S7 | `mktemp` for `recs` fails | `:127` | `single_profile` | `:617` | fallback line |
| S8 | one probe rc≠0 or empty stdout (incl. rc 124 kill at `:159`) | `:164-166` | record scores `-` → `UNKNOWN`=101 | — | that profile is simply never picked unless all are unknown |
| S9 | budget exhausted before profile i | `:135-138` | remaining entries score `-` | — | `WARN: profile probe budget exhausted` (discarded in prod); pick runs on whoever completed |
| S10 | **zero** probes completed | `:175-178` | `single_profile` | `:617` | fallback line — deliberately not a blind all-unknown pin |
| S11 | pick exits non-zero or prints nothing | `:179`, `:181` | `single_profile` | `:617` | fallback line |
| S12 | pick prints `profile=- reason=single_profile` (its own `:72` no-records path) | `:182` | that line | `re_sel` fails on `profile=-` | fallback line |
| S13 | **all records unknown** | pick `:77` | `profile=<first> … score=101 source=unknown reason=all_unknown candidates=N` **+ (new) `cred=…`** | `re_sel` matches (`source=unknown` is in the alternation at `:605`) → dir is pinned | lane runs on the first registry entry with zero quota evidence; `[claude-profile] selected=<label> score=101 source=unknown …` names it |
| S14 | normal win | pick `:78` | `… reason=worst_window …` **+ (new) `cred=…`** | pin | `[claude-profile] selected=<label> score=N source=live candidates=M cred_kind=<k>` |

**S13 is the state most worth reading twice**: `source=unknown` is an accepted match, not a
fallback. That is intentional (registry-order determinism beats a coin flip) and this lane does not
change it — but it means "a profile was pinned" never implies "quota was actually measured".

### 2b. `leadv2_select_claude_profile` (claude-subsession.sh) — return is always 0

| branch | condition | exports | log |
|---|---|---|---|
| B1 | flag ≠ 1 (`:575`) | none | none |
| B2 | `re_sel` matched **and** `[[ -d dir && -r dir ]]` (`:606`) | `CLAUDE_CONFIG_DIR` (`:611`); **(new)** `LEADV2_ANTHROPIC_ACTIVE_SERVICE` when `cred=keychain:*` | `:612` stderr + `:613` handoff |
| B3 | anything else (`:616-619`) | none | `single-profile fallback` |

Note B2's second condition: a pick line naming a directory that vanished between probe and spawn
falls to B3. Good; unchanged.

### 2c. `codex_spawn_gate` — rc of the child at `:78` and what happens to it (C6)
`leadv2-provider-quota-gate.sh` returns **0, 1, or 3** by its own code (`:14,15,21` → 3; `:97,102` →
1; every fail-open → 0), plus the shell-level 126/127.

| child rc | origin | today | after C6 | user-visible consequence |
|---|---|---|---|---|
| 0 | pass or any documented fail-open | `return 0` | unchanged | dispatch proceeds |
| 1 | over ceiling (`:97`,`:102`) | `:80-83` → rc 2 | unchanged | `CODEX_REFUSED_QUOTA reason=threshold`; router moves to the next candidate |
| 3 | bad provider/purpose/ceiling-lookup arg | falls through to `return 0` **silently** | **WARN + still 0** | today: the operator sees a clean dispatch and never learns check 3 was skipped |
| 126 | file exists, exec bit lost | falls through to `return 0` **silently** | **WARN + still 0** | same; this is the documented-but-untested hole the bonus targets |
| 127 | file missing / bad interpreter | falls through to `return 0` **silently** | **WARN + still 0** | same |

Terminal trace for 126: `codex_spawn_gate` → 0 → `session-runner.sh:502` `if !` is false → `codex
exec` launches → **a codex spawn happens with no quota check and no line anywhere saying so.** That
is the plain-words consequence, and it is why WARN (not fail-closed) is the right minimum: the
behaviour is unchanged, the silence is not.

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at each boundary. "Blast radius" is the closure question: does a
bad value take down more than the one thing it belongs to?

### `LEADV2_CLAUDE_MULTIPROFILE`
| case | behaviour | blast radius |
|---|---|---|
| absent / empty | `:48` exit 0, `:575` return 0 — fully inert | none |
| `0`, `true`, `yes`, `1 ` (trailing space) | **not** `1` → inert (string equality, `:48`) | none — a typo disables, never misfires |
| `1` | active | scoped to this spawn |

### `LEADV2_CLAUDE_PROFILES_FILE` (default `~/.claude/state/leadv2/claude-profiles.tsv`)
| case | behaviour |
|---|---|
| absent | default path used; if that path does not exist → `-r` fails → `single_profile` |
| empty string | `-r ""` fails → `single_profile` |
| file empty / all comments | 0 entries → `n>=2` fails → `single_profile` |
| 1 valid entry | `single_profile` (T3) |
| max: no cap on entry count | each entry costs one probe **inside one shared budget**; a 50-entry registry does not stall the spawn, it degrades to "later entries score unknown" (S9). Correct: bounded, not truncated |
| malformed lines | skipped individually with a WARN (S3); a registry that is 90% garbage still works if 2 good lines remain |
| entirely malformed | 0 entries → `single_profile` |
| binary / no tabs | every line fails `re_label` or the missing-`config_dir` check → skipped → `single_profile` |
| **not committed to any repo** | by contract (`select.sh:5-6`); C5 restates this for external consumers |

### Registry columns
| column | absent | empty | malformed | over-cap |
|---|---|---|---|---|
| `label` | line is blank → `continue` (`:72`) | same | charset/length reject `:74`, `@`/`.` hard-rejected so an email cannot become a label | >32 chars → reject |
| `config_dir` | `:78` reject | `:78` reject | relative → `:82-85` reject; missing/unreadable dir → `:86-89` reject | n/a |
| `credential_source` | defaults to `file:<config_dir>/.credentials.json` (`:90`) | same as absent | anything not `keychain:?*` / `file:/*` → `:96-99` reject | n/a |

### `LEADV2_CLAUDE_PROFILE_TIMEOUT`
| case | behaviour |
|---|---|
| absent | 12s total |
| non-integer / negative / `12s` | WARN, default 12 (`:54-57`); wrapper independently re-clamps (`:580`) |
| `0` | clamped to 1 (`:58`) |
| `999` | clamped to 60 (`:59`) |
| — | wrapper budget is `clamp(t)+5` (`:583`), so the wrapper always outlives the selector. **A bad value can never stall a spawn — this is the QUOTA-GATE-PARITY-01 F4 pattern and it is correctly applied twice.** |

### `LEADV2_QUOTA_CACHE_DIR`
| case | behaviour |
|---|---|
| absent | `~/.claude/state/leadv2/quota-cache` |
| set | per-profile subdir `…/profile-<label>` (`:148`,`:152`) — one profile's corrupt cache cannot reach another's. Probes run `--no-cache` anyway |

### `LEADV2_ANTHROPIC_ACTIVE_SERVICE` — **the boundary this lane adds**
| case | behaviour |
|---|---|
| inherited from the parent shell, `file:` winner | **today: leaks into the child and re-points its quota reads at an unrelated account.** After C2 the value is still not cleared — see the counterexample; the lane's answer is test I12 asserting the child does not see a stale pin for a `file:` winner, and the operator-visible `cred_kind=file` |
| exported by C2, `keychain:` winner | child's quota reads measure the selected account (`quota-read.py:444-451`) |
| service string contains whitespace/quotes | it came from a registry line that already passed `keychain:?*`; it is passed as a single `export` argument, never re-parsed by a shell, and **never logged** (label-only rule, `select.sh:13-17`) |
| absent | `quota-read.py:418` falls back to the bare `Claude Code-credentials` service — pre-feature behaviour |

### `cred=` field on the pick line (new)
| case | `claude-subsession.sh` behaviour |
|---|---|
| absent (old-shape line, e.g. a stale plugin copy) | sed scrape yields empty → `cred_kind=unknown` → export nothing → **still selects.** This is why C2 must use `sed`, not a widened `re_sel` |
| `keychain:<svc>` | export the pin, `cred_kind=keychain` |
| `file:/abs` | export nothing extra, `cred_kind=file` |
| garbage | `cred_kind=unknown`, export nothing, proceed |

---

## 4. COUNTEREXAMPLE — what still violates the invariant after every fix lands

The invariant this mechanism exists to protect: *the account whose quota was measured is the account
the spawned session burns.*

After C1–C6 land, **that invariant is still not enforced, and cannot be by this lane.** The selector
probes keychain service `S` (`select.sh:147-150`) and hands the child config home `D`
(`claude-subsession.sh:611`). The CLI derives its own keychain entry from `CLAUDE_CONFIG_DIR` — that
is the only lever the parent has (P2, and `CLAUDE_CODE_CREDENTIALS_SERVICE` is absent from the
installed binary per the adopted prepass's `strings` probe, which I did not re-run). Nothing on
either side exposes a comparable account identity: the probe payload's account objects carry
`service`, `entry_suffix`, `status`, pct fields and `account_label` (`quota-read.py:405,417,426`),
but `account_label` is derived from the keychain entry, not from whatever account `D` resolves to —
so comparing it proves nothing about `D`. Per the ruling, C3 ships as registry **self-consistency**
only (both columns present, service non-empty, config_dir readable — all of which
`select.sh:74-100` already enforces), and cross-account verification is **deferred**.

So the surviving hole, in plain words: **if an operator writes a registry row whose `config_dir` and
`credential_source` belong to different accounts, the lane will read account A's low quota, spawn on
account B, burn B, and print a green `selected=<label> score=12 source=live cred_kind=keychain`
line while doing it.** No test in this lane detects that, because no fixture can distinguish it from
a correct row. The mitigations that *do* land are honest but partial: `cred_kind=` on the log makes
the mode visible to a human reading the line, and C5 documents the feature as internal/advanced so
the only people writing registries are people who know the pairing is load-bearing.

Two smaller survivors, stated so they are not rediscovered in review:
1. **S13 (`all_unknown`)** pins a config home on zero quota evidence. Pre-existing, deliberate, out
   of scope — but it means the invariant is vacuous on that path.
2. **A stale `LEADV2_ANTHROPIC_ACTIVE_SERVICE` in the operator's own shell** re-points the child's
   quota reads even for a `file:` winner. I12 asserts the test-harness case; the lane does **not**
   add an `unset` in the `file:` branch, because unsetting a variable the operator deliberately
   exported is a behaviour change outside this lane. Flagged, not fixed.

**What I checked to say this:** every reader of `LEADV2_ANTHROPIC_ACTIVE_SERVICE` in the repo (§1d),
every field the probe emits (`quota-read.py:400-460`), every registry validation branch
(`select.sh:70-110`), and every consumer of the pick line (§1a-1c).

---

## 5. CHANGES — exact files and edits

### C1 — `plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py`
Append `cred=<credential_source>` as the **last** field of the `print` at `:78-79`, using
`record[2]` (already in hand). New shape:

```
profile=<label> config_dir=<path> score=<n> source=live|unknown reason=<r> candidates=<n> cred=<keychain:svc|file:/path>
```

Update the docstring at `:16-19`. The no-records line at `:72` (`profile=- reason=single_profile`)
gains **no** `cred=`. Module stays pure (no env/fs/network) — T10 depends on it.

### C2 — `plugins/leadv2/scripts/claude-subsession.sh` (`leadv2_select_claude_profile`)
Leave `re_sel` (`:605`) **byte-identical**. Scrape `cred` the way `candidates` is scraped at `:609`
(bash-3.2 safe, degrades to empty):

```sh
cred="$(printf '%s' "$sel" | sed -n 's/.*[[:space:]]cred=\([^[:space:]]*\).*/\1/p')"
```

Between `:611` and `:612`:

| `cred` | action | `cred_kind` |
|---|---|---|
| `keychain:<svc>` | `export LEADV2_ANTHROPIC_ACTIVE_SERVICE="${cred#keychain:}"` (consumer verified: `quota-read.py:413,444-451`) | `keychain` |
| `file:<abs>` | export nothing extra — `CLAUDE_CONFIG_DIR` already carries it | `file` |
| empty / unrecognised | export nothing | `unknown` |

Extend `line_log` (`:610`) with ` cred_kind=${cred_kind}`. Declare `cred` and `cred_kind` in the
`local` list at `:571`. **Label-only privacy rule binds**: log the kind, never the service or path.

### C3 — `plugins/leadv2/scripts/leadv2-claude-profile-select.sh` — LEAN, per the ruling
No new code path. The registry self-consistency the ruling names is already enforced at `:74-100`
(both columns present, `keychain:?*` requires a non-empty service, `config_dir` must be an absolute
readable directory). The change is a `# lean:` marker comment at that guard site recording that
**cross-account identity verification is deferred** and why (probe payload carries no identity
comparable to what `config_dir` resolves to). **No `reason=cred_mismatch`. No widening of the
`:617` fallback log line.** Inventing a mismatch path is explicitly forbidden by the ruling.

### C4 — `plugins/leadv2/scripts/tests/test-claude-profile-select.sh` (extend, do not rewrite)

*Repairs mandated by X1/X2 (not optional — the suite is red without them):*
- T4 `:105`, T5 `:113`, T6 `:122`, T7 `:136`: extend each pattern to accept the trailing
  ` cred=…` (either `… candidates=2 cred=file:[^ ]*$` or drop the `$` anchor; prefer the explicit
  form so the new field stays asserted).
- I2b `:195` and I4 `:199`: extend to `… candidates=2 cred_kind=file$`.
- Fake child at `:174-179`: also capture `LEADV2_ANTHROPIC_ACTIVE_SERVICE`, e.g. a second
  `printf 'LEADV2_ANTHROPIC_ACTIVE_SERVICE=%s\n' "${LEADV2_ANTHROPIC_ACTIVE_SERVICE:-<unset>}"`
  appended to `$I9_CAPTURE`.

*New cases — numbered **I10..I13** to avoid colliding with the existing I1..I9 (X2):*

| id | case | assertion |
|---|---|---|
| I10 | pick line carries `cred=` | selector stdout matches ` cred=keychain:` for a keychain-source registry |
| I11 | keychain winner ⇒ child pinned | capture file contains `LEADV2_ANTHROPIC_ACTIVE_SERVICE=<winning svc>` **and** `CLAUDE_CONFIG_DIR=<winning dir>`; stderr line ends `cred_kind=keychain` |
| I12 | `file:` winner ⇒ no stale pin | with `LEADV2_ANTHROPIC_ACTIVE_SERVICE` deliberately set in the harness env, capture file shows the child did not receive a pin attributable to the selector; stderr line ends `cred_kind=file` |
| I13 | old-shape pick line (no `cred=`) | still selects, `cred_kind=unknown`, **no** fallback. Drive it with a stub `PICK` (or a fixture selector stdout) that omits `cred=` — this is the regression that a widened `re_sel` would have caused |

The keychain fixture works hermetically: the probe is stubbed via `LEADV2_CLAUDE_PROFILE_PROBE`, so
a `keychain:<svc>` row only changes which env the stub is invoked with (`select.sh:147-150`); the
stub keys on the cache dir (`test:44-46`), not the service, so it returns the same canned payload.
No keychain is touched.

`I5` from the adopted prepass is **DROPPED** (ruling). T1..T3, T8..T10, I1, I3, I5..I9 unchanged.

### C5 — `docs/model-routing.md` — amend the **existing** section at `:112`
`## Claude multi-profile selection (CLAUDE-MULTIPROFILE-QUOTA-02, opt-in)` already exists (X3). Add
to it:
- an explicit **internal / advanced, opt-in** framing for external plugin consumers: the feature
  does nothing unless `LEADV2_CLAUDE_MULTIPROFILE=1` **and** a user-level registry with ≥2 valid
  entries exists; the registry lives outside any repo and is never committed;
- the fail-open inventory (the §2a table, condensed) as the evidence that a consumer with no
  registry is inert on every path;
- the **deferral record** required by the ruling: cross-account identity verification is not
  implemented, the registry's `config_dir`↔`credential_source` pairing is operator-trusted, and a
  mismatched row will silently burn the wrong account (§4).

### C6 — bonus: `plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh`
After `:84`, one branch covering every silent-pass rc (126 as mandated; 127 and 3 come free and are
the same defect — see §2c):

```sh
if [[ "$_gate_rc" -ne 0 && "$_gate_rc" -ne 1 ]]; then
  printf '[codex-task] WARN quota gate check skipped (rc=%s)\n' "$_gate_rc" >&2
fi
```

Behaviour unchanged: still `return 0`. **Do not make it fail-closed** — that is a behaviour change
outside this lane. Test in `plugins/leadv2/scripts/tests/test-codex-quota-gate.sh`: new case —
point `_CODEX_QG_DIR` at a fixture tree whose `leadv2-provider-quota-gate.sh` copy is `chmod 644`,
source the lib, call `codex_spawn_gate exec`, assert stderr matches `rc=126` **and** rc is 0. No
existing case in either codex suite asserts empty stderr (§1e), so this is additive.

---

## 6. Concurrency / race surface
- `claude-profile.log` (`claude-subsession.sh:613`) is append-only, one short line per spawn, and
  each spawn has its own `HANDOFF_DIR` — no cross-lane contention. Two spawns in the *same* task id
  can interleave appends; a single `printf` of a sub-PIPE_BUF line is atomic on macOS. No lock
  needed.
- Per-profile cache dirs (`…/profile-<label>`) isolate concurrent probes. Probes run `--no-cache`.
- `mktemp` is used for both `recs` and each probe's `out`; both are removed on every path
  (`:163`, `:176`, `:180`). A killed selector (wrapper timeout, `:595`) leaks one `recs` file into
  `$TMPDIR` — pre-existing, not worth a trap in this lane.
- The exports at `:611` and the new pin happen at file scope before `CLAUDE_ARGS` is built, so both
  launch sites see the same values. No ordering hazard introduced.

## 7. Constraint checklist
1. **Env naming:** `LEADV2_CLAUDE_MULTIPROFILE`, `LEADV2_CLAUDE_PROFILES_FILE`,
   `LEADV2_CLAUDE_PROFILE_PROBE`, `LEADV2_CLAUDE_PROFILE_TIMEOUT`, `LEADV2_QUOTA_CACHE_DIR`,
   `LEADV2_ANTHROPIC_ACTIVE_SERVICE` — all `LEADV2_*`. No new env var is introduced. ✔
2. **Paths:** every file in LANE_WRITES exists on disk at 36e7080 (verified). Nothing `(to-create)`. ✔
3. **`claude -p`:** this lane adds no `claude -p` invocation. The existing one
   (`claude-subsession.sh:625-637`) already carries `--max-turns` and `--permission-mode`; it uses
   `--output-format stream-json` (not `json`) by design, machine-parsed. Untouched. ✔
4. **Concurrent access:** §6. ✔
5. **Config contradiction:** `LEADV2_ANTHROPIC_ACTIVE_SERVICE` semantics after C2 ("the service the
   selector chose") match both existing readers (`quota-read.py:413`, `:444`) and the existing
   writer (`select.sh:149`). No contradiction. Recorded: `quota-read.py:414` accepts
   `CLAUDE_CODE_CREDENTIALS_SERVICE` as an alias; we neither set nor rely on it (P2). ✔

## 8. Non-goals (explicit — the implementer ignores all of these)
- No cherry-pick, no branch off `worktree-tmux-statusline`, no git-graph surgery. Both commits are
  already ancestors of `main`; all three files are tracked at 36e7080. (P1, ruling)
- No `CLAUDE_CODE_CREDENTIALS_SERVICE` export. (P2, ruling)
- No `CLAUDE_CODE_HOST_CREDS_FILE` export — unprobed semantics.
- No `reason=cred_mismatch`, no cross-account identity check, no test I5. (ruling)
- No change to `leadv2-quota-read.py` — scoring, probe shape, `--credential-file` all untouched.
- No registry schema change (columns stay `label / config_dir / credential_source`).
- No change to rc-126 *behaviour* — WARN only, still passes.
- No `unset LEADV2_ANTHROPIC_ACTIVE_SERVICE` in the `file:` branch (§4 survivor 2).
- No change to the `all_unknown` pin policy (§4 survivor 1).
- No tmux-statusline / pulse-hook work; no unrelated files from the other branch.
- No writes under `docs/leadv2/` or `docs/handoff/`.

## 9. Risks
| risk | mitigation |
|---|---|
| Widening `re_sel` would silently send every lane to single-profile | C2 scrapes with `sed`; `re_sel` stays byte-identical; I13 is the regression test |
| Suite goes red on the `$`-anchored patterns | X1/X2 make the T4/T5/T6/T7 + I2b/I4 repairs part of C1/C2, not follow-up |
| New test ids collide with existing I1..I9 | new cases numbered I10..I13 |
| CLI version drift changes keychain derivation | design contracts with the CLI only via `CLAUDE_CONFIG_DIR` |
| Service string leaking into a log or handoff | `cred_kind=` only; existing leak scans (T9b/T9c, I5, I6) stay green because `keychain`/`file`/`unknown` contain no `/`, `@`, or `sk-ant` |
| C6 WARN breaks a codex test asserting clean stderr | none exists (§1e, grepped) |
| Operator writes a mismatched registry row | **unmitigated by design** — §4; visibility via `cred_kind=` + the C5 deferral record |

## 10. acceptance

```yaml
acceptance:
  authored_at: 2026-08-25T09:47:00Z
  items:
    - id: A1
      surface: log_line
      observable: >
        In a dispatch's docs/handoff/<task>/claude-profile.log, the operator reads a selection
        line that now ends with a credential-kind word — e.g. "[claude-profile] selected=alpha
        score=12 source=live candidates=2 cred_kind=keychain" — where today the same line stops
        after the candidate count, and the kind word is "keychain", "file", or "unknown" and is
        never a service name or a path.
    - id: A2
      surface: log_line
      observable: >
        When the quota gate has lost its executable bit, a codex dispatch's log shows a line
        reading "[codex-task] WARN quota gate check skipped (rc=126)"; today that same situation
        produces no line at all and the operator sees a clean dispatch with no hint that the
        quota check never ran.
    - id: A3
      surface: rendered_line
      observable: >
        The existing "Claude multi-profile selection" section of docs/model-routing.md renders
        text telling a plugin consumer that the feature does nothing unless
        LEADV2_CLAUDE_MULTIPROFILE=1 is set and a user-level registry with two or more valid
        entries exists outside the repo.
    - id: A4
      surface: rendered_line
      observable: >
        That same docs/model-routing.md section renders a stated limitation: that the registry's
        pairing of config directory to credential source is trusted as written, that no check
        confirms the two name the same account, and that a mismatched row will spend the wrong
        account's quota without any warning.
    - id: A5
      surface: file_artifact
      observable: >
        The environment-capture file written by the test harness's fake child names the winning
        profile's keychain service, so a reader can see for themselves which account the spawned
        session was pointed at; before this change that file records only the config directory.
```

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py, plugins/leadv2/scripts/claude-subsession.sh, plugins/leadv2/scripts/leadv2-claude-profile-select.sh, plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh, plugins/leadv2/scripts/tests/test-claude-profile-select.sh, plugins/leadv2/scripts/tests/test-codex-quota-gate.sh, docs/model-routing.md

DELIVERABLE_COMPLETE
