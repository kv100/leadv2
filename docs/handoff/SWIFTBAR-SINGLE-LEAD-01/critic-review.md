# SWIFTBAR-SINGLE-LEAD-01 — critic review

Verdict: **BLOCK**

## Critical

1. **Legacy lanes rendering is NOT byte-compatible — violates hard invariant #1.**
   `plugins/leadv2/scripts/leadv2-status-surface.sh:1235` adds a new fallback inside
   `resolve_name()`: when `LEGACY_MODE` is true (supervisor active) and no `task_id`/
   `lane_label` exist, it now reads `mission.md`/`architect-prepass.md`/`context.yaml`
   under `HANDOFF_DIR/dispatch-<sig8>/` and derives a name from file content, instead
   of falling through to the pre-existing final line `return "unnamed"` (confirmed via
   `git show HEAD:...` — that line was the unconditional terminal case before this diff,
   for *both* modes). This is new behavior gated specifically on `LEGACY_MODE`, i.e. it
   changes the output of the untouched "supervisor active" path for any row lacking
   `task_id`/`lane_label`. The mission explicitly required legacy lanes to stay
   byte-compatible when supervisor is on; this diff breaks that for exactly the rows
   it claims to protect. Fix: either gate this fallback out of legacy mode entirely
   (single-lead-only) or get explicit sign-off that legacy output is allowed to change,
   and add a regression test proving old vs new output diverges/matches as intended.

2. **Single-lead title can silently fall back to legacy title logic on any renderer
   failure — violates the fail-loud invariant.** `render_single_lead()`
   (`leadv2-status-surface.sh:2588`) pipes its output through a bare
   `python3 2>/dev/null <<PYEOF ... PYEOF` with no exit-code check, and the caller
   (`all)` case, `leadv2-status-surface.sh:2726-2733`) doesn't check it either. If that
   python3 invocation fails for any reason (binary missing from SwiftBar's minimal
   `PATH=/usr/bin:/bin` — Apple no longer ships `/usr/bin/python3` on recent macOS,
   heredoc/runtime error, etc.), `render_single_lead` prints nothing. In
   `leadv2-status-surface.10s.sh:170-171`, `_sl_hdr` is then empty, the
   `case "$_sl_hdr" in mode=single-lead*)` test misses, `WIDGET_SINGLE_LEAD=0`, and the
   script falls straight into the OLD legacy `⚠ > ❓ > 🔴 > 🟢 > ⚪` title block below
   line ~173 — even though the repo is genuinely in single-lead mode. That block reads
   `SUP_ON`/lane counts that make no sense in single-lead context and will render a
   confident (wrong) title instead of the promised `⚠ ledger не прочитан`. This is
   the exact "silent `2>/dev/null` swallowing that fakes idle/green" failure class the
   mission called out. Fix: `render_single_lead` must emit an unambiguous sentinel
   (or the caller must check `$?`) and the surface script must treat "single-lead mode
   active but section 6 empty/malformed" as `⚠`, never fall through to legacy title
   logic.

3. **No fixture test was added — acceptance criteria not met.** `git diff --stat -- '*test*'`
   is empty; no file under `plugins/leadv2/scripts/tests/` or `tests/` was touched.
   Mission acceptance explicitly requires: "fixture test — craft a tmp snapshot+ledger,
   run render+surface, assert single-lead title glyphs for: no-dispatch idle, active
   dispatch, questions>0, broken ledger → ⚠." None of the four scenarios exist in any
   test, including the specific ⚠-on-corrupt-ledger case that finding #2 shows is
   currently broken. `test-status-surface-bash32.sh` 11/0 passing is pre-existing
   legacy coverage and proves nothing about this diff.

## High

4. **Collector's new `single_lead` snapshot section is dead code with its own,
   divergent mode-detection logic.** `leadv2-status-collector.sh:129-179` computes
   inclusion from `.supervise-active` file presence ONLY (no `active.yaml`
   sessions-empty check). `leadv2-status-surface.sh`'s `SINGLE_LEAD` (lines ~463-491)
   is `.supervise-active` absent **OR** sessions empty — per mission requirement #1.
   These two computations will disagree (e.g. `.supervise-active` present but
   sessions empty → surface.sh says single-lead, collector omits the section).
   It doesn't matter today because nothing reads it: `render_single_lead()` in
   surface.sh explicitly bypasses the collector snapshot and re-reads the ledgers
   itself (comment at `leadv2-status-surface.sh:2586-2587`), and `render_repo_facts`
   only reads the pre-existing `repo_facts` key. So this ~53-line collector addition
   is unused, untested surface area with logic that will silently drift from the
   thing it's supposed to mirror. Either wire it in or drop it.

