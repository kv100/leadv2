# architect — CLAUDE-PROFILE-SELECT-FINISH-01 (prepass, terse)

## 0. Two mission premises are refuted by evidence — read before planning the lane

### P1. Task 1 (cherry-pick) is already done. Drop it.

```
$ git merge-base --is-ancestor 8d00999 main && echo YES   -> YES
$ git merge-base --is-ancestor 747c1ad main && echo YES   -> YES
$ git log --oneline -1 main                               -> b5ea9f8
```

Both selector commits are ancestors of `main` at b5ea9f8; the working tree already
contains `leadv2-claude-profile-select.sh`, `lib/leadv2-claude-profile-pick.py`, the
`leadv2-quota-read.py` changes and the `claude-subsession.sh` wiring. There is nothing to
cherry-pick and no lane branch to cut from `worktree-tmux-statusline`. **Non-goal: any
git-graph surgery.** The lane is a normal branch off `main`.

### P2. `CLAUDE_CODE_CREDENTIALS_SERVICE` is NOT honored by the Claude CLI. Do not export it.

Probe against the installed binary (`~/.local/share/claude/versions/2.1.245`, Mach-O arm64,
376 MB, the version this host runs):

```
$ strings -a 2.1.245 | grep -c CLAUDE_CODE_CREDENTIALS_SERVICE   -> 0
$ strings -a 2.1.245 | grep -c CLAUDE_CONFIG_DIR                 -> 53
$ strings -a 2.1.245 | grep -o "CLAUDE_CODE_[A-Z_]*" | grep -i cred
   CLAUDE_CODE_FORCE_WINDOWS_CREDMAN
   CLAUDE_CODE_HOST_CREDS_FILE
   CLAUDE_CODE_SKIP_AWS_CRED_CACHE
```

`leadv2-quota-read.py:413-414` reads `CLAUDE_CODE_CREDENTIALS_SERVICE` only as a *fallback
name for our own pin*; it is not evidence the CLI emits or consumes it. Exporting it before
spawn would be a pure no-op — the exact failure mode the mission is trying to close.

**How the CLI actually separates profiles** (evidence, this host's login keychain):

```
$ security dump-keychain | grep -o '"svce"<blob>="Claude Code[^"]*"' | sort -u
  "Claude Code-credentials"
  "Claude Code-credentials-47fc2659"
  "Claude Code-credentials-5a3c2328"
  "Claude Code-credentials-eb6c5b97"
$ strings -a 2.1.245 | grep -c "\.credentials\.json"             -> 2
```

Default (`~/.claude`) has the bare service; three alternate config homes each have a
`-<8 hex>` suffixed service. **UNVERIFIED (derivation not read out of the compiled bundle):
the suffix is a hash of the config home, i.e. the CLI derives its keychain service from
`CLAUDE_CONFIG_DIR` with no env override.** The consequence holds either way and is what
the design must be built on: *there is no env var by which the parent can pin the spawned
`claude`'s keychain entry.* `CLAUDE_CONFIG_DIR` is the only lever, and it is already
exported at `claude-subsession.sh:611`.

### Therefore the real critical gap is not "an export is missing"

`credential_source` is dropped between `pick.py:78` and `claude-subsession.sh:605` — that
part of the review finding is correct (pick.py's `print` at line 78-79 emits
`profile/config_dir/score/source/reason/candidates` and never `cred`; the record's
`cred` field is bound at `score_record()` line 35 and discarded). But the *harm* is not a
missing child env var. The harm is **unverified account identity**: the selector scores a
profile by probing keychain service `S` (`select.sh:147-150`, pinned via
`LEADV2_ANTHROPIC_ACTIVE_SERVICE`), then hands the child a `config_dir` `D`, and **nothing
anywhere asserts that `S` is the service the CLI will resolve from `D`**. A registry whose
`config_dir` and `credential_source` columns point at different accounts makes the lane
pick account A's low quota and burn account B — silently, with a green log line.

So: thread `credential_source` through (cheap, needed for any of this), export the pin the
things that *do* read it will honor, and add the mismatch guard that is the actual fix.

---

## 1. Changes

### C1 — `plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py`
Append `cred=<credential_source>` as the **last** field of the single stdout line
(after `candidates=`). Appending keeps `claude-subsession.sh:605`'s front-anchored
`re_sel` and the `candidates=` sed scrape valid unchanged — an old consumer against a new
pick line still parses. `record[2]` is already in hand at line 78.

New line shape:
```
profile=<label> config_dir=<path> score=<n> source=live|unknown reason=<r> candidates=<n> cred=<keychain:svc|file:/path>
```
Update the module docstring (lines 16-19) to match. The `profile=- reason=single_profile`
line (line 72) is unchanged — no `cred=` on the fail-open line.

### C2 — `plugins/leadv2/scripts/claude-subsession.sh` (`leadv2_select_claude_profile`)
Do **not** widen `re_sel`. Scrape `cred` the same bash-3.2-safe way `candidates` is
scraped at line 609, so a pick line without `cred=` degrades to empty rather than dropping
the whole match to the single-profile fallback:

```
cred="$(printf '%s' "$sel" | sed -n 's/.*[[:space:]]cred=\([^[:space:]]*\).*/\1/p')"
```

Then, between line 611 (`export CLAUDE_CONFIG_DIR`) and line 612 (the stderr line):

| `cred` | action |
|---|---|
| `keychain:<svc>` | `export LEADV2_ANTHROPIC_ACTIVE_SERVICE="<svc>"` — verified in-repo consumer: `leadv2-quota-read.py:413,444-451` pins exactly this service, so the child's own quota gate / in-lane quota reads now measure the profile that was selected instead of re-scanning every `Claude Code-credentials*` entry (`quota-read.py:453`). `cred_kind=keychain`. |
| `file:<abs path>` | export nothing extra; `CLAUDE_CONFIG_DIR` already carries it (the CLI reads `<config_dir>/.credentials.json`). `cred_kind=file`. **Do not** export `CLAUDE_CODE_HOST_CREDS_FILE` — it exists in the binary but its semantics are unprobed; out of scope. |
| empty / unrecognised | export nothing; `cred_kind=unknown`; still proceed (fail-open). |

Extend `line_log` (line 610) with ` cred_kind=${cred_kind}`. **Label-only privacy rule
still binds** (`select.sh:13-17`): log the *kind*, never the service string or path.

### C3 — `plugins/leadv2/scripts/leadv2-claude-profile-select.sh` — mismatch guard (the fix)
After the winner is chosen (i.e. after line 179, before the `printf` at 182), for a
`keychain:` winner assert the probed account identity is the one that config_dir would
resolve to. Implementation note for the developer — resolve this at build time, one probe,
in this preference order and stop at the first that exists:

1. The probe payload's active account already carries an identity field (email / account
   label / uuid) — `leadv2-quota-read.py` emits accounts with a `status` and pct fields;
   check whether it also emits an identity field. If yes: compare against the identity
   recorded under `<config_dir>` (`.claude.json` / config home account record).
