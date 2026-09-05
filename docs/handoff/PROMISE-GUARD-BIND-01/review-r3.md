# PROMISE-GUARD-BIND-01 — round 3 review

**Verdict: fail** — both round-3 items are genuinely fixed and independently proven, but the fix
re-opens the exact false-positive class this file's own history says killed the previous shape rule,
and it does so under a pinned negative fixture that was already going to pass.

Lane `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/PROMISE-GUARD-BIND-01`, HEAD
`57bf893`. All commands below were run by the reviewer, not read from the worker's logs.

---

## Item 1 — the Russian extractor (marker may precede the verb) — **WORKS**

Not verified through the suite (see [Medium] "the morphology suite does not run the hook"). Verified
through the **real hook**: a two-record transcript (user + one assistant text block, **zero tool_use
blocks**), `{"transcript_path":…,"session_id":…}` on stdin, `HOME` pointed at a fresh `mktemp -d`,
journal row counted out of `$HOME/.claude/leadv2-promise-guard.jsonl`.

All eleven promises named at `review-r1.md:88-98`, post-fix:

```
rows=1 verdict=fired | Сейчас поправлю регэксп в хуке
rows=1 verdict=fired | Сейчас прогоню тесты
rows=1 verdict=fired | Сейчас закоммичу фикс
rows=1 verdict=fired | Сейчас напишу отчёт          <- was NO-ROW in r1
rows=1 verdict=fired | Сейчас исправлю биндинг      <- was NO-ROW in r1
rows=1 verdict=fired | Сейчас диспатчу воркера
rows=1 verdict=fired | Сейчас подниму лейн
rows=1 verdict=fired | Дальше беру третий таск
rows=1 verdict=fired | I'll dispatch the lane now
rows=1 verdict=fired | Now I'm going to run the suite
rows=1 verdict=fired | Сейчас поднимаю наблюдателя
```

Same eleven through the pinned pre-fix fixture — reproduces r1's measurement exactly, 5 silent:

```
rows=0 NO-ROW | Сейчас поправлю регэксп в хуке
rows=0 NO-ROW | Сейчас прогоню тесты
rows=0 NO-ROW | Сейчас закоммичу фикс
rows=0 NO-ROW | Сейчас напишу отчёт
rows=0 NO-ROW | Сейчас исправлю биндинг
rows=1 fired  | Сейчас диспатчу воркера          (+ the other five fired)
```

The `допишу/перепишу/обновлю/смерджу/добавлю` family, **both orders**, all `rows=1 verdict=fired`:
`Сейчас допишу тесты` … `Сейчас добавлю кейс`, and `Допишу тесты сейчас` … `Добавлю кейс сейчас`.
`Сейчас же исправлю биндинг` also fires (the `(?:же\s+)?` arm at `leadv2-promise-guard.sh:219`).

Note: `review-r1.md:88-98` names **eleven** sentences, not twelve; the round-3 mission's "twelve" is
off by one against its own citation. The suite carries all eleven plus five r3-family cases.

## Item 2 — fixtures restored — **WORKS**

`test-promise-guard-morphology.sh:154-171` now carries the reviewer's eleven verbatim
(`case_r1_01_popravlyu` … `case_r1_11_podnimayu`), not a self-selected set, and no earlier fixture
was deleted or weakened to make the fix pass. The five r3-family cases at `:177-181` are additions,
not replacements.

## Mutation control — **WORKS, and the shipped RED log is genuine**

Mutation applied to the production file, inside the `COMMIT_RU_SHAPE` assignment in the embedded
python decision body (`leadv2-promise-guard.sh:217-220`), deleting the marker-before-verb
alternative. Not a zero-match: `md5 2c4ac537… -> cd6a1f3b…`.

```
Results: 3 passed(red->green), 7 failed, 22 green-pre-fix, 0 could-not-run
FAIL: r1-04-napishu / r1-05-ispravlyu / r3-dopishu / r3-perepishu / r3-obnovlyu / r3-smerdzhu / r3-dobavlyu
```

and through the real hook under the mutation:

```
rows=0 NO-ROW | Сейчас напишу отчёт
rows=0 NO-ROW | Сейчас исправлю биндинг
```

