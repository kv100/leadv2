#!/usr/bin/env bash
# changed-scope triggers, self-registered (SD-SUITE-MAP-SERIALIZES-EVERY-WAVE-01, migrated from tests/run-all.sh EXTRA_SUITE_MAP; discovered by scan_suite_triggers):
# run-all-triggers: leadv2-control-prover leadv2-control-prover.sh leadv2-review-run.sh
# tests/test-control-prover.sh — GATE-PROVES-ITS-OWN-CONTROL-01
#
# Proves lib/leadv2-control-prover.sh against fixture lanes ONLY — never a
# real lane, never a real state root. Every fixture lives under a mktemp -d
# tree, torn down on every exit path (including failure) by the EXIT trap.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../../../.." && pwd)"
PROVER="${ROOT}/plugins/leadv2/scripts/lib/leadv2-control-prover.sh"

FAILS=0
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-control-prover.XXXXXX")"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

# ---- shared fixture builders ---------------------------------------------

# A tiny "production" script with one function whose call-path can be
# mutated, plus a suite that genuinely exercises it.
mk_prod() { # dir name
  local dir="$1" name="$2"
  cat > "${dir}/${name}" <<'EOF'
#!/usr/bin/env bash
compute_sum() { # a b
  echo $(( $1 + $2 ))
}
EOF
}

mk_diagnostic_suite() { # dir name prod_name
  local dir="$1" name="$2" prod="$3"
  cat > "${dir}/${name}" <<EOF
#!/usr/bin/env bash
set -u
HERE="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
source "\${HERE}/${prod}"
result="\$(compute_sum 2 3)"
printf 'ran: compute_sum 2 3 -> %s\n' "\${result}"
[[ "\${result}" == "5" ]]
EOF
  chmod +x "${dir}/${name}"
}

# ---- 1. genuinely diagnostic control ⇒ passes ----------------------------
d1="${WORK}/lane1"; mkdir -p "${d1}"
mk_prod "${d1}" "prod.sh"
mk_diagnostic_suite "${d1}" "suite.sh" "prod.sh"
cat > "${d1}/catalog.txt" <<EOF
c1|product|${d1}/prod.sh|\$1 + \$2|\$1 - \$2|${d1}/suite.sh|
EOF
out1="$(bash "${PROVER}" --catalog "${d1}/catalog.txt")"; rc1=$?
if [[ ${rc1} -eq 0 ]] && grep -q '^\[KILLED\] id=c1 kind=product$' <<<"${out1}" \
   && grep -q 'scored=1 killed=1 unscored=0 product_killed=1 self_test_killed=0 invariant=ok' <<<"${out1}"; then
  pass "1: diagnostic control passes"
else
  fail "1: diagnostic control passes (rc=${rc1}) out=<<${out1}>>"
fi
if ! cmp -s "${d1}/prod.sh" <(printf '#!/usr/bin/env bash\ncompute_sum() { # a b\n  echo $(( $1 + $2 ))\n}\n'); then
  fail "1: production file not byte-identical after prove cycle"
fi

# ---- 2. suite stays green with the fix removed ⇒ control_not_diagnostic --
d2="${WORK}/lane2"; mkdir -p "${d2}"
mk_prod "${d2}" "prod.sh"
cat > "${d2}/suite.sh" <<'EOF'
#!/usr/bin/env bash
echo "suite ran (unconditional pass, ignores the target)"
exit 0
EOF
chmod +x "${d2}/suite.sh"
cat > "${d2}/catalog.txt" <<EOF
c2|product|${d2}/prod.sh|\$1 + \$2|\$1 - \$2|${d2}/suite.sh|
EOF
out2="$(bash "${PROVER}" --catalog "${d2}/catalog.txt")"; rc2=$?
if [[ ${rc2} -ne 0 ]] && grep -q '^\[BLOCKED\] id=c2 reason=control_not_diagnostic$' <<<"${out2}"; then
  pass "2: silent suite ⇒ control_not_diagnostic"
