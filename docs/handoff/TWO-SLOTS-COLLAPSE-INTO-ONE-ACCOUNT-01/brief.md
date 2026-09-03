# TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01 — implementation brief

Repo: `~/Projects/leadv2`. Design only; no code here. All facts below measured 2026-09-03 on this
machine, metadata only — no token value was read into any artifact.

## 1. Proven cause of the 9 events

**A slot's identity has two halves, both owned by the config dir, and only ONE operation writes
both coherently: an OAuth login performed while that dir is the active `CLAUDE_CONFIG_DIR`.**
Halves: `<dir>/.claude.json:oauthAccount` (email/accountUuid/org/tier) and keychain service
`Claude Code-credentials-<sha256(dir)[:8]>`. Hash verified exactly:
`sha256("/Users/kostiantyn.vlasenko/.claude")[:8]==eb6c5b97`,
`sha256("…/.claude-work")[:8]==5a3c2328`.

Timeline from `docs/handoff/*/claude-profile.log` (9 `same_account` lines, both directions):

| when (UTC) | personal slot derives | work slot derives | state |
|---|---|---|---|
| 08-25 11:49→15:38 (6 runs) | — (older log format) | — | healthy, 2 candidates |
| 08-28 02:09 / 02:24 | default probe: `max/…@mythical.games` | `team/…@mythical.games` | **personal dir already on the work account** |
| 08-28 09:44:41 | `team/…@mythical.games` | `team/…@mythical.games` | **COLLAPSED → work** |
| 08-29 02:37 → 08-30 | default probe: `max/vkk1008k@gmail.com` | `team/…@mythical.games` | healthy (but work skipped nightly) |
| **08-31 15:55:11** | selected, candidates=2, no warn | distinct | **healthy** |
| **08-31 16:31:49** | `max/vkk1008k@gmail.com` | `max/vkk1008k@gmail.com` | **COLLAPSED → personal, inside 36 min** |
| 08-31 17:23/17:59/18:10/19:28/20:16, 09-01 10:25/15:58 | same | same | collapsed |
| 09-03 today | uuid…6ab506 / gmail / max / `default_claude_max_20x` | uuid…502204 / Mythical / team / `default_claude_max_5x` | healthy |

**What changed between the dates: nothing in the tooling. A human logged in.** In each episode an
interactive login into account B ran while `CLAUDE_CONFIG_DIR` resolved to slot A's dir, moving A's
`.claude.json` *and* A's suffixed keychain record onto account B; a later re-login moved it back.
Direction is simply which dir was active at login time.

Four corroborating facts that kill the competing theories:

1. **Registry is innocent.** `~/.claude/state/leadv2/claude-profiles.tsv` mtime is
   `2026-08-25T13:37:42Z` — untouched across all 9 events. Nothing repointed the slots at the
   registry level.
2. **A keychain mix-up cannot do it.** `same_account` needs BOTH halves equal, and the email half
   comes only from `.claude.json`; the credential blob has no email key at all (live keys:
   `accessToken, expiresAt, rateLimitTier, refreshToken, refreshTokenExpiresAt, scopes,
   subscriptionType`). A duplicate/stale keychain read moves the `sub` half only.
3. **The 08-28 chimera proves the dir was rewritten.** The default probe printed
   `max/kostiantyn.vlasenko@mythical.games` — personal's *stale legacy* keychain `sub=max` merged
   with an email that could only have come from `~/.claude/.claude.json` holding the **work**
   account. Independent of any credential read.
4. **The act leaves no shell trace.** `~/.zsh_history` contains zero `CLAUDE_CONFIG_DIR`, `/login`
   or `setup-token` lines — `/login` is a slash command typed *inside* a running session. `.claude.json`
   mtime is also useless (rewritten continuously; today 20:12Z). This is precisely why the collapse
   is invisible today.

**Aggravating factor (PLAUSIBLE, not proven):** the sibling lane's false `default_token_expired`
warn fired 207 times, and its documented remedy is literally "run `claude /login` with
`CLAUDE_CONFIG_DIR` set". Both collapse episodes are preceded in the same log by that warn. A false
alarm whose runbook is the collapse-causing action is a cause multiplier. Do not claim causation
without a login receipt; do state the coupling.

## 2. Collapse made LOUD (it cannot be made impossible from here)

The write happens in the Claude CLI, outside this repo. So: refuse to lie about it, and put the
signal where an operator stands.

**2a. The selector stops continuing.** In `leadv2-claude-profile-select.sh`, when ≥2 registry slots
resolve to one real account, print `profile=- reason=same_account` on stdout and exit 0 instead of
proceeding to probe and pin a dir. Today it warns and continues, then emits
`selected=personal … candidates=2` — a line that *reads as healthy two-bucket operation* and is a
lie. `claude-subsession.sh:485`'s regex does not match `profile=-`, so the lane falls back to
single-profile and still runs: availability preserved, honesty restored. Purely additive;
`reason=all_expired` is untouched.

