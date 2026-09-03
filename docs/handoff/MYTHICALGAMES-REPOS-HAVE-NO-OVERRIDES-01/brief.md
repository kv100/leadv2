# MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01

Eight MythicalGames repos were adopted on 2026-09-03. All eight report
`leadv2-overrides ABSENT`. Until each has one, `/leadv2` there runs on generic defaults: it does not
know the stack, cannot verify, and cannot deploy.

## State after the adoption sweep

| repo | kind | overrides |
|---|---|---|
| `m3` | Turborepo monorepo — Next.js frontend + Go microservices | ABSENT |
| `pf3-backend` | Go services (gRPC, Kafka, Temporal) | ABSENT |
| `pf3-local-dev` | local docker-compose harness for the above | ABSENT |
| `pf3-smart-contracts` | contracts | ABSENT |
| `mp-frontend` | frontend | ABSENT |
| `mondia-portal` | portal | ABSENT |
| `mythical-aii` | — | ABSENT |
| `environment-platform` | infra | ABSENT |
| `m3-market` (not a git repo) | **the workspace's leadv2 control dir** | present, rich |

`m3-market/.claude/leadv2-overrides/` already holds a 622-line `extensions.md`, a `stack.yaml`
describing the m3 monorepo, `mission-templates.md`, `verify.sh`, `deploy.sh`, `codex-policy.yaml`,
`frontend-paths.txt`. That knowledge exists; it is just not reachable from the repos themselves.

## The real question this task must answer first

**Is `m3-market` meant to stay the single control dir for the whole workspace, or should each repo
carry its own overrides?** Do not guess — this decides everything else. Evidence either way:
`m3-market` is not a git repo, so it cannot host per-repo phase gates; but its overrides describe
`m3` + `pf3-backend` + `pf3-local-dev` together, which is genuinely one system.

Answer it, argue it in the report, then:

1. **If per-repo:** scaffold `leadv2-overrides` in each of the eight via `leadv2-init`, deriving
   `stack.yaml` from what is actually in the repo (read `Makefile`, `go.mod`, `package.json`,
   `.circleci/`, not from this brief). Split `m3-market`'s extensions.md into the parts that belong
   to each repo. Nothing is copied blind.
2. **If one control dir:** say what makes a repo's `/leadv2` read `m3-market`'s overrides, and
   prove it with a live run from inside `~/MythicalGames/m3` that resolves the m3 stack.
3. Either way: `verify.sh` and `deploy.sh` must exist for any repo where a lane could deploy, or
   deployment must be explicitly refused there with a named reason.
4. Green on macOS and in a Linux container, exit codes pasted. Register any new suite in
   `tests/run-all.sh` and prove `--scope changed` selects it.
5. Commit in this lane before you finish.

Note: these are the founder's **employer's** repos. Anything written into them must stay untracked —
the sweep added `.claude/scripts/`, `.claude/agents/`, `.claude/commands/leadv2.md`,
`.claude/leadv2-overrides/` and `docs/leadv2/` to each repo's `.git/info/exclude` for exactly this
reason. Do not commit to any MythicalGames repo, and do not undo those excludes.

Related: `INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01`.
