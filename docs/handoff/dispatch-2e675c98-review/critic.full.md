# Round-1 EXHAUSTIVE adversarial review — 98ce586 (CLAIM-EVIDENCE-GATE-01)

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/d784b987`
Commit: `98ce586` — `feat(review): CLAIM-EVIDENCE-GATE-01 …`
Reviewer: critic (round 1, exhaustive, five lenses incl. the diff's own new lens 5)

## REVIEW_VERDICT: FAIL
## REVIEW_FINDINGS: critical=0 high=2 medium=5 low=6

---

## 0. Mission-contract results (what was asked, what was proved)

| # | Contract item | Result | Evidence |
|---|---|---|---|
| 1 | UNVERIFIED-tag contract lives in the LIVE preamble source and is actually injected | **PARTIAL — see H1** | Preamble bullets ARE in the rendered worker prefix; the SKILL.md §11 half is NOT |
| 2 | Fifth lens inside the ROUND-1 exhaustive branch, no round/arm logic changes | **PASS** | `leadv2-review-run.sh:703-706` (exhaustive branch only); diff touches only `printf` lines |
| 3a | `test-claim-evidence-gate.sh` runs, red-first, not tautological | **PARTIAL — see M1** | 10 passed / 0 failed / 0 green-pre-fix; C6 is a genuine rendered-output probe, C1 is not |
| 3b | `run-core-offline.sh` = 53/0 | **PASS** | `suites passed=53 failed=0 missing=0`, exit 0 |
| 4 | `leadv2-dispatch-product-close.sh` untouched; no new env vars | **PASS** | not in `--stat`; `LEADV2_TEST_BASELINE_REF` pre-exists in 3 sibling tests |
| 5 | Apply lens 5 to the diff itself | **DONE — see M4** | 2 untagged external-system claims found |

---

# CRITICAL

None.

---

# HIGH (blocking)

## H1 — `SKILL.md` §11 never reaches a dispatched worker prompt; half the deliverable is lying-green
**Category:** correctness / lying-green (rule-without-a-reader)
**Files:** `plugins/leadv2/skills/leadv2-subagent-protocol/SKILL.md:186-196` (added §11)
· `plugins/leadv2/scripts/claude-subsession.sh:285,294-295,306-308`

The commit sells "UNVERIFIED-tag contract **in subagent protocol**". `build_cached_prefix()`
composes the worker prefix from `role_body + SHARED_PROTOCOL_BOILERPLATE + "Protocol reference:" +
skill_body`, where:

```
plugins/leadv2/scripts/claude-subsession.sh:285
  local skill_file="$PROJECT_ROOT/.claude/skills/leadv2-subagent-protocol/SKILL.md"
```

That path does not exist in any live repo:

```
$ for r in persona-engine m3-market respiro-ios; do ls -d "/Users/…/Projects/$r/.claude/skills/leadv2-subagent-protocol"; done
ls: …/persona-engine/.claude/skills/leadv2-subagent-protocol: No such file or directory
ls: …/m3-market/.claude/skills/leadv2-subagent-protocol: No such file or directory
ls: …/respiro-ios/.claude/skills/leadv2-subagent-protocol: No such file or directory
```

Line 295 fails open to empty:

```
$ out=$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2 {print}' /nonexistent/SKILL.md 2>/dev/null \
        || printf '%s' "$(cat /nonexistent/SKILL.md 2>/dev/null || true)"); echo "skill_body_len=${#out}"
skill_body_len=0
```

Rendered-artifact proof — I ran the real script against the real repo root:

```
$ PROJECT_ROOT=/Users/…/Projects/persona-engine LEADV2_DRY_RUN=1 \
    bash …/plugins/leadv2/scripts/claude-subsession.sh --role critic --model sonnet \
    --task-id CEGPROBE --mission-file /tmp/ceg-probe/m.md --wait
[claude-subsession] stable prefix materialised for critic → /tmp/leadv2-cache/prefix-critic.90e77ad41552bb31927c2a110681383c.md
[DRY_RUN] subsession spawn: role=critic model=sonnet task=CEGPROBE

