# Lead note, 2026-09-17 — a live measurement that may be the cause

Probed `glm-4.6` directly from the VPS against `api.z.ai/api/anthropic/v1/messages`:

| max_tokens | HTTP | content[0].type | visible text |
|---|---|---|---|
| 16 | 200 | (none reached) | **empty** |
| 64 | 200 | `thinking` | **empty**, `stop_reason: max_tokens` |

GLM 4.6 emits a **thinking block before any text block**. With a small budget it spends the
whole allowance reasoning and never reaches `text` — while the transport reports success.

**Hypothesis for this row, not yet proven:** the reviewer resolves GLM, gets HTTP 200 and an
empty body, and emits no verdict marker. Every transport check passes, so the failure looks
like "the arm had no opinion".

Two cheap checks that settle it, and they must be run before this explanation is believed:
1. what `max_tokens` the reviewer path actually sends to a GLM arm;
2. whether the verdict parser reads `content[0].text` blindly instead of scanning
   `content[*]` for `type == "text"`.

If both point the same way, the fix is budget plus a parser that treats
`stop_reason: max_tokens` with no text block as a **named** failure — never as "no verdict".
A silence must be distinguishable from a verdict.
