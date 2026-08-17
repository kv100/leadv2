# Founder status format — the contract every status surface must satisfy

Founder decision, 2026-08-17. This is not a style preference: he read a hand-written status in this
shape and asked for it to be what the plugin itself produces, in every repo. Anything that renders a
status for a human — `leadv2-broad-status.sh`, the pulse beat, a lead's `/leadv2` status reply — obeys
this file.

## The table

Exactly three columns:

| линия | что делает | состояние |
|---|---|---|

- **`линия` is a human name, never a hex id.** «Браузерная дверь», «Уборщик готовых черновиков»,
  «Ложные блокировки провайдеров», «T3, богатый промпт». Take it from the mission title. The dispatch
  id is diagnostic detail — it belongs in the artifact's detail lines, never in the founder's first
  column. **Names stay stable across beats** so one line can be followed through time; a lane that
  changes its name between pulses reads as a different lane.
- **`что делает` is one plain sentence about the product effect**, not the file being edited.
  «8 из 18 потерянных постовых слотов выкошены с готовым текстом» — not
  «правит prefill-drafter.sh».
- **`состояние` is one short honest phrase**: `пишет` · `диффа готова, идёт ревью` · `стартует` ·
  `ревью провалено, правит` · `молчит N мин`.

Below the table: a short ranked queue (only what changed rank or is next), **one** delta line, **one**
blockers line (or «вопросов нет»).

## The rules that make it true rather than merely pretty

1. **A pulse is a delta, not a ledger.** Only what is live and what is next. Never re-list finished
   rows. Every relayed status is permanent conversation context re-sent on every later turn, so a
   chatty status is paid on every turn that follows, not once.
2. **Evidence, never self-report.** Lane state comes from stream mtime, live worker pids, `git status`
   in the worktree, and the review gate — never from what a lane says about itself. Lane verdicts have
   repeatedly been wrong in both directions (`no_work` while a diff existed; `terminal=landed` with an
   empty worktree).
3. **A plugin lane's work is in `~/Projects/leadv2`, not in the repo worktree.** The review gate reads
   only the repo worktree, so a plugin lane falsely reads `no_work`. Any status surface must check the
   plugin repo too, or it will report real work as nothing.
4. **A row with no worktree is not a lane.** `leadv2-lane-detail.sh:227-231` returns nothing when the
   registry's worktree path is gone, which degrades the row to `(dispatch id unknown) / неизвестно`.
   Reconcile such rows — tombstone or prune — never render them as ghost lanes. This is what broke the
   status on 2026-08-17 after a 111 → 4 worktree cleanup: eleven-day-old rows survived in the registry
   with their worktrees deleted.
5. **Never present a rendering artifact as a fact.** If a field is genuinely unknown, the status says
   so about *that field* — it does not fill the row with «неизвестно» and pass it off as knowledge.
6. **The plugin owns the beat; the lead relays it verbatim.** The lead must not compose a status or
   schedule its own timer. Before relaying, compare the ready-line's `at=` stamp with the timestamp on
   line 1 of the artifact — if they differ, publish *that fact*, not the stale file.

## Why the shape matters

The founder does not read dispatch ids, file paths, or phase names. He reads: which lines are alive,
what each will change about the product, and whether anything needs him. A status that requires him to
translate hex ids into meaning is a status he will stop reading — and a status nobody reads is the same
as no status, except it costs tokens on every turn.
