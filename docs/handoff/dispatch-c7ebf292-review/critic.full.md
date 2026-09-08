REVIEW_VERDICT: PASS_WITH_NITS
REVIEW_FINDINGS: critical=0 high=0 medium=2 low=4

# critic — adversarial review of dispatch-c7ebf292 (fable arm)

Diff: `docs/handoff/dispatch-c7ebf292/review.diff` — one new file,
`docs/audits/seamless-account-switching-fable.md`, +456/-0. Markdown only; no shell, Python,
or config is touched, so there is no runtime regression surface. The review dimension is
therefore **correctness of the report's claims and of the proof it offers**, judged
adversarially: every claim that names a file, a line, a command, or a count was re-derived
here from the live tree.

There was no `context.yaml` for this review task (`docs/handoff/dispatch-c7ebf292-review/`
contains only stream/session artifacts), so no `decisions` or `off_limits` constrained this
review. Nothing was modified.

---

## A. What I re-derived, and what held

Every one of these was checked against the live tree in this session, not taken from the
report. All held.

| Report claim | Line(s) | Independent check | Result |
|---|---|---|---|
| `~/ccswitch.sh` touches only the un-suffixed record, at 198 and 218 | 218-223 | `sed -n '195,222p' ~/ccswitch.sh`, offsets 4 and 24 → lines 198, 218; `grep -c 'Claude Code-credentials-'` → **0** | ✅ exact, and the zero-suffixed-hits count strengthens it |
| `leadv2-history-primer.sh:43` hardcodes `$HOME/.claude/projects`, builds `CWD_NORM` from `pwd` with no realpath | 278-282 | line 42 `CWD_NORM="$(pwd \| tr '/' '-')"`, line 43 `PROJ_DIR="$HOME/.claude/projects/$CWD_NORM"` | ✅ exact line |
| …and it is dormant | 280-282 | `grep -rl leadv2-history-primer plugins/leadv2` → only itself | ✅ |
| `UNKNOWN_PROBE_PENALTY=50.0` at `lib/leadv2-route-arbiter.sh:913` | 290 | line 913 verbatim | ✅ exact line |
| No plugin code reads `cachedUsageUtilization` | 346 | `grep -rl cachedUsageUtilization plugins/leadv2/scripts` → rc=1, no hits | ✅ |
| `claude-subsession.sh` refs 207/215/216/566/568/596 | 265-269 | each line printed; uuidgen@207, SESSION_MAP_FILE@215, printf-append@216, `export CLAUDE_CONFIG_DIR="$dir"`@566, profile-log append@568, `--session-id`@596 | ✅ all six exact |
| Keychain suffix = `sha256(config_dir)[:8]` → `5a3c2328` / `eb6c5b97` | 206-208 | recomputed both; byte-identical | ✅ |
| `~/.zshrc` 26/27/34/36/37/38 — work root is the default for plain `claude` | 101-108 | all six lines match verbatim | ✅ |
| Burn `rate_limit_history` per-key state counts | 310-318 | re-queried live: 343766 unauth 26; 356133 ok **105** / unauth **18**; 646566 unauth **58**; 656236 ok **91** / unauth 14. Growth since the report's 94/17 and 79/14 is monotone and consistent with continued probing | ✅ reproduces; the "94 ok vs 17 unauthenticated" premise-refutation stands |

The report's central technical thesis — resume is bound to the **config root**, not the
account; cross-root resume works by absolute path and writes back into the origin root;
`/switch` rotates a record no live session reads — is supported by its own control/cross
probe pair, and every artifact I could re-derive matches. The evidence contract is honoured:
`UNVERIFIED:` appears where it should (lines 228, 255, 399) and §5 is an explicit
did-not-check list with the command that would settle each item. No untagged
external-system claim drives a recommendation.

---

## B. Findings

### MEDIUM-1 — the §7 self-check proof prints the inverse of its own label
`docs/audits/seamless-account-switching-fable.md:458` · dimension: correctness-of-proof

```
$ git diff --name-only main...HEAD -- . | grep -vE '\.md$' ; echo "non-markdown changes: $?"
```

`$?` here is **grep's** exit status, not a count: grep exits 1 when it matches nothing and 0
when it matches. Reproduced:

```
$ printf 'a.md\nb.md\n' | grep -vE '\.md$' ; echo "non-markdown changes: $?"
non-markdown changes: 1          ← clean lane
$ printf 'a.md\nb.sh\n' | grep -vE '\.md$' ; echo "non-markdown changes: $?"
b.sh
non-markdown changes: 0          ← dirty lane
```

So a **clean** lane publishes `non-markdown changes: 1` and a lane that leaked a `.sh`
publishes `non-markdown changes: 0`. §7 states this output "is pasted in the lane's
`developer.full.md` after the commit" and it is the *only* proof of scope the report offers.
Anyone auditing that artifact against its label reads the scope guarantee backwards. Fix:
drop the `$?` and print the count — `... | grep -vcE '\.md$'` — or assert explicitly
(`... | grep -qE '\.md$' && echo DIRTY || echo CLEAN`).

Not High: the underlying claim (doc-only lane) is independently true from the diff itself,
which is a single `.md` file. The defect is in the proof, not the fact.

### MEDIUM-2 — probe-call accounting is off by one, in the side-effects section
`docs/audits/seamless-account-switching-fable.md:118-119` and `:445-446` · dimension: self-report accuracy

§1.3 line 118: "Four `claude -p --model haiku` calls in total". §6 line 445: "four `haiku`
`-p` calls (two on work, two on personal)".