else
  fail "2: silent suite ⇒ control_not_diagnostic (rc=${rc2}) out=<<${out2}>>"
fi

# ---- 3. suite prints FAIL: while exiting 0 ⇒ control_not_diagnostic -----
d3="${WORK}/lane3"; mkdir -p "${d3}"
mk_prod "${d3}" "prod.sh"
cat > "${d3}/suite.sh" <<'EOF'
#!/usr/bin/env bash
echo "FAIL: something looks wrong"
exit 0
EOF
chmod +x "${d3}/suite.sh"
cat > "${d3}/catalog.txt" <<EOF
c3|product|${d3}/prod.sh|\$1 + \$2|\$1 - \$2|${d3}/suite.sh|
EOF
out3="$(bash "${PROVER}" --catalog "${d3}/catalog.txt")"; rc3=$?
if [[ ${rc3} -ne 0 ]] && grep -q '^\[BLOCKED\] id=c3 reason=control_not_diagnostic$' <<<"${out3}"; then
  pass "3: FAIL:-printing-but-exit-0 suite ⇒ control_not_diagnostic"
else
  fail "3: FAIL:-printing-but-exit-0 suite ⇒ control_not_diagnostic (rc=${rc3}) out=<<${out3}>>"
fi

# ---- 4. mutation also killed by a second gate ⇒ not counted as a kill ----
d4="${WORK}/lane4"; mkdir -p "${d4}"
mk_prod "${d4}" "prod.sh"
mk_diagnostic_suite "${d4}" "suite.sh" "prod.sh"
cat > "${d4}/other_gate.sh" <<EOF
#!/usr/bin/env bash
grep -qF '\$1 + \$2' "${d4}/prod.sh"
EOF
chmod +x "${d4}/other_gate.sh"
cat > "${d4}/catalog.txt" <<EOF
c4|product|${d4}/prod.sh|\$1 + \$2|\$1 - \$2|${d4}/suite.sh|${d4}/other_gate.sh
EOF
out4="$(bash "${PROVER}" --catalog "${d4}/catalog.txt")"; rc4=$?
if [[ ${rc4} -ne 0 ]] && grep -q '^\[BLOCKED\] id=c4 reason=shared_gate_kill$' <<<"${out4}"; then
  pass "4: shared-gate kill not counted"
else
  fail "4: shared-gate kill not counted (rc=${rc4}) out=<<${out4}>>"
fi

# ---- 5. mutation applied to a fixture, not the production call path -----
d5="${WORK}/lane5"; mkdir -p "${d5}/tests"
mk_prod "${d5}/tests" "prod.sh"
mk_diagnostic_suite "${d5}/tests" "suite.sh" "prod.sh"
cat > "${d5}/catalog.txt" <<EOF
c5|product|${d5}/tests/prod.sh|\$1 + \$2|\$1 - \$2|${d5}/tests/suite.sh|
EOF
out5="$(bash "${PROVER}" --catalog "${d5}/catalog.txt")"; rc5=$?
if [[ ${rc5} -ne 0 ]] && grep -q '^\[BLOCKED\] id=c5 reason=fixture_not_production' <<<"${out5}"; then
  pass "5: fixture-path mutation not counted"
else
  fail "5: fixture-path mutation not counted (rc=${rc5}) out=<<${out5}>>"
fi

