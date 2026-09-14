verdict: APPROVE
next_action: continue

No published Anthropic per-model quota weight exists (checked CLI accounting, live probe, API docs, unified headers); nested windows DO vary — 62% of intervals show unexplained quota drain, not model mix.

- New tool `leadv2-anthropic-window-compare.py` + hermetic test (11/11 pass, self-registered) proves ratio 5h/7d unstable (mean 3.83, range 0-9, n=9) and 123/199 intervals move with zero tokens attributed to ANY known account.
- Calibration path designed: costs ~150K tokens/tick (7d) to ~19K (5h), low-100Ks to low-millions total, multi-day, double-digit% error — real but not cheap.
- `test-arbiter-prices-by-provider.sh` does not exist anywhere in repo history — reported, not fabricated.
- All named regression suites green; no price written anywhere.

Full: full.md