The report's own step list contains **five** invocations:

| step | root | line | rc |
|---|---|---|---|
| step1 create | work | 126 | 0 |
| step2 resume-by-uuid | personal | 131 | 1 |
| step3 wrong-path | personal | 135-137 | 1 |
| CONTROL resume-by-uuid | work | 140 | 0 |
| CROSS resume-by-path | personal | 145 | 0 |

That is 2 work + **3** personal = 5, not 4 (2+2). §1.3 parenthetically acknowledges the
extra call ("My first path attempt used the wrong path… it is shown"), so the count was
simply not updated after step3 was added to the narrative. This matters more than a typo
because §6 is the *spend and side-effect declaration* the founder is asked to accept without
re-running anything; an accounting section that miscounts its own listed calls cannot be used
as the audit trail it claims to be. The API cost of one extra haiku call is negligible; the
credibility of the declaration is the finding.

### LOW-1 — §1.3 step3 annotation over-reads its own evidence
`:136` vs `:150` · dimension: correctness

Line 136 annotates the fresh uuid `ec32d662` with "a non-existent path is silently treated as
a new session". But the call exited **rc=1** with `No conversation found with session ID`,
and the report's own "stores after" block (line 150) records that the personal root received
`memory/` and **no `.jsonl`**. No session was created. The behaviour actually observed is
"an argument that is not an existing path is treated as a session *id*, gets a generated
uuid in the error message, and is not found" — a different and much less alarming fact than
silent session creation. As written, a reader building the R1 wrapper would guard against a
phantom-session hazard that the evidence says does not exist.

### LOW-2 — §3.1(b) says "5 account keys"; the table's own 282-row total needs 6
`:307` · dimension: correctness

Live re-query returns **6** distinct `account_key` values. The sixth, `756E6B`, holds one
`ok` row at 2026-09-03 20:28:19 — before the report's window opened — so it existed at
measurement time. The six table rows shown sum to 281 (26+94+17+51+79+14); the stated total
of 282 is only reachable by including the omitted singleton. The total is right and the
argument is unaffected; the key count and the table are one row short of the total they
claim to decompose.

### LOW-3 — the un-suffixed record's measured failure is 429, not an auth rejection
`:215`, `:299`, `:304` · dimension: correctness of inference

Both measurements of the un-suffixed record show `http 429` / `429 rate_limited`. §3.1 then
writes "The only failure was the dead un-suffixed record" (line 304), letting the 429 read as
corroboration of deadness. It is not: 429 is rate-limiting — the endpoint accepted the
credential and throttled the request — whereas the deadness claim rests entirely on
`expiresAt=2026-08-25` (line 215, line 39). Both may be true, but the 429 is not evidence for
the expiry and the prose implies it is. This is the same conflation the report correctly
criticises elsewhere (§3.1: "This is a token state pattern, not a plan-type rule"), applied
in the report's own favour. The recommendations (R2 retire `/switch`) do not depend on it —
the `expiresAt` reading plus `grep -c 'Claude Code-credentials-' → 0` carries R2 on its own.

### LOW-4 — the independence statement is self-attesting, and the admitted read contains the headline finding
`:13-18` vs `:31-34` · dimension: methodology

The arm exists to produce an independent second measurement. The statement admits reading
`PRE-WAVES-PLAN.md` §E1 line 83, which contains "resume fails by UUID and works by absolute
path" — verbatim the report's finding #2. The defence is ordering ("I read that line in the
same tool batch in which my own probe had already run with its design fixed"), which nothing
in the artifact can corroborate: no probe timestamp is recorded against the read, and a
"same tool batch" claim is precisely the kind of self-report §3 of this same report
distrusts elsewhere. I am **not** alleging contamination — the probe design (control + cross
pair) is stronger than the one-line summary it echoes, and the control/cross pair is
independently convincing. The note is that the independence guarantee is asserted, not
evidenced, and a lead comparing arms should weight finding #2 as *replicated* rather than
*independently discovered*.

---

## C. What I did not find

- No Critical or High. No executable code changed; `bash -n` / `py_compile` have no targets,
  which §7 states correctly.
- No unhedged destructive recommendation. R5 (symlink `~/.claude-work/projects` →
  `~/.claude/projects`) is the riskiest proposal in the report and is tagged **UNVERIFIED**
  with an explicit "Do it on scratch roots, not the live ones" and a stated test. Adequate.
- No credential leakage in the artifact: token bytes are never printed, emails are redacted,
  keychain records appear by service name and `expiresAt` only. Confirmed by reading the
  full 456 lines.
- The realpath hazard the report raises (§1.1, `/tmp` → `/private/tmp`) is real and correctly
  generalised to R1's wrapper; the dormant `leadv2-history-primer.sh:43` instance is a
  genuine latent bug found in passing, correctly labelled dormant rather than live.

## D. Verdict rationale

Two Mediums, both in the report's *self-verification* layer rather than its technical body:
a scope-proof command that publishes the inverse of its label, and a spend declaration that
miscounts the calls listed three lines above it. Neither invalidates a finding; both would
mislead an auditor who trusts the artifact instead of re-running it — which is exactly what
the artifact asks for. The four Lows are precision defects in inference and counting. The
technical core survived full re-derivation: every file:line, hash, alias, and DB count in the
report reproduces against the live tree.

PASS_WITH_NITS. Recommend fixing MEDIUM-1 and MEDIUM-2 before this report is cited in a
decision, since both live in the sections a reader uses to decide whether to trust the rest.

DELIVERABLE_COMPLETE
