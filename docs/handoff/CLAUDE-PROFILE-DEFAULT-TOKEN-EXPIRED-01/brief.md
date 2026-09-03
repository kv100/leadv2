# CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01 — implementation brief

Repo: `~/Projects/leadv2`. Design only; no code here.

## 1. Verdict: the warn is a FALSE ALARM. Two independent defects, both confirmed live.

Measured 2026-09-03T17:03Z on this machine (`now_ms=1788455007334`), metadata only — no token
value was read into any artifact.

| keychain service | sub / tier | `expiresAt` | `refreshToken` | `refreshTokenExpiresAt` |
|---|---|---|---|---|
| `Claude Code-credentials` (unsuffixed) | max / max_20x | **2026-08-25T07:51Z — EXPIRED** | present | **2026-09-21T07:04Z — LIVE** |
| `Claude Code-credentials-eb6c5b97` | max / max_20x | 2026-09-03T22:26Z — live | present | 2026-09-25T22:41Z — live |
| `Claude Code-credentials-5a3c2328` | team / max_5x | 2026-09-04T00:55Z — live | present | 2026-09-30T02:02Z — live |
| `Claude Code-credentials-47fc2659` | team / max_5x | 2026-08-25T07:54Z — EXPIRED | present | 2026-09-23T06:25Z — live |
| `Claude Code-Account-{1,2}-<email>` x4 | legacy | expired 2026-02..04 | present | field ABSENT |

**Defect A — wrong record (dominant cause of the 207 warns).** `~/.claude/.credentials.json` does
not exist, so the selector falls through to the hardcoded `keychain:Claude Code-credentials`
(`leadv2-claude-profile-select.sh:169`). That service is a **legacy record frozen at
2026-08-25T07:51Z**. The CLI now writes per-config-dir services named
`Claude Code-credentials-<sha256(config_dir)[:8]>` — verified by hash, exact match on both:
`sha256("/Users/kostiantyn.vlasenko/.claude")[:8] == eb6c5b97` and
`sha256("/Users/kostiantyn.vlasenko/.claude-work")[:8] == 5a3c2328`.
The live record for the default slot is therefore `...-eb6c5b97`, whose `expiresAt` is **5.4 h in the
future**. The selector reads a corpse and reports on a slot it never looked at.
This also explains why the founder's re-login did not stop it: re-login rewrote the *suffixed*
record; nothing ever rewrites the unsuffixed one. (There are also **two** `Claude Code-credentials`
entries in the keychain — `security find-generic-password -s` returns an arbitrary one. Independent
reason never to key on that service.)

**Defect B — wrong predicate (residual, and the more dangerous one).** `claudeAiOauth.expiresAt` is
the **access-token** expiry, a ~8 h rolling value that is legitimately in the past whenever the CLI
has not been invoked since it lapsed. Liveness lives in a different pair the selector never reads:
`refreshToken` + `refreshTokenExpiresAt` (~3-week horizon). Even after Defect A is fixed, a healthy
`...-eb6c5b97` goes "expired" tonight at 22:26Z.

**Latent availability bug from the same predicate (higher severity than the warn).** The registry
path applies the identical raw-`expiresAt` test at `:245-253` and **skips the entry**, escalating to
`refuse_all_expired` at `:283-285`. Both registry slots' access tokens lapse tonight (22:26Z and
00:55Z). After 00:55Z, `n==0 && expired_count==2` -> `profile=- reason=all_expired` -> the caller's
regex at `claude-subsession.sh:480` does not match -> every lane silently reverts to single-profile.
Quota balancing across the two accounts stops working every night and nothing says so. Fixing the
warn without fixing this leaves the lying-green half in place.

## 2. Decision: (a) check refreshability — and fix service resolution. Not (b).

Demoting the warn (option b) would hide Defect A rather than correct it, and would leave `:245-253`
refusing selection nightly. The honest predicate:

```
slot_is_dead  <=>  refreshToken is empty/absent
               OR  (refreshTokenExpiresAt is a number AND <= now_ms)
```

Legacy records with **no** `refreshTokenExpiresAt` field but a present `refreshToken` (the four
`Account-N` entries) are NOT provably dead -> not dead, no warn. `expiresAt` in the past with a live
refresh window is normal steady state -> **silent, not even info**. A per-8-hour heartbeat nobody can
act on is exactly the channel-poisoning we are removing.

Rename the warn `default_token_expired` -> `default_token_unrefreshable`. The new name is required:
the old string is what 207 lines trained everyone to ignore, and greps and eyes must not match both.

**What an operator does when it fires:** run `claude /login` with `CLAUDE_CONFIG_DIR` set to the dir
named in the warn — the only remedy for a dead refresh token. That is the whole runbook; if it is not
that, the signal should not exist.

## 3. Changes (files, all under `plugins/leadv2/scripts/`)

