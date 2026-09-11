verdict: APPROVE
next_action: review_round_2

Fixed both architect-prepass wrapper defects in `leadv2-dispatch-code.sh`: D1 (valid artifact ignored on race) via a bounded 2s poll before declaring failure; D2 (timeout not enforced against escaped descendants) via recursive `pgrep`-based descendant kill, since `os.killpg` alone cannot reach a grandchild that calls `os.setsid()`.

- RED/GREEN reproductions run through the real dispatcher for both defects (evidence in full.md).
- Two new tests added, both shown RED pre-fix / GREEN post-fix.
- Fixed a real bash `$(...)`+heredoc quoting bug I introduced along the way (apostrophes break parsing there).

Full: full.md
