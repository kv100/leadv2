# GLM-5.3 live transport probe

Captured 2026-08-25 against the configured Z.AI Anthropic-compatible endpoint.
Credentials were loaded locally and are deliberately omitted.

```sh
ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic \
ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3 \
ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.3 \
claude -p 'Reply exactly: GLM-53-ALIVE' --model sonnet --output-format json
```

Observed result (sanitized):

```json
{
  "is_error": false,
  "terminal_reason": "completed",
  "modelUsage": {
    "glm-5.3": { "canonicalModel": "glm-5.3", "provider": "firstParty" }
  },
  "result": "GLM-53-ALIVE"
}
```

The local Claude CLI emitted an `unrecognized_model` SDK-name warning before
the response. The completed API result above is the acceptance criterion for
this wrapper; it does not assert that the CLI has a built-in catalog entry.
