# FP-03 — freepool installer + settings ownership (P1)

Repo: canonical leadv2 plugin (this repo). Context: docs/leadv2/freepool-backlog.md §FP-03
and its Appendix "FCC admin UI field ownership" (read both first).

Goal: plugins/leadv2/scripts/freepool-install.sh stops being a stub. It must:
1. Create ~/.fcc/.env skeleton if absent with ALL keys the proxy reads (FCC_CONFIG_SCHEMA,
   DEEPSEEK_API_KEY, GEMINI_API_KEY, GROQ_API_KEY, MISTRAL_API_KEY, NVIDIA_NIM_API_KEY,
   OPENROUTER_API_KEY, PROXY_AUTH_ENABLED, PORT) — commented placeholders, never real
   values; NEVER overwrite an existing .env (idempotent; print a "missing keys" list and
   append only missing keys as comments).
2. Print the ownership table from the backlog appendix: operator fills provider API keys
   once; system defaults cover the rest; FCC admin UI matters only for Fallback Models +
   the Default Model safety net.
3. Health-verify: ${FREEPOOL_PROXY_URL:-http://127.0.0.1:8317}/health with 5s curl timeout;
   if down and FREEPOOL_AUTOSTART!=0, one freepool-proxy.sh start + one re-check; still
   down -> exit non-zero with a clear reason.
4. --check mode: report-only, machine-parsable KEY=present|missing lines, no writes.

Tests (plugins/leadv2/scripts/tests/): skeleton created when absent; existing .env
untouched byte-for-byte (cmp); --check output shape; negative control declared in header
and RUN red (mutation: installer overwrites existing .env — the untouched-.env case must
catch it). bash -n + suite raw output in report.
Commit: feat(leadv2): FP-03 freepool installer — env skeleton, ownership table, health check.
Report: docs/handoff/FP-03/report.md (max 250 words), end DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-cb411cf7" "<question>" \
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