**2b. Persistent alarm file, not a handoff log.** `~/.claude/state/leadv2/claude-profile-alarm.json`
(env override `LEADV2_CLAUDE_ACCOUNT_ALARM_FILE`). Written atomically (`mktemp` + `mv`) on detect,
`rm -f` on a clean run. Contents: `kind`, `labels[]`, `account_uuid_tail`, `sub`, `detected_at`,
`remedy_dir`. **No email, no digest of a token, no values.** Grepping 94 handoff dirs is not a
surface; one well-known path is.

**2c. The surface an operator actually sees — a SessionStart banner.** New hook
`plugins/leadv2/hooks/leadv2-claude-account-alarm.sh` (to-create), registered in
`plugins/leadv2/hooks/hooks.json` under `SessionStart` using the existing wrapper idiom
(`rc<=2` pass-through, else append to `$LEADV2_DEGRADE_LOG` and `exit 0`). It emits a **nested**
`hookSpecificOutput.additionalContext` block — a top-level `additionalContext` is discarded and
would be a silent no-op. It does its own cheap check every session start: read
`oauthAccount.accountUuid` from each registry slot's `.claude.json` (2 file reads, no keychain, no
network, <50 ms) and compare. That makes the banner independent of whether any lane spawned, and it
works identically in a Linux container. Banner text names the two labels, the shared uuid tail, the
dir to re-login, and the check command from §3.

**2d. Identity keys on `accountUuid`, not on `<sub>/<email>`.** Email is display and can drift
(alias, case, org rename); `accountUuid` is the account. Use it for same-account detection and for
the quota-cache bucket key, falling back to today's `<sub>/<email>` comparison when the uuid is
unresolvable (`na` stays suppressed, as now). Keep `identity=<sub>/<email>` on stdout unchanged —
`claude-subsession.sh:485` parses it. Bucket-key change abandons existing cache dirs (one cold read
each, no migration) — same precedent as the M1 note in the script header.

**2e. Existing `same_account` warn goes email-free**, per the constraint: labels + `sub` + uuid tail
only. `tests/…/test-claude-profile-select.sh` T14 asserts the current string and must be updated in
the same commit.

## 3. The daily two-buckets check

**File (to-create):** `plugins/leadv2/scripts/leadv2-claude-account-check.sh`
**Invocation:** `bash ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-claude-account-check.sh`
(no args, no flags, no env required).

Compares **real account identity only** — never labels. Per registry slot:
`oauthAccount.accountUuid` (last 6), `organizationUuid` (last 6), `organizationRateLimitTier` /
`userRateLimitTier` (this is what shows 20x vs 5x after 09-15), `subscriptionType` from the
credential, and `sha256(raw credential blob)[:12]` as a **digest** proving the two slots hold
physically different credentials. Output shape, no values:

```
slot=personal dir_hash=eb6c5b97 account=..6ab506 org=..981b21 sub=max  tier=default_claude_max_20x cred=dd46d7125d81
slot=work     dir_hash=5a3c2328 account=..502204 org=..f6715f sub=team tier=default_claude_max_5x  cred=3e6bf028c640
VERDICT: TWO_BUCKETS accounts=2 creds=2
```

Exit codes: `0` TWO_BUCKETS · `1` ONE_BUCKET (prints `collapsed=[personal,work] account=..6ab506`)
· `2` INDETERMINATE (a slot's `.claude.json` unreadable). Digests are computed in `python3` (already
a hard dependency of `derive_identity`) — never `shasum`/`sha256sum`, which differ across the two
platforms.

**Linux container, no keychain:** guard every keychain read with `command -v "$SECURITY_BIN"`. With
no keychain the credential source falls back to `file:<dir>/.credentials.json`; if that is absent
too, `sub` and `cred` print `-` and the line reads
`VERDICT: TWO_BUCKETS accounts=2 creds=unavailable(no-keychain)`. **A missing keychain must never
produce exit 2** — `accountUuid` lives in `.claude.json`, is present on Linux, and is by itself a
sufficient discriminator. bash 3.2: parallel indexed arrays only, no associative arrays, no
`mapfile`, no `${var^^}` — mirror the selector's existing registry-parse loop.

**Cadence until 2026-09-15 and on the day:** §2c's SessionStart banner is the standing automatic
surface (every session start ≥ daily); this command is the on-demand confirmation. No new scheduler.

## 4. Negative control (mandatory)

Two mutations, **both inside a function body**, artifacts produced via the existing
`plugins/leadv2/scripts/leadv2-mutation-control.sh`.

**Precondition — extraction is part of the change.** The same-account detection is currently
top-level straight-line code (the `# --- same-account detection` block, after `done < "$REGISTRY"`),
exactly as the sibling brief found for the default-slot check. A line-number insert there lands at
file top level, makes every suite red for the wrong reason, and reads as a pass — that invalidated a
measurement on 2026-08-25. So the block moves into `detect_same_account()` first; that is a
precondition of this section, not cosmetics.

