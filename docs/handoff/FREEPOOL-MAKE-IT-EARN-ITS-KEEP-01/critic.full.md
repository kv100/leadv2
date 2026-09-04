# Adversarial review, round 2 — FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01 @ 8c5db82

**fail**

Reviewed the lane at `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01`,
diff `origin/main...HEAD -- plugins/ tests/` (10 files, +737/−32). The proxy at
`127.0.0.1:8317` was live for this review (`/v1/models` → `http=200 time=0.019`), so every
selector claim below is a live measurement, not a code read. Platform: `GNU bash, version
3.2.57(1)-release (arm64-apple-darwin25)`.

`mypy --strict` / `npx tsc --noEmit` are N/A — the diff is 100 % shell + YAML. The equivalent
static gate was run on every changed shell file:

```
OK  plugins/leadv2/scripts/freepool-coder.sh
OK  plugins/leadv2/scripts/leadv2-dispatch-code.sh
OK  plugins/leadv2/scripts/lib/leadv2-freepool-model-select.sh
OK  plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh
OK  plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh
OK  plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh
OK  plugins/leadv2/scripts/tests/test-freepool-model-selector.sh
OK  plugins/leadv2/scripts/tests/test-worker-output-gate.sh
OK  tests/run-all.sh
```

All mutations below were applied to a scratch copy of the lane's `plugins/`+`tests/` tree
(`scratchpad/r2`), never to the lane. No lane source was edited.

---

## 1. Content-based liveness probe — **WORKS**

Suite green as shipped:

```
$ bash plugins/leadv2/scripts/tests/test-freepool-model-liveness.sh
[TEST] PASS: bash syntax: selector
[TEST] PASS: content probe: 200+blank primary rejected, secondary (real text) chosen
[TEST] PASS: content probe: blank route logged as probe failure, not silently skipped
[TEST] PASS: mutation applied: _probe reverted to status-code-only check (scratch copy)
[TEST] PASS: MUTATION KILLED: status-only probe wrongly picks the blank-body route
=== 5 passed, 0 failed ===
```

My own mutation, inside `_probe`'s body on the production file (not the author's scratch-copy
control — I neutralised the real assertion at
`lib/leadv2-freepool-model-select.sh:238`, `[[ "${has_content}" == "1" ]]` →
`[[ "${has_content}" == "1" || "${has_content}" == "0" ]]`), anchor matched, suite went RED:

```
mutation applied: content assertion neutralised
238:  [[ "${has_content}" == "1" || "${has_content}" == "0" ]]
[TEST] FAIL: content probe: 200+blank primary rejected, secondary (real text) chosen (rc=0 chosen=anthropic/nvidia_nim/deepseek-ai/deepseek-v4-pro-0813)
[TEST] FAIL: content probe: blank route logged as probe failure, not silently skipped
=== 3 passed, 2 failed ===
SUITE_RC=1
```

The author's own control is scratch-copy-based, which is one of the fake-control shapes — but it
is paired with Case 1, which runs the **production** file against the same fixture, so a broken
production file cannot satisfy the suite. That pairing is what makes it real, and my independent
production mutation confirms it. The underlying trap is real and reproduced independently:

```
== groq/openai/gpt-oss-120b tokens=1  ms=194   ...content":[{"type":"text","text":" "}]... HTTP=200
== groq/openai/gpt-oss-120b tokens=64 ms=2278  ...content":[{"type":"text","text":"OK"}]... HTTP=200
```

## 2. Selector end to end — **BROKEN** (the report's headline is false on the path that dispatches)

`report.md` line 1: *"Tomorrow the free arm will run on `groq/openai/gpt-oss-120b` first."*
It will not. `FREEPOOL_ROLE` unset defaults to `implement`
(`lib/leadv2-freepool-model-select.sh:82`), and `lib/leadv2-admission-class.sh:99` maps
`build|diagnose → implement`, which `leadv2-dispatch-code.sh:4727` exports. Measured live, cold
cache, one run per role:

```
role=implement rc=0 elapsed_s=34
    probe failed for "anthropic/nvidia_nim/moonshotai/kimi-k3", advancing rank
    chosen="anthropic/nvidia_nim/nvidia/nemotron-3-super-120b-a12b" probe_ms=3933
role=bulk      rc=0 elapsed_s=1   chosen="anthropic/groq/openai/gpt-oss-120b"
role=review    rc=1 elapsed_s=90
    probe failed for "anthropic/nvidia_nim/nvidia/nemotron-3-ultra-550b-a55b"
    probe failed for "anthropic/nvidia_nim/moonshotai/kimi-k3"
    probe failed for "anthropic/gemini/models/gemini-3.7-flash"
    all ranked candidates failed their liveness probe
role=read      rc=0 elapsed_s=1   chosen="anthropic/groq/openai/gpt-oss-120b"
```

Reproduced twice (unset role and explicit `FREEPOOL_ROLE=implement`, both 34–35 s).
`groq/openai/gpt-oss-120b` — the bakeoff winner and the report's headline model — **does not
appear in `role_rank.implement` at all**; that block is kimi → nemotron → gemini → mistral
(`config/freepool-arm.yaml`, implement block, prefixes verified). So the bakeoff's fastest,
correct route is excluded from the exact role the 2026-08-30 incident hit.

Per-spawn latency cost: **~34 s on every implement dispatch**, of which ~30 s is the
guaranteed-failing kimi probe. Direct confirmation that kimi cannot pass a probe at all:

```
== nvidia_nim/moonshotai/kimi-k3 tokens=64 ms=45046 |HTTP=000
```

## 3. Bakeoff — **UNPROVEN as a ranking basis** (transcripts are real; the task cannot rank)

The transcripts are genuine, not assertions: distinct `msg_` ids, distinct `usage.output_tokens`
(groq 94, nemotron 128), real proxy envelope shapes, deepseek's `.response.json` genuinely empty.
`nemotron` **was** included as the brief required, and passed.

But four of the five passing candidates emitted byte-identical output:

```
$ md5 *.candidate.sh
720130d83c057d2b80391af4674c4599  gemini_models_gemini-3.7-flash.candidate.sh
720130d83c057d2b80391af4674c4599  groq_openai_gpt-oss-120b.candidate.sh
2405de80a176013a1923f8cec2bca2bc  mistral_mistral-code-latest.candidate.sh
720130d83c057d2b80391af4674c4599  nvidia_nim_moonshotai_kimi-k3.candidate.sh
720130d83c057d2b80391af4674c4599  nvidia_nim_nvidia_nemotron-3-super-120b-a12b.candidate.sh
```

A four-line `greet()` that every candidate produces identically discriminates on **latency
only**. `report.md` §3 and `freepool-arm.yaml:39-53` claim the list is "ordered by measured
correctness first" — the transcripts do not support that; correctness was a 5-way tie. This is
the "fixture chosen because it already passes" shape. The thing that actually failed on
2026-08-30 was three multi-file agentic missions; nothing here measures that.

## 4. Output gate — **BROKEN** (correct on files, crashes on the production call shape)

Direct feed, broken `.sh` + broken `.py`, both rejected:

```
worker_output_gate_reject file=broken.sh tool=bash-n
.../broken.sh: line 2: syntax error: unexpected end of file from `if' command on line 1
worker_output_gate_reject file=broken.py tool=py_compile
  File ".../broken.py", line 1
    def f(:
          ^
SyntaxError: invalid syntax
rc=1
```

My production mutation (`lib/leadv2-worker-output-gate.sh:45`, `if ! err="$(bash -n …)"` →
`if false`) turned the suite RED, and the suite's own anchor check hard-failed rather than
skipping:

```
FAIL: broken sh: expected reject, got rc=0 out= --
FAIL: --from-git-diff: expected reject, got rc=0 out= --
mutation anchor not found -- zero-match, hard failure
FAIL: mutation replace failed -- anchor text drifted -- zero-match
PASS=4 FAIL=3
```

The gate's *logic* is sound. Its *wiring* is not — see Critical-1/2/3 below.

## 5. Arbiter honours the router's exclusion set — **WORKS**

Green as shipped (`PASS=4 FAIL=0`). My mutation on the production dispatch file
(`leadv2-dispatch-code.sh:6664`, removed `"allowed_arms":allowed` from the descriptor):

```
mutation applied: allowed_arms key removed from arbiter descriptor (production file)
mutated file parses
PASS: (green) router still excludes freepool for a light task (when=standard,bulk)
FAIL: (green) arbiter picked freepool despite router exclusion
mutation anchor not found -- zero-match, hard failure
FAIL: (red) mutation anchor not found in production file -- cannot prove the control
PASS=2 FAIL=2
```

The founding defect is genuinely fixed and the control is falsifiable. (The suite's *file
placement* is a separate finding — High-7.)

## 6. `--scope changed` — **WORKS for `.sh`, BROKEN for the yaml**

Dirty scratch git tree, selection listed via a list-only variant of `run-all.sh` (the real run
was abandoned after `run-core-offline.sh` exceeded 10 min — unrelated pre-existing cost):

```
dirty = lib/leadv2-freepool-model-select.sh  -> SELECTED: tests/test-freepool-model-liveness.sh
dirty = freepool-coder.sh                    -> SELECTED: test-freepool-model-selector.sh,
                                                          test-worker-output-gate.sh,
                                                          test-freepool-model-liveness.sh
dirty = leadv2-dispatch-code.sh              -> SELECTED: test-arm-capability-honoured.sh
dirty = config/freepool-arm.yaml (ONLY)      -> SELECTED: <nothing freepool-related>
```

---

# Findings

## Critical

**C-1 — `plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh:70-75` — bash 3.2 unbound array kills every committed run.**
`local -a files=()` then `worker_output_gate_check "$repo_root" "${files[@]}"` under `set -u`.
On bash 3.2.57 an empty array expansion is an unbound-variable fatal:

```
$ /bin/bash -c 'set -u; a=(); echo "count=${#a[@]}"; echo "expand=[${a[@]}]"'
count=0
/bin/bash: a[@]: unbound variable
```

Live, on the gate itself, against a clean repo whose work is committed:

```
$ bash leadv2-worker-output-gate.sh "$T" --from-git-diff HEAD
leadv2-worker-output-gate.sh: line 75: files[@]: unbound variable
gate_rc=1
```

`freepool-coder.sh:1536-1540` treats *any* nonzero rc as `reason="parse_error"` and writes
`LEADV2_WORKER_NO_DELIVERABLE`. The lane protocol mandates "Commit before you stop", so a worker
that commits leaves `git diff HEAD` empty — and **every clean, successful, committed free-arm run
is falsely flagged as a parse error.** This is the opposite of the commercial goal and it is
newly introduced by this round's wiring.
Fix: guard before the call — `if [[ ${#files[@]} -eq 0 ]]; then return 0; fi` (bash 3.2 evaluates
`${#files[@]}` safely under `set -u`), and add a test case for the zero-file path.

**C-2 — `plugins/leadv2/scripts/freepool-coder.sh:1536` — the gate is blind to the incident it cites.**
The invocation is `--from-git-diff HEAD`, i.e. working tree vs HEAD. It cannot see committed
changes. The gate's own header (`leadv2-worker-output-gate.sh:8-10`) names the motivating
incident as "a `bash -n`-failing test suite **committed four times**" — which this invocation
provably cannot catch:

```
$ git status --porcelain          # clean, broken.sh is committed
$ git diff --name-only --diff-filter=ACMR HEAD
                                  # empty -> gate has zero files to check
```

Fix: diff against the run's baseline head, which `deadhand_check` already has —
`work_delta_present` reads `head=` from `${run_dir}/.workbase` at `freepool-coder.sh:1463`. Use
`git diff --name-only <base_head>` (base..worktree), not `HEAD`.

**C-3 — no test covers the production call shape.** `test-worker-output-gate.sh:70` exercises
`--from-git-diff --cached` only. Neither `--from-git-diff HEAD` (the shape production uses) nor
the empty-diff branch has a case. Two new logic branches, zero coverage — that is what let C-1
and C-2 ship green.

## High

**H-4 — `report.md:1` is false for the dispatching path.** Headline names
`groq/openai/gpt-oss-120b`; the code path that a `build` dispatch takes selects
`nemotron-3-super`. The mission's Done-means clause was explicitly "a `report.md` whose first
line states which model the free arm will actually run on tomorrow". Measured answers:
implement → `nvidia_nim/nvidia/nemotron-3-super-120b-a12b` (34 s), bulk/read → groq (1 s),
review → nothing. Fix: correct line 1 to name the per-role truth, and put groq into
`role_rank.implement` — the round's own evidence says it is the fastest correct route, and the
role that omits it is the role that failed.

**H-5 — `config/freepool-arm.yaml`, `role_rank.implement` primary `kimi-k3` can never pass the
probe.** Probe timeout default is 30 s (`leadv2-freepool-model-select.sh:24`); the report's own
bakeoff clocks kimi at 67 s; my direct 64-token probe returned `HTTP=000` after 45 s. A model
whose real latency exceeds the probe timeout is a guaranteed 30 s tax on every implement spawn
and can never be selected. The report keeps it primary with the justification "still the
best-independently-benchmarked agentic coder AND it passed the round-2 bakeoff" — that reasoning
is unreconciled with the probe it just shipped. Fix: demote kimi below nemotron (or exclude it on
the same standard used to exclude deepseek), or make probe timeout role-aware.

**H-6 — `role_rank.review` is now dead, and the round caused it.** `rc=1` after **90 s**, all
three candidates rejected, then `freepool_select_model` (`freepool-coder.sh:296`) fails open to
the static `sonnet` alias. `report.md` §3 waives review/bulk/read as "not part of the measured
incident" — but this round changed probe semantics *globally*, so review was broken by this diff,
not left alone by it. A `review`-kind freepool dispatch now costs 90 s and returns an unranked
model. Fix: re-probe the review roster under the new content probe before merge, or gate the
content probe per role.

**H-7 — `plugins/leadv2/scripts/tests/test-arm-capability-honoured.sh:137` writes a real copy of
a plugin-owned file into the production scripts directory.**
`MUT_BIN="${SCRIPTS_ROOT}/leadv2-dispatch-code.ARMCAP-MUTATED.$$.sh"` — a full copy of the
6,700-line `leadv2-dispatch-code.sh` dropped into `plugins/leadv2/scripts/`. That directory is
the canonical single source symlinked into three repos. The only cleanup is an EXIT trap
(line 138-139); a `SIGKILL`, a CI timeout, or a crashed subshell leaves a drifting copy in
canonical. This is the single-source rule the brief asked me to check, violated directly.
Fix: keep the mutated binary in `$TMP` and make the sibling-helper resolution explicit via an
env override, or `PATH`-shim the siblings — do not write into the plugin tree.

**H-8 — `plugins/leadv2/scripts/tests/test-worker-output-gate.sh:78-105` mutates the PRODUCTION
gate file in place with no failure-safe restore.** The file's only trap is
`trap 'rm -rf "$TMP"' EXIT` (line 19); restoration is two inline `cp "$TMP/gate.orig" "$GATE"`
calls on the happy path. Interrupt between mutation and restore and
`plugins/leadv2/scripts/lib/leadv2-worker-output-gate.sh` stays permanently neutered (`*.sh)` →
`:`) in canonical — the gate silently disabled, every suite still green. That is the lying-green
disease with a loaded gun.
Fix: `trap 'cp "$TMP/gate.orig" "$GATE" 2>/dev/null; rm -rf "$TMP"' EXIT INT TERM`, or mutate a
copy in `$TMP` and invoke that (the gate has no sibling-path dependencies, so a copy works here).

**H-9 — the re-rank asserts a conclusion the bakeoff cannot support.** See item 3: 4/5 candidates
byte-identical, so "measured correctness first" (`freepool-arm.yaml:39-53`, `report.md` §3) is
latency ordering wearing a correctness label. Fix: either restate the rationale as "ordered by
measured latency among routes that all passed a trivial correctness check", or run a bakeoff task
that can actually separate them (a multi-file edit with a failing-then-passing test, which is the
shape that failed on 2026-08-30).

## Medium

**M-10 — "failed the bakeoff twice" has one artifact.**
`bakeoff/round2/nvidia_nim_deepseek-ai_deepseek-v4-pro-0813.verdict.txt` records exactly one
failure (`http=000000 elapsed_s=90`). The claimed 125 s retry — load-bearing for the *exclusion*
decision in `freepool-arm.yaml:47-52` and `report.md` §3 — has no transcript. Fix: add the second
verdict/response pair, or downgrade the wording to one measured failure.

**M-11 — `bakeoff/README.md` contradicts `bakeoff/round2/`.** The README is unmodified round-1
text: *"not re-run; pre-existing evidence found and cited instead … this environment has no live
network path to the founder's free-claude-code proxy (127.0.0.1:8317)"* — sitting in the same
directory as 26 files of live round-2 transcripts from that exact proxy. A future reader lands on
the README first. Fix: rewrite or date-stamp it.

**M-12 — the round's headline artifact escapes CI.** `tests/run-all.sh:150` matches only
`plugins/leadv2/scripts/*.sh`, so a `config/freepool-arm.yaml`-only change selects no suite
(measured, item 6). This round's primary deliverable *is* the yaml. Compounding it,
`test-freepool-model-selector.sh:414` now hardcodes `anthropic/groq/openai/gpt-oss-120b` against
the real checked-in yaml — so the next rank edit breaks that assertion with no CI signal on the
change that broke it. The report flags the gap and ships anyway. Fix: add a `*.yaml` arm to the
scope matcher mapping `freepool-arm.yaml` → the two freepool suites (three lines, and it is in
`LANE_WRITES`).

**M-13 — root-cause overclaim.** `report.md` §1: *"Root cause, confirmed against the proxy's own
source … `ReasoningPolicy.provider_default()`, line 66-69"*. I verified the citation is accurate —
`~/tools/free-claude-code/src/free_claude_code/core/reasoning.py:66-69` is
`def provider_default(cls): """Leave reasoning computation to the provider.""" return cls()`.
But that source only shows the proxy sets *no* reasoning policy; it does not show reasoning tokens
are charged against `max_tokens`. The empirical evidence (1→blank, 64→"OK") stands on its own and
is sufficient; the causal sentence should be tagged as inference, not "confirmed".

**M-14 — probe cost went up 64× per rank per spawn** (`max_tokens` 1 → 64,
`leadv2-freepool-model-select.sh:191`) against free-tier quotas, and probe *results* are not
cached between spawns — only the `/v1/models` catalog is (TTL 60 s). Combined with H-5 that is
~64 wasted output tokens plus 30 s, per implement spawn, forever. Fix: cache a probe verdict per
route for the same TTL as the catalog.

## Low

**L-15 — `FREEPOOL_MODEL_PROBE_MAX_TOKENS` is read at `_probe` but absent from the file's own
env-var contract block** (`leadv2-freepool-model-select.sh:18-40`, which documents every other
`FREEPOOL_*`). New knob, undocumented where its siblings live.

**L-16 — dead citation carried forward.** `config/freepool-arm.yaml` `role_rank.implement`
primary `why:` cites `docs/handoff/AUDIT-THIRDPARTY/free-model-research.md`; that path does not
exist in the lane (`ls` → No such file). Pre-existing from 2026-08-27, but this round rewrote
that exact line and kept the dead reference.

**L-17 — scope creep in `tests/run-all.sh`.** The branch range adds eight
`leadv2-broad-status:*` mappings unrelated to freepool. Harmless, but they arrive under this
lane's commit range and were not in the round-2 brief.

---

## Pre-finalize contradiction scan

- **env-var names vs settings:** `FREEPOOL_MODEL_PROBE_MAX_TOKENS` read but undocumented (L-15).
  All other `FREEPOOL_*` reads match their documented defaults. No mismatch between
  `freepool-coder.sh`'s exports and the selector's reads.
- **Flag semantics vs other usages:** `FREEPOOL_ROLE` unset ⇒ `implement` (selector:82) is
  consistent with `leadv2-admission-class.sh:96-104`; the *report* is what contradicts it (H-4).
  `gate_rc != 0 ⇒ parse_error` (`freepool-coder.sh:1539`) conflates "gate crashed" with "file
  does not parse" (C-1).
- **Path existence:** `~/tools/free-claude-code/src/free_claude_code/core/reasoning.py:66-69` —
  exists, quoted accurately. All `bakeoff/round2/*` paths cited in `report.md` — exist.
  `docs/handoff/AUDIT-THIRDPARTY/free-model-research.md` — **does not exist** (L-16).
  `lib/leadv2-worker-output-gate.sh` resolved from `${SELF%/*}/lib/` — exists.
- **Claim vs measurement:** `report.md` §4 "8/8 green, mutation control intact" — reproduced, true.
  `report.md` §2 "Suite is 25/25 green again" — reproduced, true (`=== 25 passed, 0 failed ===`).
  `report.md` line 1 model claim — **false on the implement path** (H-4).

---

Commercially: no — tomorrow the free arm pays 34 s of dead probe latency per implement spawn to
land on a model that was never bakeoff-ranked for that role, review-kind work fails outright after
90 s, and the one gate that was supposed to make weak free output survivable will falsely reject
every worker that commits its work, so free-arm tasks will still come back to a paid arm.

**fail** — `/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/FREEPOOL-MAKE-IT-EARN-ITS-KEEP-01/review-r2.md`

DELIVERABLE_COMPLETE
