# Hack-Detection Review: build-attempt-1.diff

## Findings

FINDING: severity=High file=plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh line=29 dimension=hack desc=Broad silent exception: `} 2>/dev/null || true` suppresses all errors (file writes, mkdir, disk full, permissions) from entire verdict-recording block without any logging or alerting

FINDING: severity=Medium file=plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh line=17 dimension=hack desc=Silent mkdir: `mkdir -p "$_lv2_gv_dir" 2>/dev/null` swallows permission denied, disk full, and other critical errors silently

FINDING: severity=Medium file=plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh line=18 dimension=hack desc=Silent fallback: `date` failure returns string "unknown-ts" instead of ISO timestamp, creating invalid journal records with semantic mismatch

FINDING: severity=Low file=plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh line=22 dimension=hack desc=Silent grep: `grep -q ... 2>/dev/null` masks file-not-found errors when $STDOUT_FILE doesn't exist

## Analysis

The verdict-recording block (lines 15–29) in leadv2-bash-pre-dispatch.sh attempts to journal guard execution outcomes to enable the census to track which guards ran. However, the implementation has multiple silent-failure points:

1. **Line 29 (Critical):** The entire block is wrapped in `} 2>/dev/null || true`, creating a broad exception handler that silences ALL errors—including:
   - mkdir failures (permission denied, disk full)
   - Journal file write failures (I/O errors, disk full)
   - Date command failures
   - Grep errors
   
   This means if the journal cannot be written (e.g., permission denied on the cache directory, disk full), the verdict record is silently lost, and the guard census will still report "never-ran" for a guard that actually executed.

2. **Line 17 (Medium):** `mkdir -p "$_lv2_gv_dir" 2>/dev/null` creates the verdict cache directory but silently ignores all errors. If this fails, the subsequent append to `journal.tsv` (line 20, 27) will fail, but that failure is also silenced by the outer `2>/dev/null || true`.

3. **Line 18 (Medium):** `date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown-ts` falls back to the literal string `"unknown-ts"` if date fails. This is then written to the journal.tsv, creating semantically invalid records (a string instead of a timestamp). The journal consumer may misparse or skip these rows.

4. **Line 22 (Low):** `grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' "$STDOUT_FILE" 2>/dev/null` silently masks file-not-found errors if $STDOUT_FILE doesn't exist or is unreadable. While grep's non-match is expected, a true file error (e.g., permission denied on $STDOUT_FILE) is indistinguishable from no match.

## Recommendation

- **High:** Add logging (even if brief) when the verdict-recording block fails. At minimum, log to a separate error file or stderr before the `|| true`.
- **Medium:** Validate that mkdir succeeded before attempting to write. Consider checking the exit code.
- **Medium:** Validate that date succeeded and return a safe fallback (e.g., the empty string or a sentinel that is clearly not a timestamp), not the misleading "unknown-ts" string.
- **Low:** If $STDOUT_FILE is critical, check that it exists and is readable before grep, or log any unexpected state.

DELIVERABLE_COMPLETE