**`leadv2-claude-profile-select.sh`**

1. New helper `keychain_service_for_dir <config_dir>` -> prints `Claude Code-credentials-<8hex>`,
   `<8hex> = sha256(config_dir)[:8]`. Compute in `python3` (already a hard dependency of
   `derive_identity`) — no `shasum` / `sha256sum`, no new dependency, bash-3.2 safe.
2. `derive_identity` (`:121-143`) — extend its stdout tuple to
   `<sub>\t<email>\t<expiresAt|->\t<refreshTokenExpiresAt|->\t<has_refresh:0|1>\t<cj_ok>\t<cred_ok>`.
   The python heredoc emits **only** the boolean `has_refresh`, never the token. Keep the `-` sentinel
   convention (tab is IFS whitespace; empty fields collapse under `IFS=$'\t' read`).
3. New function `credential_health()` taking the derived fields, returning `0`=refreshable /
   `1`=unrefreshable / `2`=unreadable. **This must be a function** — the current default-slot check is
   top-level straight-line code (`:159-178`), which makes an inside-a-body negative control
   impossible. Moving it into a function is a precondition of §5, not cosmetics.
4. Default-slot probe (`:165-178`) — resolution order becomes:
   `file:$default_dir/.credentials.json` -> `keychain:$(keychain_service_for_dir "$default_dir")` ->
   `keychain:Claude Code-credentials` (legacy last resort). First readable wins. Then
   `credential_health`; warn
   `default_token_unrefreshable identity=<sub>/<email> dir=<default_dir> -- fail-open`
   only on `1`. `default_token_absent` on `2` — unchanged.
5. Registry loop (`:245-253`) — replace the raw-`expiresAt` skip with `credential_health`; only `1`
   skips and increments `expired_count`. Rename that warn `token_expired` -> `token_unrefreshable`;
   keep `reason=all_expired` on **stdout unchanged** (it is a caller-visible contract token; renaming
   it is an out-of-scope caller change).
6. Header comment block (`:66-79`) — restate the contract: what `expiresAt` actually is, what proves
   refreshability, the suffixed-service scheme and its derivation.

**No new env vars** (checklist item 1: nothing to name, nothing to cross-check against
`.claude/settings.json`; item 5: no config-contradiction surface). Existing `LEADV2_*` names all
conform. No caller change: `claude-subsession.sh` only journals stderr and parses the `profile=`
stdout line, both unchanged in shape.

**Linux container behaviour (no keychain):** `~/.claude/.credentials.json` exists there, so step 4
resolves on the first attempt and the keychain branch is never reached. If that file is also missing,
`read_cred_json keychain:*` execs a non-existent `security`, `2>/dev/null` swallows it, output is
empty -> `default_token_absent`, which is the correct verdict. Guard both keychain attempts with
`command -v "$SECURITY_BIN" >/dev/null` so a keychain-less host costs zero failed execs and emits no
new noise. `keychain_service_for_dir` is a pure python3 hash and is portable as-is.

## 4. Blast radius — who reads this warn today

Grepped `**/*.{sh,js,py,md,json,yaml}` for
`default_token_expired|token_expired|all_expired|default_token_absent`.
Emitter: the selector. Journal writer: `claude-subsession.sh:465,498,504` ->
`docs/handoff/<id>/claude-profile.log`. Assertions:
`tests/test-claude-profile-select.sh:312,321,322,387,395` and the NC comment at
`nc-claude-profile-select.sh:26`. Prose only:
`docs/handoff/TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01/brief.md:36,93`.
**No code anywhere branches on any of these strings.** Nothing breaks if the warn stops firing — its
only consumer is a human reading a log, and 207 false lines already destroyed that. The one thing
that must not regress is `reason=all_expired` on stdout, which the caller's regex non-matches into
single-profile fallback; that token stays byte-identical.

## 5. MANDATORY negative control

**Mutation (inserted INSIDE a function body, never at file top level).** In `credential_health()`,
replace the refreshability decision line with the pre-fix semantics:

```
-  if [[ "$rexp" =~ ^[0-9]+ ]] && (( ${rexp%%.*} <= now_ms )); then return 1; fi
+  if [[ "$exp"  =~ ^[0-9]+ ]] && (( ${exp%%.*}  <= now_ms )); then return 1; fi
```

i.e. judge the slot by the access-token expiry again. That is the exact defect, re-armed, and it sits
between `credential_health() {` and its closing `}` — a top-level insert (the 2026-08-25 mistake)
would make every suite red for the wrong reason and read as a pass.

