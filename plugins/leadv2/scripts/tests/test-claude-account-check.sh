#!/usr/bin/env bash
# tests/test-claude-account-check.sh — TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01
#
# Hermetic coverage for leadv2-claude-account-check.sh. No network, no real
# keychain: LEADV2_CLAUDE_PROFILE_SECURITY_BIN points at a fixture stub (or
# is left unset/pointed at a nonexistent binary to exercise the no-keychain
# path). Registry + config dirs live under mktemp -d.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK_BIN="${LEADV2_TEST_ACCOUNT_CHECK_BIN:-${SCRIPTS_ROOT}/leadv2-claude-account-check.sh}"

PASS=0; FAIL=0
log()  { printf -- '[TEST] %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); log "FAIL: $1 -- ${2:-}"; }
check_grep() { if grep -qE -- "$2" <<<"$1"; then pass "$3"; else fail "$3" "no match for '$2' in: $1"; fi; }
check_nogrep() { if grep -qE -- "$2" <<<"$1"; then fail "$3" "unexpected match for '$2' in: $1"; else pass "$3"; fi; }

unset LEADV2_CLAUDE_PROFILE_SECURITY_BIN

tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-account-check.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
REG="$tmp/registry.tsv"

mk_slot() { # <dir> <sub> <account_uuid|-> <org_uuid|-> <tier|->
  mkdir -p "$1"
  printf '{"claudeAiOauth":{"accessToken":"sk-ant-fixture","subscriptionType":"%s"}}' "$2" > "$1/.credentials.json"
  if [[ "$3" == "-" ]]; then
    rm -f "$1/.claude.json"
  else
    printf '{"oauthAccount":{"accountUuid":"%s","organizationUuid":"%s","userRateLimitTier":"%s"}}' \
      "$3" "$4" "$5" > "$1/.claude.json"
  fi
}

SECURITY_STUB="$tmp/security-stub.sh"
cat > "$SECURITY_STUB" <<'SH'
#!/usr/bin/env bash
# find-generic-password -s <service> -w -> canned JSON keyed by service name
svc=""
while [[ $# -gt 0 ]]; do
  case "$1" in -s) svc="$2"; shift 2 ;; *) shift ;; esac
done
case "$svc" in
  svc-personal) printf '{"claudeAiOauth":{"accessToken":"sk-ant-p","subscriptionType":"max"}}' ;;
  svc-work) printf '{"claudeAiOauth":{"accessToken":"sk-ant-w","subscriptionType":"team"}}' ;;
  *) exit 1 ;;
esac
SH
chmod +x "$SECURITY_STUB"

run_check() { # env assignments...
  local envs=("$@")
  OUT="$(env "${envs[@]}" LEADV2_CLAUDE_PROFILES_FILE="$REG" bash "$CHECK_BIN" 2>"$tmp/err")"
  RC=$?
  ERR="$(cat "$tmp/err")"
}

echo "=== T1: two distinct accountUuids -> TWO_BUCKETS, exit 0 ==="
mkdir -p "$tmp/dir-a" "$tmp/dir-b"
mk_slot "$tmp/dir-a" max "acct-aaa111" "org-aaa" "default_claude_max_20x"
mk_slot "$tmp/dir-b" team "acct-bbb222" "org-bbb" "default_claude_max_5x"
printf 'personal\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-a" "$tmp/dir-a" > "$REG"
printf 'work\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-b" "$tmp/dir-b" >> "$REG"
run_check
check_grep "$OUT" '^slot=personal .*account=\.\.aaa111 org=\.\.rg-aaa sub=max tier=default_claude_max_20x' 'T1a: personal slot line'
check_grep "$OUT" '^slot=work .*account=\.\.bbb222 org=\.\.rg-bbb sub=team tier=default_claude_max_5x' 'T1b: work slot line'
check_grep "$OUT" '^VERDICT: TWO_BUCKETS accounts=2 creds=2$' 'T1c: verdict line'
[[ "$RC" -eq 0 ]] && pass "T1: exit 0" || fail "T1 exit" "rc=$RC"
check_nogrep "$OUT$ERR" 'sk-ant' 'T1d: no token value ever printed'

echo "=== T2: COLLAPSED -- both slots share one accountUuid -> ONE_BUCKET, exit 1 ==="
mkdir -p "$tmp/dir-c" "$tmp/dir-d"
mk_slot "$tmp/dir-c" team "acct-shared999" "org-x" "default_claude_max_5x"
mk_slot "$tmp/dir-d" team "acct-shared999" "org-x" "default_claude_max_5x"
printf 'personal\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-c" "$tmp/dir-c" > "$REG"
printf 'work\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-d" "$tmp/dir-d" >> "$REG"
run_check
check_grep "$OUT" '^VERDICT: ONE_BUCKET collapsed=\[personal,work\] account=\.\.red999$' 'T2a: collapse verdict names both labels + uuid tail'
[[ "$RC" -eq 1 ]] && pass "T2: exit 1" || fail "T2 exit" "rc=$RC"

echo "=== T3: a slot's .claude.json unreadable -> INDETERMINATE, exit 2 ==="
mkdir -p "$tmp/dir-e" "$tmp/dir-f"
mk_slot "$tmp/dir-e" max "acct-eee" "org-e" "default_claude_max_20x"
mk_slot "$tmp/dir-f" team "-" "-" "-"
printf 'personal\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-e" "$tmp/dir-e" > "$REG"
printf 'work\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-f" "$tmp/dir-f" >> "$REG"
run_check
check_grep "$ERR" 'VERDICT: INDETERMINATE reason=claude_json_unreadable slot=work' 'T3a: names the unreadable slot'
[[ "$RC" -eq 2 ]] && pass "T3: exit 2" || fail "T3 exit" "rc=$RC"

