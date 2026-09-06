#!/usr/bin/env bash
# run-all-triggers: leadv2-mutation-control leadv2-dod-gate
#
# MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01 — the control artifact's
# lane identity is the sha256 of an EMPTY diff for a whole class of lanes, and
# nothing notices.
#
# Measured 2026-09-05 across all 63 mutation-control artifacts in the tree: 8
# carry `lane_diff_hash=e3b0c442…7852b855`, which is sha256 of empty input. All
# 8 carry a real, distinct `diff_hash`, so the mutation itself WAS applied in
# every one — what is missing is not the proof, it is the identity. The artifact
# still proves "the suite goes red"; it stops proving "it goes red ON THIS WORK",
# and with the field empty all such artifacts are indistinguishable.
#
# The mechanism is two lines. leadv2-mutation-control.sh computes
#     LANE_DIFF_HASH="$(git diff <base> HEAD … | shasum -a 256 …)"
# and then guards `[[ -z "${LANE_DIFF_HASH}" ]]`. shasum of empty input is not
# an empty string — it is a perfectly well-formed hash — so the guard tests the
# hash string instead of the diff and can never fire for the case it exists for.
# A lane working in the canonical checkout has main == HEAD, hence no diff,
# hence this every single time.
#
# The consumer has the mirror hole: lib/leadv2-dod-gate.sh already rejects the
# empty hash for `artifact_hash`, but for `lane_hash` it only compares against a
# value it recomputes the same way — so in exactly the degenerate case both
# sides are the empty hash and compare EQUAL. The check passes with maximum
# confidence on zero information.
#
# WHAT IS REAL HERE. Every case runs the real leadv2-mutation-control.sh against
# a real throwaway git repository holding a real production file and a real
# suite that genuinely goes red under the mutation. Nothing stubs
# _mc_resolve_base, the hash computation, or the artifact writer; the fake is one
# level lower — the repository's own history shape.
#
# RED-FIRST. Cases 1-3 and 5 assert the behaviour this row asks for and are RED
# until the producer is fixed; that is the defect being exhibited, not a broken
# suite. Case 4 is the positive control and must be GREEN both before and after:
# it proves the instrument CAN produce a real lane identity, so the reds are
# about the degenerate case and nothing else.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$(cd "${SCRIPT_DIR}/.." && pwd)/leadv2-mutation-control.sh"
EMPTY_SHA=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
T="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# mkrepo <name> -> a real git repo whose suite really reddens under the mutation.
# Prints the repo path. `main` is left pointing at HEAD, which is the whole
# point: this is the shape every lane that works in the canonical checkout has.
mkrepo() {
  local r="$T/$1"
  mkdir -p "$r/plugins/leadv2/scripts/tests" "$r/docs/handoff/LANE"
  cat > "$r/plugins/leadv2/scripts/prod.sh" <<'EOF'
#!/usr/bin/env bash
decide() {
  local answer="known"
  printf '%s\n' "$answer"
}
EOF
  cat > "$r/plugins/leadv2/scripts/tests/test-prod.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
d="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$d/prod.sh"
[[ "$(decide)" == "known" ]] || { echo "FAIL: decide changed"; exit 1; }
echo "PASS: decide"
EOF
  chmod +x "$r/plugins/leadv2/scripts/tests/test-prod.sh"
  git -C "$r" init -q
  git -C "$r" config user.email t@e.com
  git -C "$r" config user.name t
  git -C "$r" add -A >/dev/null 2>&1
  git -C "$r" commit -q -m base
  git -C "$r" branch -f main HEAD 2>/dev/null || git -C "$r" branch -M main
  printf '%s' "$r"
}

