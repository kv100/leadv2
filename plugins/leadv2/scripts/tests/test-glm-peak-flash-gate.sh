#!/usr/bin/env bash
# run-all-triggers: leadv2-glm-quota-gate.sh glm-coder.sh
# tests/test-glm-peak-flash-gate.sh — GLM-PEAK-RULE-IS-MODEL-BLIND-01
# (founder ruling 2026-09-04: in peak, flash is allowed; the regular GLM is
# peak-refused. Discriminator is the ARM NAME, never a model version literal.)
#
# Cases (GLM_SIMULATE_UTC_HOUR forces the clock; LEADV2_QUOTA_LIVE is a stub
# emitting a healthy quota payload — no network, no real provider):
#   1. peak + flash arm            -> exit 0
#   2. peak + plain glm arm        -> exit 2, LEADV2_DISPATCH_REFUSED: peak_hours
#   3. outside peak + plain glm    -> exit 0 (unchanged)
#   4. VERSION-ROTATION: flash arm
#      with nonexistent glm-9.9    -> still exit 0 in peak
#   5. NEGATIVE CONTROL: mutate the *flash* discriminator inside the gate body
#      (scratch copy) -> case 1 goes RED; restore -> green again.
#
# Run: bash plugins/leadv2/scripts/tests/test-glm-peak-flash-gate.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${SCRIPT_DIR}/../leadv2-glm-quota-gate.sh"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1"; }

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/glm-peak-flash.XXXXXX")"
trap 'rm -rf "${FIXTURE}"' EXIT INT TERM

# healthy-quota stub: 5h/weekly both low, status ok
cat > "${FIXTURE}/quota-live-stub.sh" <<'EOF'
#!/usr/bin/env bash
printf '{"status":"ok","five_hour":{"pct":7,"reset_iso":"2026-09-04T15:00:00Z"},"weekly":{"pct":12,"reset_iso":"2026-09-08T00:00:00Z"}}'
EOF
chmod +x "${FIXTURE}/quota-live-stub.sh"

run_gate() { # $1 = hour, $2 = arm ("" for none) -> echoes "<rc>|<stderr>"
  local hour="$1" arm="$2" out rc
  out="$(LEADV2_QUOTA_LIVE="${FIXTURE}/quota-live-stub.sh" \
        GLM_SIMULATE_UTC_HOUR="$hour" \
        LEADV2_GLM_GATE_ARM="${arm}" \
        bash "${GATE}" 2>&1 >/dev/null)"; rc=$?
  printf '%s|%s' "$rc" "$out"
}

bash -n "${GATE}" && pass "bash -n leadv2-glm-quota-gate.sh" || fail "bash -n leadv2-glm-quota-gate.sh"
bash -n "${SCRIPT_DIR}/../glm-coder.sh" && pass "bash -n glm-coder.sh" || fail "bash -n glm-coder.sh"

# ── case 1: peak + flash arm -> allow ────────────────────────────────────────
out="$(run_gate 8 "glm-flash")"
if [[ "${out}" == 0\|* ]]; then pass "peak+flash-arm exits 0"; else fail "peak+flash-arm: expected rc 0, got [${out%%|*}]"; fi

# ── case 2: peak + plain glm arm -> refuse peak_hours ────────────────────────
out="$(run_gate 8 "glm")"
if [[ "${out}" == 2\|*LEADV2_DISPATCH_REFUSED:\ peak_hours* ]]; then
  pass "peak+plain-glm exits 2 with LEADV2_DISPATCH_REFUSED: peak_hours"
else
  fail "peak+plain-glm: expected rc2 + peak_hours marker, got [${out}]"
fi

# ── case 3: outside peak + plain glm -> unchanged allow ──────────────────────
out="$(run_gate 12 "glm")"
if [[ "${out}" == 0\|* ]]; then pass "outside-peak+plain-glm exits 0 (unchanged)"; else fail "outside-peak+plain-glm: expected rc 0, got [${out%%|*}]"; fi

# ── case 3b: no arm passed -> legacy blind behaviour (refuse in peak) ────────
out="$(run_gate 8 "")"
if [[ "${out}" == 2\|* ]]; then pass "no-arm default still peak-refuses (back-compat)"; else fail "no-arm default: expected rc 2, got [${out%%|*}]"; fi

# ── case 4: version rotation — flash arm name with a nonexistent version ─────
out="$(run_gate 8 "glm-9.9-flash")"
if [[ "${out}" == 0\|* ]]; then pass "version-rotation: arm glm-9.9-flash passes in peak (no version literal)"; else fail "version-rotation: glm-9.9-flash refused in peak, got [${out%%|*}]"; fi

# ── case 5: NEGATIVE CONTROL — mutate the discriminator in the gate body ─────
MUT="${FIXTURE}/gate-mutated.sh"
sed 's/  \*flash\*) glm_gate_is_flash=1 ;;/  *neverflash*) glm_gate_is_flash=1 ;;/' "${GATE}" > "${MUT}"
if grep -q '\*neverflash\*' "${MUT}"; then
  out="$(LEADV2_QUOTA_LIVE="${FIXTURE}/quota-live-stub.sh" GLM_SIMULATE_UTC_HOUR=8 \
        LEADV2_GLM_GATE_ARM="glm-flash" bash "${MUT}" 2>&1 >/dev/null)"; mrc=$?
  if [[ "${mrc}" -eq 2 ]]; then
    pass "mutation: flash no longer recognised -> case 1 goes RED (rc 2, peak refuse)"
  else
    fail "mutation: expected the mutated gate to refuse (rc 2), got rc=${mrc}"
  fi
  # restore = the pristine gate again; case 1 green
  out="$(run_gate 8 "glm-flash")"
  if [[ "${out}" == 0\|* ]]; then pass "restore: pristine gate green again (rc 0)"; else fail "restore: expected rc 0 after restore, got [${out%%|*}]"; fi
else
  fail "mutation: sed did not apply to the discriminator line — negative control never ran"
fi

printf -- '[TEST] %s: %d passed, %d failed\n' "test-glm-peak-flash-gate" "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
