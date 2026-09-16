# A-DEGRADED-PROFILE-SELECT-EXITS-ZERO-01

Founder order 2026-09-16 (item 3 of the balancer list). Standing rules:
`docs/handoff/MAIN-RED-SUITES-CENSUS-01/lane-rules.md`.

## Why this row exists

When the live quota read fails, `leadv2-claude-profile-select.sh` stops ranking and falls back to
"run on whatever account is already active" — and it reports that with **exit 0** and
`profile=- reason=single_profile`. The caller cannot distinguish that from a real ranked selection,
so a session can sit on one account indefinitely and nothing in the system says so.

This is the mechanism behind the 2026-09-16 incident: getmany hit the degraded path at 09:33:55Z and
this repo hit it at 09:34:58Z, about a minute apart — machine-wide, not repo-specific. Across 269
profile logs on this machine: 37 fallbacks against 66 live ranked selections.

The asymmetry that makes it invisible: `--requested-profile <label>` on a mismatch is a **hard
refusal** (`NO-WAY-TO-PIN-A-DISPATCH-TO-A-NAMED-ACCOUNT-01`, exit 5), loud and unmissable. The
unpinned degraded path is a silent exit 0. The loud behaviour exists; it just is not on the path
everyone actually uses.

## Measured, with its boundary stated

```
registry: personal + work; every live probe returns {"status":"unknown","accounts":[]}
exit code : 0
stdout    : profile=- reason=single_profile
stderr    : WARN ... identity_email_unresolved ... -- fail-open   (x2, one per label)
```

**Boundary — read this before you build.** The fixture degrades the selector through
`identity_email_unresolved` (no readable `.claude.json`). The live 09:33/09:34 incident degraded
through `degradation=stale_last_known`. Both end at the same silent exit 0, but this probe exercises
**one of at least two entrances**. Your first job is to enumerate the entrances to the fallback and
say how many you found — do not assume it is two. A fix that closes one entrance and leaves the other
open would still pass this probe, which is exactly the failure mode to avoid.

## Acceptance (red at dispatch, rc=1 measured 2026-09-16)

```
bash docs/handoff/A-DEGRADED-PROFILE-SELECT-EXITS-ZERO-01/probe.sh
```

Not in your write set. Do not edit it.

## What the fix must establish

1. A degraded selection is **distinguishable by the caller** from a ranked one. A stderr WARN is not
   enough — the caller already ignores it. Decide between a non-zero exit and a machine-readable
   marker on stdout, and justify the choice against what the callers actually do. Callers to check:
   `claude-subsession.sh` (`:588-600`) and `leadv2-dispatch-code.sh`'s `claude_profile` decision line.
2. Fail-open stays fail-open. This row must NOT make a degraded read block a dispatch — the founder
   has never asked for that, and a balancer that refuses work when a probe is flaky is worse than one
   that runs on the wrong account. Make it *visible*, not *fatal*.
3. Every entrance you enumerated in the boundary section above is covered, or the report names the
   ones that are not and why.
4. The `--requested-profile` hard-refusal path must keep working unchanged; it is the one loud path
   that exists today. `test-claude-profile-requested.sh` guards it — run it before and after.

## Controls

Paired: the probe above red before, green after. Plus one control per independent claim, and
`test-claude-profile-select.sh`, `test-claude-profile-requested.sh`,
`test-profile-select-skips-exhausted.sh`, `nc-claude-profile-select.sh` run with counts reported
before and after.

## Write set — FILES, never directories

```
plugins/leadv2/scripts/leadv2-claude-profile-select.sh
plugins/leadv2/scripts/tests/test-degraded-select-is-distinguishable-01.sh
docs/handoff/A-DEGRADED-PROFILE-SELECT-EXITS-ZERO-01/report.md
```

## Ordering constraint — this lane cannot start while another holds the file

`leadv2-claude-profile-select.sh` is in the declared write set of lane `2af7d13d`
(row `7ea4fed65451`, the account-picker fix). A live lane's write set cannot be widened and a second
lane cannot take the same file. This row waits for that lane to reach terminal. Ledger:
`SD-DEGRADED-SELECT-WAITS-FOR-THE-PICKER-LANE-01`.
