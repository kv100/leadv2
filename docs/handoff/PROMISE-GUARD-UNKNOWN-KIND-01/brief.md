# PROMISE-GUARD-UNKNOWN-KIND-IS-A-HOLE-01 — the guard is silent on the commonest promise a lead makes

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.**
- Suite path is `tests/run-all.sh` at the repo **ROOT**. Do NOT open with a full suite run — a
  sibling round burned three hours that way and committed nothing. Prove granularly first.

**Class:** Standard. **Repo:** leadv2 plugin. File: `plugins/leadv2/hooks/leadv2-promise-guard.sh`.

## The hole, traced on a real escape 2026-09-02

The lead ended a turn with «так что сейчас разбираю все три» — a promise — and did nothing. The
founder caught it by hand. The guard stayed silent. Traced through the source:

1. `COMMIT_RE` **does** match the clause: `COMMIT_RU_SHAPE`'s marker-before-verb alternative
   (`RU_INTENT_MARKER` `\s+` `RU_1SG_NONPAST`) fires on «сейчас разбираю», and `VETO_RE` finds no
   past-tense word in that comma-clause. So detection worked.
2. `classify_promise_kind()` returns **None** — `PROMISE_KIND_PATTERNS` covers only
   `test | commit | dispatch | write`, and «разбираю» is in none of them.
3. Line ~590:
   ```python
   if primary_kind is None:
       action_after_promise = has_action     # ANY tool call counts as keeping the promise
   ```
   The turn contained only **reads** (`grep`, `head`). The guard concluded the promise was kept.

So the guard is weakest exactly where a promise is vaguest — and a vague promise is the one that
most needs binding, because it commits to nothing checkable.

## Deliver

1. **A `diagnose` kind.** «разбираю / разбираюсь / смотрю / выясняю / копаю / изучаю / займусь /
   посмотрю / гляну» and their obvious relatives. Follow the file's own convention — it deliberately
   matches grammatical shape over a verb dictionary where it can (see the
   `PROMISE-GUARD-MORPHOLOGY-01` comment), and its authors were burned repeatedly by false
   positives on ordinary prose. Read those comments before adding a pattern; they record exactly
   which shapes cry wolf (`-ому/-ему` datives, `потому`, 3rd-person-plural collisions).
2. **Close the unknown-kind path.** When the kind is unknown, a promise is kept only by an action
   that **changes state** — Write, Edit, a dispatch, a commit — never by a read. Reads are how you
   look; they are not how you do. Keep a bare-`has_action` fallback only if you can name a case
   that needs it; if you cannot, remove it and say so.
3. **Do not make it shout.** The file's own history says a guard that cries wolf on status prose
   gets switched off within a day, which costs more than the escape it was built to catch. Every
   pattern you add must be tested against real status prose that must stay silent.

## Prove it
- **The actual escape:** feed the guard the real clause «Ни одну из трёх причин нельзя починить
  ожиданием, так что сейчас разбираю все три» with a turn containing only Read/Grep → it must FIRE.
  Paste it. This is the case that failed in production today.
- **Same clause, but the turn contains a Write or a dispatch** → silent. Paste it.
- **Status prose stays silent:** at least six real sentences from this repo's own lead messages that
  report finished work (past tense, artifacts, shas) → no fires. Take them from
  `docs/handoff/*/report.md` or a transcript; do not invent them.
- **Negative control:** revert the unknown-kind branch to `action_after_promise = has_action` in a
  mktemp FULL copy whose baseline is proven green → the escape case goes silent again. Paste
  baseline and mutant runs. Insert the mutation INSIDE the function body.
- `tests/run-all.sh --scope changed` from the LANE ROOT at the END, FOREGROUND, `timeout 1800`.
  Paste the real tail.

## Note
`run-all.sh` now applies `tests/known-red-suites.txt` to granular nested suite names. If an
allow-listed suite still blocks you, say so — that is a plumbing gap worth more than this round.

## Constraints
LANE_WRITES only. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`,
`plugins/leadv2/scripts/docs/`, `critic.*`. Mutants and fixtures in mktemp only.

## Done when
The real escape fires; the same clause with a state-changing action stays silent; six real status
sentences stay silent; the negative control is silent-again against a green baseline.
