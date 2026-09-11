# LEAD-BURN-MECHANISM-01 — PROPOSAL-fable (revision 2 mission)

Status: **BLOCK on two premises, then the deliverable anyway.** The brief's census method cannot
observe the behaviour it reports on. Corrected numbers below; the batchable fraction and the
cause of near-zero batching are given on the corrected base.

All numbers: the same six opus sessions as the brief (fe5013c6, 07a43616, afa985a8, 678952be,
c85c1885, 123266e0; DB `cr_total` sum 4,599.3M, unchanged). Source: `~/.claude/burn/history.db`
opened `mode=ro&immutable=1`, plus the six transcripts on disk. Scripts under `/tmp/burn-fable/`
(`census.py`, `classify.py`, `extra.py`), not committed.

## Report back (≤400 words)

**Premise failure (the one number that is wrong).** The brief counted JSONL *lines*, not API
responses. Claude Code writes one line per content block, sharing `message.id`. Grouped by
`message.id` the six sessions have **14,931 responses — exactly the DB `turns` sum** the brief
called "a different thing". Consequences:

| item | brief (line-level) | measured (response-level) |
|---|---|---|
| text-only turns | 11,356 (45.8%) | **1,572 (10.5%)** — 7,926 of the 11,356 lines are redacted `thinking` blocks |
| interstitial narration between tool calls | implied 11,356 | **0** — every text-only response is the turn terminator (the agent loop ends only on a no-tool response); 1,470 follow a tool result, 77 a founder message, 25 an injected one |
| multi-tool responses | 0 of 13,437 | **74 of 13,359 (0.55%)**, 152 calls; a line can never carry two `tool_use` blocks, so 0 was true by construction |
| session length range | 1,168–3,101 turns | 1,926–3,101 |

So the "single largest line item" does not exist as paid turns, and astra's hook verdict stands
for a different reason: the only removable surfaces are one-tool responses and injected turns.

**Batchable fraction.** 11,875 of 13,421 tool responses are pairable (preceded by a tool call in
the same user turn). Argument-level heuristic (novel-token data dependency, retry-after-error,
write-after-read, identical reissue, sequential same-file edit, wait-on-spawn): 6,894 independent
(58.1%), 4,981 dependent. Manual audit on the stricter criterion "arguments *and* the decision to
issue the call were fixable before the previous result": 20/40 of heuristic-independent pairs
hold, 4/20 heuristic-dependent pairs were false. Corrected: **≈4,400 mergeable responses = 37%
of pairable = 30% of all 14,931 turns, 95% range 19%–44% (2,850–6,500 turns)**. At flat ~300k
cr/turn that is ≈1.3B of the six sessions' 4.6B. Thinking is redacted on disk (1,726/1,726 blocks
zero-length), so decision dependence is only inferable by hand; that is the error bar.

**Why 0.55%, not why zero.** The supportable cause: *the next call is chosen after the previous
result, not before.* Evidence: 42% are argument-dependent by construction; half of the rest were
decision-gated in audit (merge status before dispatch, empty log → rerun, FAIL → dig); the 74
batched responses are exactly the plan-shaped moments (Agent+Agent fan-outs, Bash+SendMessage,
census Bash pairs); sonnet in the same harness under the same sentence batches 0 of 5,629, fable
5 of 70 — a model propensity, not a harness block. The instruction presumes a plan; the lead runs
a loop, and at emission time there is one call in mind.

**What moves the number (hooks cannot).** (1) 1,557 turns (10.4%) are consecutive bounded
re-reads of the *same file* (`sed -n` slice, then the next slice): token-discipline rule 2 buys ~1k
tokens for a 300k turn — a doctrine contradiction, fixable in doctrine and in `Read` defaults.
(2) 707 injected events opened turns holding 4,956 responses (33%); the producer is outside the
plugin. (3) Emitter propensity is model-owned (fable 7% vs opus 0.55%, n small). (4) Nothing in
`plugins/leadv2` can raise batching of the lead's own emissions.

## 1. Census — line level vs response level

Line level reproduces the brief byte-for-byte: 24,793 lines, 11,356 no-tool, 13,437 one-tool,
0 multi-tool, 13,437 calls.

Response level (`message.id`, `isSidechain` excluded):