echo "=== T4: no keychain binary -> TWO_BUCKETS with creds=unavailable(no-keychain), never exit 2 ==="
mkdir -p "$tmp/dir-g" "$tmp/dir-h"
mk_slot "$tmp/dir-g" max "acct-ggg111" "org-g" "default_claude_max_20x"
mk_slot "$tmp/dir-h" team "acct-hhh222" "org-h" "default_claude_max_5x"
printf 'personal\t%s\tkeychain:svc-personal\n' "$tmp/dir-g" > "$REG"
printf 'work\t%s\tkeychain:svc-work\n' "$tmp/dir-h" >> "$REG"
run_check "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=/no/such/security/binary"
check_grep "$OUT" '^VERDICT: TWO_BUCKETS accounts=2 creds=unavailable\(no-keychain\)$' 'T4a: keychain-less verdict still resolves via accountUuid'
check_grep "$OUT" 'cred=unavailable\(no-keychain\)' 'T4b: per-slot cred field reads unavailable, not a value'
[[ "$RC" -eq 0 ]] && pass "T4: exit 0 (missing keychain never forces INDETERMINATE)" || fail "T4 exit" "rc=$RC"

echo "=== T5: keychain present -> per-slot cred is a real digest, distinct across slots ==="
mkdir -p "$tmp/dir-i" "$tmp/dir-j"
mk_slot "$tmp/dir-i" max "acct-iii111" "org-i" "default_claude_max_20x"
mk_slot "$tmp/dir-j" team "acct-jjj222" "org-j" "default_claude_max_5x"
printf 'personal\t%s\tkeychain:svc-personal\n' "$tmp/dir-i" > "$REG"
printf 'work\t%s\tkeychain:svc-work\n' "$tmp/dir-j" >> "$REG"
run_check "LEADV2_CLAUDE_PROFILE_SECURITY_BIN=$SECURITY_STUB"
check_grep "$OUT" '^VERDICT: TWO_BUCKETS accounts=2 creds=2$' 'T5a: two distinct credential digests'
check_nogrep "$OUT$ERR" 'sk-ant' 'T5b: no token value printed even with a live keychain stub'
[[ "$RC" -eq 0 ]] && pass "T5: exit 0" || fail "T5 exit" "rc=$RC"

echo "=== T6: distinct accountUuids, SAME organizationUuid -> ORG_COLLAPSE, exit 3 ==="
mkdir -p "$tmp/dir-k" "$tmp/dir-l"
ORG_SHARED="org-shared777"
mk_slot "$tmp/dir-k" max "acct-kkk111" "$ORG_SHARED" "default_claude_max_20x"
mk_slot "$tmp/dir-l" team "acct-lll222" "$ORG_SHARED" "default_claude_max_5x"
printf 'personal\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-k" "$tmp/dir-k" > "$REG"
printf 'work\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-l" "$tmp/dir-l" >> "$REG"
run_check
org_tail="..${ORG_SHARED: -6}"
check_grep "$OUT" "^VERDICT: ORG_COLLAPSE collapsed=\[personal,work\] org=${org_tail}\$" 'T6a: org-collapse verdict names both labels + org tail'
[[ "$RC" -eq 3 ]] && pass "T6: exit 3" || fail "T6 exit" "rc=$RC"
check_nogrep "$OUT$ERR" 'sk-ant' 'T6b: no token value printed on the org-collapse path'

echo "=== T7: different accountUuids AND different organizationUuids -> still TWO_BUCKETS (org branch must not over-fire) ==="
mkdir -p "$tmp/dir-m" "$tmp/dir-n"
mk_slot "$tmp/dir-m" max "acct-mmm111" "org-one111" "default_claude_max_20x"
mk_slot "$tmp/dir-n" team "acct-nnn222" "org-two222" "default_claude_max_5x"
printf 'personal\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-m" "$tmp/dir-m" > "$REG"
printf 'work\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-n" "$tmp/dir-n" >> "$REG"
run_check
check_grep "$OUT" '^VERDICT: TWO_BUCKETS accounts=2 creds=2$' 'T7a: distinct accounts + distinct orgs stays TWO_BUCKETS'
[[ "$RC" -eq 0 ]] && pass "T7: exit 0" || fail "T7 exit" "rc=$RC"

echo "=== T8: one slot's organizationUuid unresolved (-) -> TWO_BUCKETS, no spurious ORG_COLLAPSE ==="
mkdir -p "$tmp/dir-o" "$tmp/dir-p"
mk_slot "$tmp/dir-o" max "acct-ooo111" "-" "default_claude_max_20x"
mk_slot "$tmp/dir-p" team "acct-ppp222" "org-ppp999" "default_claude_max_5x"
printf 'personal\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-o" "$tmp/dir-o" > "$REG"
printf 'work\t%s\tfile:%s/.credentials.json\n' "$tmp/dir-p" "$tmp/dir-p" >> "$REG"
run_check
check_grep "$OUT" '^VERDICT: TWO_BUCKETS accounts=2 creds=2$' 'T8a: unresolved org on one slot never triggers ORG_COLLAPSE'
[[ "$RC" -eq 0 ]] && pass "T8: exit 0" || fail "T8 exit" "rc=$RC"

printf '[TEST] Results: PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