2. If neither side exposes a comparable identity, **do not invent one.** Ship the guard as
   a *registry self-consistency* check only (both columns present, service non-empty,
   config_dir readable — already at 86-100) and record in the deliverable that
   cross-account verification is deferred, with a `# lean:` marker at the guard site.

On mismatch: `warn` + `single_profile` (fail-open, never a wrong-account spawn). Emit the
reason on the fail-open line so the operator can see *why*:
`printf 'profile=- reason=cred_mismatch\n'` — and correspondingly widen
`claude-subsession.sh`'s fallback log line to carry `reason=` when the pick line supplies
one (today line 617-619 is a bare `single-profile fallback`).

### C4 — `plugins/leadv2/scripts/tests/test-claude-profile-select.sh` (extend, do not rewrite)
Existing I1 (line 193) asserts only `CLAUDE_CONFIG_DIR`; the fake-child capture harness at
lines 179-193 is reused verbatim — just widen what it dumps:

| id | case | assertion |
|---|---|---|
| I2 | pick line carries `cred=` | stdout of the selector matches ` cred=keychain:` for a keychain winner |
| I3 | keychain winner ⇒ child is pinned | capture file contains `LEADV2_ANTHROPIC_ACTIVE_SERVICE=<winning svc>` **and** `CLAUDE_CONFIG_DIR=<winning dir>` |
| I4 | file: winner ⇒ no stale pin | capture file contains `LEADV2_ANTHROPIC_ACTIVE_SERVICE=<unset>` (guards a leaked pin from the parent env, which would silently re-point the child's quota reads) |
| I5 | cred mismatch ⇒ fail-open | selector prints `reason=cred_mismatch`, child sees `CLAUDE_CONFIG_DIR=<unset>` |
| I6 | old-shape pick line (no `cred=`) | still selects; `cred_kind=unknown`; no fallback |

I7 (line 216) and T1..T10 stay as they are. If C3 lands as the lean self-consistency form,
I5's fixture is a registry line with an empty/garbage service, not a cross-account fixture.

### C5 — external-consumer safety (founder requirement) — audit + document, no code
Fail-open chain is already complete; the lane's job is to *confirm on the record*, not to
add anything. Verified sites:

| condition | site | outcome |
|---|---|---|
| flag unset / != 1 | `select.sh:48`, `claude-subsession.sh:575` | exit 0, silence, `CLAUDE_CONFIG_DIR` untouched |
| registry missing/unreadable | `select.sh:68` | `single_profile` |
| malformed line (label charset, missing/relative/unreadable config_dir, bad cred) | `select.sh:74-100` | line skipped + WARN, run continues |
| < 2 valid entries | `select.sh:115` | `single_profile` |
| probe or pick script missing | `select.sh:116-117` | `single_profile` |
| every probe hung/crashed | `select.sh:175-178` | `single_profile` |
| pick produced nothing / unparseable / unreadable dir | `select.sh:181`, `claude-subsession.sh:606,616` | single-profile fallback |
| selector wedged | `claude-subsession.sh:576-598` (clamped budget + kill) | fallback |

Conclusion: **a plugin consumer with no registry is inert on every path.** Add one section
to `docs/model-routing.md` (the doc 8d00999 already extended) titled *Multi-profile Claude
selection — internal / advanced, opt-in*, stating: requires `LEADV2_CLAUDE_MULTIPROFILE=1`
**and** a user-level registry with ≥2 valid entries; the registry lives outside any repo
and is never committed; without both the feature is a no-op.

### C6 — bonus: rc-126 fail-open is real and untested
`plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh:75-86` — the comment at 75-77 states
the exec bit is load-bearing and that rc 126 is treated as pass ("tests/a4c guards it");
the only branch is `-eq 1` at line 80, so **126 falls through to `return 0` with no output
at all**, and no test named for it exists. Add, at line 84:

```
if [[ "$_gate_rc" -eq 126 ]]; then
  printf '[codex-task] WARN quota gate not executable (rc=126) — quota check skipped\n' >&2
fi
```
(WARN only — do not change it to fail-closed; that is a behaviour change outside this
lane's scope.) Test: `plugins/leadv2/scripts/tests/test-codex-quota-gate.sh`, new case —
`chmod 644` a fixture copy of `leadv2-provider-quota-gate.sh`, invoke the lib gate, assert
stderr matches `rc=126` and rc is still 0.

---

## 2. Non-goals (explicit)
- No cherry-pick, no lane branch off `worktree-tmux-statusline`, no touching that branch.
- No `CLAUDE_CODE_CREDENTIALS_SERVICE` export anywhere (refuted above).
- No `CLAUDE_CODE_HOST_CREDS_FILE` export (unprobed semantics).
- No change to `leadv2-quota-read.py` scoring, probe shape, or `--credential-file`.
- No registry schema change (columns stay `label / config_dir / credential_source`).
- No change to rc-126 *behaviour* (WARN only, still passes).
- No tmux-statusline / pulse-hook work; no unrelated uncommitted files from the other branch.
- No writes under `docs/leadv2/` or `docs/handoff/` from the implementation.

## 3. Risks
| risk | mitigation |
|---|---|
| Widening `re_sel` breaks the anchored match and silently sends every lane to single-profile | C2 scrapes `cred` with `sed`, leaves `re_sel` byte-identical |
| CLI version drift (2.1.245 today) changes keychain derivation | design depends on no env-var contract with the CLI; only `CLAUDE_CONFIG_DIR`, which has 53 references and is the documented lever |
| Guard (C3) fails closed and kills dispatch | every guard path ends in `single_profile` + exit 0 |
| Service string leaking into the handoff log | `cred_kind=` only; the label-only rule at `select.sh:13-17` is restated in C2 |
| `LEADV2_ANTHROPIC_ACTIVE_SERVICE` inherited from the parent shell re-points a `file:` profile's child quota reads | I4 asserts it is unset for `file:` winners |

## 4. acceptance

```yaml
acceptance:
  authored_at: 2026-08-25T08:51:11Z
  items:
    - id: A1
      surface: log_line
      observable: >
        In a dispatch's docs/handoff/<task>/claude-profile.log, the operator reads a
        selection line that now ends with a credential-kind field — e.g.
        "[claude-profile] selected=alpha score=12 source=live candidates=2 cred_kind=keychain" —
        where today the same line stops after candidates=.
    - id: A2
      surface: log_line
      observable: >
        When the quota gate has lost its executable bit, a codex dispatch's stderr shows a
        line reading "[codex-task] WARN quota gate not executable (rc=126) — quota check
        skipped"; today that same situation produces no line at all and the operator sees a
        clean dispatch.
    - id: A3
      surface: rendered_line
      observable: >
        docs/model-routing.md renders a section headed "Multi-profile Claude selection —
        internal / advanced, opt-in" whose text tells a plugin consumer the feature does
        nothing unless LEADV2_CLAUDE_MULTIPROFILE=1 is set and a user-level registry with
        two or more valid entries exists outside the repo.
    - id: A4
      surface: log_line
      observable: >
        When the winning profile's credential_source does not match its config_dir, the
        claude-profile.log shows a fallback line carrying a reason —
        "[claude-profile] single-profile fallback reason=cred_mismatch" — instead of
        today's bare "single-profile fallback", and no profile is pinned for that spawn.
    - id: A5
      surface: file_artifact
      observable: >
        The env-capture file written by the test harness's fake child contains a line
        naming the winning profile's keychain service, so a reader can see for themselves
        which account the spawned session was pointed at; before this change the file
        records only the config directory.
```

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py, plugins/leadv2/scripts/claude-subsession.sh, plugins/leadv2/scripts/leadv2-claude-profile-select.sh, plugins/leadv2/scripts/lib/leadv2-codex-quota-gate.sh, plugins/leadv2/scripts/tests/test-claude-profile-select.sh, plugins/leadv2/scripts/tests/test-codex-quota-gate.sh, docs/model-routing.md

DELIVERABLE_COMPLETE