This is line-for-line the counts in `round3-red/shape-mutation-RED.log`, so that log records a real
failing run — not a green run under a RED header. Restored (`md5 2c4ac537…`, `git diff` empty),
suite back to `10 passed, 0 failed`.

## Journal sandbox spot-check — **WORKS**

`~/.claude/leadv2-promise-guard.jsonl` across all three suites plus the mutation cycle:

```
PRE : size=760936 mtime=1788100455 inode=48439811 md5=7ac129bad2353c953d101f15663d931d
POST: size=760936 mtime=1788100455 inode=48439811 md5=7ac129bad2353c953d101f15663d931d
```

Suite counts, all three, unmutated: morphology `10 passed / 0 failed / 22 green-pre-fix`; binding
`2 / 0 / 8` plus `PASS: sandbox-control`; `tests/test-promise-guard.sh` `17/17 pass`.

---

# Findings

## [High] the marker-first alternative fires on ordinary status prose — the exact class that got the previous shape rule reverted

`plugins/leadv2/hooks/leadv2-promise-guard.sh:219`

`(?:MARKER)\s+(?:же\s+)?RU_1SG_NONPAST` treats the marker's next word as a verb candidate. Russian
accusative singular ends in -у/-ю, and `RU_1SG_NONPAST`'s exclusion list (`:174`) covers only
`[ое]му|ку|гу|ху|це|ре|ле`. So «сейчас **работу**…», «сейчас **задачу**…», «дальше **картину**…» all
read as commitments. Measured through the real hook — ten hand-written prose clauses, every one of
which is `rows=0` on the pre-fix hook:

```
rows=1 fired  | Сейчас работу делают два воркера
rows=1 fired  | Сейчас задачу держит лейн A
rows=1 fired  | Сейчас команду не трогаем
rows=1 fired  | Дальше картину покажет соак
rows=1 fired  | Сейчас версию 5.2 использует прод
rows=1 fired  | Потом ситуацию посмотрим вместе
rows=0 NO-ROW | Сейчас базу мигрировали вручную      (past-tense veto, not this rule)
rows=0 NO-ROW | Затем таблицу привёл к виду выше     (past-tense veto)
rows=0 NO-ROW | Сейчас очередь пустая
rows=0 NO-ROW | Сейчас статистику собирает джоба
```

Six new false positives out of ten, none of which existed before this commit. The comment block the
fix added (`:206-216`) claims adjacency solves this — "a preposition or adjective between marker and
candidate is real prose … and blocks the match". That is true only for the *preposition* sub-case. An
accusative noun sitting **directly** after the marker is the common shape and is not blocked.

This matters beyond noise. `docs/leadv2/scheduled-decisions.md:9` gates the BLOCK flip on "≥20
consecutive `fired` rows with no false positive". Round 3 seeds that stream with a prose
false-positive class, so the GO-condition becomes unreachable by construction — the log-only rollout
can no longer produce the evidence it exists to produce. And this same file's own history
(`:465-478`) records the previous version of this trade: five false positives in one day, zero true
catches, whole rule reverted.

**Required fix:** the marker-first arm needs a discriminator the trailing arm gets for free from
word order. Either restrict the candidate to a verbal-stem shape (`-ю/-у` preceded by a consonant
class that excludes the nominal accusatives, and extend the exclusion list with the `-ту -ду -ну -зу
-чу -щу -ию -ру -лу` families where they are nominal), or require a second signal in the clause (no
other finite verb present; or the candidate is clause-final). Whichever is chosen, pin **«Сейчас
работу делают два воркера»** and **«Сейчас задачу держит лейн A»** as MISS fixtures and show them RED
against the current `COMMIT_RU_SHAPE` before the fix lands.

## [High] the pinned negative for this rule was chosen from the sub-case the fix already handles

`plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh:276` — `case_neg_shape_adverb` is
«сейчас **по этому** делу решения нет»: marker, then a two-letter preposition. The adjacency rule
blocks it for free, and the case duly reports `GREEN-PRE-FIX`. The sub-case that actually breaks
(marker + adjacent accusative noun) has no fixture at all.

