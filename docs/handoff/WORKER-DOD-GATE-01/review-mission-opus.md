Review ONLY the diff at /tmp/WORKER-DOD-GATE-01-review.diff. You are independent of the author (glm).
Report correctness findings by severity (Critical / High / Medium / Low).
EXHAUSTIVE ROUND 1

Review this diff through FIVE lenses:
1. correctness
2. tests-can-fail (falsification)
3. product-invariant/contract
4. census
5. claims-without-evidence

Census rule: if you find one instance of a defect shape, enumerate ALL same-shape instances in the touched files before returning.
Claims-without-evidence rule: enumerate every factual claim about an external system or API made in the diff, its comments, or the deliverable. Each must carry inline evidence (probe output, log excerpt, doc link plus live check) or the literal tag UNVERIFIED. An untagged evidence-free claim that DRIVES a decision -- a code path, a config value, a limit, a retry policy -- is a BLOCKING finding. A tagged one is MEDIUM at most.

Report EVERYTHING you find in this one pass. Never stop at the first 1-3 findings.

Your review MUST contain these two lines, verbatim format, before any prose:
REVIEW_VERDICT: <FAIL|PASS|PASS_WITH_NITS>
REVIEW_FINDINGS: critical=<n> high=<n> medium=<n> low=<n>
FAIL if any Critical or High finding. PASS if the diff is clean. PASS_WITH_NITS otherwise.
Also report every Critical/High finding on its own line, exact format:
FINDING: severity=<Critical|High> file=<path> line=<n> dimension=<correctness|security|design|perf> desc=<one line>

If no findings are found, please output a brief explanation (at least one sentence) after the required lines to ensure the review body is sufficient for processing.
