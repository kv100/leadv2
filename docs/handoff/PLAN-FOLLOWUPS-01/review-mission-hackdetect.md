Run hack-detection on the diff at docs/handoff/PLAN-FOLLOWUPS-01/build-attempt-3.diff: TODO/FIXME band-aids, magic numbers, broad except, hardcoded creds/secrets, silent fallbacks.
Report each as one line, exact format:
FINDING: severity=<Critical|High|Medium|Low> file=<path> line=<n> dimension=hack desc=<one line>
Emit nothing else.
