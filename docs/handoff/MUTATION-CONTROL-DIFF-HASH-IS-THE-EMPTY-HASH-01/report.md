# MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01 — report

The quiet half of the premise is true and now fixed. The loud half is false and
I can prove it, so it is disposed of first.

| | |
|---|---|
| `ad4be1e3` | producer + consumer fixed, the dod fixture repaired, the new suite |
| *this commit* | catalog rows, the two run controls, live before/after, the invalidated list, this report |

Write set, as extended: `plugins/leadv2/scripts/leadv2-mutation-control.sh`,
`plugins/leadv2/scripts/lib/leadv2-dod-gate.sh`,
`plugins/leadv2/scripts/tests/`, `tests/mutations/catalog.yaml`,
`docs/handoff/MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01/`.
`scripts/mutation-kill-rate.sh` does not exist in this repo — that path came
from persona-engine, where the kill-rate doctrine lives.

---

## The loud claim is false: the night is valid

The row opened with "the mutation was not applied and the control was recorded
anyway". Checked all eight artifacts individually:

```
ARBITER-REMEMBERS-FAILURES-01           diff_hash=615157a5…   7d5d179a…
DARK-SUITES-UNREACHABLE-BY-RUNNER-01    diff_hash=7538506f…
PHASE-GATE-DEFAULT-CLASS-ESCAPES-IT-01  diff_hash=9b146241…
PHASE-GATE-NAMES-EVERYTHING-AT-ONCE-01  diff_hash=9c6f77d5…   ca72756f…
WRITESET-CAROUSEL-01                    diff_hash=128d007a…   4df6337d…
```

Eight artifacts, eight **real and distinct** mutation hashes. The mutation was
applied every time and every suite genuinely went red. What is void is
**identity**, not proof: the artifact still proves "this suite reddens under this
mutation" and no longer proves "it reddened ON THIS WORK".

### The measurement that nearly manufactured a crisis

My first pass reported that six of the eight had an empty `diff_hash` too — the
catastrophe in the row's title. It was a bad query: **`grep -o 'diff_hash=…'`
matches inside `lane_diff_hash=…`, because it is a substring.** The tool was
reporting the benign field as the catastrophic one. It survived exactly one
command, because the number was surprising enough to re-derive a second way.

That is the second time in a day that the *instrument* rather than the subject
produced a false finding, and both times the author caught it before the report.
Worth stating as a rule: a surprising number is a claim about your query first
and about the world second.

---

## The mechanism, in two lines and one mirror

**Producer**, `leadv2-mutation-control.sh:87-88`:

```bash
LANE_DIFF_HASH="$(git diff <base> HEAD … | shasum -a 256 …)"
if [[ -z "${LANE_DIFF_HASH}" ]]; then … exit 2; fi
```

The guard tests its own **output** instead of its **input**. `shasum` of empty
input is not an empty string — it is a perfectly well-formed hash. A guard that
checks its own output can never fire for the case it exists for.

And the case is not rare. Base resolution is
`LEADV2_LANE_START_SHA` → `main` → `origin/main`; a lane working in the
**canonical checkout** rather than on its own branch has `main == HEAD`, so the
diff is empty every single time. Not "sometimes empty" — **always, by
construction, for a whole class of lanes.** Three of the five affected lanes are
mine from earlier today, which is how I know the mechanism rather than guessing
it.

**Consumer**, `lib/leadv2-dod-gate.sh` — and this is the sharper half:

```bash
[[ "${artifact_hash}" != e3b0c442…7852b855 ]] || return 1     # guarded
[[ "${lane_hash}"     == "${expected}"     ]] || return 1     # not guarded
```

The empty-hash guard exists for the mutation hash and is **absent for the lane
hash**, which is instead compared against `expected` — a value
`_dod_worker_diff_hash()` recomputes with the same command over the same
repository. In exactly the degenerate case, both sides are that same empty-diff
hash and **compare EQUAL**.

So the check passed with maximum confidence on zero information. This is the
day's third instance of one disease, and the worst-shaped: in the arbiter,
unknown became *forbidden*; in the review gate, unknown became *permission*; here
**unknown became positive CONFIRMATION.** A gate that cannot tell what happened
did not merely wave the lane through — it certified it. The guard the case needed
was already written one line above, for its neighbour.

---

## The fix

**Producer.** `git diff --quiet` (exit 0 = no diff) tests the *diff*, separately
from the hash. The hash pipeline is left **byte-identical**, because the gate
recomputes it with the same command and the two must never drift. An empty diff
is now a refusal that says what to do:

```
leadv2-mutation-control: control_not_applied reason=empty_lane_diff base=1dc15a0f66ae
  This lane has no committed diff against its resolved base, so the artifact would carry
  the sha256 of an empty diff as its identity -- a value every such artifact shares, which
  is why it is refused rather than written.
  Set LEADV2_LANE_START_SHA=<sha of the commit before this lane started> and re-run.
```

