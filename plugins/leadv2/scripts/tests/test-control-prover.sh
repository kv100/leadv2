#!/usr/bin/env bash
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
   && grep -q 'scored=1 killed=1 product_killed=1 self_test_killed=0 invariant=ok' <<<"${out1}"; then
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
[[ "\${result}" == "3" ]]
EOF
chmod +x "${d6}/suite2.sh"
cat > "${d6}/catalog.txt" <<EOF
c6a|product|${d6}/prod.sh|\$1 + \$2|\$1 - \$2|${d6}/suite.sh|
c6b|self_test|${d6}/prod2.sh|\$1 - \$2|\$1 + \$2|${d6}/suite2.sh|
EOF
out6="$(bash "${PROVER}" --catalog "${d6}/catalog.txt")"; rc6=$?
if [[ ${rc6} -eq 0 ]] && grep -q 'scored=2 killed=2 product_killed=1 self_test_killed=1 invariant=ok' <<<"${out6}"; then
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
[[ "\${result}" == "3" ]]
EOF
chmod +x "${d7}/suite2.sh"
cat >> "${d7}/catalog.txt" <<EOF
c7b|product|${d7}/prod2.sh|\$1 - \$2|\$1 + \$2|${d7}/suite2.sh|
EOF
out7b="$(bash "${PROVER}" --catalog "${d7}/catalog.txt")"; rc7b=$?
if [[ ${rc7a} -eq 0 ]] && grep -q 'scored=1 killed=1' <<<"${out7a}" \
   && [[ ${rc7b} -eq 0 ]] && grep -q 'scored=2 killed=2 product_killed=2' <<<"${out7b}"; then
  pass "7: catalog growth keeps invariant without touching the prover"
else
  fail "7: catalog growth keeps invariant without touching the prover (rc7a=${rc7a} rc7b=${rc7b}) out7a=<<${out7a}>> out7b=<<${out7b}>>"
fi

printf 'test-control-prover: %d failed\n' "${FAILS}"
(( FAILS == 0 ))
