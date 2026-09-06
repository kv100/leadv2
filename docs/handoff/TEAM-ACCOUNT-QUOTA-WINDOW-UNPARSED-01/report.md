# TEAM-ACCOUNT-QUOTA-WINDOW-UNPARSED-01

Founder-visible: the second (Team) Claude account never receives work,
even though its own limits show 0% used and were raised until Sept 13.
Leadmain's original framing: `leadv2-claude-profile-select.sh` prints an
unparsed window (`work:-=-`) for it, and "unknown != unusable" — a
profile with an unparsed window loses the quota comparison forever.

Registry file (`~/.claude/state/leadv2/claude-profiles.tsv`) contents are
never referenced anywhere in this investigation or report — only the
profile labels `personal`/`work` are used, no tokens, no session paths.

## Measurement (live, not code-reading)

Ran the real selector: `profile=personal ... windows=personal:seven_day=29|work:-=-`,
plus stderr `WARN: registry line 2: expiresAt_stale label=work
identity=team/kostiantyn.vlasenko@mythical.games -- probing live anyway`.

That WARN already says the window is not statically refused — it's
*probed live anyway* and still comes back empty. Ran the underlying
`leadv2-quota-read.py anthropic --no-cache` probe directly for the work
profile (its keychain service name extracted into an unprinted shell
variable via `LEADV2_ANTHROPIC_ACTIVE_SERVICE`). Result: `status: unknown`,
`error: 'http 401'`, all quota sub-objects None, `tier:
default_claude_max_5x`, `subscription_type: team`.

## Diagnosis: NOT a parser bug

The original framing was wrong. This is a genuine `http 401` — the OAuth
credential for the work profile is expired. There is no window to parse;
authentication itself fails before any quota field is ever returned. Two
independent signals agree: the selector's own `expiresAt_stale` metadata
warning, and the live 401. Leadmain retracted the "unparsed window /
parser bug" framing on this finding and confirmed the double signal.

**This does not, by itself, restore the Team account to working order** —
that needs a credential re-login, which Leadmain owns escalating to the
founder separately, out of scope here.

## What was still worth fixing here

Independent of that credential's state, the *scoring contract* has a real
defect: any profile whose window can't be resolved for ANY reason (never
probed, malformed payload, or a confirmed live failure) scored a single
flat `UNKNOWN=101` sentinel — worse than every live-scored profile, even
one that is itself fully exhausted (pct=100). An idle, 0%-used account
that simply has not been probed yet can never win a comparison it should
trivially win.

## Fix

Split the single `UNKNOWN` sentinel into two tiers
(`lib/leadv2-claude-profile-pick.py`):
- `UNKNOWN_TRIABLE = 100` — an ordinary unknown (never probed, or a
  probe whose payload didn't parse). Competes fairly: loses only to a
  live profile with genuine free quota (pct < 100).
- `UNKNOWN_COOLING = 101` — reserved for a profile whose most recent
  live probe returned a CONFIRMED API error and is still inside its
  cooldown window. Strictly worse than everything.

`leadv2-claude-profile-select.sh` persists the cooldown across rounds via
a new marker file under the per-identity cache dir
(`${CACHE_BASE}/identity-<id>/probe-cooldown-until`):
- Post-probe: if the active/only account came back with `status != "ok"`
  AND a non-empty `error` field (a CONFIRMED failure, not "we never got
  a chance to try"), write `now + COOLDOWN_S` to the marker
  (`LEADV2_CLAUDE_PROFILE_COOLDOWN_S`, default 900s).
- Pre-probe: if the marker says still cooling, skip the live probe
  entirely and emit a `cooling=1` record instead.

The record format grew a 6th tab-separated field (`cooling`, `0`|`1`),
threaded from the bash orchestrator to the pure Python scorer — the
scorer itself remains env/filesystem/network-free per its own contract.

Mandatory pair control, both halves, per Leadmain's explicit instruction:
- **Half 1 (today's defect fixed)**: an unknown-scored profile is now
  selectable — it wins even a tie against a fully exhausted (100%) live
  profile (T24a).
- **Half 2 (no regression)**: unknown still loses to a live profile with
  real free quota (T24b) — the fix does not over-correct into "unknown
  always wins."
- **Cooldown enforcement**: a confirmed-failing profile is excluded on
  the very next round even when its (rewritten) fixture would otherwise
  score better than the live competitor that round (T25c/d) — proving
  the cooldown is *enforced*, not merely recorded. The first failing
  round itself still scores fairly (T25b) — never retroactively punished
  before a failure is even confirmed.

`test-claude-profile-select.sh`: 91/91 pass (T6/T13a updated from
`score=101` to `score=100` as an intentional contract change — documented
inline in the diffs).

## Mandatory negative control — TWO mutations (per Leadmain's instruction)

Selection-scoring and cooldown-persistence are independent decision
points (one lives in `pick.py`, one in `select.sh`) — a single mutation
would only prove one path's liveness. Both proven independently,
mutation strictly inside the changed function body:

1. **Scoring split** (`lib/leadv2-claude-profile-pick.py:85`): collapsed
   `unknown_score = UNKNOWN_COOLING if cooling else UNKNOWN_TRIABLE` back
   to the unconditional old-sentinel `unknown_score = UNKNOWN_COOLING`.
   RED exactly on T6: `score=101` instead of the expected `score=100` —
   the precise pre-fix symptom. Artifact:
   `20260906T155555Z-70507.txt`.
2. **Cooldown enforcement** (`leadv2-claude-profile-select.sh:408`):
   neutered the cooldown-check gate to `if false; then`. RED exactly on
   T25c/T25d: `flaky` is re-probed instead of skipped ("no match for
   ...cooling down..."), and the round falls back to `single_profile`
   instead of `steady` winning on live merit — the precise
   cooldown-bypass symptom. Manually re-verified against the mutant
   directly (not just the tool's summary line): PASS=66 FAIL=25, with
   T25c/T25d the actual failures. Artifact: `20260906T155738Z-51343.txt`.

GREEN on the committed code in both cases (mutated_rc=1, suite red, on
the unmutated tree the same suite is 91/91 green).

## Commits

`60048231` (fix + tests, leadv2 plugin repo, `main`). This report +
mutation-control artifacts next.

## Not done here

Credential re-login for the work/Team profile — Leadmain owns escalating
that to the founder. This fix makes the account *selectable* once its
credential is valid again; it cannot make an expired OAuth token work.
