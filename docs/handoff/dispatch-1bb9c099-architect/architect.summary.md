verdict: REVISE
next_action: continue

Design closed; two of five required cases describe behaviour the tree does not have.

- DRIFT exits 0 today (`:917`) — case 3 needs rc 4; no caller breaks (all `|| true` or ignore rc).
- No exception list in plugin-sync — case 5 needs ~20 lines reusing `LEADV2_ONE_COPY_EXCEPTIONS_FILE`.
- (c2) is a second `_link_one_file` caller (`:664`) whose DRIFT never counts.

Full: architect.full.md
