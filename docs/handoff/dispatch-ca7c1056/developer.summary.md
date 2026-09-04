verdict: APPROVE
next_action: review_round_2

Fixed PPC-G11 integration test harness timeout — supersedes the earlier BLOCK/no-op verdict in this same file. Commit eb78d37.

- `GLM_POLICY_RESOLVER=""` in the E2E harness does NOT disable dispatch-code.sh's real resolver (bash `:-` treats unset/empty identically) — it falls through to the real `leadv2-glm-policy-resolve.py`, whose `--quota-live` defaults to the real co-located `leadv2-quota-live.sh` (not None), so real subprocess quota probes with 10-15s timeouts each did fire.
- Fixed by pointing GLM_POLICY_RESOLVER at a fast deterministic stub. Measured: full suite now ~177s wall, pass=78/79 (1 pre-existing unrelated red).

Full: full.md
