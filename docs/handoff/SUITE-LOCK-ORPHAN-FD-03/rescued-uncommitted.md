# SUITE-LOCK-ORPHAN-FD-03 — uncommitted work rescued from the checkout

Carried out of `.claude/worktrees/SUITE-LOCK-ORPHAN-FD-03` on 2026-09-06 by the blocking filter of
LEADV2-WORKTREE-ADJUDICATION-01, **before** any verdict was written about the
branch. A lane's branch can be an empty anchor while the work sits untracked or
merely staged inside its checkout: `git log` never sees the index, and removing
the checkout would take both with it.

Text only — nothing here is installed or made executable. Restoring any of it is
a deliberate act by whoever owns the row.

## `git diff HEAD -- plugins tests` (staged and unstaged)

```diff
diff --git a/plugins/leadv2/scripts/tests/run-core-offline.sh b/plugins/leadv2/scripts/tests/run-core-offline.sh
index 8306bf59..b6fbd451 100755
--- a/plugins/leadv2/scripts/tests/run-core-offline.sh
+++ b/plugins/leadv2/scripts/tests/run-core-offline.sh
@@ -61,10 +61,26 @@ fi
 # literal path (that is the regression this comment exists to prevent).
 #
 # LEADV2_SUITE_LOCK_DISABLE=1 is the kill-switch (debugging, or a caller that
-# has already serialized externally). Default wait is unbounded (matches "the
-# lane should finish, not race") — set LEADV2_SUITE_LOCK_WAIT_S for a bounded
-# wait (used by tests, and by any caller that prefers a fast, loud failure to
-# a long silent block).
+# has already serialized externally).
+#
+# SUITE-LOCK-ORPHAN-FD-03: the default wait used to be unbounded ("the lane
+# should finish, not race"), but that reasoning only holds if the holder is
+# guaranteed to release. It is not: a child of a suite that outlives the
+# suite (a backgrounded `sleep`, a detached worker, anything reparented to
+# launchd) inherits fd 9 and keeps the flock alive long after the run that
+# opened it has exited. An unbounded waiter then queues behind a corpse
+# forever, gets killed from outside by its own dispatch timeout with no
+# reason recorded anywhere, and (having never reached its own run) leaves
+# nothing behind to explain why -- this is what made six lanes on
+# 2026-08-31 read as "died silently" when they were in fact queuing on a
+# lock nothing was ever going to release. See the fd-inheritance fix below
+# (`9<&-` on every suite invocation) for the other half of this: closing the
+# fd stops NEW orphans from being created, but does not un-stick a waiter
+# already queued behind one made before that fix existed, so the wait must
+# also be bounded. `LEADV2_SUITE_LOCK_WAIT_S` still overrides the default
+# (0 or any explicit value); unset means "use the bounded default", not
+# "wait forever".
+LEADV2_SUITE_LOCK_WAIT_S_DEFAULT=600
 LEADV2_SUITE_LOCK_DISABLE="${LEADV2_SUITE_LOCK_DISABLE:-0}"
 # bash-3.2-safe slug: no external hashing tool needed for the default case,
 # and no `${var//pat/rep}` surprises across worktree paths that only differ
@@ -77,7 +93,11 @@ _core_offline_lock_slug() {
   s="${s//[^A-Za-z0-9]/-}"
   printf '%s' "$s"
 }
-LEADV2_SUITE_LOCK_FILE="${LEADV2_SUITE_LOCK_FILE:-/tmp/leadv2-core-offline-$(_core_offline_lock_slug "$REPO_ROOT").lock}"
+# ${TMPDIR:-/tmp}, matching RUN_TMP below: lets a test redirect the DEFAULT
+# lock location into a private fixture directory via TMPDIR, so a scoping
+# test never has to compute a path under the real, shared /tmp namespace
+# that live lanes on this machine use (SUITE-LOCK-ORPHAN-FD-03).
+LEADV2_SUITE_LOCK_FILE="${LEADV2_SUITE_LOCK_FILE:-${TMPDIR:-/tmp}/leadv2-core-offline-$(_core_offline_lock_slug "$REPO_ROOT").lock}"
 # Pure introspection (lists the shard partition, runs nothing) never needs to
 # serialize against a concurrent real run — skip the lock entirely for it.
 if [[ "$LEADV2_SUITE_LOCK_DISABLE" != "1" && -z "${LEADV2_SUITE_SHARDS_DUMP:-}" ]]; then
@@ -89,17 +109,27 @@ if [[ "$LEADV2_SUITE_LOCK_DISABLE" != "1" && -z "${LEADV2_SUITE_SHARDS_DUMP:-}"
   exec 9<>"$LEADV2_SUITE_LOCK_FILE"
   if ! flock -n 9; then
     _lock_holder="$(cat "$LEADV2_SUITE_LOCK_FILE" 2>/dev/null || true)"
-    printf -- '[CORE-OFFLINE] waiting for lock file=%s holder=%s (held by a concurrent run)\n' \
-      "$LEADV2_SUITE_LOCK_FILE" "${_lock_holder:-<unknown>}" >&2
-    if [[ -n "${LEADV2_SUITE_LOCK_WAIT_S:-}" ]]; then
-      if ! flock -w "$LEADV2_SUITE_LOCK_WAIT_S" 9; then
-        _lock_holder="$(cat "$LEADV2_SUITE_LOCK_FILE" 2>/dev/null || true)"
-        printf -- '[CORE-OFFLINE] FATAL lock_timeout file=%s wait_s=%s holder=%s\n' \
-          "$LEADV2_SUITE_LOCK_FILE" "$LEADV2_SUITE_LOCK_WAIT_S" "${_lock_holder:-<unknown>}" >&2
-        exit 2
+    _lock_wait_s="${LEADV2_SUITE_LOCK_WAIT_S:-$LEADV2_SUITE_LOCK_WAIT_S_DEFAULT}"
+    printf -- '[CORE-OFFLINE] waiting for lock file=%s holder=%s wait_s=%s (held by a concurrent run)\n' \
+      "$LEADV2_SUITE_LOCK_FILE" "${_lock_holder:-<unknown>}" "$_lock_wait_s" >&2
+    if ! flock -w "$_lock_wait_s" 9; then
+      _lock_holder="$(cat "$LEADV2_SUITE_LOCK_FILE" 2>/dev/null || true)"
+      _lock_holder_age_s="unknown"
+      _lock_holder_since="$(printf '%s' "${_lock_holder:-}" | sed -n 's/.*since=\([0-9TZ:-]*\).*/\1/p')"
+      if [[ -n "$_lock_holder_since" ]]; then
+        _lock_holder_epoch="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_lock_holder_since" +%s 2>/dev/null || true)"
+        if [[ -z "$_lock_holder_epoch" ]]; then
+          # GNU date fallback (Linux CI / non-BSD date) -- `-j -f` above is
+          # the macOS/BSD form; harmless no-op failure there under BSD date.
+          _lock_holder_epoch="$(date -u -d "$_lock_holder_since" +%s 2>/dev/null || true)"
+        fi
+        if [[ -n "$_lock_holder_epoch" ]]; then
+          _lock_holder_age_s=$(( $(date -u +%s) - _lock_holder_epoch ))
+        fi
       fi
-    else
-      flock 9
+      printf -- '[CORE-OFFLINE] FATAL lock_timeout file=%s wait_s=%s holder=%s holder_age_s=%s\n' \
+        "$LEADV2_SUITE_LOCK_FILE" "$_lock_wait_s" "${_lock_holder:-<unknown>}" "$_lock_holder_age_s" >&2
+      exit 2
     fi
   fi
   # We now hold the lock (immediately or after waiting) -- stamp holder info
@@ -235,10 +265,25 @@ run_check() {
   fi
 
   local cmd_rc=0
+  # SUITE-LOCK-ORPHAN-FD-03: `9<&-` closes fd 9 (the suite lock, opened above
+  # with `exec 9<>...` when the lock is active) for THIS command only. bash
+  # applies per-command redirections around fork+exec for an external command,
+  # so the child's exec()'d image never has fd 9 open at all -- anything IT
+  # forks (a backgrounded `sleep`, a detached worker, anything that outlives
+  # the suite and gets reparented to launchd) inherits nothing to hold the
+  # flock open with. For the two function-based checks (syntax_all,
+  # validate_plugin, no fork/exec -- see the cmd=("$@") branch above) bash
+  # saves/restores fd 9 around the call instead of closing it for real, so
+  # the runner's own hold on the lock is untouched either way. A silent no-op
+  # when the lock was never opened (LEADV2_SUITE_LOCK_DISABLE=1): closing an
+  # fd that isn't open is not an error. Do not drop this on children whose
+  # `sleep 900 &`-style orphans held the machine-wide lock for up to 15
+  # minutes each on 2026-08-31 -- that incident is exactly what an inherited
+  # fd 9 reproduces.
   if [[ -n "$suite_home" ]]; then
-    HOME="$suite_home" PYTHONUSERBASE="$_CORE_OFFLINE_PYTHONUSERBASE" "${cmd[@]}" || cmd_rc=$?
+    HOME="$suite_home" PYTHONUSERBASE="$_CORE_OFFLINE_PYTHONUSERBASE" "${cmd[@]}" 9<&- || cmd_rc=$?
   else
-    "${cmd[@]}" || cmd_rc=$?
+    "${cmd[@]}" 9<&- || cmd_rc=$?
   fi
   if [[ "$cmd_rc" -eq 0 ]]; then
     PASS=$((PASS + 1))
```

## `plugins/leadv2/scripts/tests/test-suite-lock-scope.sh` (untracked, 14862 bytes)

```
#!/usr/bin/env bash
# test-suite-lock-scope.sh — SUITE-LOCK-ORPHAN-FD-03
#
# Round 1 (SUITE-LOCK-IS-MACHINE-WIDE-01, 57aa62a) scoped run-core-offline.sh's
# suite lock to REPO_ROOT instead of a single machine-wide /tmp path, but
# shipped with no suite of its own. Round 2 additionally closes the
# fd-inheritance hole (an orphaned child of a suite kept the flock alive
# forever) and bounds the default wait (an unbounded wait made a queued run
# indistinguishable from a dead one). This suite locks all three in:
#
#   1. two runs in DIFFERENT roots            -> neither waits on the other
#   2. two runs in the SAME root               -> the second one contends
#   3. a run whose child outlives it (orphan)  -> the NEXT run acquires
#                                                  immediately (no held fd)
#   4. a run that cannot acquire within budget -> loud, bounded, non-zero,
#                                                  names file+holder+age; and
#                                                  the unset-default is itself
#                                                  bounded (not infinite)
#   5. LEADV2_SUITE_LOCK_DISABLE=1              -> no lock taken (regression)
#   6. LEADV2_SUITE_LOCK_FILE override          -> still honoured (regression)
#
# Restoring the pre-round-1 hardcoded machine-wide path collapses case 1's two
# independent default-derived paths into one, so case 1 (which deliberately
# never sets LEADV2_SUITE_LOCK_FILE) is the negative control for that
# regression — see the "case 1" comment below and report.md for the RED/GREEN
# proof.
#
# Every fixture lives under its own throwaway TMPDIR (never the real /tmp
# leadv2-core-offline* files a live lane on this machine might be holding —
# see the TMPDIR-redirect comment on LEADV2_SUITE_LOCK_FILE's default in
# run-core-offline.sh) and every fixture is a scratch git repo, never a real
# lane worktree.

set -euo pipefail

# --- locate the runner under test (physical, not logical) -------------------
_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
TEST_DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _dir
RUNNER="$TEST_DIR/run-core-offline.sh"

pass=0
fail=0
cleanup_items=()
cleanup_pids=()
cleanup() {
  local p
  for p in "${cleanup_pids[@]:-}"; do
    [[ -n "$p" ]] && kill "$p" 2>/dev/null || true
  done
  for p in "${cleanup_pids[@]:-}"; do
    [[ -n "$p" ]] && wait "$p" 2>/dev/null || true
  done
  local item
  for item in "${cleanup_items[@]:-}"; do
    rm -rf "$item" 2>/dev/null || true
  done
}
trap cleanup EXIT

# --- helpers -----------------------------------------------------------------

# Extract a KEY=value token from a probe/diagnostic line (values are
# space-free by construction — pid=, host=, since=, file=, holder_age_s=).
probe_field() {
  local key="$1" line="$2"
  printf '%s' "$line" | sed -nE "s/.*${key}=([^ ]*).*/\1/p"
}

# A scratch git repo with the runner symlinked in at the conventional
# .claude/scripts/tests location (mirrors test-core-offline-root-arith.sh's
# fixture (a) — the symlink-entry shape every real consumer repo uses).
make_fixture_root() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@test.test
  git -C "$dir" config user.name Test
  mkdir -p "$dir/.claude/scripts/tests"
  ln -s "$RUNNER" "$dir/.claude/scripts/tests/run-core-offline.sh"
  touch "$dir/.gitkeep"
  git -C "$dir" add -A
  git -C "$dir" commit -qm init >/dev/null
  printf '%s' "$dir"
}

# Runs the runner's own probe mode against a fixture root's OWN private
# TMPDIR (never the real /tmp) and prints the default-derived lock file path.
# Fast: probe mode acquires-then-exits immediately, so this never contends.
discover_default_lock_file() {
  local root="$1" tmp="$2" out
  out="$(env -u LEADV2_SUITE_LOCK_FILE TMPDIR="$tmp" LEADV2_SUITE_LOCK_PROBE=1 \
    bash "$root/.claude/scripts/tests/run-core-offline.sh" 2>&1)" || true
  probe_field file "$out"
}

# Holds a lock file exactly like a real holder would (flock + the same
# holder-diagnostic content run-core-offline.sh itself writes), for
# <secs> seconds, in the background. Prints the holder pid.
hold_lock_external() {
  local lockfile="$1" secs="$2" since="${3:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  # `>/dev/null 2>&1` on the backgrounded subshell is load-bearing, not
  # cosmetic: this function is always invoked as `x="$(hold_lock_external
  # ...)"`, and a command substitution's pipe only reaches EOF once EVERY
  # process holding its write end has closed it. Without an explicit
  # redirect the backgrounded child inherits that same pipe fd, so the
  # substitution blocks for the full `sleep "$secs"` instead of returning
  # immediately with the pid -- silently turning "hold in the background"
  # into "hold synchronously", which makes every case below race against a
  # holder that never actually overlaps the probe it's supposed to contend
  # with (caught empirically: cases 2/4a/4b all read "lock-probe acquired"
  # immediately, holder_age/wait_s came back empty).
  (
    exec 9<>"$lockfile"
    flock -x 9
    printf 'pid=%s host=%s since=%s\n' "$$" "$(hostname 2>/dev/null || printf unknown)" \
      "$since" >"$lockfile" 2>/dev/null || true
    sleep "$secs"
  ) >/dev/null 2>&1 &
  echo $!
}

# Runs a bounded command in the background and kills it if it outlives
# <deadline_s> — a portable (no external `timeout`/`gtimeout` dependency)
# safety belt so a red mutation (e.g. a reverted-to-unbounded default wait)
# fails this suite loudly within seconds instead of hanging the whole
# verification run.
run_with_deadline() {
  local deadline="$1"; shift
  local outfile rc=0
  outfile="$(mktemp)"
  "$@" >"$outfile" 2>&1 &
  local cmd_pid=$!
  ( sleep "$deadline"; kill -9 "$cmd_pid" 2>/dev/null || true ) &
  local watchdog_pid=$!
  wait "$cmd_pid" 2>/dev/null || rc=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  cat "$outfile"
  rm -f "$outfile"
  return "$rc"
}

# --- fixtures ------------------------------------------------------------
root_a="$(make_fixture_root)"; cleanup_items+=("$root_a")
root_b="$(make_fixture_root)"; cleanup_items+=("$root_b")
tmp_a="$(mktemp -d)"; cleanup_items+=("$tmp_a")
tmp_b="$(mktemp -d)"; cleanup_items+=("$tmp_b")

lock_a="$(discover_default_lock_file "$root_a" "$tmp_a")"
lock_b="$(discover_default_lock_file "$root_b" "$tmp_b")"

echo "[LOCK-SCOPE] discovered default lock files:"
echo "[LOCK-SCOPE]   root_a -> $lock_a"
echo "[LOCK-SCOPE]   root_b -> $lock_b"

# --- case 1: different roots never collide (negative control for the ------
# pre-round-1 hardcoded machine-wide path: restoring that path collapses
# lock_a/lock_b to the SAME string, and this whole case goes red) -----------
echo "[LOCK-SCOPE] case 1: two different roots proceed independently"
if [[ -z "$lock_a" || -z "$lock_b" ]]; then
  echo "[LOCK-SCOPE]   (1) FAIL: could not discover a default lock path (lock_a='$lock_a' lock_b='$lock_b')"
  fail=$((fail + 1))
elif [[ "$lock_a" == "$lock_b" ]]; then
  echo "[LOCK-SCOPE]   (1) FAIL: root_a and root_b derived the SAME lock file ($lock_a) — machine-wide path regression"
  fail=$((fail + 1))
else
  holder_pid="$(hold_lock_external "$lock_a" 2)"
  cleanup_pids+=("$holder_pid")
  sleep 0.3
  start_ts=$(date +%s)
  if out_b="$(env -u LEADV2_SUITE_LOCK_FILE TMPDIR="$tmp_b" LEADV2_SUITE_LOCK_PROBE=1 \
    bash "$root_b/.claude/scripts/tests/run-core-offline.sh" 2>&1)"; then
    rc_b=0
  else
    rc_b=$?
  fi
  end_ts=$(date +%s)
  wait "$holder_pid" 2>/dev/null || true
  if [[ "$rc_b" -eq 0 ]] && ! echo "$out_b" | grep -q 'waiting for lock' \
    && echo "$out_b" | grep -q 'lock-probe acquired' && (( end_ts - start_ts < 2 )); then
    echo "[LOCK-SCOPE]   (1) root_b proceeded immediately while root_a's lock was held ✓ (elapsed $((end_ts - start_ts))s)"
    pass=$((pass + 1))
  else
    echo "[LOCK-SCOPE]   (1) FAIL rc=$rc_b elapsed=$((end_ts - start_ts))s out=<<<$out_b>>>"
    fail=$((fail + 1))
  fi
fi

# --- case 2: same root contends -------------------------------------------
echo "[LOCK-SCOPE] case 2: two runs in the SAME root contend"
holder_pid="$(hold_lock_external "$lock_a" 2)"
cleanup_pids+=("$holder_pid")
sleep 0.3
if out_a2="$(env -u LEADV2_SUITE_LOCK_FILE TMPDIR="$tmp_a" LEADV2_SUITE_LOCK_WAIT_S=10 \
  LEADV2_SUITE_LOCK_PROBE=1 bash "$root_a/.claude/scripts/tests/run-core-offline.sh" 2>&1)"; then
  rc_a2=0
else
  rc_a2=$?
fi
wait "$holder_pid" 2>/dev/null || true
if [[ "$rc_a2" -eq 0 ]] && echo "$out_a2" | grep -q 'waiting for lock' \
  && echo "$out_a2" | grep -q 'lock-probe acquired'; then
  echo "[LOCK-SCOPE]   (2) second run in same root waited then acquired ✓"
  pass=$((pass + 1))
else
  echo "[LOCK-SCOPE]   (2) FAIL rc=$rc_a2 out=<<<$out_a2>>>"
  fail=$((fail + 1))
fi

# --- case 3: orphan (child outlives the run) -> next run acquires immediately
echo "[LOCK-SCOPE] case 3: a suite's orphaned child must not hold the lock"
orphan_suite="$tmp_a/spawn-orphan.sh"
cat >"$orphan_suite" <<'EOF'
#!/usr/bin/env bash
# A suite that backgrounds a long-lived, disowned child and exits — the
# incident shape from 2026-08-31 (a "sleep 900" reparented to launchd,
# each holding the machine-wide lock for up to 15 minutes).
( sleep 30 & disown ) 2>/dev/null
exit 0
EOF
chmod +x "$orphan_suite"

run_rc=0
env -u LEADV2_SUITE_LOCK_FILE TMPDIR="$tmp_a" \
  LEADV2_SUITE_DEFS_OVERRIDE="orphan|||bash $orphan_suite" \
  bash "$root_a/.claude/scripts/tests/run-core-offline.sh" >/dev/null 2>&1 || run_rc=$?
sleep 0.5

if [[ "$run_rc" -ne 0 ]]; then
  echo "[LOCK-SCOPE]   (3) FAIL: orphan-spawning run itself failed rc=$run_rc"
  fail=$((fail + 1))
else
  start_ts=$(date +%s)
  if out_a3="$(env -u LEADV2_SUITE_LOCK_FILE TMPDIR="$tmp_a" LEADV2_SUITE_LOCK_WAIT_S=3 \
    LEADV2_SUITE_LOCK_PROBE=1 bash "$root_a/.claude/scripts/tests/run-core-offline.sh" 2>&1)"; then
    rc_a3=0
  else
    rc_a3=$?
  fi
  end_ts=$(date +%s)
  if [[ "$rc_a3" -eq 0 ]] && ! echo "$out_a3" | grep -q 'waiting for lock' \
    && echo "$out_a3" | grep -q 'lock-probe acquired' && (( end_ts - start_ts < 2 )); then
    echo "[LOCK-SCOPE]   (3) next run acquired immediately, no orphan holder ✓ (elapsed $((end_ts - start_ts))s)"
    pass=$((pass + 1))
  else
    echo "[LOCK-SCOPE]   (3) FAIL rc=$rc_a3 elapsed=$((end_ts - start_ts))s out=<<<$out_a3>>>"
    fail=$((fail + 1))
  fi
fi
# Reap the still-sleeping orphan so it doesn't outlive this suite either.
pkill -f "sleep 30" 2>/dev/null || true

# --- case 4a: explicit budget exceeded -> loud, named, non-zero -----------
echo "[LOCK-SCOPE] case 4a: explicit wait budget exceeded"
since_30s_ago="$(date -u -v-30S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d '30 seconds ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u +%Y-%m-%dT%H:%M:%SZ)"
holder_pid="$(hold_lock_external "$lock_a" 5 "$since_30s_ago")"
cleanup_pids+=("$holder_pid")
sleep 0.3
if out_a4="$(env -u LEADV2_SUITE_LOCK_FILE TMPDIR="$tmp_a" LEADV2_SUITE_LOCK_WAIT_S=1 \
  LEADV2_SUITE_LOCK_PROBE=1 bash "$root_a/.claude/scripts/tests/run-core-offline.sh" 2>&1)"; then
  rc_a4=0
else
  rc_a4=$?
fi
wait "$holder_pid" 2>/dev/null || true
holder_age="$(probe_field holder_age_s "$out_a4")"
if [[ "$rc_a4" -ne 0 ]] && echo "$out_a4" | grep -q 'FATAL lock_timeout' \
  && echo "$out_a4" | grep -q "file=$lock_a" && echo "$out_a4" | grep -q 'holder=pid=' \
  && [[ "$holder_age" =~ ^[0-9]+$ ]] && (( holder_age >= 25 )); then
  echo "[LOCK-SCOPE]   (4a) bounded wait times out naming file+holder+age ($holder_age s) ✓"
  pass=$((pass + 1))
else
  echo "[LOCK-SCOPE]   (4a) FAIL rc=$rc_a4 holder_age='$holder_age' out=<<<$out_a4>>>"
  fail=$((fail + 1))
fi

# --- case 4b: the UNSET default is itself bounded, not infinite ----------
# Deliberately does not set LEADV2_SUITE_LOCK_WAIT_S. A holder that releases
# quickly proves the default resolves to a real positive number in normal
# operation; run_with_deadline caps the whole check at 15s so a regression to
# an unconditional `flock 9` (no bound at all) fails loudly here instead of
# hanging this suite for the production default's full budget.
echo "[LOCK-SCOPE] case 4b: default wait (unset) is bounded, not unbounded"
root_c="$(make_fixture_root)"; cleanup_items+=("$root_c")
tmp_c="$(mktemp -d)"; cleanup_items+=("$tmp_c")
lock_c="$(discover_default_lock_file "$root_c" "$tmp_c")"
holder_pid="$(hold_lock_external "$lock_c" 1)"
cleanup_pids+=("$holder_pid")
sleep 0.3
if out_c4="$(run_with_deadline 15 env -u LEADV2_SUITE_LOCK_FILE TMPDIR="$tmp_c" \
  LEADV2_SUITE_LOCK_PROBE=1 bash "$root_c/.claude/scripts/tests/run-core-offline.sh")"; then
  rc_c4=0
else
  rc_c4=$?
fi
wait "$holder_pid" 2>/dev/null || true
default_wait_s="$(probe_field wait_s "$out_c4")"
if [[ "$rc_c4" -eq 0 ]] && echo "$out_c4" | grep -q 'lock-probe acquired' \
  && [[ "$default_wait_s" =~ ^[0-9]+$ ]] && (( default_wait_s > 0 )); then
  echo "[LOCK-SCOPE]   (4b) unset default announced a bounded wait_s=$default_wait_s and succeeded ✓"
  pass=$((pass + 1))
else
  echo "[LOCK-SCOPE]   (4b) FAIL rc=$rc_c4 default_wait_s='$default_wait_s' out=<<<$out_c4>>>"
  fail=$((fail + 1))
fi

# --- case 5: kill-switch bypasses even a held lock (regression guard) -----
echo "[LOCK-SCOPE] case 5: LEADV2_SUITE_LOCK_DISABLE=1 bypasses a held lock"
holder_pid="$(hold_lock_external "$lock_a" 2)"
cleanup_pids+=("$holder_pid")
sleep 0.3
if out_a5="$(env -u LEADV2_SUITE_LOCK_FILE TMPDIR="$tmp_a" LEADV2_SUITE_LOCK_DISABLE=1 \
  LEADV2_SUITE_LOCK_PROBE=1 bash "$root_a/.claude/scripts/tests/run-core-offline.sh" 2>&1)"; then
  rc_a5=0
else
  rc_a5=$?
fi
wait "$holder_pid" 2>/dev/null || true
if [[ "$rc_a5" -eq 0 ]] && ! echo "$out_a5" | grep -q 'waiting for lock' \
  && echo "$out_a5" | grep -q 'lock-probe acquired'; then
  echo "[LOCK-SCOPE]   (5) kill-switch bypassed the held lock ✓"
  pass=$((pass + 1))
else
  echo "[LOCK-SCOPE]   (5) FAIL rc=$rc_a5 out=<<<$out_a5>>>"
  fail=$((fail + 1))
fi

# --- case 6: explicit LEADV2_SUITE_LOCK_FILE still overrides (regression) -
echo "[LOCK-SCOPE] case 6: explicit LEADV2_SUITE_LOCK_FILE overrides the default"
explicit_lock="$tmp_b/explicit-override.lock"
if out_b6="$(env LEADV2_SUITE_LOCK_FILE="$explicit_lock" LEADV2_SUITE_LOCK_PROBE=1 \
  bash "$root_b/.claude/scripts/tests/run-core-offline.sh" 2>&1)"; then
  rc_b6=0
else
  rc_b6=$?
fi
file_b6="$(probe_field file "$out_b6")"
if [[ "$rc_b6" -eq 0 ]] && [[ "$file_b6" == "$explicit_lock" ]]; then
  echo "[LOCK-SCOPE]   (6) explicit override honoured ✓"
  pass=$((pass + 1))
else
  echo "[LOCK-SCOPE]   (6) FAIL rc=$rc_b6 file='$file_b6' expected='$explicit_lock'"
  fail=$((fail + 1))
fi

echo "[LOCK-SCOPE] pass=$pass fail=$fail"
(( fail == 0 ))
```

