# TWO-ACCOUNTS-EVERYWHERE-AND-QUOTA-AWARE-01

**Founder order, 2026-09-03, verbatim:**

> «оба аккаунта должны быть рабочими для всех моих локальных репо, диспатчер должен работать с
> обоими, арбитр должен учитывать оба аккаунта и их квоты и умно распределять нагрузку. Так что вот
> это надо сделать всеми силами, как хочешь так и делай. Если надо логины я сделаю.»

He also stated the credential state, which you must verify rather than assume: the work login lives
in `~/.claude-work` under the work email; the default profile `~/.claude` is now logged in as
`vkk1008k@gmail.com`. His expectation is «все ключи так или иначе уже есть».

This is not a greenfield build. **Most of the mechanism already exists** — the job is to make it
true everywhere, quota-aware, and observable. Do not rewrite the selector; extend it.

## What exists today, measured 2026-09-03

The seam is `plugins/leadv2/scripts/leadv2-claude-profile-select.sh`. It runs per dispatch, prints
the chosen profile on stdout, and writes `docs/handoff/dispatch-<sig>/claude-profile.log`. Live:

    profile=work config_dir=/Users/…/.claude-work score=23 source=live reason=worst_window
    candidates=2 cred=keychain:… identity=team/kostiantyn.vlasenko@mythical.games

The registry is **user-level, never committed**: `~/.claude/state/leadv2/claude-profiles.tsv`,
overridable via `LEADV2_CLAUDE_PROFILES_FILE`. Two rows today:

| label | config_dir | expected cred |
|---|---|---|
| `personal` | `~/.claude` | `keychain:Claude Code-credentials-eb6c5b97` |
| `work` | `~/.claude-work` | `keychain:Claude Code-credentials-5a3c2328` |

Across the 94 `claude-profile.log` files on disk, 123 recorded selections: **93 personal, 29 work.**
So per-dispatch two-account routing already works. `reason=worst_window` shows it already avoids the
account with the worse rate-limit window.

