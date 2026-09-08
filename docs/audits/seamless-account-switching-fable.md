# Seamless account switching — design report (fable arm)

Mission: PRE-WAVES-PLAN §E1, founder order 2026-09-08. Arm: fable. Task: dispatch-c7ebf292.
Measured on 2026-09-08 between 16:40Z and 16:55Z on the founder's machine, Claude Code 2.1.263
(`claude --version`). Account slots are named by registry LABEL only: **personal** and **work**.

**Independence statement.** I did not open `docs/audits/seamless-account-switching-astra.md` or
`docs/audits/seamless-account-switching-lead-verification.md`, which are present in this tree.
The mission told me to read `PRE-WAVES-PLAN.md`; its §E1 status cell (line 83) contains a one-line
summary of the lead's conclusion ("resume fails by UUID and works by absolute path"). I read that
line in the same tool batch in which my own probe had already run with its design fixed, so the
probe below was not shaped by it. Everything in this report is my own measurement.

---

## 0. The findings, shortest form

1. **Resume is not bound to the account.** It is bound to the **config root** (`CLAUDE_CONFIG_DIR`).
   The transcript store is `<root>/projects/<realpath-of-cwd, slashes→dashes>/<session-uuid>.jsonl`,
   and a transcript carries no account identity. The founder's two "accounts" are two config roots
   (`~/.claude` = personal, `~/.claude-work` = work, wired in `~/.zshrc`), so a session started on
   one root is invisible to `--resume <uuid>` and to the `/resume` picker on the other root.
   **Nothing server-side blocks it**: I resumed a transcript created on the work account from the
   personal account by absolute path, and it answered from the prior context.
2. **`--resume <absolute path>` works cross-account today but does not migrate the transcript.** It
   keeps the same session uuid and appends to the file *in the origin root*. After a cross-root
   resume the destination root gets only a `memory/` directory. So a path-resume wrapper fixes the
   founder's pain, but the `/resume` picker on the new root will still not list that session.
3. **`~/ccswitch.sh --switch` (the `/switch` skill) rotates a Keychain record that neither of the
   founder's config roots reads.** Credentials are stored per root under the service name
   `Claude Code-credentials-<sha256(root)[:8]>`. Both live roots use suffixed records (`eb6c5b97`
   for personal, `5a3c2328` for work); the un-suffixed `Claude Code-credentials` record that
   ccswitch reads and writes holds a token whose `expiresAt` is 2026-08-25. `/switch` therefore does
   not change which account any of the founder's sessions run on, and its "restart Claude Code"
   advice is moot. Two roots + two aliases is the actual switching mechanism in use.
4. **A live session's credential cannot be changed from outside without rewriting that root's
   Keychain record**, which is precisely the 2026-08-28/31 slot-collapse incident (both labels
   ending up on one account). `/login` inside the lead session is the only in-process path and it
   is the incident generator. The lead differs from a lane in exactly one way: a lane's root and
   session uuid are chosen and recorded at spawn (`claude-subsession.sh`), so a lane can be
   re-raised on the other account by path; the lead is an interactive process whose root is fixed
   by the alias that launched it.
5. **The premise "max_5x team answers 401 by design" is false as a standing fact.** One live probe
   today returned **http 200** for the team account (five_hour 67%, seven_day 45%); the burn
   database holds 94 `ok` readings against 17 `unauthenticated` for the max_5x key since 2026-09-03;
   and the Claude Code client itself cached a usage reading for the team root this morning. The 401
   is intermittent and token-state-related, not structural. D1 is still right that a 401 must not
   price an account out, but the balancer is not blind for team accounts.
6. **Three usage signals already exist locally, with zero endpoint calls, and none is read by the
   selector today**: the client's own `cachedUsageUtilization` in `<root>/.claude.json`, the burn
   `rate_limit_history` table, and per-root token totals in the burn `sessions` table.

---

## 1. Where exactly a switch breaks resume

### 1.1 The store is per config root, keyed by cwd realpath and uuid — not by account

Enumeration of the two roots (`ls | wc -l`, not truncated):

