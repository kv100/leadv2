# E1 — lead's live verification, and the founder's actual symptom explained

Run by the lead, 2026-09-08, on real accounts. Astra's report
(`seamless-account-switching-astra.md`, merged `9909091b`) proved local transcript loading against
a **loopback fixture server** and marked the decisive question unverified in its own words:

> **UNVERIFIED: a real OAuth conversation can continue under the other account.** No real account
> was authenticated, switched, refreshed or queried in this audit.

That question is answered here: **verified.** One short live turn per probe, haiku, no
authentication performed, no account switched for the founder's own session — each probe is a
separate process with its own `CLAUDE_CONFIG_DIR`, which is what the `claude-work` /
`claude-personal` aliases (`~/.zshrc:36-37`) already do.

## The founder's symptom, stated in his own terms

> «когда мы делаем свитч я стартую новую сессию и потом делаю `/resume` … и когда я выбираю какую
> сессию продолжить то тут нет всех сессий, а вот если бы я был сейчас под аккаунта max x20 то там
> было бы намного больше сессий»

His `/resume` picker showed **7 sessions** (`newlead`, `d3`, `d1`). That is not a bug in `/resume`.
The picker enumerates `<config-root>/projects/<project>/*.jsonl`, and the two roots hold very
different amounts of history:

| label | root | project dirs |
|---|---|---|
| personal | `~/.claude` | **1871** |
| work | `~/.claude-work` | **153** |

So after a switch the picker is not hiding sessions — it is looking in a different drawer. The
sessions still exist, on disk, unmodified, under the other root.

## Setup for the probes

Both roots are already authenticated (labels only, no credential content read or printed):
personal carries a `.credentials.json`; work carries none and uses the macOS Keychain, as the
official authentication docs describe. A throwaway conversation was created under **personal**
carrying a string that appears nowhere else — `MARKER-ALPHA-7731`, session
`31613ff8-23ec-42bf-ad2e-9305eb95b7ca`.

## Probe A — the boundary, reproduced on real accounts

    CLAUDE_CONFIG_DIR=~/.claude-work  claude -p "…" --resume 31613ff8-…
    → No conversation found with session ID: 31613ff8-23ec-42bf-ad2e-9305eb95b7ca

The same observable astra got against a fixture. The transcript exists under
`~/.claude/projects/<project>/31613ff8-….jsonl` and nowhere under `~/.claude-work/projects/`. The
failure is **local discovery**, and it happens before any request leaves the machine.

## Probe B — the decisive one

    CLAUDE_CONFIG_DIR=~/.claude-work  claude -p "What marker did you say earlier in this
      conversation? Reply with only the marker." --resume /Users/…/.claude/projects/…/31613ff8-….jsonl
    → MARKER-ALPHA-7731

**A conversation started under the personal account continued under the work account, against real
OAuth.** The marker appears nowhere in probe B's prompt, so its only possible source is the prior
turn — the earlier context was serialized into the request and the API accepted it under the second
account's identity.

## Probe C — the control that makes B mean what it says

    CLAUDE_CONFIG_DIR=~/.claude-work  claude -p "Reply with exactly: WORKROOT-OK"
    → WORKROOT-OK

The work root authenticates on its own, so B was not served by a silent fallback to the personal
credentials. Probe A cannot serve as this control — it fails before any request is made.

## Probe D — a fact neither astra nor I had

The resumed session **kept writing to the original transcript file under the original root.** After
probe B, `~/.claude/projects/…/31613ff8-….jsonl` contains the new turn (4 occurrences of probe B's
question); the work root received no copy of that conversation. The only new file under the work
root is probe C's own session — 6 occurrences of `WORKROOT-OK`, zero of the marker question,
confirmed by reading it rather than assuming which run produced it.

So resume-by-path reads *and* writes the file wherever it lives, independent of the config root.
**A switch does not fragment history.**

## What this changes for E1

«После свитча resume нереально» is false as stated. Resume is impossible **by UUID** and works **by
absolute path**, cross-account, today, with no change to the CLI. The distance between the
founder's symptom and a fix is therefore a **picker that enumerates both roots and resumes by
path** — a wrapper, not a subsystem. That is a much smaller thing than E1 was scoped as.

## What is still NOT proven — read this before building on it

- **Same human, two accounts.** Both roots belong to the same person. Resuming across two different
  people's accounts is untested and is a different question.
- **One short haiku turn, print mode.** Untested: long context, thinking signatures, prompt-cache
  reuse across accounts, a conversation carrying tool results.
- **No live interactive session was moved.** Astra's warning stands and this does not weaken it: a
  transcript restores messages; a terminated process's live tool jobs and in-memory state need
  separate reconciliation. Do not restart lanes with the lead.
- **Entitlements were not exercised.** Both accounts could serve haiku. Whether a model available
  under one account resumes cleanly under an account lacking it is untested.