| # | target | mutation (inside the body) | suite that must go red |
|---|---|---|---|
| NC1 | `detect_same_account()` in the selector | make the account comparison always-unequal (`== "X${ACCOUNTS[$_sa_j]}"`) | `tests/nc-claude-account-collapse.sh` → `test-claude-profile-select.sh` T14 + the new refusal test |
| NC2 | `verdict()` in `leadv2-claude-account-check.sh` | force `TWO_BUCKETS` unconditionally | `test-claude-account-check.sh` collapse fixture |

Model NC1 on `plugins/leadv2/scripts/tests/nc-claude-profile-select.sh`, which already mutates
inside the `derive_identity` body and fails setup loudly when its pattern stops matching — keep that
`NC-SETUP-FAIL` guard.

**Proof format:** `baseline_rc=0`, `mutated_rc=<nonzero>`, **plus the literal red suite line copied
from the run** (e.g. `FAIL: T14 same_account fires when both slots resolve to one accountUuid`).
**Do NOT cite a `diff_hash` field** — a known open defect records the SHA-256 of the empty string
there, so it proves nothing.

**CI selection.** `test-claude-profile-select.sh` is registered at `run-core-offline.sh:423`, and
`run-core-offline.sh` is always-on in `tests/run-all.sh` regardless of scope — already selected, no
`EXTRA_SUITE_MAP` row needed. The **new** `test-claude-account-check.sh` is not in the core set and
must be added there in the same shape as `:423`. Note the trap: the stem convention would look for
`test-leadv2-claude-account-check.sh` while the suite is `test-claude-account-check.sh` — a stem
mismatch, so explicit registration is mandatory, not optional. Prove it with
`tests/run-all.sh --scope changed` and paste the selection line.

## 5. Hard constraints, seam with the sibling lane, and checklist

- **Ownership split — stated explicitly, as asked.** The **nightly single-profile fallback**
  (`:245-253` skip → `refuse_all_expired` `:283-285`) and the expiry predicate and `:159-178` belong
  to **CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01**, which is already dispatched. **This lane does not
  touch those lines and does not fix that fallback.** Neither lane may skip it on the assumption the
  other has it.
- **Shared surface = `derive_identity` (`:121-143`).** Both lanes extend its tuple. Seam: the
  sibling lands first; this lane rebases and **appends** at the end. Agreed final order:
  `<sub>\t<email>\t<expiresAt|->\t<refreshTokenExpiresAt|->\t<has_refresh>\t<cj_ok>\t<cred_ok>\t<account_uuid|->\t<org_uuid|->\t<cred_digest12>`.
  Keep the `-` sentinel convention (tab is IFS whitespace). The heredoc emits the digest, never the
  blob.
- **MUST NOT touch** `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (another lane).
- **MUST NEVER print or log** a credential value, access token or refresh token. Labels,
  `subscriptionType`, uuid tails, tier strings and digests only. The registry stays label-only.
- **MUST NOT** add to `tests/known-red-suites.txt` (`THIS LIST MAY ONLY SHRINK`), weaken any
  assertion, or commit to `main`.
- **Platforms:** macOS bash 3.2 and a Linux container — see §3 for the keychain-less path.

**Checklist run.** (1) Env: one new var, `LEADV2_CLAUDE_ACCOUNT_ALARM_FILE` — `LEADV2_` prefix,
matches the existing `LEADV2_CLAUDE_PROFILE_*` family; cross-checked `~/.claude/settings.json` env
block, which holds only `LEADV2_CLAUDE_MULTIPROFILE=1`; no `LEAD_V2_*` drift, no contradiction.
(2) Paths: verified on disk — selector, `claude-subsession.sh`, `plugins/leadv2/scripts/tests/`,
`nc-claude-profile-select.sh`, `run-core-offline.sh`, `tests/run-all.sh`, `tests/known-red-suites.txt`,
`plugins/leadv2/hooks/hooks.json`, the registry; everything else marked (to-create).
(3) `claude -p`: this change introduces none — N/A.
(4) **Concurrency:** the alarm file is written by every lane spawn, and WIP is 2 lanes with
unlimited sessions — two selectors can write and clear it simultaneously. Mitigation: atomic
`mktemp`+`mv` write, idempotent `rm -f` clear; worst case is a stale-by-one-run alarm, a false
POSITIVE costing one check run, which is the safe direction. The SessionStart hook's own file-only
check (§2c) does not read the alarm file, so a lost write never loses the signal.
(5) Config contradiction: no existing variable's semantics change.

## 6. Out of scope — ignore these

The expiry predicate / legacy unsuffixed keychain service (sibling lane) · preventing the login
itself, e.g. a wrapper that pins `CLAUDE_CONFIG_DIR` at login time (worth a follow-up row, not this
task) · quota scoring and `lib/leadv2-claude-profile-pick.py` · the orphan keychain service
`Claude Code-credentials-47fc2659` (team/max_5x, frozen 2026-08-25, no registry slot — noted, not
cleaned here) · SwiftBar/statusline surfacing · any change to `reason=all_expired` or to the
`profile=…` stdout grammar beyond adding the `reason=same_account` token.

DELIVERABLE_COMPLETE