```
$ echo "CLAUDE_CONFIG_DIR in this process: ${CLAUDE_CONFIG_DIR:-<unset>}"
CLAUDE_CONFIG_DIR in this process: /Users/kostiantyn.vlasenko/.claude-work
$ ls ~/.claude/projects | wc -l          →  1871   (1872 on a later count, one dir added by my probe)
$ ls ~/.claude-work/projects | wc -l     →   155   (156 after the probe)
$ find ~/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine -maxdepth 1 -name '*.jsonl' | wc -l → 259
$ find ~/.claude-work/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine -maxdepth 1 -name '*.jsonl' | wc -l → 21
```

This session's own transcript exists only under the work root; the personal root has no directory
for this cwd at all:

```
~/.claude/projects/-Users-...-E1-SWITCH-FABLE4        → No such file or directory
~/.claude-work/projects/-Users-...-E1-SWITCH-FABLE4   → 63e22f84-....jsonl (195382 bytes)
```

A transcript line carries `sessionId`, `timestamp`, `type`, `content`, `operation` and no account
field (grep over the whole file for `userID|accountUuid|organizationUuid|oauth*|email` returned
zero matches). Account identity lives in `<root>/.claude.json` under `oauthAccount`, one per root:

```
~/.claude       oauthAccount: organizationType=claude_max   organizationRateLimitTier=default_claude_max_20x  (label: personal)
~/.claude-work  oauthAccount: organizationType=claude_team  userRateLimitTier=default_claude_max_5x          (label: work)
```

The cwd key is the **realpath**: a session started in `/tmp/e1-resume-probe-92660` was stored under
`-private-tmp-e1-resume-probe-92660` (macOS `/tmp → /private/tmp`). Any wrapper that derives the
store path from `$PWD` without resolving symlinks will miss it — the same class of bug this repo
already had with symlinked plugin paths.

### 1.2 How the founder actually switches: two roots, two aliases

```
$ grep -nE 'claude\(\)|CLAUDE_CONFIG_DIR' ~/.zshrc
26:claude() {
27:  local cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-work}"
34:  CLAUDE_CONFIG_DIR="$cfg" command claude --dangerously-skip-permissions "$@"
36:alias claude-work='CLAUDE_CONFIG_DIR=$HOME/.claude-work command claude --dangerously-skip-permissions'
37:alias claude-personal='CLAUDE_CONFIG_DIR=$HOME/.claude command claude --dangerously-skip-permissions'
38:alias claude20='CLAUDE_CONFIG_DIR=$HOME/.claude command claude --dangerously-skip-permissions'
```

Plain `claude` runs on the work root. Running `claude-personal --resume <uuid>` for a session that
was started with plain `claude` fails, because the uuid is looked up in the personal root's store.
That is the whole mechanism behind «после свитча нереально сделать resume».

### 1.3 The probe: one session, three resumes

Design: create a tiny haiku session on the work root, then (a) resume it by uuid on the personal
root, (b) resume it by uuid on the work root as the control, (c) resume it by absolute path on the
personal root. Four `claude -p --model haiku` calls in total, no authentication attempts, no account
switched. (My first path attempt used the wrong path because of the `/private/tmp` realpath fact
above; it is shown because its output is itself informative.)

```
probe_cwd=/tmp/e1-resume-probe-92660 sid=3b0458c9-34c8-44ab-ad22-eb0dcf945dca

=== step1: create session under label=work (~/.claude-work) ===
CLAUDE_CONFIG_DIR=$HOME/.claude-work claude -p --model haiku --session-id "$sid" "Reply with exactly the word PROBE-ALPHA and nothing else."
rc=0
→ stored at ~/.claude-work/projects/-private-tmp-e1-resume-probe-92660/3b0458c9-….jsonl (105696 bytes)

=== step2: resume by ID under label=personal (~/.claude) ===
CLAUDE_CONFIG_DIR=$HOME/.claude claude -p --model haiku --resume "$sid" "What word did I ask you to reply with? Answer with the word only."
No conversation found with session ID: 3b0458c9-34c8-44ab-ad22-eb0dcf945dca
rc=1

=== step3 (wrong path, /tmp instead of /private/tmp): resume by PATH under label=personal ===
No conversation found with session ID: ec32d662-86f2-4a02-9ccf-847575ed684d      ← a FRESH uuid: a non-existent path is silently treated as a new session
rc=1

=== CONTROL: resume by ID under the SAME slot (work) ===
CLAUDE_CONFIG_DIR=$HOME/.claude-work claude -p --model haiku --resume "$sid" "Answer with the single word you were asked to reply with earlier, nothing else."
PROBE-ALPHA
rc=0

=== CROSS: resume by absolute PATH under the OTHER slot (personal) ===
CLAUDE_CONFIG_DIR=$HOME/.claude claude -p --model haiku --resume "$HOME/.claude-work/projects/-private-tmp-e1-resume-probe-92660/$sid.jsonl" "Answer with the single word you were asked to reply with earlier, nothing else."
задача закрыта: captured ask completed (PROBE-ALPHA response sent twice as requested and marked done in open-threads.md)
rc=0      ← it knew PROBE-ALPHA and that it had been asked before: prior context was loaded under a different account

=== stores after ===
~/.claude/projects/-private-tmp-e1-resume-probe-92660:        memory/            (no .jsonl)
~/.claude-work/projects/-private-tmp-e1-resume-probe-92660:   3b0458c9-….jsonl   148930 bytes (grew from 105696), memory/
$ grep -o '"sessionId":"[^"]*"' <work-root file> | sort | uniq -c
  87 "sessionId":"3b0458c9-34c8-44ab-ad22-eb0dcf945dca"      ← one uuid, no fork
```