$ P=/tmp/leadv2-cache/prefix-critic.90e77ad41552bb31927c2a110681383c.md
$ wc -c < $P                                             # 6707
$ grep -c "EVIDENCE CONTRACT" "$P"                       # 1   ← preamble bullets land
$ grep -c "Evidence contract for external-system claims" "$P"   # 0   ← SKILL.md §11 does NOT
$ grep -n "Protocol reference:" "$P"; tail -5 "$P"
71:Protocol reference:
…
---

Protocol reference:                                       ← file ENDS here; body is empty
```

So the entire "Protocol reference" block that this diff extended has been an empty section in every
headless worker prompt, in all three live repos. The operative bullets in
`claude-subsession.sh` do land (that is why this is High, not Critical), but §11 — the text the
commit message and the deliverable name as the contract's home — is inert on the dispatch path.
It only reaches Agent-tool subagents via the Claude Code skill loader
(`~/.claude/plugins/local/leadv2/plugins/leadv2 -> ~/Projects/leadv2/plugins/leadv2`), i.e. once
this lands on `main` — never the `claude -p` workers `/leadv2` actually dispatches.

**Required fix (pick one, in the same commit):**
1. Resolve `skill_file` from the plugin root when `$PROJECT_ROOT/.claude/skills/…` is absent
   (`${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/skills/leadv2-subagent-protocol/SKILL.md`),
   AND fail loudly (stderr warn + non-zero-ish log line) when `skill_body` resolves empty — silent
   fail-open is what hid this; **or**
2. Drop the §11 SKILL.md hunk from this commit and say plainly that the contract lives only in
   `SHARED_PROTOCOL_BOILERPLATE`, so no one else builds on a section no worker reads.
   Either way add the rendered-prefix assertion in M1.

## H2 — The lens BLOCKS on a contract the primary code writer never receives
**Category:** product-invariant / contract asymmetry
**Files:** `plugins/leadv2/scripts/leadv2-review-run.sh:705` (new rule)
· `plugins/leadv2/scripts/leadv2-dispatch-code.sh:2532, 2696`
· `plugins/leadv2/scripts/glm-coder.sh:106-111, 229`

Round-1 review now declares:

```
leadv2-review-run.sh:705
  …An untagged evidence-free claim that DRIVES a decision -- a code path, a config value,
  a limit, a retry policy -- is a BLOCKING finding.
```

But only the `sonnet`/`opus` arm goes through `claude-subsession.sh` and therefore only that arm's
worker ever sees the EVIDENCE CONTRACT. The GLM / Kimi / Codex arms get the raw mission text:

```
$ grep -n "GLM_BIN\|CODEX_BIN" plugins/leadv2/scripts/leadv2-dispatch-code.sh | sed -n '…'
2532:  out="$(LEADV2_COSTLOG_ARM=glm-coder bash "${GLM_BIN}" bg "${mission}" --cwd "${WORK_ROOT}" …)"
2696:  out="$(bash "${CODEX_BIN}" task "${mission}" --background --cwd "${WORK_ROOT}" …)"

$ grep -n "resolved_prompt=" plugins/leadv2/scripts/glm-coder.sh
229:    resolved_prompt="${AGENT_BAN_PREAMBLE}${resolved_prompt}${FINISH_CONTRACT_TRAILER}"

$ grep -rn "subagent-protocol\|EVIDENCE CONTRACT" plugins/leadv2/scripts/leadv2-dispatch-code.sh \
        plugins/leadv2/scripts/glm-coder.sh
(no matches)
```

`AGENT_BAN_PREAMBLE` (`glm-coder.sh:107-111`) and `FINISH_CONTRACT_TRAILER` (`:102-105`) are the
only wrappers; neither carries the evidence contract. Per GLM-FIRST-01 GLM is the **primary** code
writer, so the common case is: worker never told to tag → reviewer BLOCKS for a missing tag. That
is a rule with no reader on the writing side and a hard gate on the reading side — the exact
failure shape the founder's `feedback_rule_without_reader_is_not_a_rule` memory names.

**Required fix:** either (a) prepend the same evidence-contract text to the mission for the
glm/kimi/codex arms (cheapest: a shared `LEADV2_EVIDENCE_CONTRACT` heredoc in
`leadv2-helpers.sh`, appended in `spawn_worker` before the arm switch, so all four arms get one
inode of truth), or (b) downgrade the untagged-claim finding to MEDIUM until every arm is covered,
and say so in the rule text. Do not ship the BLOCKING severity while coverage is one arm of four.

---

# MEDIUM

## M1 — C1 is a source-file grep of the file just edited; the preamble half has no rendered-output probe
**Category:** test coverage / tautology
**File:** `plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh:65-70, 105`

```
65 case_c1_preamble_evidence_contract() {
67   local f="${scripts_dir}/claude-subsession.sh"
69   grep -q 'EVIDENCE CONTRACT' "${f}" && grep -q 'UNVERIFIED:' "${f}"
```

C6 (`:138-190`) does the right thing for the review half — it invokes the real engine and greps the
**generated** `review-mission-sonnet.md`. C1 has no counterpart: it only asserts the string exists
in the source file the author just edited. The red-first harness makes it non-trivially red against
`559cf15`, which is the only thing saving it from being fully tautological — but "the string is in
the file" is not "the string is in the prompt", and that gap is exactly H1. A C7 that ran
`LEADV2_DRY_RUN=1 claude-subsession.sh` and grepped `/tmp/leadv2-cache/prefix-*.md` would have
failed and surfaced H1 before commit. I proved that probe works (see H1 evidence).

**Required fix:** add C7 — dry-run `claude-subsession.sh` with `PROJECT_ROOT` set to a scratch repo,
capture the `stable prefix materialised … → <path>` line, and assert the prefix file contains BOTH
`EVIDENCE CONTRACT` and the §11 heading. Run it through `run_case` so it is red-first too.

## M2 — Failure path emits no diagnostic, and aborts on bash 3.2
**Category:** correctness (test harness)
**File:** `plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh:196-200`

```
197 if [[ "${FAIL}" -gt 0 || "${GREEN_PRE_FIX}" -gt 0 ]]; then
198   printf -- 'FAIL: %s\n' "${ERRORS[@]}"
```

A green-pre-fix-only failure never appends to `ERRORS`, so the suite goes red with an empty reason:

```
$ LEADV2_TEST_BASELINE_REF=HEAD bash plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh
[TEST] GREEN-PRE-FIX: preamble-evidence-contract -- passed against baseline too (pre_rc=0)
[TEST] GREEN-PRE-FIX: exhaustive-five-lenses -- passed against baseline too (pre_rc=0)
Results: 8 passed(red->green), 0 failed, 2 green-pre-fix, 0 could-not-run
FAIL:                       ← no reason at all
```

Worse, under `set -u` on macOS system bash the same line aborts instead of printing:

```
$ /bin/bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
$ /bin/bash -c 'set -uo pipefail; E=(); printf -- "FAIL: %s\n" "${E[@]}"'
/bin/bash: E[@]: unbound variable
```

The test's own C5 case explicitly asserts bash-3.2 syntax compatibility of the *subject* scripts
(`:34-38`) while the test itself is 3.2-unsafe at runtime. The repo already uses the safe idiom
(`leadv2-dispatch-code.sh:4283` — `"${phase_waivers[@]+"${phase_waivers[@]}"}"`).

**Required fix:** `printf -- 'FAIL: %s\n' "${ERRORS[@]+"${ERRORS[@]}"}"`, and push the green-pre-fix
case name into `ERRORS` at `:97-99` so a red run always names its cause.

## M3 — Off-mission hunk: a byte-identical duplicate of a commit already on `origin/main`
**Category:** scope / process
**File:** `plugins/leadv2/scripts/tests/test-supervise-v2.sh:264-275`

```
$ git merge-base --is-ancestor 512ecda HEAD; echo $?    → 1 (NOT an ancestor)
$ git branch -a --contains 512ecda
+ main
  remotes/origin/HEAD -> origin/main
  remotes/origin/main
$ git show 512ecda --stat --oneline | head -2
512ecda fix(tests): supervise-v2 3b — symlink the fake claude instead of copying …
 plugins/leadv2/scripts/tests/test-supervise-v2.sh | 8 ++++++--
$ diff <(git show 512ecda -- …/test-supervise-v2.sh | tail -n +6) \
       <(git show 98ce586 -- …/test-supervise-v2.sh | tail -n +6) && echo IDENTICAL
IDENTICAL
```

It merges cleanly (identical both sides), so this is not a correctness break — but a supervise-v2
tmux fix has nothing to do with CLAIM-EVIDENCE-GATE-01, and the lane copied it instead of rebasing
onto `origin/main`. `git log --graph` will show the same change twice.

**Required fix:** rebase this lane onto `origin/main` (which already carries `512ecda`) and drop the
duplicate hunk, so the commit contains only its own subject.

## M4 — Lens 5 applied to this diff: two untagged, evidence-free external-system claims that drive a code path
**Category:** claims-without-evidence (the diff's own new rule)
**File:** `plugins/leadv2/scripts/tests/test-supervise-v2.sh:267-271`

```
267   # symlink, NOT a copy: macOS SIGKILLs a copied Apple-signed binary
268   # (signature/path mismatch, rc=137), so the fake claude died instantly and
269   # 3b failed deterministically. Through a symlink the kernel execs the
270   # original signed file while ps comm reports the symlink path ("…/claude"),
272   ln -sf "$(command -v sleep)" "$repo/claude"
```

Two claims about an external system (macOS code signing; `ps -o comm` semantics). Neither carries a
probe artifact, neither is prefixed `UNVERIFIED:`, and together they drive a code-path change
(`cp` + `chmod 700` → `ln -sf`). By `leadv2-review-run.sh:705` as written by this very diff, that is
a BLOCKING finding. I held it at Medium because I ran the probes the author owed and **both claims
are true**:

```
$ cp "$(command -v sleep)" cpprobe/claude && chmod 700 cpprobe/claude && ./cpprobe/claude 1
copied-binary rc=137
$ ln -sf "$(command -v sleep)" cpprobe/claudelink && ./cpprobe/claudelink 1
symlink rc=0
$ uname -m; sw_vers -productVersion
arm64
26.5.1
$ ./cpprobe/claudelink 8 & sleep 0.4; ps -o pid=,comm= -p $!
15185 ./cpprobe/claudelink
```

**Required fix:** inline those three lines of probe output into the comment (or the commit body).
The rule the same commit introduces must be honoured by the same commit, or round-1 reviewers get a
worked example of the exact violation they are told to block.

## M5 — Preamble states the BLOCKING consequence unconditionally; enforcement exists only in round 1
**Category:** contract accuracy
**File:** `plugins/leadv2/scripts/claude-subsession.sh:250-252`

```
251   untagged evidence-free external-system claim is a protocol violation, and reviewers
252   treat one that drives a decision as BLOCKING.
```

Not true of round 2+. `_review_build_contract`'s `verify_only` branch carries no lens text, and the
test explicitly pins that purity (`test-claim-evidence-gate.sh:108-117`, C3). `SKILL.md:192-194`
gets it right — "Round-1 review checks for this under the `claims-without-evidence` lens". The
preamble, which is the text workers actually read (H1), is the one that overstates.

**Required fix:** `…and round-1 reviewers treat one that drives a decision as BLOCKING.`

---

# LOW

## L1 — Dangling protocol pointer in the live preamble
`plugins/leadv2/scripts/claude-subsession.sh:253` — `- See full protocol:
.claude/skills/leadv2-subagent-protocol/SKILL.md`. That path exists in zero of the three live repos
(proof in H1). Every worker is pointed at a file it cannot open. Fix with H1.

## L2 — Terminal baseline fallback is `HEAD`, which guarantees a red suite instead of a valid floor
`test-claim-evidence-gate.sh:56` — `[[ -n … ]] || LEADV2_TEST_BASELINE_REF="HEAD"`. With no
`origin/main` ref (fresh clone / CI without the remote), the baseline becomes the fix commit and
every content probe reports GREEN-PRE-FIX → exit 1 (demonstrated in M2). The sibling
`test-review-round-exhaustive.sh:503` pins a SHA (`85ae886`) for exactly this reason; the cited
model (`test-review-gate-scope-evidence.sh:238`) has the same weakness, so this diff propagates it.
Fix: fall back to `559cf15`, matching the pin already on line 53.

## L3 — C4's quote/backtick guard leaves the sibling changed line unguarded
`test-claim-evidence-gate.sh:125` greps only `claims-without-evidence|Claims-without-evidence rule`.
Line `leadv2-review-run.sh:704` (`printf 'Review this diff through FIVE lenses:\n'`) is also new and
also flows into `--focus "…${review_contract_focus}…"` at `leadv2-review-run.sh:322`, a
double-quoted string where a backtick would command-substitute. Widen the pattern to
`FIVE lenses|claims-without-evidence`.

## L4 — Baseline extraction self-nullification guard checks only one of the two subject files
`test-claim-evidence-gate.sh:52` greps `claims-without-evidence` in `leadv2-review-run.sh` only. If
a future baseline gains the preamble half without that exact marker in the review file, the guard
does not fire and C1 goes green-pre-fix. Also grep `EVIDENCE CONTRACT` in `claude-subsession.sh`.

## L5 — `PREFIX_DIR` leaks on the FATAL and interrupt paths
`test-claim-evidence-gate.sh:47` creates it; `:193` removes it, but `:60-61` `exit 1` and any signal
skip the cleanup. Add `trap 'rm -rf "${PREFIX_DIR}" "${c6_stub_dir:-}" "${c6_root:-}"' EXIT INT TERM`.

## L6 — C6 is not red-first (informational)
`:138-190` runs only against `SCRIPT_DIR`, so it cannot report green-pre-fix; every other content
probe goes through `run_case`. Acceptable (the engine invocation is expensive), but note it: if the
lens text is ever removed, C6 fails — which is the important direction — yet it can never prove the
probe was meaningful pre-fix.

## L7 — SKILL.md edit invalidates every cached role prefix once (informational)
`build_cached_prefix` checksums `role_body + boilerplate + skill_body`. Both edited inputs change
the checksum, so `/tmp/leadv2-cache/prefix-<role>.<sum>.md` regenerates for every role on first use
and server-side prompt caching misses once per role. One-time, no action needed. (Note the irony:
because of H1 the SKILL.md half does not actually change the checksum — only the preamble does.)

---

# Raw probe output

## Type checkers
The diff contains **no Python and no TypeScript** — five bash files only. `mypy --strict` and
`npx tsc --noEmit` are not applicable; the equivalent static gate is `bash -n` on both bash
generations plus `shellcheck`:

```
$ for f in claude-subsession.sh leadv2-review-run.sh tests/run-core-offline.sh \
           tests/test-claim-evidence-gate.sh tests/test-supervise-v2.sh; do …; done
plugins/leadv2/scripts/claude-subsession.sh                    bash5:OK bash3.2:OK
plugins/leadv2/scripts/leadv2-review-run.sh                    bash5:OK bash3.2:OK
plugins/leadv2/scripts/tests/run-core-offline.sh               bash5:OK bash3.2:OK
plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh       bash5:OK bash3.2:OK
plugins/leadv2/scripts/tests/test-supervise-v2.sh              bash5:OK bash3.2:OK

$ shellcheck -S warning plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh; echo "rc=$?"
rc=0
```

## `bash plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh` (executed, from the worktree)

```
[TEST] PASS: bash -n claude-subsession.sh
[TEST] PASS: /bin/bash -n claude-subsession.sh (bash 3.2 syntax)
[TEST] PASS: bash -n leadv2-review-run.sh
[TEST] PASS: /bin/bash -n leadv2-review-run.sh (bash 3.2 syntax)
[TEST] RED-then-GREEN: preamble-evidence-contract (pre_rc=1 -> post_rc=0)
[TEST] RED-then-GREEN: exhaustive-five-lenses (pre_rc=1 -> post_rc=0)
[TEST] PASS: verify_only branch does not contain claims-without-evidence
[TEST] PASS: exhaustive branch new text has no quote/backtick
[TEST] PASS: preamble evidence bullets have no quote/backtick
[TEST] PASS: rendered round-1 mission contains claims-without-evidence lens

Results: 10 passed(red->green), 0 failed, 0 green-pre-fix, 0 could-not-run
RC=0
```

Red-first baseline actually resolved (not a no-op): `git merge-base origin/main HEAD` =
`559cf15419a72afee9c4b0b2045063db0ec63d83`, which is `HEAD~1` and pre-dates the fix — both content
probes were genuinely red against it (`pre_rc=1`). The commit-comment claim
"pinned floor is 559cf15 (HEAD immediately before this lane)" is **verified**:

```
$ git log --oneline -3
98ce586 feat(review): CLAIM-EVIDENCE-GATE-01 …
559cf15 fix(tests): PLUGIN-CORE-OFFLINE-4RED-01 …
b18aca3 feat(beat): BROAD-STATUS-RELAY-SCOPE-01 …
$ for r in 9e03dc0 8cc6bf8 85ae886 559cf15; do git cat-file -t $r; done
commit commit commit commit          ← every SHA cited in the new comments resolves
```

## `bash plugins/leadv2/scripts/tests/run-core-offline.sh` (executed, from the worktree)

```
[TEST] PASS: T21: legacy CLAUDE_SESSION_ID still populates LEAD_SESSION (fallback preserved)

25 passed, 0 failed

[CORE-OFFLINE] suites passed=53 failed=0 missing=0 repo=/Users/…/.claude/worktrees/d784b987
exit code 0
```

53/0 as claimed. `test-supervise-v2.sh` (the M3 hunk) is inside that green.

---

# Pre-finalize contradiction scan

| Check | Result |
|---|---|
| New env vars introduced? | **None.** `LEADV2_TEST_BASELINE_REF` pre-exists in `test-review-round-exhaustive.sh:496`, `test-review-verdict-recovery.sh:169`, `test-review-gate-scope-evidence.sh:229`. Contract item 4 satisfied. |
| `leadv2-dispatch-product-close.sh` touched? | **No.** Absent from `git show 98ce586 --stat`. |
| Flag semantics vs other usages | No flags added or changed. `REVIEW_MODE` / `REVIEW_ROUND` semantics untouched — the diff edits only `printf` payloads inside the existing `else` (exhaustive) branch. |
| Round-detection / arm-selection logic changed? | **No.** `_review_round_context`, `_review_state_write`, `resolve_review_pool_call`, fan-out list — all byte-identical. |
| Path existence: `.claude/skills/leadv2-subagent-protocol/SKILL.md` (referenced `claude-subsession.sh:253, 285`) | **CONTRADICTION — missing in persona-engine, m3-market, respiro-ios.** Raised as H1 / L1. |
| Path existence: SHAs cited in new comments (`559cf15`, `9e03dc0`, `8cc6bf8`, `85ae886`) | All resolve to commits. |
| Path existence: `test-review-gate-scope-evidence.sh:229-242` (cited as the pattern source) | Exists and matches the described shape. |
| Test registered in every runner that needs it | Only one registry (`run-core-offline.sh:227`); `grep -rln test-review-round-exhaustive plugins/` confirms no second aggregate runner. No census gap. |
| `512ecda` relationship to this branch | **CONTRADICTION — on `origin/main`, not an ancestor of HEAD; hunk duplicated byte-for-byte.** Raised as M3. |

---

# Verdict

**FAIL** — 2 High findings block the commit.

The review-side half (lens 5 in the round-1 exhaustive branch) is correctly placed, correctly
scoped, and genuinely proved by a rendered-output test (C6). The worker-side half is half-delivered:
the preamble bullets reach `claude`-arm workers, `SKILL.md` §11 reaches nobody on the dispatch path
(H1), and the GLM/Kimi/Codex arms — the primary code writers — reach nothing at all while the new
lens BLOCKS their diffs for it (H2). Fix H1 + H2, add the rendered-prefix probe (M1) so the next
regression is caught by the suite rather than by a reviewer, and the rest is mechanical.

DELIVERABLE_COMPLETE