# the mutation: applied by REGEX to a line INSIDE decide()'s body
SED='s/  local answer="known"/  local answer="mutated"/'
run_tool() { # <repo> [env assignments...] -> sets OUT RC
  local r="$1"; shift
  OUT="$(cd "$r" && env "$@" timeout 240 bash "$TOOL" \
    plugins/leadv2/scripts/tests/test-prod.sh \
    plugins/leadv2/scripts/prod.sh \
    "$SED" \
    docs/handoff/LANE 2>&1)"
  RC=$?
}

# ── 1. THE REFUSAL. An empty lane diff is not an identity. It must refuse.
R="$(mkrepo r1)"
run_tool "$R" LEADV2_LANE_START_SHA=
if [[ "$RC" == 2 ]] && printf '%s' "$OUT" | grep -q 'control_not_applied'; then
  ok "a lane with no diff against its base is refused, not stamped (rc=2, control_not_applied)"
else
  bad "1: rc=$RC out=$(printf '%s' "$OUT" | tail -1 | cut -c1-140)"
fi

# ── 2. NOTHING IS WRITTEN. A refused control that still leaves an artifact is
#      worse than no control: the artifact outlives the refusal.
if ! grep -rlq "lane_diff_hash=${EMPTY_SHA}" "$R/docs/handoff/LANE" 2>/dev/null; then
  ok "no artifact carrying the empty-diff hash is left behind"
else
  bad "2: an artifact with lane_diff_hash=${EMPTY_SHA:0:8}… was written anyway"
fi

# ── 3. THE REFUSAL IS ACTIONABLE. Refusing here means a lane working in the
#      canonical checkout cannot produce an artifact until it names its start
#      commit. That is a real constraint, so the refusal has to SAY it —
#      otherwise the next lane concludes the tool is broken.
if printf '%s' "$OUT" | grep -q 'LEADV2_LANE_START_SHA'; then
  ok "the refusal names LEADV2_LANE_START_SHA, so the lane knows what to do next"
else
  bad "3: refusal does not say how to resolve it: $(printf '%s' "$OUT" | tail -1 | cut -c1-140)"
fi

# ── 4. POSITIVE CONTROL — must be green before AND after. With a real start
#      commit the identity resolves, and the tool works exactly as before.
R2="$(mkrepo r4)"
BASE="$(git -C "$R2" rev-parse HEAD)"
printf '\n# lane work\n' >> "$R2/plugins/leadv2/scripts/prod.sh"
git -C "$R2" add -A >/dev/null 2>&1
git -C "$R2" commit -q -m "lane work"
run_tool "$R2" "LEADV2_LANE_START_SHA=$BASE"
LANE_HASH="$(printf '%s' "$OUT" | grep -o 'lane_diff_hash=[0-9a-f]*' | head -1 | cut -d= -f2)"
if [[ "$RC" == 0 ]] && [[ -n "$LANE_HASH" ]] && [[ "$LANE_HASH" != "$EMPTY_SHA" ]]; then
  ok "with a real start commit the control succeeds and its lane identity is real (${LANE_HASH:0:8}…)"
else
  bad "4: rc=$RC lane_hash=${LANE_HASH:-<none>} out=$(printf '%s' "$OUT" | tail -1 | cut -c1-120)"
fi

# ── 5. THE EMPTY HASH IS NEVER A VALUE. Whatever the outcome, that one hash
#      must not appear as a lane identity in what THIS RUN wrote.
#
#      MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01 adjudication, 2026-09-06:
#      this case used to say "in any artifact". It checks two fixture lane
#      directories this suite created itself, and the live tree carries 8
#      artifacts with lane_diff_hash=<empty sha> to this day (all 8 in the
#      lane position, 0 in the mutation position -- the report's central claim,
#      recounted independently). A sentence broader than its subject is how a
#      sentinel comes to be trusted for something it never looked at, so the
#      sentence now names its scope, and 5b proves the check can actually fail.
_empty_identity_in() { # <dir>... -> prints the dirs that carry the empty lane id
  local d out=""
  for d in "$@"; do
    [[ -d "${d}" ]] || continue
    if grep -rq "lane_diff_hash=${EMPTY_SHA}" "$d" 2>/dev/null; then out="${out}${d} "; fi
  done
  printf '%s' "${out}"
}
found="$(_empty_identity_in "$R/docs/handoff/LANE" "$R2/docs/handoff/LANE")"
if [[ -z "$found" ]]; then
  ok "no artifact THIS RUN wrote (the two fixture lanes) carries the empty sha as a lane identity"
