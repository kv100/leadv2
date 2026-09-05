T12 — honest profile registry (LEAD-FINAL-FIXES-01, canonical leadv2 repo). Base: main.

Problem: the claude-profile selector trusts the SLOT LABEL as identity, so when both slots were logged into the same personal account (happened 2026-08-26: label said team/max_5x, actual account was personal max_20x), team usage was written into the personal bucket and tier weighting was garbage. Slots are now distinct again (default=vkk1008k personal max_20x; ~/.claude-work=mythical.games team) — build the code so a future relabel/relogin cannot lie.

Scope (find the real files first: plugins/leadv2/scripts/leadv2-claude-profile-select.sh + whatever writes usage buckets / reads subscriptionType):
1. Identity derived FROM the credential at selection time: read oauthAccount.emailAddress (+ subscriptionType when present) from the selected CLAUDE_CONFIG_DIR's .claude.json; the slot label is display-only.
2. Usage bucketing keys on the derived account identity, never the label.
3. WARN loudly (journal + selector stdout) when: two slots resolve to the SAME account; a slot's derived identity differs from its label; the default token is expired/absent. Fail-open: selection still proceeds (availability > purity), the warning is the product.
4. Tests: fixture config dirs with .claude.json files — (a) same-account-in-both-slots triggers the warn and buckets once; (b) label/identity mismatch warns and buckets by identity; (c) missing .claude.json = fail-open with warn. Negative control: mutate the identity-derivation line, show red.

Constraints: bash -n; no behavior change to which profile gets SELECTED (ordering logic untouched); commit on the lane branch.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-db335a0d" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.