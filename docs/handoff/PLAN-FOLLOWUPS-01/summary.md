# PLAN-FOLLOWUPS-01 summary

1. Refused architect arms spill to the next eligible arm: [leadv2-plan-run.sh:591](../../../plugins/leadv2/scripts/leadv2-plan-run.sh:591); covered by `Caveat 1a` and `Caveat 1b` in `test-plan-followups-01.sh`.
2. YAML extraction accepts marker→fence and fence→marker: [leadv2-plan-run.sh:371](../../../plugins/leadv2/scripts/leadv2-plan-run.sh:371); covered by `Caveat 2a`, `Caveat 2b`, and `Caveat 2c`.
3. Non-mapping acceptance fails and preserves `authored_at`: [leadv2-context-merge.py:41](../../../plugins/leadv2/scripts/lib/leadv2-context-merge.py:41); covered by `Caveat 3a` and `Caveat 3b`.
4. Planning review floors exclude non-dispatchable arms: [leadv2-glm-policy-resolve.py:250](../../../plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:250), [leadv2-glm-policy-resolve.py:526](../../../plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:526), and [leadv2-glm-policy-resolve.py:755](../../../plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:755); covered by `Caveat 4a`, `Caveat 4b`, and `Caveat 4c`.

Mutation proof: `MUT_RC=1` with 4 failures pre-fix; green verification: 13/13.