Two things the control/cross pair proves that a single grep could not:

- **The failure is local lookup, not server refusal.** The identical uuid resumes on the origin
  root and fails on the other; the identical bytes resume on the other root when addressed by path.
- **Path resume writes back into the origin root.** No new file appeared in the personal root; the
  work-root file grew. Whoever builds on this must expect the session to stay "owned" by the root
  it was born in.

The odd Russian text in step 1 and the CROSS step is the founder's global hook stack (task-anchor,
open-threads) firing inside a `-p` session in `/tmp`; the haiku model role-played the orchestrator.
I checked its transcript: it used Read×2, Bash×2, Edit×1 and the only paths it edited were
`/private/tmp/e1-resume-probe-92660/docs/leadv2/open-threads.md` and `…/tasks/dispatch-c7ebf292/STATE.md`
inside the probe cwd. The `open-threads.md` modifications in persona-engine and getmany-followup-bot
that appeared in the same window contain neither `PROBE-ALPHA` nor the probe uuid and belong to
other live sessions. No side effect outside `/tmp` and the two `projects/` dirs named above.

### 1.4 Is there any server-side binding? What does a switch actually cost?

No server-side conversation binding was observed: the API is stateless per request and the same
transcript was continued under a different organization. The one server-side thing that *is*
bound to the organization is the prompt cache:

> "Caches are isolated between organizations. Different organizations never share caches, even if
> they use identical prompts." — https://platform.claude.com/docs/en/docs/build-with-claude/prompt-caching
> (fetched 2026-09-08; the docs.anthropic.com URL 301-redirects there)

So the real, unavoidable cost of moving a live conversation to the other account is **one cold
cache write of the whole context** on the destination org. For scale, this session's first turn:

```
"usage":{"input_tokens":2,"cache_creation_input_tokens":80222,"cache_read_input_tokens":0,"output_tokens":1421,…}
```

