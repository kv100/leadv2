verdict: APPROVE
next_action: review_round_2

Installer now refuses to write env keys into a git-tracked `.claude/settings.json`; routes to `settings.local.json` instead.

- `env_py()` in `leadv2-repo-install.sh` targets `_lv2_settings_target()` (new), which checks `git ls-files --error-unmatch` per-repo.
- New suite `test-repo-install-tracked-settings.sh`, registered in `tests/run-all.sh` EXTRA_SUITE_MAP (one row, appended at end).
- Negative control (mutation inside `_lv2_settings_is_tracked` body) verified RED/GREEN on macOS + a linux container.

Full: developer.full.md