| session | responses | text-only | one-tool | multi-tool | text+tool in one response |
|---|---|---|---|---|---|
| fe5013c6 | 3,101 | 346 | 2,751 | 4 | 473 |
| 07a43616 | 2,822 | 107 | 2,703 | 12 | 352 |
| afa985a8 | 2,444 | 198 | 2,246 | 0 | 14 |
| 678952be | 2,467 | 195 | 2,272 | 0 | 87 |
| c85c1885 | 1,926 | 416 | 1,487 | 23 | 391 |
| 123266e0 | 2,171 | 310 | 1,826 | 35 | 543 |
| **total** | **14,931** | **1,572** | **13,285** | **74** | **1,860** |

Composition of the 11,356 no-tool lines: `thinking` only 7,926; `text` only 3,429; both 1.
Multi-tool combos: Bash+Bash 36, Bash+SendMessage 8, Bash+Agent 5, Agent+Agent 3, Monitor+Bash 3,
Agent+Bash 3, Bash+ToolSearch 2, Bash+Write 2, SendMessage+SendMessage 2, SendMessage+Bash 2,
Bash+TaskStop 1, Agent×4 1.

What this does to the brief's four "ignored rules":
- *Silence protocol* — narration is 1,860 text blocks riding inside tool responses (output tokens,
  not turns) plus 1,572 turn terminators that the loop requires. Turn cost of narration: ~0.
- *Parallel tool calls* — 0.55% compliance, not 0%. Still effectively unfollowed.
- *Understand code through subagents* — unchanged (345 Agent vs 10,188 Bash).
- *One watcher per journal* — 707 injected events (brief: 693; drift).

Boundary the brief asked for: the DB `turns` column and the response-level census now count the
same thing (14,931 = 14,931), so cr/turn × responses is a legitimate multiplication here.

## 2. Batchable fraction — method

Unit: a one-tool response N whose previous assistant response in the same user turn also carried
a tool call ("pairable": 11,875; 1,546 tool responses are first-in-turn and cannot merge backward).
Human events (founder 1,039, injected 707) reset the batch.

Heuristic labels N **DEP** if any of:
- R1 novel token: a token (≥5 chars, path/id/word) in N's input appears in a result of the open
  batch and nowhere in context before the batch — 4,678
- R2 retry after error: previous result matched an error pattern and N is the same tool with input
  Jaccard ≥0.4 — 446
- R5 sequential edit of the same path — 118 · R4 identical reissue — 77 · R3 write after read of
  the same path — 34 · R6 TaskOutput/SendMessage/TaskStop after Agent/Monitor — 15
Else **IND**. Result: IND 6,894 / DEP 4,981. Per-session IND share 44% (07a43616) to 64%
(fe5013c6, c85c1885). IND is dominated by Bash→Bash (4,660).