**The known defect:** the selector logs `WARN: default_token_expired identity=max/vkk1008k@gmail.com
-- fail-open` — **198 occurrences.** The expired credential is NOT either registry row; both of those
are live (proved by `candidates=2`, since expired credentials are excluded from scoring per the
script's own header). What is dead is the *inherited default slot* the selector resolves at
`:167-170`: first `file:~/.claude/.credentials.json`, else the **canonical, unsuffixed** keychain
service `Claude Code-credentials`. That is the credential a lane falls back to on fail-open. Filed
separately as `CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01`; **re-measure it before assuming it is still
true — the founder logged in again after that count was taken.**

## Deliverables, ordered, each committed in the lane before the next

### D1 — Establish the truth, then say what is actually missing

Before changing anything: for **every** local repo the founder uses, determine whether a dispatch
from that repo would reach the selector at all. The repos are `persona-engine`, `leadv2`,
`respiro-ios`, `getmany-followup-bot`, `getmany-crm-reports`, and the adopted MythicalGames set
(`m3`, `m3-market`, `pf3-backend`, `pf3-local-dev`, `pf3-smart-contracts`, `mp-frontend`,
`mondia-portal`, `mythical-aii`, `environment-platform`).

The registry is user-level, so the *credentials* are shared by construction. What is **not**
guaranteed per repo is that the dispatch path invokes the selector: check whether each repo's
`.claude/scripts/` symlink farm carries `leadv2-claude-profile-select.sh` and whether that repo's
dispatcher calls it. Produce a table: repo → selector reachable? → evidence.

**Deliver this table before writing any fix.** If the answer is "already true everywhere", say so
plainly — that is a fine and valuable result, and it means D2/D3 are the whole task.

### D2 — Make the arbiter quota-aware across BOTH accounts

Today the selector scores by `worst_window`. That is one signal. The founder asked for the arbiter to
«учитывать оба аккаунта и их квоты и умно распределять нагрузку». Concretely:

1. **Read both accounts' live windows, not one.** `leadv2-quota-live.sh` / `leadv2-ratelimit-probe.sh`
   report `five_hour_pct`, `seven_day_pct` and `binding_window` per account. Establish whether the
   selector currently probes **both** or infers one from the other, and name the file:line.
2. **Score on the binding window, per account.** A 5-hour window at 90% with a weekly at 20% is a
   different situation from the reverse, and the two accounts can be in opposite states. Use each
   account's own `binding_window` rather than a fixed field.
3. **Respect the existing ceilings** — `feedback_quota_ceilings_per_provider`: claude 95/95, with the
   higher ceiling reserved for review work. Two accounts do not license exceeding either.
4. **Explain the decision in the log line**, extending what is already there: `reason=`, plus each
   candidate's binding window and percentage. A routing decision that cannot be read back from
   `claude-profile.log` did not happen.

This overlaps `CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01` (the same arbiter, the reset axis) — read
that brief and say in your report which parts you subsumed, so the two lanes do not fix the same line
twice.

### D3 — Make a degraded router loud instead of silent

The design is fail-open everywhere: opt-out unset, missing registry, fewer than two valid entries, a
malformed registry, or an exhausted probe budget all end in fail-open on the inherited account. That
is the right default, **and it means "we silently went back to one account" is the expected failure
mode.** Today the only indicator is `candidates=` buried in a per-dispatch log nobody reads.

Deliver: a single check the founder or the lead can run that answers "are both accounts live and
being used right now", and a surface where a drop to `candidates=1` is visible without grepping 94
files. Re-measure the 198 `default_token_expired` warnings first; if the founder's new login cleared
them, say so and keep the visibility work anyway.

### D4 — Prove it with a live dispatch on each account

Not a unit test: **two real dispatches**, one landing on each account, each with its
`claude-profile.log` line and a commit in its lane. Paste both. A selector that scores correctly but
whose chosen account never actually runs the work proves nothing — that is the same lying-green as a
code-intel preamble that attaches and is never called.

### D5 — teach every repo, and verify each one can actually do it

**Founder addition, 2026-09-03:** «как только научишься использовать оба аккаунта клод то научи все
мои репо и убедись что все они могут, приоритет на гет мени фоллоу бот и м3».

Order matters and is his, not yours: **`getmany-followup-bot` first, `m3` second**, then the rest.

D1 produced the reachability table. D5 turns every row that is not already true into one that is,
and then **proves each repo individually** — the founder's word is «убедись что все они могут», and
a table saying "should work" is not that.

Per repo, in the founder's priority order:

1. `getmany-followup-bot` — note it ran a **forked** `/leadv2` command until today (de-forked
   2026-09-03; the fork is archived at `.claude/leadv2-overrides/archive/leadv2.md.fork-2026-08-12`).
   Its `.claude/scripts/` farm had only 6 links when re-installed, against ~291 in a fully adopted
   repo — so check what else is missing there before assuming the selector is reachable.
2. `m3` — its env block lives in `.claude/settings.local.json`, **not** `settings.json`, because the
   latter is git-tracked and belongs to the founder's employer. Never write to the tracked file and
   never commit inside any MythicalGames repo.
3. Then: `persona-engine`, `leadv2`, `respiro-ios`, `getmany-crm-reports`, `m3-market`,
   `pf3-backend`, `pf3-local-dev`, `pf3-smart-contracts`, `mp-frontend`, `mondia-portal`,
   `mythical-aii`, `environment-platform`.

**Acceptance, and nothing less:** for each of `getmany-followup-bot` and `m3`, a **real dispatch
launched from inside that repo** whose `claude-profile.log` shows `candidates=2` and a selected
identity — pasted in the report. For the remaining repos a scripted check is acceptable, provided
the check actually invokes the selector from that repo's own path rather than inspecting files.

If a repo genuinely cannot reach the selector and the fix is not local to that repo, say which repo
and why, rather than reporting it green. `MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01` is a separate
open task — do not absorb it here; if a missing override blocks D5 for some repo, name it and move
on to the next repo.

## Standing requirements

Negative control per claimed fix: name the mutation, insert it **inside** the function body (not at
file top level — the 2026-08-25 lesson), show the suite red, revert, show green. Green on macOS
**and** in a Linux container with exit codes pasted. Every new suite registered in
`tests/run-all.sh` and **proven selected** by `--scope changed` — D0 of
`CONTROL-PLANE-HAS-NO-OWNER-01` found that only 9 of 23 named suites are reachable by the runner at
all, so an unregistered suite here is a suite that will silently rot.

Before finishing, run `git diff --stat main..HEAD` and look for files this lane would **delete**
because it branched early; restore them from `main`. That trap hit five lanes today and one would
have removed a 221-line production suite.

## Off limits

`main`; `tests/known-red-suites.txt`; weakening assertions; **printing, logging or echoing any
credential value** — the registry deliberately keeps identities label-only on every surface, and
`claude-profile.log` must stay that way; committing inside any MythicalGames repo (their leadv2
config is local-only and excluded via `.git/info/exclude`); and removing the fail-open behaviour —
make it visible, do not make it fatal.

Do not ask the founder for logins speculatively. He has offered, but D1 must first establish whether
any are actually missing — his own belief is that they are not, and the measured evidence so far
agrees with him.
