Run hack-detection on the diff at docs/handoff/03c5b9f4f110/build-attempt-1.diff: TODO/FIXME band-aids, magic numbers, broad except, hardcoded creds/secrets, silent fallbacks.
Report each as one line, exact format:
FINDING: severity=<Critical|High|Medium|Low> file=<path> line=<n> dimension=hack desc=<one line>
Emit nothing else.
