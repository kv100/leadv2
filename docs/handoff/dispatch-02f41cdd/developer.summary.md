verdict: APPROVE
next_action: continue

CI now runs `tests/run-all.sh` on push/PR (`--scope changed`) and nightly (`--scope all`), gated by a 15-entry known-red allow-list that can only shrink.

- `.github/workflows/test-suites.yml` (macos-latest, real `/bin/bash` 3.2) + `tests/ci-gate.sh` (names failures, non-allow-listed = blocking) + `tests/known-red-suites.txt` + `tests/known-red-guard.sh` (fails if the list grows).
- Proved: break→red+named, fix→green, negative control (remove step → undetected), guard (fake entry → fails). All pasted in full.md.
- Branch-protection "require status checks" is a GitHub setting I cannot make from here — named explicitly, not silently assumed done.

Full: developer.full.md