The last line is load-bearing. Refusing here means a lane in the canonical
checkout cannot produce an artifact until it names its start commit; a refusal
without an exit is read as "the tool is broken" and routed around, and **a
bypassed guard is worse than an absent one, because it still counts.**

**Consumer.** The mirror guard: the lane hash must be a 64-hex identity and must
not be the empty-diff hash, *before* it is compared to anything.

---

## Two live runs, before and after

Same suite, same pinned tree, once without the fix and once with it
(`live-runs.log`):

```
BEFORE  pass=1 fail=5
  FAIL 1  rc=0, the tool prints "MUTATION-CONTROL ok"
  FAIL 2  an artifact with lane_diff_hash=e3b0c442… is written anyway
  FAIL 3  nothing in the output says how to resolve it
  PASS 4  with a real start sha the identity is real (670aa6f4…)
  FAIL 5  the empty-diff hash sits in an artifact as a value
  FAIL 6  empty_vs_empty=0   ← the gate ACCEPTED the empty identity

AFTER   pass=6 fail=0
```

**Case 4 is green in both columns, and green for the real reason** — the check
asked for. Its assertion is on the OUTPUT, not the exit code: it requires a
`lane_diff_hash` that is present and is not the empty hash, and the value is
**`670aa6f4…` before and `670aa6f4…` after**. Identical. The working path is
byte-for-byte what it was; the refusal does not short-circuit ahead of it.

---

## The requirements

**1. A real function under the claim.** All six cases stand up a real throwaway
git repository with a real production file and a real suite that genuinely
reddens under the mutation, and run the real `leadv2-mutation-control.sh`. Case 6
sources `lib/leadv2-dod-gate.sh` and calls the real
`_dod_valid_mutation_artifact` against real artifact files. Nothing stubs
`_mc_resolve_base`, the hash computation, the artifact writer or the verifier;
the fake is one level lower — the repository's own history shape.

The defect was reproduced **from scratch**, not read off the eight artifacts.
They could not exist and the conclusion would be unchanged.

**2. Negative controls — run, by regex, on a scratch copy:**

| control | mutation | result |
|---|---|---|
| `MUTATION-CONTROL-STAMPS-AN-EMPTY-IDENTITY` | both producer guards removed | **4 red** — 1, 2, 3, 5. Cases 4 and 6 green |
| `DOD-GATE-ACCEPTS-AN-EMPTY-IDENTITY` | the lane-hash empty guard becomes `:` | **1 red** — 6 only. Every producer case green |

**The first control failed on its first run, and that was the control working.**
Disabling only the `git diff --quiet` refusal left the suite 6/0: the property is
implemented at *two* sites (the empty-diff refusal and a belt-and-braces
empty-hash refusal), so a single-site mutation leaves the property intact. The
control now removes the **property**, not one implementation of it. Recorded
because the failure taught something the passing version would have hidden — and
because it is the same shape as our standing note that a case named for one
branch may never reach it.

**3. Catalog rows.** `mutation-control-stamps-an-empty-identity` and
`dod-gate-accepts-an-empty-identity`. Counted: **23 entries, all
`expected: killed`.**

**4. CI selection, proven from BOTH production files**, one appended comment each,
reverted in the same command:

```
CONTROL  clean tree                    4 selected
PROOF    leadv2-mutation-control.sh    6 — incl. test-mutation-control-lane-identity.sh,
                                            test-worker-dod-gate.sh
PROOF    lib/leadv2-dod-gate.sh        7 — incl. both of those and test-dod-gate-lane-state-md.sh
```

**5. Suite state, before and after.**

| suite | before | after |
|---|---|---|
| `test-worker-dod-gate.sh` | 35 / 0 | **35 / 0** (fixture repaired — see below) |
| `test-dod-gate-lane-state-md.sh` | 7 / 0 | 7 / 0 |
| `test-mutation-control-lane-identity.sh` | did not exist | **6 / 0** |

### The existing suite had pinned the defect, again

`test-worker-dod-gate.sh` went 35/0 → 31/4 on the fix. Its fixture pinned
`LEADV2_LANE_START_SHA` to a commit that **was HEAD** — the repository had
exactly one commit — so every artifact that block produced carried the empty-diff
hash, and the cases passed because the gate recomputed the same empty hash and
the two compared equal. The suite was confirming itself on zero information, in
miniature, and would have gone green again if I had relaxed the assertions.

Repaired the way a real lane is shaped: a base commit, then a lane-work commit,
with the start sha pinned **before** it. Nothing else about those cases moved,
and they are 35/0 again.

---

## What is not fixed, on purpose

- **The eight existing artifacts are listed, not repaired**
  (`invalidated-artifacts.txt`, with a header saying precisely what is void and
  what is not). A repaired identity would be a fabricated one, and we would lose
  the record of which claims were bound to their work.