A lead session near the 200K mark pays that in full once per switch. That is the same "cold-return"
the session-start burn digest already counts (`cold-returns: 46` in this session's startup hook).

### 1.5 Credential storage, and why `/switch` is a no-op for the founder's sessions

Keychain service names (names only, `security dump-keychain | grep svce`):

```
2 Claude Code-credentials
1 Claude Code-credentials-5a3c2328
1 Claude Code-credentials-eb6c5b97
4 Claude Code-Account-{1,2}-<two emails>        ← ccswitch.sh's own backup slots
```

The suffix is `sha256(config_dir)[:8]`, checked for both roots:

```
$ printf '%s' "$HOME/.claude-work" | shasum -a 256 | cut -c1-8   →  5a3c2328
$ printf '%s' "$HOME/.claude"      | shasum -a 256 | cut -c1-8   →  eb6c5b97
```

Token state per record (expiresAt only; no token bytes were printed):

```
Claude Code-credentials-eb6c5b97  (personal root)  subscriptionType=max  rateLimitTier=default_claude_max_20x  live probe http 200
Claude Code-credentials-5a3c2328  (work root)      subscriptionType=team rateLimitTier=default_claude_max_5x   expiresAt=2026-09-08T18:59:59Z (future)  live probe http 200
Claude Code-credentials           (un-suffixed)    subscriptionType=max  rateLimitTier=default_claude_max_20x  expiresAt=2026-08-25T07:51:47Z (expired)  live probe http 429
```

`~/ccswitch.sh` reads and writes **only** the un-suffixed record:

```
198:            security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || echo ""
218:            security add-generic-password -U -s "Claude Code-credentials" -a "$USER" -w "$credentials" 2>/dev/null
```

and the `/switch` skill is exactly `~/ccswitch.sh --switch` plus "restart Claude Code". Since every
launch path on this machine (the `claude` function, both aliases, and the lane selector's
`export CLAUDE_CONFIG_DIR`) sets `CLAUDE_CONFIG_DIR` explicitly, they all resolve to suffixed
records. UNVERIFIED (inference from the two hash matches and the stale expiry): the CLI uses the
un-suffixed name only when `CLAUDE_CONFIG_DIR` is unset. Either way the measured fact stands: the
record ccswitch rotates has not held a live token since 2026-08-25 while both roots kept working.

---

## 2. Can a live session's credential change without killing the session?

**What is fixed for a running process:** its `CLAUDE_CONFIG_DIR` (environment, immutable after
exec) and therefore its Keychain service name and its transcript store. The account a running
session bills to is whatever that one Keychain record holds at the moment the client next refreshes
its token.

**Consequently there are only two ways to change a live session's account, and both rewrite the
slot:**

1. `/login` inside the session — the binary carries the in-app command ("Switch Anthropic accounts"
   string present in `~/.local/share/claude/versions/2.1.263`). It writes the new OAuth blob into
   the *current root's* record and `oauthAccount` into the current root's `.claude.json`. That is
   the documented 2026-08-28/31 incident in `leadv2-claude-account-check.sh`:
   > "an interactive `claude /login` run while CLAUDE_CONFIG_DIR pointed at the wrong slot rewrote
   > that slot's .claude.json + suffixed keychain record onto the other account"
   After it, the registry's two labels point at one account and the balancer balances nothing.
2. Rewriting the record from outside (what ccswitch does to the un-suffixed one). Same collapse,
   minus the UI.

UNVERIFIED: whether the *conversation* survives `/login` in-process (I expect yes — it is a slash
command, not a restart — but the only test is to run a throwaway interactive session under a scratch
`CLAUDE_CONFIG_DIR`, `/login` into a *test* account, and check the transcript keeps its uuid). I did
not run it: it requires an interactive OAuth flow and would touch a real slot. Even if it survives,
the mechanism is disqualified by the slot-collapse above unless the lead runs on a *third*,
throwaway root that no lane ever selects.

**Why lanes are "halfway there" and the lead is not.** `claude-subsession.sh` chooses the root per
process and records everything needed to find the transcript later:

```
566:    export CLAUDE_CONFIG_DIR="$dir"                     ← per-lane root, from leadv2-claude-profile-select.sh
568:    … >> "$HANDOFF_DIR/claude-profile.log"            ← label of the chosen slot
215: SESSION_MAP_FILE="$HANDOFF_DIR/sessions.map"
216: printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$SESSION_LABEL" "$SESSION_ID" >> "$SESSION_MAP_FILE"
596:   --session-id "$SESSION_ID"                         ← uuid chosen by the dispatcher (uuidgen, line 207)
```

A sample lane log line (identity redacted): `[claude-profile] selected=work score=19 source=live candidates=2 cred_kind=keychain identity=<redacted>`.
So for a lane, `<root>/projects/<enc(realpath worktree)>/<SESSION_ID>.jsonl` is computable from
the handoff directory alone — the "re-raise this lane on the other account" primitive is a path
resume away. The lead has none of that: its root is whichever alias the founder typed, its uuid is
whatever `/resume` shows, and nothing in the plugin records either.

One latent bug found while checking: `plugins/leadv2/scripts/leadv2-history-primer.sh:43` hardcodes
`PROJ_DIR="$HOME/.claude/projects/$CWD_NORM"` and builds `CWD_NORM` from `pwd` without realpath —
under the founder's default (work) root it reads the wrong store. It has no callers in the plugin
today (`grep -rl leadv2-history-primer plugins/leadv2` returns only itself), so it is dormant, not
live.

---

## 3. How does the balancer know which account is free without a usage endpoint?

### 3.1 First, the premise: the team account does answer

The route arbiter charges `UNKNOWN_PROBE_PENALTY=50.0` (`lib/leadv2-route-arbiter.sh:913`) to any
arm whose probe did not return a number. The mission and D1 state that `max_5x` is a team account
whose usage endpoint answers 401 by design. Three independent sources say otherwise:

**(a) One live probe today** through the plugin's own reader (`leadv2-quota-read.py anthropic`,
which enumerates every `Claude Code-credentials*` record and calls `https://api.anthropic.com/api/oauth/usage`
with the stored bearer token; run once, output filtered to non-identifying fields):