This is the same defect round 3 was dispatched to fix — a fixture that measures nothing because it
was going to pass either way — recurring inside the fix for it. Third occurrence of this shape in
this repo today, per the round-3 mission's own note.

**Required fix:** add the two sentences named above as MISS cases and show them RED against HEAD.

## [Medium] the morphology suite does not run the hook it claims to test

`plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh:49-128` — `_verdict` never executes
`leadv2-promise-guard.sh`. It greps the regex assignments out of the source, `exec`s them into a
Python namespace, and **re-implements the decision**: it rebuilds `commit` from
`COMMIT_RU_NOW|COMMIT_RU|COMMIT_EN|COMMIT_RU_SHAPE`, rebuilds `veto`, re-evaluates
`COMMIT_RU_LEADING`, and applies its own `hit and veto -> False` ordering. Clause splitting
(`hook:471-479`), `classify_promise_kind`, the kind binding, the journal write, the once-per-turn
sentinel and the rollout gate are all outside its reach — a change to any of them keeps this suite
green.

`test-promise-action-binding.sh:151-158` *does* drive the real hook, so the capability exists in the
lane; the morphology suite simply does not use it. The round-3 "done means" required the twelve to be
verified "through the real hook" — that was satisfied only by this review's own driver, not by
anything committed in the lane.

**Required fix:** move the morphology cases onto the binding suite's driver shape (sandboxed `HOME`,
real stdin JSON, assert on a journal row), keeping the pre/post fixture arm.

## [Medium] both suites print `PASS: bash -n` before running `bash -n`

`test-promise-guard-morphology.sh:225` and `test-promise-action-binding.sh:266`:

```
log "PASS: bash -n leadv2-promise-guard.sh"
bash -n "${HOOK}" || { log "FAIL: bash -n"; exit 1; }
```

The PASS line is unconditional and precedes the check. On a syntax error the log reads
`PASS: …` then `FAIL: bash -n` on consecutive lines. Exit code is still correct, but the transcript
lies. Swap the two lines.

## [Low] the bash-3.2 claim is not checked under bash 3.2

`bash -n` in both suites resolves to `$PATH` bash, which on this machine is homebrew 5.3.9. Under real
`/bin/bash` 3.2.57 the same command reports `line 241: syntax error near unexpected token '('` — a
bash-3.2 `-n` limitation with a heredoc inside `$( … )`, **not** a hook defect: `/bin/bash <hook>`
executes to `rc=0`. The hook is fine on 3.2; the suites' 3.2 claim is simply unproven by them.

---

## Contradiction scan

- `tests/run-all.sh:122-124` maps all three suites to `leadv2-promise-guard.sh`. CI selects them; no gap.
- `LEADV2_PROMISE_GUARD_BLOCK` unset ⇒ stdout silent with a journal row still written; confirmed on
  every post-fix probe above (`stdout=silent`, `rows=1`). The pre-fix fixture emits output at
  `BLOCK=0`, which is expected — the gate postdates it.
- `COMMIT_RU_SHAPE` is now an un-parenthesised alternation, but its only consumer (`:223`) already
  wraps it in a top-level `(?: … | … )`, so operator precedence is safe. `grep` confirms `:217` and
  `:223` are the only occurrences.
- Handoff-path split: `review-r1.md` / `review-r2.md` / `fix-round-3.md` live only in the MAIN
  checkout `docs/handoff/PROMISE-GUARD-BIND-01/`, while `fixtures/`, `red/`, `round2-red/`,
  `round3-red/` and `report.md` live only in the lane worktree. The morphology suite resolves
  `PRE_HOOK` via `git rev-parse --show-toplevel`, so it finds the fixture inside the lane; confirm
  `fixtures/leadv2-promise-guard.pre-bind01.sh` is actually committed before merge, or the suite
  hard-fails on main. Nothing else contradicts.

## Verdict

**fail.** Round 3's two named items are done and independently proven, and the RED log is honest.
Blocking on the two High findings: the fix trades a silent-extractor bug for a false-positive class
in ordinary status prose, and it ships with a negative fixture that could never have caught it —
which also poisons the only evidence stream the BLOCK flip is gated on.