else
  bad "5: present in: $found"
fi

# ── 5b. PAIRED NEGATIVE. Case 5 asserts an absence, and an absence check that
#       cannot detect a presence is worth nothing -- it would read green over a
#       tree full of empty identities. Seed one and require it to be seen.
SEED_DIR="${R}/docs/handoff/LANE-SEEDED"
mkdir -p "${SEED_DIR}"
printf 'MUTATION-CONTROL ok suite=x file=y lane_diff_hash=%s\n' "${EMPTY_SHA}" \
  > "${SEED_DIR}/artifact.md"
if [[ -n "$(_empty_identity_in "${SEED_DIR}")" ]]; then
  ok "5b NEG-CTL: a seeded empty lane identity IS detected (the absence check can fail)"
else
  bad "5b NEG-CTL: the check missed a planted empty lane identity — case 5 proves nothing"
fi
rm -rf "${SEED_DIR}"

# ── 6. THE CONSUMER'S MIRROR HOLE. lib/leadv2-dod-gate.sh has guarded the
#      MUTATION hash against the empty-diff sha since it was written; the LANE
#      hash beside it had no such guard and was only compared against a value
#      the gate recomputes the same way from the same repository. In the
#      degenerate case BOTH sides are that same empty hash and compare EQUAL —
#      so the check passed with maximum confidence on zero information. Not
#      "unknown became permission": unknown became positive CONFIRMATION.
#
#      Driven against the REAL _dod_valid_mutation_artifact, with a real
#      artifact file on disk; only the artifact's contents are authored.
GATE_LIB="$(cd "${SCRIPT_DIR}/../lib" && pwd)/leadv2-dod-gate.sh"
mk_artifact() { # <path> <lane_hash>
  cat > "$1" <<ART
suite=plugins/leadv2/scripts/tests/test-prod.sh
file=plugins/leadv2/scripts/prod.sh
baseline_rc=0
mutated_rc=1
diff_hash=615157a58ff4790988bfa80cd54e6da4f95322f8d67d6c8e121ca26dc06c3f7e
lane_diff_hash=$2
ART
}
mk_artifact "$T/art-empty.txt" "$EMPTY_SHA"
mk_artifact "$T/art-real.txt"  "670aa6f4b2c1d3e4f5061728394a5b6c7d8e9f00112233445566778899aabbcc"
cons="$(bash -c '
  source "$1" >/dev/null 2>&1 || exit 99
  declare -F _dod_valid_mutation_artifact >/dev/null || { echo "nofunc"; exit 98; }
  _dod_valid_mutation_artifact "$2" "$4"; echo "empty_vs_empty=$?"
  _dod_valid_mutation_artifact "$3" "670aa6f4b2c1d3e4f5061728394a5b6c7d8e9f00112233445566778899aabbcc"; echo "real_vs_real=$?"
' _ "$GATE_LIB" "$T/art-empty.txt" "$T/art-real.txt" "$EMPTY_SHA" 2>&1)"
if printf '%s' "$cons" | grep -q 'empty_vs_empty=1' \
   && printf '%s' "$cons" | grep -q 'real_vs_real=0'; then
  ok "the gate refuses an empty lane identity even when its own expected value is equally empty, and still accepts a real one"
else
  bad "6: $(printf '%s' "$cons" | tr '\n' ' ' | cut -c1-160)"
fi

printf '[MUTATION-CONTROL-LANE-IDENTITY] pass=%d fail=%d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
