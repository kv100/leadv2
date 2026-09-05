REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=0 high=1 medium=5 low=6

FINDING: severity=High file=docs/handoff/LEADV2-HOOK-CACHE-DEPLOY-01/report.md line=30 dimension=design desc="macOS `sort` has no `-V`" is an untagged, evidence-free, decision-driving platform claim — and it is FALSE on the target machine (verified: `/usr/bin/sort --version` → "2.3-Apple (199)"; `printf '0.9.0\n0.10.0\n0.3.0\n' | sort -V` → 0.3.0/0.9.0/0.10.0, rc=0).

## High (1) — detail

The claim drives the fallback implementation (hand-rolled `-t. -k1,1n -k2,2n -k3,3n` keys instead of `sort -V`). The implemented sort is itself correct and the suite regresses it (d1 fallback passed in my run), so there is no code bug — but under this lane's evidence contract an untagged decision-driving external claim is BLOCKING, and this one is provably wrong, which is worse. Fix: either carry the probe artifact (`sort --version` + a `-V` ordering run) or delete the parenthetical; the code needs no change.

## Medium (5)

1. **Fail-open fallback on inconsistent installPath** — `plugins/leadv2/scripts/leadv2-plugin-cache-sync.sh:113-118` (resolution step 2). If `installed_plugins.json` exists and names a `leadv2@` entry whose installPath is missing on disk, the script silently falls back to the highest numeric dir, syncs there, and prints `synced=N` — a green deploy into a dir Claude Code does not load. That is exactly the invisible-stale-cache defect class this lane exists to close; the report itself stresses "only installPath is authoritative" (verified live: 0.5.7, lastUpdated 2026-09-01T23:00:10.973Z). Should BLOCK on "meta names installPath X but X absent", not guess.
2. **Stale round-1 evidence presented as current, contradicting the round-2 correction** — report.md §Test results item 3 (~line 91): the pasted deploy.sh e2e output says "NOTE: plugin hooks/commands/agents load from the cache on the NEXT session", but the rewritten deploy.sh says "the hook LIST (hooks.json) loads…" and round-2 probe (b) proved bodies load from the repo. The paste asserts a claim the author's own probe falsified, with no round-1 marker. Census of same shape in the deliverable: (a) this paste; (b) the table's "13 asserts" (final suite is 16 — verified by running it: 16 passed, 0 failed); (c) the `leadv2-hook-session-kind.sh` mid-flight caveat (~line 51) is now moot — BEAT-LOOP-ORPHANS-01 landed at 38be66c and the file is present in this tree.
3. **Wrong git attribution in the sync-script header** — `leadv2-plugin-cache-sync.sh:~45`: "deleted in the repo at 2d6c9b4" for all six zombie hooks. Verified: only `leadv2-plugin-sync-drift-warn.sh` was deleted at 2d6c9b4; the five supervisor scripts were deleted at c312ac8 and 517bc13 (`git log --diff-filter=D` per file). report.md line 116 attributes correctly — the header does not.
4. **Untested safety paths (tests-can-fail census)** — the suite covers the happy paths and c1-c2 fail-closed, but none of: (i) CACHE-REFUSAL exit 3 (advertised in the report table as script behavior — never exercised; testable via `HOME=$tmp` fixture); (ii) rsync-failure BLOCK (exit 1 branch); (iii) non-git source BLOCK (`REPO_HEAD` empty); (iv) malformed `installed_plugins.json` (python `except: pass` → silent fallback — same shape as finding 1, also unprobed).
5. **`.synced-from`/deletion under-reporting in the success line** — `N_SYNCED` counts only `^>f` itemize lines; deletions (`*deleting`) and attribute-only changes are invisible in `synced=<n>`. A future reader auditing "what did the deploy change" gets half the answer. (Informational, but it is the operation's only audit line.)

## Low (6)

1. `a1` does not assert rc=0 — the rc appears only inside the label string; the check matches `synced=` in output. Same shape in `b3` (`rc=$rc2` label-only).
2. Duplicate assert IDs: `d1`/`d2` used for both the hooks.json pair and the fallback pair — the mutation output ("FAIL: d1: hooks.json…") is ambiguous against the suite text.
3. `--exclude='hooks.bak-*'` matches at any depth, so a legitimately repo-side file named `hooks.bak-*` will never sync (acceptable, declared intent, but unstated).
4. `--delete` removes cache-only `.mypy_cache`/`.pytest_cache` on every deploy — the report enumerates them as cache extras yet presents the exclusion list as "protecting cache-only paths"; regenerable, so informational.
5. CACHE-REFUSAL checks only `${HOME}/.claude/plugins/cache/*`, not `${LEADV2_PLUGIN_CACHE_ROOT}` — a script copy under an env-overridden cache root is not refused.
6. run-all.sh row is correct (verified: `plugins/leadv2/scripts/*.sh` reaches the stem loop at tests/run-all.sh:391-397, key `leadv2-plugin-cache-sync.sh` matches `stem.sh`, and no `test-leadv2-plugin-cache-sync.sh` exists) — no finding; noted as checked.

## Verified live this review (evidence for the checks above)

- Suite green on this machine: `LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-plugin-cache-sync.sh` → `[TEST] 16 passed, 0 failed`, rc=0, under openrsync (`rsync --version` → "openrsync: protocol version 29") — so `--itemize-changes`/`--delete`/`--exclude` all work here.
- `installed_plugins.json` → installPath 0.5.7, cache root holds 0.1.0/0.3.0/0.5.7 (matches report).
- Zombie claim: all six named scripts present in 0.3.0 cache, absent from repo; repo 93 hooks vs cache 99 (matches report).
- `leadv2-plugin-sync.sh` ~line 130 hardcodes `CACHE_TARGET=…/0.1.0` (report's related finding confirmed).
- deploy-merge override BLOCK exists where cited; `~/.claude/settings.json:12` pins CLAUDE_PLUGIN_ROOT exactly as claimed.

Everything else in the diff's evidence trail held up under live re-probing — the probes are genuinely measured, and the one unverifiable claim (hook LIST parsed only from the cache) is properly UNVERIFIED-tagged.

---

FINISH CONTRACT: no stash created; review-only session — zero files modified, so NOT-COMMITTED (nothing to commit; the artifact under review, `docs/handoff/LEADV2-HOOK-CACHE-DEPLOY-01/build-attempt-2.diff`, was only read). Test results above are from my own runs this session, all quoted verbatim.