**Suite that catches it:** `plugins/leadv2/scripts/tests/test-claude-profile-select.sh`, via the
re-pointed T17 block. **CI selects it:** `run-core-offline.sh:423` runs it under the label
`Claude multi-profile selector (CLAUDE-MULTIPROFILE-QUOTA-02)`, and `tests/run-all.sh` runs the whole
curated core-offline set on every scope. It is **not** in `tests/known-red-suites.txt`, so it is a
hard-failure suite today and must stay one — do not add it. Prove the NC by running
`bash plugins/leadv2/scripts/tests/nc-claude-profile-select.sh` after adding the second arm below,
and paste the `NC-PASS` line into the close.

**`nc-claude-profile-select.sh`:** its existing mutation targets the identity-email line, which this
task does not touch — it keeps working, leave it. Add a **second** arm (`NC2`) carrying the sed above,
run the suite against it, require red. Both arms must pass.

**How T12 / T13 / T17 change, and why that is re-pointing, not weakening.**
Every current fixture carries `"refreshToken":"sk-ant-r"` (`cred_json` `:260-262`, `mk_slot`
`:331-341`), so under the corrected contract they are *refreshable* and would go green where they
should be red. Required edits:

| test | today | after | why |
|---|---|---|---|
| `cred_json` / `mk_slot` | fixed shape | add an **optional trailing** `refresh_state` arg (`live` default / `none` / `dead`), emitting `refreshToken` and `refreshTokenExpiresAt` accordingly | keeps T11 / T14 / T15 / T16 call sites byte-identical |
| T12 `:307-315` | expired `expiresAt`, live refresh | fixture `refresh_state=dead`; assert `token_unrefreshable` | "excluded from scoring" must now mean *genuinely dead*, not *access token lapsed* |
| T13 `:317-324` | both expired | both `refresh_state=dead`; the `reason=all_expired` assertion stays **unchanged** | refusal contract preserved verbatim |
| T17 `:380-389` | asserts the warn fires on past `expiresAt` | asserts **silence** on that fixture | the old assertion states a false proposition |
| T17c **(new)** | — | `refresh_state=none` -> `default_token_unrefreshable` fires | the real dead case, uncovered today |
| T17d **(new)** | — | `refresh_state=dead` (past `refreshTokenExpiresAt`) -> warn fires | second dead shape |
| T17e **(new)** | — | default dir has no `.credentials.json`; assert via `$STUB_SEEN` that the **suffixed** service is queried **before** the legacy one | pins Defect A; add two lines to the existing security stub (`:276-289`) so it appends each queried `-s <service>` to `$STUB_SEEN` |
| T18 `:391-397` | absent credential | unchanged | still correct |

Assertion count on the default-slot contract goes **1 -> 5**. T17's old assertion is deleted because
it encodes the bug, and is replaced by a strictly larger set — that is re-pointing at the corrected
contract, not lowering the bar. Keep `check_nogrep "$OUT" 'sk-ant'` / `check_nogrep "$ERR" 'sk-ant'`
(T11k) and add the same pair around the new T17c / T17d / T17e runs, since the new code path handles
refresh-token material.

## 6. Hard constraints (restated for the implementer)

- **Do NOT touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh`** — another lane owns it. No change
  is needed there.
- **Never print or log a credential value, access token, or refresh token.** `derive_identity` emits
  a boolean `has_refresh`, never the token; the registry stays labels-only. Expiry epochs,
  `subscriptionType`, `rateLimitTier`, labels and config dirs are fine on stderr / journal;
  `config_dir` remains stdout-only for the *selected* line, per the existing header contract.
- **Do NOT add anything to `tests/known-red-suites.txt`** (it may only shrink; `known-red-guard.sh`
  enforces that). Do not weaken assertions. **Never commit to `main`** — worktree branch + review.
- **macOS bash 3.2 AND linux container.** No associative arrays, no `${var^^}`, no `mapfile`, no
  process substitution on the hot path. Hash via `python3`, not `shasum` / `sha256sum`. Keychain-less
  behaviour is specified in §3.
- **Concurrent access:** the only shared write surface is `docs/handoff/<id>/claude-profile.log`,
  appended by parallel lanes. Appends must stay single `printf` calls (under `PIPE_BUF`, atomic with
  `>>`) — do not switch to multi-line writes or read-modify-write. No lock needed; do not add one.
- Every path named above was verified to exist on disk. No `claude -p` invocation is introduced, so
  the `--max-turns` / `--permission-mode bypassPermissions` / `--output-format json` checklist item
  is N/A for this task.

## 7. Out of scope

Retiring the stale `Claude Code-credentials`, `Claude Code-credentials-47fc2659` and
`Claude Code-Account-*` keychain entries (operator hygiene, not code). Changing the `reason=` stdout
vocabulary or anything in `claude-subsession.sh`. Quota scoring, `leadv2-quota-read.py`, the pick
helper. Purging the 207 historical log lines. Anything under `docs/handoff/*/claude-profile.log`.

DELIVERABLE_COMPLETE