# ---- 6. half self_test entries ⇒ headline shows the product number only -
d6="${WORK}/lane6"; mkdir -p "${d6}"
mk_prod "${d6}" "prod.sh"
mk_diagnostic_suite "${d6}" "suite.sh" "prod.sh"
cat > "${d6}/prod2.sh" <<'EOF'
#!/usr/bin/env bash
compute_diff() { # a b
  echo $(( $1 - $2 ))
}
EOF
cat > "${d6}/suite2.sh" <<EOF
#!/usr/bin/env bash
set -u
source "${d6}/prod2.sh"
result="\$(compute_diff 5 2)"
printf 'ran: compute_diff 5 2 -> %s\n' "\${result}"
[[ "\${result}" == "3" ]]
EOF
chmod +x "${d6}/suite2.sh"
cat > "${d6}/catalog.txt" <<EOF
c6a|product|${d6}/prod.sh|\$1 + \$2|\$1 - \$2|${d6}/suite.sh|
c6b|self_test|${d6}/prod2.sh|\$1 - \$2|\$1 + \$2|${d6}/suite2.sh|
EOF
out6="$(bash "${PROVER}" --catalog "${d6}/catalog.txt")"; rc6=$?
if [[ ${rc6} -eq 0 ]] && grep -q 'scored=2 killed=2 unscored=0 product_killed=1 self_test_killed=1 invariant=ok' <<<"${out6}"; then
  pass "6: mixed catalog reports product number separately"
else
  fail "6: mixed catalog reports product number separately (rc=${rc6}) out=<<${out6}>>"
fi

# ---- 7. catalog grows by one ⇒ invariant still holds, no script edit ----
d7="${WORK}/lane7"; mkdir -p "${d7}"
mk_prod "${d7}" "prod.sh"
mk_diagnostic_suite "${d7}" "suite.sh" "prod.sh"
cat > "${d7}/catalog.txt" <<EOF
c7a|product|${d7}/prod.sh|\$1 + \$2|\$1 - \$2|${d7}/suite.sh|
EOF
out7a="$(bash "${PROVER}" --catalog "${d7}/catalog.txt")"; rc7a=$?
cat > "${d7}/prod2.sh" <<'EOF'
#!/usr/bin/env bash
compute_diff() { # a b
  echo $(( $1 - $2 ))
}
EOF
cat > "${d7}/suite2.sh" <<EOF
#!/usr/bin/env bash
set -u
source "${d7}/prod2.sh"
result="\$(compute_diff 5 2)"
printf 'ran: compute_diff 5 2 -> %s\n' "\${result}"
[[ "\${result}" == "3" ]]
EOF
chmod +x "${d7}/suite2.sh"
cat >> "${d7}/catalog.txt" <<EOF
c7b|product|${d7}/prod2.sh|\$1 - \$2|\$1 + \$2|${d7}/suite2.sh|
EOF
out7b="$(bash "${PROVER}" --catalog "${d7}/catalog.txt")"; rc7b=$?
if [[ ${rc7a} -eq 0 ]] && grep -q 'scored=1 killed=1 unscored=0' <<<"${out7a}" \
   && [[ ${rc7b} -eq 0 ]] && grep -q 'scored=2 killed=2 unscored=0 product_killed=2' <<<"${out7b}"; then
  pass "7: catalog growth keeps invariant without touching the prover"
else
  fail "7: catalog growth keeps invariant without touching the prover (rc7a=${rc7a} rc7b=${rc7b}) out7a=<<${out7a}>> out7b=<<${out7b}>>"
fi

# ---- 8. suite: nonexistent path ⇒ still [BLOCKED] suite_missing (regression,
#         GATE-PROVES-ITS-OWN-CONTROL-01 round 1) -------------------------
d8="${WORK}/lane8"; mkdir -p "${d8}"
mk_prod "${d8}" "prod.sh"
cat > "${d8}/catalog.txt" <<EOF
c8|product|${d8}/prod.sh|\$1 + \$2|\$1 - \$2|${d8}/does/not/exist.sh|
EOF
out8="$(bash "${PROVER}" --catalog "${d8}/catalog.txt")"; rc8=$?
if [[ ${rc8} -ne 0 ]] && grep -q '^\[BLOCKED\] id=c8 reason=suite_missing' <<<"${out8}"; then
  pass "8: suite: nonexistent path still BLOCKED suite_missing"
else
  fail "8: suite: nonexistent path still BLOCKED suite_missing (rc=${rc8}) out=<<${out8}>>"
