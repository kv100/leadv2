# SWIFTBAR-SINGLE-LEAD-01 — retune menu-bar widget for single-lead mode

Repo: ~/Projects/leadv2 (canonical plugin). Base: current main HEAD. Founder-approved shared edit.

CONTEXT: supervisor/fanout mode is PAUSED (persona-engine docs/leadv2/single-lead-mode.md). The SwiftBar chain (leadv2-status-collector.sh → status-snapshot.json → leadv2-status-render.sh → leadv2-status-surface.sh → leadv2-status-surface.10s.sh) renders supervisor lanes. With supervisor off it shows noise/⚠.

WRITE SET (only these): plugins/leadv2/scripts/leadv2-status-surface.10s.sh, leadv2-status-surface.sh, leadv2-status-render.sh, leadv2-status-collector.sh.

REQUIREMENTS:
1. Mode detection: single-lead when `<state-dir>/.supervise-active` absent OR active.yaml sessions list empty; else legacy lanes view unchanged.
2. Single-lead view sections (dropdown order): (a) ACTIVE dispatch — newest non-terminal row of `~/.claude/leadv2-state/<repo>/dispatch-ledger.jsonl`: task sig, arm/channel, state, age; "none" when all terminal; (b) repo facts — render ALL keys the snapshot's repo_facts section carries (generic key: value lines, no repo-specific logic in plugin); (c) SD due/overdue (existing section, keep); (d) provider limits/quotas (existing limits section, keep); (e) pending questions (existing, keep).
3. Title priority single-lead: ⚠ parse-broken > ❓N questions > 🔴 (any repo_facts key ending `_alarm` truthy) > 🛠 active dispatch present > ⚪ idle.
4. Preserve fail-loud invariants: unreadable ledger/snapshot renders ⚠ title, never a confident ⚪/🟢 (lying-green rule in surface.10s comments).
5. Collector: add dispatch-ledger tail + supervise-active flag into snapshot (new `single_lead` section); guard so one failing section never kills the snapshot.

NON-GOALS: no per-repo facts content here; no reply-router changes; no launchd/cron changes.

ACCEPTANCE: bash -n all 4 files; fixture test — craft a tmp snapshot+ledger, run render+surface, assert single-lead title glyphs for: no-dispatch idle, active dispatch, questions>0, broken ledger → ⚠. Return PASS|FAIL + changed paths + test output. Do NOT commit; leave diff in tree.

Rollback: git checkout of the 4 files.