- **The artifact is still forgeable by hand.** Everything here raises the floor
  on an accident; a worker that hand-writes all six fields correctly still
  passes. The gate's own comment already says so and this row does not change it.
- **`_dod_worker_diff_hash()` can still compute the empty hash** on its side; it
  simply can no longer be *matched* by one. Making the gate refuse to even
  compute an expected value in the degenerate case is a larger change to the
  gate's contract, and I did not take it inside a row about the artifact.

---

# ВЕРДИКТ (adjudication, 2026-09-06, s1) — ряд ЗАКРЫТ с названным остатком

Вердикт не опирается на этот отчёт. Каждая из четырёх проверок сделана заново.

## 1. Восемь хэшей пересчитаны своим запросом — отчёт прав

Популяция шире, чем пять строк отчёта: 28 каталогов `docs/handoff/*/mutation-control`, 92 файла.
Счёт подстрочно-безопасным способом (вычитанием, а не regexp-ом с отрицанием):

```
diff_hash=<hex>            всего 125
lane_diff_hash=<hex>       из них  62      ->  настоящих diff_hash: 63
sha пустого дерева e3b0c442…b855:  8 вхождений,
   из них в позиции lane_diff_hash: 8,  в позиции diff_hash: 0
```

**Все восемь пустых — в позиции идентичности линии, ни одного в позиции мутации.** Громкая
половина предпосылки («мутацию не применили, а контроль записали») действительно ЛОЖНА, и это
теперь измерено дважды разными людьми и разными запросами.

Мой первый счёт по этим же файлам дал ноль вхождений — regexp `(^|[^_a-z])diff_hash=` не сработал
как задумано. Ноль был мой, а не в данных; вывела вторым способом и записываю это здесь, потому
что на этом же ряде первый проход отчёта чуть не сфабриковал кризис ровно такой же ошибкой.

## 2. Код лежит на main — по ИМЕНОВАННЫМ символам, не по id ряда

```
git grep -l empty_lane_diff       main -- plugins/  -> leadv2-mutation-control.sh
git grep -l _dod_worker_diff_hash main -- plugins/  -> leadv2-mutation-control.sh,
                                                       lib/leadv2-dod-gate.sh,
                                                       tests/test-worker-dod-gate.sh
```

Плюс улика сильнее грепа: сегодня я вызвала раннер из main по другому делу и получила от него
`control_not_applied reason=empty_lane_diff` — код не просто лежит, он исполняется.

## 3. Сюиту CI ОТБИРАЕТ — доказано прогоном, а не рассуждением

`grep` по имени сюиты в `tests/run-all.sh` даёт 0, и на этом можно было бы объявить «зелёное,
которое CI не выбирает». Это был бы ложный отрицательный: отображение data-driven, а не по имени
в скрипте. Рецепт этого репозитория (`LEADV2_RUN_ALL_SELECT_ONLY` — 1 вхождение в
`~/Projects/leadv2/tests/run-all.sh`, в persona-engine его ноль) в изолированном рабочем дереве:

```
<правка leadv2-mutation-control.sh> + LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] …/tests/test-mutation-control-lane-identity.sh     <- отбирается
run-all: 6 selected, scope=changed, select_only=1
```

## 4. Различие удержано: идентичность защищена ВПЕРЁД, но не восстановлена НАЗАД

Правка делает пустой diff линии отказом, поэтому новый артефакт с пустой идентичностью появиться
не может. Восемь СТАРЫХ артефактов никуда не делись: они лежат в дереве сегодня и по-прежнему
доказывают «эта сюита краснеет от этой мутации», но не «она покраснела на этой работе». Ничто их
не помечает, и следующая сессия прочтёт их как обычные. Строка заведена:
`MUTATION-ARTIFACTS-WITH-A-VOID-IDENTITY-ARE-UNLABELLED-01`.

## Дефект, найденный в сюите самого ряда — и починенный

Случай 5 утверждал: «sha пустого диффа никогда не появляется как идентичность линии **в любом
артефакте**», а проверял два фикстурных каталога, которые сюита создала сама. В живом дереве в
этот момент лежало восемь таких артефактов. Предложение шире своего предмета — это то, как часовой
начинает считаться доказательством того, на что он не смотрел. Плюс у случая не было парного
негатива: проверка ОТСУТСТВИЯ, неспособная увидеть присутствие, зелена над любым деревом.

Сузила формулировку до того, что она проверяет, и добавила 5b: подложить артефакт с пустой
идентичностью и потребовать, чтобы его увидели. 7/0. Объявленная мутация (ослепить проверку
отсутствия) убита и валит ровно 5b.

**Ряд закрыт.** Не закрыто и названо: восемь артефактов с пустой идентичностью не помечены.
