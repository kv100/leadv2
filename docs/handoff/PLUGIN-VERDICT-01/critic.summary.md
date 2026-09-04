# PLUGIN-VERDICT-01 — critic summary

**Do not rewrite.** ~20% of 500 fix commits (90d) are language-caused (hand sample n=42, CI 17-45%). `shellcheck --severity=error` finds **0** issues in the 5 most-fixed files. In-repo Python already runs at 4.2 fixes/1kLOC vs bash 3.8 — no better.

- Real cause: `leadv2-dispatch-code.sh` = 8,405 LOC, 102 fixes, 12.1/1kLOC = 3.2x repo rate.
- CI runs **zero** test suites (1 workflow, lints SKILL.md front-matter). 2 of 315 suites have a real negative control.
- Highest leverage: one CI job running `tests/run-all.sh --scope all`.

Full: critic.full.md