Manual audit (random, seed 7, `/tmp/burn-fable/samples.txt`):
- 40 IND pairs, criterion "arguments and the decision to issue N were fixable before result N−1":
  **20 hold.** Heuristic misses: line numbers under 5 chars reused from grep into `sed -n` (#03);
  decision gates — merge status before dispatch (#13), empty log → rerun (#12), FAIL → dig (#24),
  arbiter output before Agent spawn (#11, #17); temporal — Write then run it (#30), `nohup` then
  grep its log (#22); retry after hook refusal with a tool change Bash→Write (#37).
- 20 DEP pairs: **16 hold.** False DEP: pagination `sed -n 1,60p` → `300,330p` (#16), an
  unrelated `tail` after an unrelated census (#07), a Write after a result of "5" (#14), a Write
  after a timeout notice (#17).

Corrected count = 6,894 × 0.50 + 4,981 × 0.20 = 3,447 + 996 ≈ **4,440**.
Wilson 95% on the two audit rates: IND precision 0.355–0.645 → 2,447–4,447; DEP false rate
0.081–0.416 → 403–2,072. Sum: **2,850–6,500 of 11,875 pairable (24%–55%), i.e. 19%–44% of all
14,931 responses; point 30%.** A merged call also merges its result into the same user message,
so input tokens do not fall; only the per-response re-send is saved — consistent with Fact 1.

Not measurable from disk: decision dependence. Thinking blocks are stored as `signature` only
(fe5013c6: 1,726 blocks, all zero-length). The 50% audit rate is a human judgement of what the
model *could* have planned, not what it did.

Astra's ceiling of 6,718 (pairing) is not the bound: any run of k independent calls collapses to
one response, saving k−1, which is what the IND count already measures. The bound is 11,875
(everything pairable), reached only if nothing were dependent.

## 3. Why 0.55%

Named cause: **independence is unknowable at emission because the next call is selected from the
previous result** — the lead's working mode is probe → look → probe. Support:

1. 42% of pairable calls consume the previous result in their arguments (R1–R6).
2. Of the argument-independent half, half were decision-gated on the previous result in audit.
3. The 74 batched responses are precisely the moments when the set of calls existed before any
   result: fan-out spawns (Agent+Agent, Agent×4), a report plus a probe (Bash+SendMessage), two
   census views (Bash+Bash). Batching happens when there is a plan, never when there is a loop.
4. Same harness, same sentence, other emitters: sonnet 0 of 5,629 tool responses (4 heaviest
   sessions); fable 5 of 70. The harness does not prevent batching; the emitter's habit does.
5. 6,438 of 11,875 pairable responses opened with a thinking block, i.e. the model deliberated
   after seeing the result before choosing the next call.

The other two candidates (cost lands on a later turn; instruction read once, behaviour chosen
thousands of times) are consistent with the data but not distinguishable by it; no evidence for
either beyond plausibility. UNVERIFIED: that a "plan then execute" prompt shape would raise the
rate — the 74 plan-shaped cases suggest it, but nothing here tests it.

## 4. What would move the number, given that hooks cannot

Ranked by measured turns on these six sessions; none is a hook, none is a doctrine line.

| # | lever | measured turns | where it lives | failure mode |
|---|---|---|---|---|
| 1 | **Stop paging files.** 7,338 consecutive Bash→Bash pairs; 2,416 hit the same file; **1,557 (10.4% of all responses)** are two bounded reads of the same file in a row (`sed -n a,bp` → `sed -n c,dp`, `--help \| head` → `sed -n 25,70p`). Token-discipline rule 2 ("bounded at the source") trades ~1k tokens for a 300k turn. Read the whole file once when it is under a few hundred lines. | up to 1,557 | doctrine (`~/.claude/CLAUDE.md` rule 2) and `Read` defaults — not `plugins/leadv2` | a file over ~2k lines read whole costs more than the turn; keep the bound for those |
| 2 | **Coalesce the notification producer.** 707 injected events; the turns they opened contain 4,956 responses (33% of all). Removable is the forced turn per event plus whatever the burst would have batched, not the work itself. | ≥25 pure replies, ≤707 forced turns; realistic few hundred | outside `plugins/leadv2` (Monitor / Agent / hook-output delivery is harness-owned); astra named it | a digest that delays a lane-close signal delays the merge behind it |
| 3 | **Emitter propensity.** fable 5/70 vs opus 74/13,359. | unknown; n too small | model, outside every repo; the brief rules model switching out of scope | — |
| 4 | **Delegated investigation.** The IND set is 4,660 Bash→Bash census probes; each on Opus is a 300k turn, on haiku 51k. Existing rule, 345 Agent vs 10,188 Bash. A hook at call k saves nothing on turn k (astra) but changes turns k+1…k+n — the arithmetic astra gave is per-turn, not per-sequence. Stated for the lead's reconciliation; not proposed here. | up to ~4,000 Opus turns become haiku turns | doctrine already exists; mechanism excluded by this mission | subagent returns a summary the lead then re-verifies with the same probes |

Nothing inside `plugins/leadv2` raises the batching rate of the lead's own emissions. Levers 1 and
4 reduce the number of lead turns without batching; lever 2 removes turns the machinery creates.

## 5. What this mission and the brief got wrong

- **Census unit.** JSONL line ≠ API response. `resp_multi_tool` = 74, `resp_text_only` = 1,572,
  responses = 14,931 = DB turns. The brief's 45.8% is redacted thinking plus in-response text.
- **"0 of 13,437"** is a property of the file format, not of the behaviour. Actual 74 of 13,359.
- **Session length floor**: DB shows 1,926 for c85c1885, not 1,168.
- Drift only: injected 707 (693), founder 1,039 (1,033), opus 7d 28,318 turns / 8,609.8M cr
  (mission: 28,246 / 8,582.8M).

Astra's central finding — no pre-emission hook surface, PreToolUse fires after the turn is paid —
is unaffected and was not re-derived.
