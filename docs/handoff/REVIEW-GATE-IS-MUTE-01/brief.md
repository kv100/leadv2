# REVIEW-GATE-IS-MUTE-01 — a failed review arm says `rc=1` and nothing else, and `blocked` reads like a pass

**Class:** Standard. **Repo:** leadv2 plugin. **Filed:** 2026-09-02 by the persona-engine lead, from a
cross-repo report by the getmany-followup-bot lead (their items И-2 and И-3, handed over).

## Two defects, one file

### 1. A provider failure produces no diagnosis
`leadv2-review-run.sh:1630-1631` writes:
```
review_gate status=blocked reason=provider_error rc=1 arm_rc=opus=1
```
and that is the entire record. The arm's stderr file is empty, so the round silently did not happen and
nobody can say why. Reported twice in getmany-followup-bot; the pool resolved correctly both times
(`pool=codex:blocked:100,glm:ok:5,opus:ok:21,sonnet:author:`), so the failure is inside the arm launch.

Not reproducible in persona-engine / the plugin repo: the opus arm ran three times today through the same
engine — STATUS-CHURN-01 `arms: opus status: pass`, GLM-EFFICIENCY-01 `arms: opus status: fail`
(1 critical + 2 high), WORKER-MCP-ALL-ARMS-01 `arms: opus status: fail` (4 high). No `provider_error` in
any gate here. So the environment differs — but **the muteness is the plugin's defect regardless**: the
engine must never report a failed arm without a cause, because the reader cannot tell "provider down"
from "quota exhausted" from "launcher missing".

Required:
- capture the arm's stdout+stderr head and tail (say 20 lines each) into
  `docs/handoff/<task>/review-arm-<arm>.err` and quote the first non-empty line in the gate;
- print a `remedy:` line the way the phase-precondition refusal already does (which command to run to
  diagnose: quota probe, launcher symlink check, profile check);
- classify at least: `quota_exhausted`, `launcher_missing`, `profile_no_subscription`, `unknown`.
  The three suspects, in likelihood order, from the cross-repo triage: (a) the Claude subscription window
  is exhausted for child sessions while in-session agents still work; (b) `claude-subsession.sh` in that
  repo's `.claude/scripts/` is a REAL COPY instead of a symlink and has drifted (a known killer, see
  `reference_claude_scripts_stale_copies_break_dispatch`); (c) the repo runs child sessions under a Claude
  profile with no active subscription.

### 2. `status: blocked` reads like a pass
`blocked` sits in the same field as `pass` and `fail`, in the same shape, and a hurried reader takes it as
"gate cleared". Two lanes here hit `blocked` today (`reason=review_roundcap`) and both needed a human to
notice. The gate must make a non-verdict unmistakable: a leading marker line (e.g. `NO VERDICT — <reason>`)
before the `status:` line, and the same word in the journal decision.

## Done when
- a forced arm failure (stub the launcher to `exit 1`) produces a gate carrying the arm's first error line,
  a classification and a `remedy:`; negative control: remove the capture → the gate goes back to mute and
  the suite goes red;
- a `blocked` gate is visually unmistakable from `pass` in both the file and the journal line;
- both cases have EXTRA_SUITE_MAP rows proven with `--scope changed`.
