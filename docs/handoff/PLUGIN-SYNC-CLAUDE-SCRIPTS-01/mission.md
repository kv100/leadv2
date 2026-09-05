# Mission — plugin-sync must keep `<repo>/.claude/scripts` from drifting

Repo: ~/Projects/leadv2 (plugin source; the only place this is fixed).
File: `plugins/leadv2/scripts/leadv2-plugin-sync.sh`, section (c) around L459-505
and the (c2) curated block around L505-545.

## The defect, measured 2026-08-23 (not a hypothesis)

`~/Projects/persona-engine/.claude/scripts/` holds **227 symlinks and 62 real files**,
of which **28 are real `leadv2-*` copies of canonical plugin scripts** — every one of
them a silently-drifting second inode. Canonical has 195 `leadv2-*.sh`.

Two distinct failures produce that state:

1. **Missing links are never created.** `leadv2-lanes-snapshot.sh`,
   `leadv2-lanes-resume.sh` and `leadv2-provider-rollup.sh` were absent from
   `.claude/scripts/` in persona-engine AND respiro-ios. `leadv2-status-collector.sh`
   (which IS linked there) resolves its siblings from its own directory
   (`_SC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, then
   `bash "$_SC_DIR/leadv2-lanes-snapshot.sh" --json` at :115), so the collector died
   and every founder-status beat printed "НЕ ВИЖУ ЛИНИИ" — the board looked empty when
   it was not. The lead symlinked those three by hand this session; the sync must be
   what does it. Note `leadv2-plugin-sync.sh:532`'s curated list DOES name
   `leadv2-lanes-snapshot.sh`, but that list targets `<root>/scripts/` (top-level, c2),
   NOT `.claude/scripts/` — so it never covered the collector's actual home.
2. **New canonical files land as real copies, not symlinks.** Section (c) rsyncs the
   whole canonical `scripts/` into `.claude/scripts`, `--exclude`-ing only the symlinks
   that ALREADY exist. A canonical script with no pre-existing link is therefore written
   as a real file — and from then on it drifts. This is the mechanism behind all 28.

## Required behaviour

For every repo in `~/.claude/leadv2-shared/cross-repo-paths.yaml` whose
`.claude/scripts/` is per-file-symlink-managed, after a sync run:

- every canonical plugin script that the repo needs is present **as a symlink to
  canonical** — missing ones get created;
- a **real file that is byte-identical to canonical is converted to a symlink**
  (that is a resolved drift, not a local override);
- a **real file that DIFFERS from canonical is left alone and reported loudly** as a
  drift/override needing a human — never silently overwritten, never silently linked
  over. Print path + a one-line diffstat for each.
- repo-native scripts (no canonical counterpart) are untouched. `.claude/scripts` is a
  mixed directory in every repo — that is by design, do not "clean" it.
- rsync must never materialize a real copy of a canonical script into a
  symlink-managed tree again. If keeping rsync for this section makes that guarantee
  hard, replace section (c)'s write path for canonical-named files with explicit
  per-file symlinking; rsync may stay for genuinely non-canonical payloads.

Add `--dry-run` output that lists exactly what would be linked / converted / reported,
so the founder can inspect before anything is written.

## Verify (required in the report, real output, not claims)

1. `--dry-run` against persona-engine and respiro-ios: paste the plan.
2. Real run, then re-count: `find <repo>/.claude/scripts -maxdepth 1 -type f -name 'leadv2-*' | wc -l`
   must drop to only genuinely-diverging files, each named in the report with its diffstat.
3. `bash .claude/scripts/leadv2-status-collector.sh` (or the lanes-snapshot path it
   calls) still runs in persona-engine after the sync — paste the first lines of output.
4. Run twice in a row: the second run must be a no-op (idempotent). Paste both.
5. Plugin test suite (`plugins/leadv2/scripts/tests/`) pass/fail counts verbatim, plus
   a new test covering: missing link created, identical copy converted, diverging copy
   preserved + reported.

## Off-limits

- Do not delete anything in any repo's `.claude/scripts`.
- Do not touch `~/.claude/scripts` (section e) or the leadv2 repo's own vendored tree
  (section f) in this mission.
- m3-market has no `.claude/scripts/` at all — do not create one.
- Do not change hook manifests or any other script's behaviour.

## Deliverable

`docs/handoff/PLUGIN-SYNC-CLAUDE-SCRIPTS-01/report.md` — the mechanism you changed with
file:line, the five verifications above with real pasted output, the list of diverging
files left for the founder, and `git diff --stat`. End with DELIVERABLE_COMPLETE.