fi

# ---- 9. suite RED before mutation ⇒ unscored, not killed ------------------
d9="${WORK}/lane9"; mkdir -p "${d9}"
mk_prod "${d9}" "prod.sh"
cat > "${d9}/suite.sh" <<'EOF'
#!/usr/bin/env bash
echo "baseline check"
false
EOF
chmod +x "${d9}/suite.sh"
cat > "${d9}/catalog.txt" <<EOF
c9|product|${d9}/prod.sh|\$1 + \$2|\$1 - \$2|${d9}/suite.sh|
EOF
out9="$(bash "${PROVER}" --catalog "${d9}/catalog.txt")"; rc9=$?
if [[ ${rc9} -ne 0 ]] && grep -q '^\[UNSCORED\] id=c9 reason=baseline_not_green$' <<<"${out9}" \
   && grep -q 'scored=1 killed=0 unscored=1 product_killed=0 self_test_killed=0 invariant=violated' <<<"${out9}"; then
  pass "9: suite red before mutation ⇒ unscored, not killed"
else
  fail "9: suite red before mutation ⇒ unscored, not killed (rc=${rc9}) out=<<${out9}>>"
fi
if ! cmp -s "${d9}/prod.sh" <(printf '#!/usr/bin/env bash\ncompute_sum() { # a b\n  echo $(( $1 + $2 ))\n}\n'); then
  fail "9: production file mutated despite baseline-red skip"
fi

# ---- 10. suite collects zero tests (silent green) ⇒ unscored --------------
d10="${WORK}/lane10"; mkdir -p "${d10}"
mk_prod "${d10}" "prod.sh"
cat > "${d10}/suite.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${d10}/suite.sh"
cat > "${d10}/catalog.txt" <<EOF
c10|product|${d10}/prod.sh|\$1 + \$2|\$1 - \$2|${d10}/suite.sh|
EOF
out10="$(bash "${PROVER}" --catalog "${d10}/catalog.txt")"; rc10=$?
if [[ ${rc10} -ne 0 ]] && grep -q '^\[UNSCORED\] id=c10 reason=zero_tests_collected$' <<<"${out10}" \
   && grep -q 'scored=1 killed=0 unscored=1 product_killed=0 self_test_killed=0 invariant=violated' <<<"${out10}"; then
  pass "10: silent (zero-output) green suite ⇒ unscored"
else
  fail "10: silent (zero-output) green suite ⇒ unscored (rc=${rc10}) out=<<${out10}>>"
fi

# ---- 11. mutation makes target unparseable ⇒ unscored, infra failure ------
d11="${WORK}/lane11"; mkdir -p "${d11}"
mk_prod "${d11}" "prod.sh"
mk_diagnostic_suite "${d11}" "suite.sh" "prod.sh"
cat > "${d11}/catalog.txt" <<EOF
c11|product|${d11}/prod.sh|}||${d11}/suite.sh|
EOF
out11="$(bash "${PROVER}" --catalog "${d11}/catalog.txt")"; rc11=$?
if [[ ${rc11} -ne 0 ]] && grep -q '^\[UNSCORED\] id=c11 reason=target_unparseable$' <<<"${out11}" \
   && grep -q 'scored=1 killed=0 unscored=1 product_killed=0 self_test_killed=0 invariant=violated' <<<"${out11}"; then
  pass "11: target made unparseable by mutation ⇒ unscored (infra failure)"
else
  fail "11: target made unparseable by mutation ⇒ unscored (infra failure) (rc=${rc11}) out=<<${out11}>>"
fi
if ! cmp -s "${d11}/prod.sh" <(printf '#!/usr/bin/env bash\ncompute_sum() { # a b\n  echo $(( $1 + $2 ))\n}\n'); then
  fail "11: production file not byte-identical after unparseable-mutation unscored path"
fi

printf 'test-control-prover: %d failed\n' "${FAILS}"
(( FAILS == 0 ))