```
{'entry_suffix': 'default',  'subscription_type': 'max',  'tier': 'default_claude_max_20x', 'http': 429, 'status': 'unknown', 'account_state': 'unknown', 'five_hour_pct': None, 'seven_day_pct': None, 'error': '429 rate_limited (reported as unknown, NEVER 0)'}
{'entry_suffix': '5a3c2328', 'subscription_type': 'team', 'tier': 'default_claude_max_5x',  'http': 200, 'status': 'ok',      'account_state': 'ok',      'five_hour_pct': 67.0, 'seven_day_pct': 45.0, 'error': None}
{'entry_suffix': 'eb6c5b97', 'subscription_type': 'max',  'tier': 'default_claude_max_20x', 'http': 200, 'status': 'ok',      'account_state': 'ok',      'five_hour_pct': 7.0,  'seven_day_pct': 56.0, 'error': None}
```

The team account (work, `5a3c2328`) answered 200. The only failure was the dead un-suffixed record.

**(b) The burn database's own probe history** (`~/.claude/burn/history.db`, table
`rate_limit_history`, 282 rows over 5 account keys from 2026-09-03 20:28 to 2026-09-08 16:49;
keys shown as a 6-hex prefix of `hex(account_key)`, labels shown only if they contain no `@`):

```
key     label    state            rows  first                 last
343766  max_5x   unauthenticated    26  2026-09-04 13:22:39   2026-09-07 16:26:48
356133  max_5x   ok                 94  2026-09-03 20:44:39   2026-09-08 16:49:58
356133  max_5x   unauthenticated    17  2026-09-04 05:02:11   2026-09-07 01:51:22
646566  max_20x  unauthenticated    51  2026-09-04 13:22:39   2026-09-08 16:49:58
656236  max_20x  ok                 79  2026-09-03 20:44:39   2026-09-08 16:39:47
656236  max_20x  unauthenticated    14  2026-09-04 05:02:11   2026-09-08 07:56:34
```

The max_5x key that is live today has 94 `ok` readings to 17 `unauthenticated`, and the max_20x
key that is live has 79 to 14. The 401s cluster in time and hit both tiers alike; the keys with
*only* `unauthenticated` rows (343766, 646566) look like the dead/legacy records. This is a token
state pattern, not a plan-type rule.

**(c) The Claude Code client itself** reads usage for the team account and caches it in
`<root>/.claude.json` (`cachedUsageUtilization`, utilization fields only):

```
~/.claude-work/.claude.json  fetchedAtMs=1788860611636 (2026-09-08T09:43:31Z)  five_hour.utilization=42  seven_day.utilization=26
~/.claude/.claude.json       fetchedAtMs=1788165690511 (2026-08-31T08:41:30Z)  five_hour.utilization=7   seven_day.utilization=39
```

The binary contains both `api/oauth/usage` and `api/oauth/usage?at_wall=` — the same endpoint
family the plugin calls.

I therefore contradict the mission text on this point: D1's *conclusion* (a 401 must never price an
account out) is right, but its *premise* for team accounts is not a fact about the endpoint. Design
for "the number is sometimes missing for any account", not for "the number is never there for team".
The founder's standing rule "we do not measure spend on it" is a policy choice and is untouched by
this — a policy can forbid using the number; it cannot make the number unavailable.

### 3.2 Signals that exist locally today, at zero endpoint calls, and nobody reads

| Signal | Where | Freshness | Read by the selector today? |
|---|---|---|---|
| Client's own usage cache | `<root>/.claude.json` → `cachedUsageUtilization.{fetchedAtMs, utilization.five_hour, seven_day}` | Whenever a client process on that root last refreshed: work root 7h old, personal root 8 days old at measurement | **No** (`grep -rl cachedUsageUtilization plugins/leadv2/scripts ~/.claude/burn` → nothing) |
| Probe history | burn `rate_limit_history` (`account_key`, `five_hour_pct`, `seven_day_pct`, reset epochs, `state`) | Every ratelimit-probe run; last row 16:49:58Z today | No — the arbiter sees only the current probe |
| Per-root token accounting | burn `sessions` (`jsonl_path`, `input_total`, `output_total`, `cc_total`, `cr_total`, `last_asst_ts`) — scans both roots: 14527 personal-root sessions, 725 work-root | Continuous (session-start hook) | No |
| Launchability | the lane's own first API call: 200/401/429 | Real time | Partly — D1 is moving this way |