## Medium

5. **`render_single_lead` reads both ledger files with no line cap**
   (`leadv2-status-surface.sh:2596-2617`, unbounded `for line in fh` scan of
   `LEDGER_FILE` and `${STATE_DIR}/dispatch-ledger.jsonl`).
   The existing lanes reader explicitly caps at `tail -n 400` with a comment noting the
   ledger "grows unbounded." Here, a single malformed line anywhere in the full history
   (not just recent) permanently trips `⚠ ledger unreadable` until manually cleaned, and
   the widget re-reads the entire file every 10-second SwiftBar tick. Add the same
   bounded-tail treatment for both perf and blast-radius parity with the rest of the file.

## Low

6. `leadv2-status-render.sh` is listed in the mission's WRITE SET but was not touched —
   worth a one-line note in the handoff on why (not itself a defect, just confirm it was
   intentional and not a missed requirement).

## Evidence
- `bash -n` clean on all 3 changed files.
- `git diff --stat -- '*test*'` → empty (no test changes).
- `git show HEAD:plugins/leadv2/scripts/leadv2-status-surface.sh` confirms pre-diff
  `resolve_name()` unconditionally returned `"unnamed"` as the final case.

DELIVERABLE_COMPLETE

## Re-review (2026-08-03)

Verdict: **PASS**

- C1 confirmed fixed: `leadv2-status-surface.sh:1247` gates the handoff-derived
  name fallback on `not LEGACY_MODE` — legacy path falls straight to the
  unconditional `return "unnamed"` at line 1278, byte-compatible with the
  pre-diff HEAD. `test-status-surface-bash32.sh` R5-C1 now asserts BOTH sides
  (legacy=`unnamed`+no title leak, single-lead=resolved title) — a real
  strengthening, not a weakening, of the prior assertion.
- C2 confirmed fixed: `render_single_lead()` (surface.sh:2600-2686) always
  emits a `mode=single-lead...` prefixed line on every exit path — python3
  missing (2604-2606), in-heredoc `fail()` (2615-2617, exits 0 after
  printing), and heredoc/runtime crash (`if ! ... ; then` at 2684, printed by
  the wrapper). `leadv2-status-surface.10s.sh:171` matches on the
  `mode=single-lead*` prefix alone, so `WIDGET_SINGLE_LEAD=1` is set on the
  failure path too, and line 175's `*"active ⚠"*` substring check routes to
  the `⚠️ ledger не прочитан` title — the legacy title block below is
  structurally unreachable once `WIDGET_SINGLE_LEAD=1`. Verified live: the
  new fixture test flips `PATH` to a python3-less dir and gets the ⚠ title.
- M1 confirmed: both ledger reads in `render_single_lead` go through
  `tail_lines()` (surface.sh:2629-2639), capped at `tail -n 400`, matching the
  existing lanes-reader convention.
- H1 confirmed wired, not dead: collector's `single_lead` section is consumed
  by `leadv2-status-render.sh:133-154` (periodic status output) and by
  `leadv2-status-surface.10s.sh:116-117,167` (widget). Mode predicate is
  computed once in `SINGLE_LEAD`/`LEGACY_MODE` (surface.sh:467-529) and
  threaded through as data — collector no longer runs a second, divergent
  mode check for anything that's actually read.
- `git status --short`: only the 4 status scripts + 2 test files touched, no
  out-of-scope files.
- Both test files pass live: `test-status-surface-bash32.sh` 11/0/0,
  `test-status-surface-single-lead.sh` 6/0 (idle, active, questions,
  malformed-ledger ⚠, no-python3 ⚠, render.sh consumes snapshot — all
  mission-required fixture scenarios plus render.sh wiring covered).
- No new findings. Prior BLOCK findings 1-5 all resolved; finding 6 (Low,
  render.sh untouched) is now moot — render.sh was touched as part of H1.

DELIVERABLE_COMPLETE
</content>
