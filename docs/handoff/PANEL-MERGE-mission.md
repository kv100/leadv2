# PANEL-TWO-IMPLEMENTATIONS-MERGE-01 — one classifier, two renderers, and a parity test so they can never drift again

**Repo for this work: `~/Projects/leadv2` (the plugin source), not persona-engine.**

## Where this stands

The status surface has TWO independent lane renderers, and only one of them has been fixed.

- **Fixed (leadv2 `89217a1`, 2026-08-04):** the single-lead path. `_ss_lanes_py`'s classify chain
  now recognises a ledger-only worker row in pending/queued/reserved with no pid and no exit code as
  `queued`, excludes it from live and dead counts, and the table header appends `, N queued` only
  when there are any (byte-identical output when zero).
- **NOT fixed:** the `--all` / menu-bar widget path, which is `render_single_lead` — a separate
  ~570-line heredoc carrying its OWN census, reservation and terminal indices.

Four of the six defects in the founder's panel screenshot live only on the unfixed path:

1. `MENUBAR-PANEL-02 · · · worker` — three empty fields rendered as an unbroken run of separators,
   while the menu-bar TITLE of that same lane shows `glm 16m`. The data exists; the row does not use
   it. **An empty field must never render its separator.**
2. `sig b12e69cc` as a second row under a lane that already shows its name — pure duplication that
   doubles the height of every named lane.
3. Names truncated mid-word: `VOICE-CUSTOMER-CONTROL-0`, `VOICE-PAGE-SCROLL-AND-WE`. Truncate on a
   separator with an ellipsis, or shorten from the middle — **never** cut so that `-CONTROL-0` reads
   as a different task id than `-CONTROL-01`.
4. Five `⚠ <repo> terminals unreadable` rows filling nearly half the panel.

## Founder requirements, 2026-08-04 21:31 — these override the earlier wording of defects 1 and 4

Taken from his own screenshot of the live panel. The rest of the panel he calls fine, so do not
redesign anything else.

- **Delete the `⚠ … terminals unreadable` family outright.** Not collapse it, not put it behind an
  expander — remove it. His words: it is unclear what it even means and why it is there. If that
  condition ever needs surfacing it belongs in a log, not in a menu the operator reads at a glance.
- **Do not show lanes that are not active.** The screenshot's only body row is
  `VOICE-PAGE-SCROLL-AND-WE · queued · sonnet 1h · persona-engine` — a lane that is finished, and the
  menu-bar TITLE carries it too (`VOICE-PAGE-SCROLL-AN sonnet 1h`). Both the title and the body must
  show only genuinely running lanes. When none are running, say so in one plain line rather than
  padding the panel with dead rows.
- Note that the row FORMAT is now correct on this path (`queued · sonnet 1h · persona-engine`
  renders its fields) — defect 1's empty-separator symptom is fixed. Keep the assertion so it cannot
  come back, but the visible problem is now the two bullets above.

## What to build

**The parity test is the deliverable, not the merge.** A merge alone just resets the drift clock;
these two renderers have already diverged once and produced a panel the founder called wrong.

1. Move the census into the shared classify chain so there is ONE source of truth for what a lane
   is.
2. Rewrite `render_single_lead` as a projection over that shared classification — presentation only,
   no independent census, no second reservation index, no second terminal index.
3. Add `tests/test-status-surface-parity.sh` asserting both paths produce the **same
   classification** for at least 10 lane shapes. Cover, at minimum: live worker with pid; live worker
   without pid; terminal `landed`; terminal `dead`; terminal `no_work`; ledger-only `queued`;
   `reserved`; a lane whose repo ledger is unreadable; a lane with a missing model field; a lane with
   a name longer than the column.
4. Fix defects 1-4 above on the now-shared path, each with its own assertion.

A previous worker returned `DELIVERABLE_BLOCKED` rather than half-merge two 600-line
implementations. That was the right call — it is why this task exists with its own budget. Do not
repeat the shortcut it refused; if the merge genuinely does not fit, deliver the parity test against
the CURRENT two implementations (it will fail, and that failure is a real artifact) and say so.

## Done means

- `tests/test-status-surface-parity.sh` exists, covers >=10 lane shapes across both renderers, green.
- `test-status-surface-single-lead.sh` 23/0, `test-status-surface-bash32.sh` 15/0,
  `test-status-surface-fast-names.sh` 12/0 — all still green.
- A row missing a field emits no separator for it; a terminal lane is neither counted nor listed;
  queued backlog rows are not counted as live; a long name truncates without producing a string that
  could be mistaken for a different task id.
- **The `terminals unreadable` warning family is gone from the panel entirely**, with a test that
  fails if any such row is ever emitted again.
- **Only running lanes appear, in both the menu-bar title and the panel body**, with a test covering
  the all-lanes-finished case (one plain line, no dead rows) and the mixed case (running shown,
  finished hidden).
- Run the status-surface suites only. Do NOT run `run-core-offline.sh`.

## Constraints

- No commit, no push. The lead merges.