The per-root accounting is already sharp enough to balance on. Sessions active in the last 5h:

```
root            sessions  tokens_cum (input+output+cache_create+cache_read, cumulative per session)
personal-root          2    481,000,723
work-root             58  1,079,786,025
```

(These are cumulative totals of sessions *active* in the window, not the window's spend; a windowed
sum needs the per-assistant-message `usage` blocks the transcripts already carry — this session has
50 of them — which burn's scanner already parses.)

### 3.3 The design: layered freshness, no penalty for silence

Feed the arbiter one number per slot, `usable_now`, from the freshest available layer, and stamp
its `source` and `age`:

1. **Live probe if a fresh one exists** (≤ 10 min, from the selector's own cache or the D1 launch
   probe). Today's path; keep it.
2. **Client cache** `cachedUsageUtilization` if `fetchedAtMs` is younger than the five-hour window's
   `resets_at`. Free, and for the root the lead is running on it is usually minutes old because the
   lead's own client refreshes it.
3. **Burn history extrapolation**: last known `five_hour_pct` for that account key plus the tokens
   the burn scanner has seen on that root since `captured_epoch`, divided by the slot's observed
   tokens-per-percent (derivable from consecutive history rows). Stale but monotone — it never says
   "empty" about an account that has been working hard since the last reading.
4. **Unknown** — only when none of the above exists. Score it as *median of known slots*, not
   `+50`. A slot we know nothing about is average, not poison; D1 fixes the 401 case, this fixes
   the "no data at all" case the same way.

Keep the two things D1 already established: a 401 is not death, launchability is the final test.
Add one: when the lane's own first call answers 429 (the rate-limit cliff), write that as a
`five_hour_pct=100` row into `rate_limit_history` so the next selection sees it without a probe.
That is the only signal that is *always* available for *every* account, and it is free.

Team-account policy: if the founder wants spend on the team slot unmeasured, the policy is "do not
*report* it", and the arbiter can still balance on it — balancing needs an ordering, not a bill.

---

## 4. What is the smallest thing that actually helps? Ranked by cost

| # | Proposal | Cost | Removes | Leaves |
|---|---|---|---|---|
| **R1** | **Cross-root resume wrapper.** A `claude-resume` shell function: enumerate `<root>/projects/<enc(realpath $PWD)>/*.jsonl` for *both* registered roots (labels from the registry, never the file contents), present them by mtime with the root label, and exec `CLAUDE_CONFIG_DIR=<chosen-account-root> claude --resume <absolute path>`. Also lets the founder pick *which account* to continue on. | ~2 h, one script, zero plugin changes | Costs 1 and 2 from the founder's framing for the lead: no context loss on a switch, no raising from scratch | The `/resume` picker inside Claude Code still lists one root; the transcript stays in its origin root (measured §1.3) |
| **R2** | **Retire `/switch` → `~/ccswitch.sh` from the live path**; make the `switch` skill print the two aliases and R1 instead. | 15 min | A tool that rotates a dead record and tells the founder to restart for nothing | — |
| **R3** | **Lane re-raise on the other account.** Record `config_dir` (or label) next to `SESSION_ID` in `sessions.map`; add `--resume-lane-on <label>` to the dispatcher that computes the absolute transcript path and re-spawns with the other root. Lanes already have everything else (§2). | ~1 day incl. a test that proves a lane resumed on the other root answers from prior context | Cost 2 for lanes: a 429'd lane continues on the other slot instead of restarting | A 429 mid-turn still ends that turn |
| **R4** | **Balancer signal layering** (§3.3): read `cachedUsageUtilization` and `rate_limit_history` in `leadv2-claude-profile-select.sh`; 429-on-launch writes a history row; unknown = median not +50. | 2–3 days with tests; lands on top of D1, does not conflict | Cost 3: routine balancing across two max_5x slots without a live probe per dispatch | Nothing measures the *team* slot's spend if policy forbids reading its number — it is still orderable |
| **R5** | **One shared transcript store**: make `~/.claude-work/projects` a symlink to `~/.claude/projects` (or bind both roots' `projects` to a third dir). Then uuid resume and the `/resume` picker work identically on both accounts and R1 shrinks to "pick the account". | 1 h to try; a scratch-root test first | Both halves of the resume problem, structurally | **UNVERIFIED** that the CLI tolerates a symlinked `projects/`; per-project `memory/` dirs would merge (probably desired); `history.jsonl` and `.claude.json` stay per root. Test: create two scratch roots with a shared `projects` symlink, run one `-p` session on each, `--resume <uuid>` across. Do it on scratch roots, not the live ones |
| R6 | **Pre-warmed lead on each account**: keep an idle lead session open per root and hand off via a handoff file. | Low build cost, high running cost | The restart latency | Two contexts to keep in sync; the prompt cache expires in 5 min idle (doc quote §1.4) so "warm" is not warm; **not recommended** |
| — | `/login` inside the lead to hop accounts | 0 | — | Rewrites the slot; re-creates the 08-28/31 collapse; **do not** |
| — | True in-process credential swap without a restart | n/a | — | No mechanism in the client we have; the env and service name are fixed at exec |

Recommended order: R2 and R1 this week (they are the "smallest thing that helps" and need no plugin
change), R3 with the next dispatcher touch, R4 on top of D1, R5 as a scratch-root experiment whose
result decides whether R1 stays or shrinks.

What a "seamless switch" would then look like in practice: the founder types `claude-resume`, sees
the sessions of this cwd across both roots with their labels, picks one and the account to continue
on, and pays one cold cache write. No restart of anything else, no lost lane, no `/switch`.

---

## 5. What I did not check, and the command that would

- **Whether `/login` preserves the conversation in-process.** Needs a scratch `CLAUDE_CONFIG_DIR`,
  an interactive session, `/login` into a test account, then `grep -c sessionId` on the transcript
  before and after. Not run: interactive OAuth on a real slot.
- **Whether the CLI re-reads the Keychain record on every token refresh or only at start.** Would
  need a scratch root, a running session, and a controlled rewrite of that root's record —
  a credential rewrite, which I will not do on this machine. This decides whether ccswitch-style
  external swaps could ever be "live".
- **Whether the un-suffixed record is used when `CLAUDE_CONFIG_DIR` is unset.** Probe: start
  `env -u CLAUDE_CONFIG_DIR command claude -p 'ok'` once in a scratch cwd and see which record's
  `expiresAt` moves. Not run because every founder launch path sets the variable, so the answer
  does not change any recommendation.
- **R5's symlinked store.** Described above; not run against the live roots.
- **The `/resume` interactive picker.** I tested `--resume` only; the picker's one-root enumeration
  is inferred from the store layout, not observed on screen.
- **Why the 401s cluster.** The burn table shows when, not why; correlating `unauthenticated` rows
  with the `expiresAt` of the record at that time would need the history of the Keychain blob,
  which nothing records (and should not).
- **Prompt-cache scope for Claude Code OAuth traffic.** The doc says organization isolation, and
  workspace isolation on the Claude API; whether the two roots are different organizations is
  implied by `organizationType` (`claude_max` vs `claude_team`) but I did not compare
  `organizationUuid` values, deliberately.

---

## 6. Side effects of this mission, and cleanup

- Two new `projects/` directories named `-private-tmp-e1-resume-probe-92660` (work root: one
  transcript of 148930 bytes and `memory/`; personal root: `memory/` only) and the scratch dir
  `/tmp/e1-resume-probe-92660` with hook-generated files inside it. Harmless; deletable.
- API spend: four `haiku` `-p` calls (two on work, two on personal) and one `leadv2-quota-read.py`
  probe that called the usage endpoint once per Keychain record (three records).
- No file outside this worktree, `/tmp`, and the two `projects/` dirs above was written. No
  credential was printed, rotated, or refreshed by hand. No account was switched.

---

## 7. Self-check

No shell or Python file was changed by this lane, so `bash -n`, `py_compile` and the changed-scope
test runner have no targets. Proof of scope (run after commit):

```
$ git diff --name-only main...HEAD -- . | grep -vE '\.md$' ; echo "non-markdown changes: $?"
```

Output is pasted in the lane's `developer.full.md` after the commit. The report itself is the
deliverable named in `LANE_WRITES`.
