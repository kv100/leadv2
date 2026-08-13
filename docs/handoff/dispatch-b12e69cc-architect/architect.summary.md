verdict: APPROVE
next_action: continue

Empty `·` fields are a widget parse bug, not a lost payload; the fix and the surface miss because `--all` §6 is a second lane walk.

- `5s.sh` splits ` · ` rows with a whitespace awk → `$2` is the separator glyph.
- `render_single_lead` walks independently: repo falls back to renderer cwd, lead excluded by pid only.
- No test invokes `--all` — the drift hole. Do NOT filter lanes by `arm == opus`.

Full: architect.full.md
