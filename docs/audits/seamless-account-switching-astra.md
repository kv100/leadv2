# Seamless account switching — Astra design report

Date: 2026-09-08. Mission E1 / dispatch-29eafe96. Design only; no production changes.

## Decision

**Fix transcript discovery and stop moving running sessions as the first delivery.** Pin the lead to one label, route new lanes between `personal` and `work`, and provide an explicit-transcript resume operation when the lead must move. Then add account admission based on reservations and actual inference outcomes. Do not promise hot swapping of a running lead.

The most valuable measured result: **changing `CLAUDE_CONFIG_DIR` can make an existing session UUID unresolvable locally, before any model request. Supplying the transcript's absolute path restored the original conversation under a different config root in the installed CLI.** This is a repairable local discovery failure, not evidence of an unavoidable server-side conversation binding. Evidence: [P2](#p2-installed-cli-resume-falsification), with a real CLI and a loopback fixture server, including the old context in the outgoing request.

**UNVERIFIED: a real OAuth conversation can continue under the other account.** No real account was authenticated, switched, refreshed or queried in this audit. The loopback test establishes local loading and request construction, not Anthropic acceptance, account entitlements, thinking-signature compatibility, prompt-cache reuse, or remote-session ownership. The founder's exact failing invocation and error were not supplied; the report diagnoses a reproduced mechanism matching the installed launcher, not a retrospectively proven incident.

The other actionable finding is independent of resume: **D1 removing the arbiter penalty is insufficient to balance two accounts without usage data.** The downstream picker repeatedly chooses the first equal-scoring record; its caller also turns a fixture usage 401 into a cooldown even when the producer says `unmetered`. Evidence: [P3](#p3-profile-selection-falsification). Both seams need an explicit contract with D1.

## 1. Where switching breaks resume

There are two coupled namespaces:

| Boundary | Finding and evidence |
|---|---|
| Interactive launch | The `claude()` function in `~/.zshrc:26-35` chooses a config root and assigns `CLAUDE_CONFIG_DIR` to the new process. The `claude-work` / `claude-personal` aliases at lines 36-37 choose different roots. Read-only function inspection plus the filesystem separation in P1 corroborate this; no shell startup file was sourced. |
| Transcript lookup | The installed executable stores and resolves local history under the selected config root's `projects/<project>/<UUID>.jsonl`. A UUID in one root is absent from the other root's lookup. The precise failing observable is `No conversation found with session ID`, rc=1, zero loopback requests. P2 reproduces it. [Official sessions documentation](https://code.claude.com/docs/en/sessions#where-transcripts-are-stored), fetched during this audit, agrees with the storage boundary. |
| Credential lookup | `CLAUDE_CONFIG_DIR` also selects credential storage. [Official authentication documentation](https://code.claude.com/docs/en/authentication#credential-management), fetched during this audit, describes directory-specific macOS Keychain entries and credential files. P4 corroborates this in the installed executable's storage-key derivation. This is why changing the account root also changes history discovery. |
| Session identity | P2 resumes the same synthetic session ID from an explicit file under a second root; the outgoing messages contain the old user marker. A local transcript is therefore not intrinsically keyed to an account ID in this exercised path. This does not prove the absence of additional checks in OAuth or remote paths. |
| Lane placement | Dispatcher `--resume-lane` selects a worktree; it is not Claude's `--resume`. `claude-subsession.sh:203-216,593-600` creates/maps a UUID and launches with `--session-id`. Do not confuse preserving the checkout with replaying a conversation. P1 and P5 identify the executing files. |

The trace is `~/.zshrc` account-root choice → new CLI process → root-specific local history search → not-found exit. On the reproduced failure, neither a stale OAuth token nor a server-side account/conversation association can be the cause: the local server receives no request. **The executable file containing that behavior is the resolved `~/.local/bin/claude`, identified by version-path and SHA-256 in P1; it is outside this repository.**

Local repair does not recover everything. A transcript can restore conversation messages; a terminated process's live tool jobs and in-memory state need separate reconciliation. Do not restart all lanes with the lead. The lanes are independent processes selected once at launch (P5); existing worktrees, handles and artifacts must be reconciled before any replacement dispatch.

There is also a discovery trap for lanes: current official CLI documentation excludes `-p` sessions from the interactive picker while allowing explicit UUID resume. [Sessions documentation](https://code.claude.com/docs/en/sessions#resume-a-session), fetched during this audit; P5 verifies our lane launcher uses `-p`. This is a documented candidate cause, not a tested claim about the founder's picker.

## 2. Can the live lead change credentials?

**Token refresh within a process and switching account identity are different operations.** Installed code contains OAuth memo clearing, credential rereads, refresh locking and a branch that accepts an access token changed by another process. P4 records the exact static code and offsets. This falsifies an argument that a token must remain immutable for a process's lifetime. It does not establish a supported account-replacement API.

**UNVERIFIED: an external credential-store change or `/login` can change the lead's account in place while preserving all lead state.** No such experiment was performed. The local shell wrapper and leadv2 profile selector expose only launch-time root selection (P1/P5). Changing the parent shell environment does not change a running child's environment. The CLI's internal refresh machinery is not a leadv2 control channel.

For a safe hot-switch implementation, a single operation would need to quiesce requests, change credentials and organization identity together, invalidate account caches, isolate late responses from the old identity, reconcile remote resources, and retain local transcript ownership. Replacing a token file alone is not a defensible design. P4's cache and refresh branches demonstrate that this state is more than one environment variable; coverage of every account-bound state is explicitly incomplete.

Lanes are easier because the dispatcher chooses the label before creating their process. The actual flag is **`--requested-profile <LABEL>`**, forwarded through the shared Claude launch branch to `claude-subsession.sh`; the mission's `--claude-profile` spelling is not the implemented spelling in the inspected dispatcher. P5 includes parser and launch excerpts. Profile selection exports `CLAUDE_CONFIG_DIR` once before argument construction; a running lane is not dynamically rebalanced.

One further correction: a selector record labelled `cred=keychain:...` exports `LEADV2_ANTHROPIC_ACTIVE_SERVICE` for leadv2's quota readers, but this is not proof that the CLI uses that arbitrary service. The launch exports `CLAUDE_CONFIG_DIR`; the installed CLI derives its own credential service from its configuration root (P4/P5). Do not use selector success as proof of the billed account. Account attribution at launch needs a separate metadata/identity consistency check, with labels only in logs.

## 3. Balance without a usage endpoint

**There is no passive way to know exact remaining subscription capacity from “token exists” plus “usage is unobservable.”** Treat the problem as admission under uncertainty. “Free” should mean “eligible for one more locally reserved job,” not “known to have N percent remaining.”

**UNVERIFIED: the two intended `max_5x` accounts both return usage 401 by design.** This is the mission's operating premise, also stated in persona-engine's `PRE-WAVES-PLAN.md` D1 and `missions/d1-a-401-is-not-a-dead-account.md`; no endpoint probe was run. The design respects the standing no-spend-measurement rule regardless of the eventual HTTP behavior.

D1's prose has a logical error worth rejecting: resolving a nonempty access-token string does **not** prove the token is valid. It can be revoked or expired. Conversely, a usage 401 alone cannot prove inference is unusable. The local classifier only receives subscription type and usage HTTP status; it cannot distinguish these cases (P3). D1 should preserve this uncertainty, not relabel it “healthy.”

### Proposed admission state

Keep independent fields per account, persisted in host-local state and exposed by LABEL only:

- `auth`: configured / unknown / inference-rejected. Local credential presence is configuration evidence only.
- `metering`: deliberately-unobserved. Do not create a synthetic percentage, spend estimate, reset timestamp or 50-point penalty.
- `admission`: eligible / cooling / half-open / operator-disabled, with reason, observation time and expiry.
- `load`: live reservations, each carrying dispatch/session ID, process start identity, owner, heartbeat, lease expiry and configurable model/task weight.
- `last_served`: a durable tie-break cursor. A random choice alone does not prevent concurrent selectors from piling onto one slot.

Selection transaction: acquire one machine-wide allocator lock → reconcile leases against live workers and their recorded start identity → filter hard refusals/active cooldowns → choose the least reserved weighted load, then alternate equal ties → reserve before spawn → pass the selected label explicitly → bind the actual worker handle or roll back the reservation on launch failure → release at completion. Both repos and review/repair launchers must use the same allocator. One successful launch must not spawn a second copy merely because its acknowledgement was lost; the reservation/dispatch ID must be idempotent.

Start with equal weights for the two intended equal-tier slots, a conservative configurable concurrency cap, and a reservation for the pinned lead. These are policy values to validate, not measured provider limits. A long job keeps its reservation while its heartbeat/process remains live; expiry alone must not free a still-running worker. PID reuse requires start-time verification. Two labels for the same underlying account must share capacity; when identity is unavailable, show that deduplication is uncertain instead of asserting two independent quota pools.

Use outcomes of useful work, not periodic inference/auth probes. A successful inference marks recent usability. An attributable inference quota refusal starts a cooldown; use a reset time only if the actual response supplies a validated one, otherwise a configurable bounded backoff. An attributable authentication rejection pauses automatic launches on that label pending credential repair; do not rotate credentials in a retry loop. Network failures and provider-wide overload remain separate from account exhaustion. When a cooldown expires, admit exactly one useful half-open job under the allocator lock. If both slots refuse, queue and report the reason; do not bounce the same job indefinitely.

**UNVERIFIED: exact refusal codes and reset fields exposed by the current subscription CLI.** The initial implementation must capture sanitized actual lane results once and establish a classifier contract before assigning meanings to provider text. The existing dispatcher has `refusal_reason` / `_maybe_record_quota_lockout` call sites (P5), but this audit did not validate account-scoped propagation through all consumers.

This cannot observe activity from an unrelated laptop or an unmanaged interactive session. Reserve known leads and reconcile local workers; let real refusal outcomes correct unseen external load. Never turn “no telemetry” into “zero usage.”

### Required D1 integration

P3 identifies three distinct stages: quota-read classification, provider-level arbiter pricing, and per-profile launch selection. The arbiter has an `unmetered` pricing branch; the picker still expects numeric windows and the selector still cools an errored account. Widening only `classify_account_state` or removing only `UNKNOWN_PROBE_PENALTY` leaves those downstream behaviors intact.

For intentionally unobserved accounts, skip the usage probe entirely, admit using the lease allocator, and record inference outcomes separately. Preserve explicit-label hard failure: an unavailable requested account must queue/refuse rather than silently inherit another root. Route review and repair launches through the same reservation API; the source audit establishes the code-lane seam, not a complete caller census.

## 4. Smallest useful deliveries, ranked by cost

Estimates below are engineering judgment, not measured schedules. “Cost” includes integration and failure-path verification.

| Rank | Delivery | Estimated cost | Pain removed / residual |
|---|---|---|---|
| 1 | Pin lead to one label; keep live lanes running; explicitly choose labels for new lanes | Hours for an operating procedure; 1–2 days to persist account/session attribution reliably | Avoids routine lead reloads while moving bulk work. Existing flag works syntactically, but P3's cooldown path must be corrected before promising reliable unobserved-account admission. Lead can still exhaust its own slot. |
| 2 | Concise handoff/checkpoint fallback | Hours for a template; 1–2 days for reliable automatic capture | Survives missing/incompatible transcripts and records decisions, pending work, commit/evidence paths, handles and open questions. Summaries lose detail; use as fallback, not primary restoration. Can accompany rank 1 immediately. |
| 3 | Resume by explicit transcript path with a durable session locator | 1–3 days plus one separately authorized real-account acceptance check | Locally proven recovery of full conversation across roots (P2). Still restarts a process and must restore launch inputs and reconcile jobs. Real OAuth continuation is unverified. |
| 4 | Shared lease allocator with least-load admission, tie rotation and inference feedback | 3–6 days with concurrent-launch/crash tests | Makes two unobserved slots useful without periodic endpoint calls. Exact remaining quota and activity on other machines remain unknown. |
| 5 | Pre-start one lead process per account with explicit ownership transfer | 5–10 days to make safe | Can reduce startup delay but cannot keep two independent contexts identical. Requires single-lead ownership and reconciliation; idle processes do not prove warm server caches or available quota. |
| 6 | Hot account replacement within the current interactive CLI, or a credential-routing proxy | Open-ended investigation; no reliable delivery estimate | Would address literal zero-reload switching only after account-transition support is proven. Proxy/SDK redesign adds auth, refresh, concurrent responses and remote-state obligations. No evidence justifies it as the first implementation. |

The first implementation should combine ranks 1, 3 and 4 in small increments, with rank 2 as recovery insurance. Do not share or symlink the entire config roots. Do not globally share `projects/` as a shortcut: concurrent transcript writers, retention, duplicate UUID lookup and profile-specific auxiliary state need explicit handling.

The session locator should store LABEL, UUID, exact transcript path, cwd/worktree, CLI artifact version, launch flags/config references, and current owner. It should not copy credentials or permissions. On an explicit handoff, wait for the old owner to quiesce, record/verify a transcript digest and last complete record, start the new process from that transcript, verify old context is present, and transfer ownership only once. P2 shows explicit-path resume can write to the source transcript; never leave two processes writing it. If copying is required later, make it a controlled snapshot/fork with original preserved, not an unqualified directory merge.

For a later real-account acceptance check, use a disposable closed synthetic session with a nonce, already authenticated account roots, and one useful resumed prompt under the other LABEL. Capture only resolved label, CLI identity, exit/result, and whether the nonce survives. Disable retries; never use the founder's live session. This is a proposed future check, **not an action taken or a ready-to-run automatic switch command**. If acceptance fails, retain the original transcript and use the checkpoint fallback.

## Evidence and method

Graph discovery was attempted first with `search_graph(project="leadv2", name_pattern=".*(switch|profile|resume).*", limit=30)`. Raw result: `MCP tool call requires approval, but approval policy is never`. No graph result was treated as a code fact. Targeted file reads followed. No other arm's report was read.

Write scope is this report alone. The profile registry was not opened. The forbidden global settings file and permission files were not inspected or edited. The real CLI was only run with a newly allocated HOME/config root, `--bare`, `--setting-sources ''`, no tools, no inherited credentials, and a local fixture endpoint. Real account authentication attempts: **0**. Live account switches: **0**. Usage probes: **0**.

### P1. Snapshot, path and parity probes

Initial lane `git status --short` and `git diff --stat` returned no output. Read-only `git rev-parse` measurements:

```text
lane HEAD dbcb984e259821be632940a703890a949ba4a388
initial main ref fe491bffb6df9f3a4ac17e14ac6a2f7ea43c2982
live checkout HEAD at parity check 9bfebf21e3a356989924018d955b36891f8c9982
persona-engine HEAD 247c61c1feddd595ccf42294df6091e6faf922cb
CLI_ARTIFACT 2.1.263 sha256 ef5d2909c8af49f31ab6d5487e90316777bc2fac170adfe8160716caa8aaf4f9
```

The executable identity came from resolving `~/.local/bin/claude`, reading its bytes and applying `hashlib.sha256`; this is a local installed artifact measurement, not a version inferred from web documentation.

Python `Path.read_bytes()` equality compared these exact lane/live pairs; enumeration was the explicit five-element list, with no truncation:

```text
PARITY plugins/leadv2/scripts/claude-subsession.sh identical=True
PARITY plugins/leadv2/scripts/leadv2-claude-profile-select.sh identical=True
PARITY plugins/leadv2/scripts/lib/leadv2-claude-profile-pick.py identical=True
PARITY plugins/leadv2/scripts/leadv2-quota-read.py identical=True
PARITY plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh identical=True
```

`Path.resolve()` on persona-engine entry paths returned:

```text
.claude/leadv2 => leadv2/plugins/leadv2
.claude/scripts/leadv2-dispatch-code.sh => leadv2/plugins/leadv2/scripts/leadv2-dispatch-code.sh
.claude/scripts/claude-subsession.sh => leadv2/plugins/leadv2/scripts/claude-subsession.sh
.claude/scripts/leadv2-claude-profile-select.sh => leadv2/plugins/leadv2/scripts/leadv2-claude-profile-select.sh
```

Targets above abbreviate the common Projects parent. An additional dispatcher byte-comparison returned `DISPATCH_PARITY True`; at that check both main and the live checkout were `9bfebf21e3a356989924018d955b36891f8c9982`. The main checkout moved during the audit; parity is a point-in-time measurement, not a claim that every source stayed unchanged afterward.

Filesystem metadata probe: `os.walk(root, followlinks=False, onerror=...)` over the two config roots' `projects` directories, accepting filenames matching `[0-9a-fA-F-]{36}\.jsonl`, collecting basename IDs and set intersection. No transcript contents or IDs were printed. No entry cap; no symlink-directory traversal; these are file/basename counts, **not a census of resumable lead sessions**. Enumeration was not atomic with ongoing sessions.

```text
LOCAL_METADATA personal root_exists=True root_is_symlink=False uuid_named_jsonl_files=5939 unique_basename_ids=5939 enumeration_errors=0 limit=none followlinks=False
LOCAL_METADATA work root_exists=True root_is_symlink=False uuid_named_jsonl_files=454 unique_basename_ids=454 enumeration_errors=0 limit=none followlinks=False
SHARED_BASENAME_IDS 0
PERSONAL_ONLY_BASENAME_IDS 5939
WORK_ONLY_BASENAME_IDS 454
```

### P2. Installed CLI resume falsification

Probe artifact and full reproduction source are embedded below. It creates a synthetic two-message transcript under `personal`, starts a loopback HTTP fixture, and invokes the installed CLI with `work` selected. The first attempt uses UUID lookup, the second the absolute transcript path. Both use the same cwd. Each CLI subprocess has a 35-second deadline, a private process group, kill-and-wait on timeout, and a joined/shut-down server in `finally`.

A preliminary fixture generated through `--bare -p` lacked its initial user record in the stored file. The first apparent rc=0 recovery therefore **failed the context oracle** (`request_contains_original_marker=False`). That result was rejected. The corrected probe seeds a complete user/assistant parent chain explicitly. This is a fixture correction, not a production-code fix and not a mutation-control claim.

Command: `python3 /tmp/e1-astra-evidence/resume_probe.py`

```python
import http.server,json,threading,subprocess,tempfile,os,signal,hashlib
from pathlib import Path
root=Path(tempfile.mkdtemp(prefix='e1-astra-resume-')); (root/'home').mkdir();(root/'repo').mkdir()
for label in ['personal','work']:(root/label).mkdir()
requests=[]
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))));requests.append(body)
  if 'count_tokens' in self.path:
   data=json.dumps({'input_tokens':10}).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(data);return
  msg={'id':'msg_fixture','type':'message','role':'assistant','content':[],'model':'claude-sonnet-4-6','stop_reason':None,'stop_sequence':None,'usage':{'input_tokens':10,'output_tokens':0}}
  events=[('message_start',{'type':'message_start','message':msg}),('content_block_start',{'type':'content_block_start','index':0,'content_block':{'type':'text','text':''}}),('content_block_delta',{'type':'content_block_delta','index':0,'delta':{'type':'text_delta','text':'LOCAL_FIXTURE_OK'}}),('content_block_stop',{'type':'content_block_stop','index':0}),('message_delta',{'type':'message_delta','delta':{'stop_reason':'end_turn','stop_sequence':None},'usage':{'output_tokens':4}}),('message_stop',{'type':'message_stop'})]
  self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
  for e,d in events:self.wfile.write(('event: '+e+'\ndata: '+json.dumps(d)+'\n\n').encode())
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever);thread.start()
base={'HOME':str(root/'home'),'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','ANTHROPIC_API_KEY':'local-fixture-not-a-secret','ANTHROPIC_BASE_URL':'http://127.0.0.1:'+str(server.server_port),'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC':'1','DISABLE_AUTOUPDATER':'1'}
cli='/Users/kostiantyn.vlasenko/.local/bin/claude';sid='12345678-1234-4123-8123-123456789abc'
common=[cli,'--bare','--setting-sources','','--strict-mcp-config','--tools','','--model','claude-sonnet-4-6','--max-turns','1','--output-format','json','-p']
def run(name,label,args,prompt):
 before=len(requests);env=dict(base,CLAUDE_CONFIG_DIR=str(root/label))
 p=subprocess.Popen(common+[prompt]+args,env=env,cwd=root/'repo',stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
 try:out,err=p.communicate(timeout=35)
 except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate();print(name,'TIMEOUT');return
 print(name,'rc='+str(p.returncode),'local_http_requests='+str(len(requests)-before))
 print('stdout='+out.strip());print('stderr='+err.strip())
 if len(requests)>before:
  texts=json.dumps(requests[-1].get('messages',[]));print('request_contains_original_marker='+str('E1_ORIGINAL_CONTEXT_MARKER' in texts))
try:
 import re,uuid,datetime
 folder=root/'personal'/'projects'/re.sub('[^a-zA-Z0-9_-]','-',str(root/'repo'));folder.mkdir(parents=True)
 user_id=str(uuid.uuid4());assistant_id=str(uuid.uuid4());stamp='2026-09-08T00:00:00.000Z'
 shared={'sessionId':sid,'cwd':str(root/'repo'),'version':'2.1.263','isSidechain':False,'timestamp':stamp,'userType':'external'}
 rows=[dict(shared,type='user',uuid=user_id,parentUuid=None,message={'role':'user','content':'E1_ORIGINAL_CONTEXT_MARKER'}),dict(shared,type='assistant',uuid=assistant_id,parentUuid=user_id,message={'id':'msg_seed','type':'message','role':'assistant','model':'claude-sonnet-4-6','content':[{'type':'text','text':'E1_PRIOR_ASSISTANT_MARKER'}],'stop_reason':'end_turn','usage':{'input_tokens':10,'output_tokens':4}})]
 file=folder/(sid+'.jsonl');file.write_text(''.join(json.dumps(r)+'\n' for r in rows));files=[file]
 print('synthetic_transcript=user+assistant; original_marker_present='+str('E1_ORIGINAL_CONTEXT_MARKER' in file.read_text()))
 run('RED_UUID_OTHER_ROOT','work',['--resume',sid],'continue marker')
 if len(files)==1:
  run('GREEN_PATH_OTHER_ROOT','work',['--resume',str(files[0])],'continue marker')
finally:
 server.shutdown();thread.join();server.server_close();print('server_stopped=True');print('fixture_root='+str(root))
```

Raw corrected output:

```text
synthetic_transcript=user+assistant; original_marker_present=True
RED_UUID_OTHER_ROOT rc=1 local_http_requests=0
stdout=
stderr=No conversation found with session ID: 12345678-1234-4123-8123-123456789abc
GREEN_PATH_OTHER_ROOT rc=0 local_http_requests=1
stdout={"duration_api_ms":61,"stop_reason":"end_turn","session_id":"12345678-1234-4123-8123-123456789abc","total_cost_usd":0.00008999999999999999,"usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":4,"output_tokens_details":{"thinking_tokens":0},"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{"claude-sonnet-4-6":{"inputTokens":10,"outputTokens":4,"cacheReadInputTokens":0,"cacheCreationInputTokens":0,"webSearchRequests":0,"costUSD":0.00008999999999999999,"contextWindow":200000,"maxOutputTokens":32000,"thinkingTokens":0,"canonicalModel":"claude-sonnet-4-6","provider":"firstParty","costBasis":"list"}},"permission_denials":[],"terminal_reason":"completed","fast_mode_state":"off","fast_mode_disabled_reason":"sdk_opt_in_required","subagent_stats":{"spawned":0,"requested":{"background":0,"foreground":0,"unset":0},"started_in_background":0,"max_depth":0,"spawned_by_subagents":0,"completed":0,"failed":0,"killed":{"parent":0,"user":0,"system":0},"refused":{"depth_limit":0,"concurrency_limit":0,"budget":0},"by_type":{}},"is_error":false,"num_turns":1,"subtype":"success","api_error_status":null,"result":"LOCAL_FIXTURE_OK","ttft_ms":26,"type":"result","duration_ms":83,"uuid":"60bb9eb2-ee33-4f37-ad07-1bb4e75f8f67","ttft_stream_ms":26,"time_to_request_ms":23,"first_content_frame_ms":26,"queued_turn_count":0}
stderr=
request_contains_original_marker=True
server_stopped=True
fixture_root=/Users/kostiantyn.vlasenko/.claude/plugins/data/codex-openai-codex/tmp/e1-astra-resume-ml0kjedb
```

The amounts in the raw CLI result are computations from fixture token counts, not measured subscription spend. The result body came from a local SSE fixture. It proves context was sent, not that a model reasoned about it. Both attempts preserved the synthetic UUID. Inspection of the generated synthetic files showed the resumed turn appended to the source transcript; no real transcript was changed. Postcheck command: read the synthetic source file, search both fixture roots for the synthetic UUID, and test the two marker strings. Raw output:

```text
P2_POSTCHECK source_retains_original_marker=True
P2_POSTCHECK resumed_prompt_appended_to_source=True
P2_POSTCHECK destination_uuid_transcript_present=False
```

### P3. Profile selection falsification

Commands: `python3 /tmp/e1-astra-evidence/profile_probe.py`, whose complete source follows. Real selector and picker, synthetic registry, synthetic credentials, stubbed quota producer, temporary HOME/cache/alarm paths, per-call deadlines. Output projects only label/score/status fields. No actual registry content is involved.

```python
import tempfile,subprocess,os,json,base64,ast
from pathlib import Path
root=Path.cwd(); scripts=root/'plugins/leadv2/scripts';temp=Path(tempfile.mkdtemp(prefix='e1-astra-picker-'))
records=''.join(label+'\t/fixture/'+label+'\tfile:/fixture/'+label+'\t'+base64.b64encode(json.dumps({'status':'unknown','accounts':[{'status':'unknown','active':True,'account_state':'unmetered','error':'http 401'}]}).encode()).decode()+'\tfixture/'+label+'\t0\n' for label in ['personal','work'])
winners=[]
for _ in range(6):
 p=subprocess.run(['python3',str(scripts/'lib/leadv2-claude-profile-pick.py')],input=records,capture_output=True,text=True,timeout=5);winners.append(p.stdout.split()[0])
print('pure_picker six independent equal-unmetered inputs:',','.join(winners))
probe=temp/'probe.py';probe.write_text("import json\nprint(json.dumps({'provider':'anthropic','status':'unknown','accounts':[{'active':True,'status':'unknown','account_state':'unmetered','error':'http 401'}]}))\n")
reg=[]
for label in ['personal','work']:
 d=temp/label;d.mkdir();(d/'.credentials.json').write_text(json.dumps({'claudeAiOauth':{'accessToken':'local-fixture','subscriptionType':'team','expiresAt':9999999999999}}));reg.append(label+'\t'+str(d)+'\tfile:'+str(d/'.credentials.json'))
registry=temp/'fixture.tsv';registry.write_text('\n'.join(reg)+'\n')
env={'HOME':str(temp),'PATH':os.environ['PATH'],'LEADV2_CLAUDE_MULTIPROFILE':'1','LEADV2_CLAUDE_PROFILES_FILE':str(registry),'LEADV2_CLAUDE_PROFILE_PROBE':str(probe),'LEADV2_CLAUDE_PROFILE_DEFAULT_DIR':str(temp/'personal'),'LEADV2_QUOTA_CACHE_DIR':str(temp/'cache'),'LEADV2_CLAUDE_ACCOUNT_ALARM_FILE':str(temp/'alarm.json')}
for name,requested in [('first',''),('second',''),('requested_after_cooldown','work')]:
 e=dict(env,LEADV2_CLAUDE_PROFILE_REQUESTED=requested)
 r=subprocess.run(['bash',str(scripts/'leadv2-claude-profile-select.sh')],env=e,capture_output=True,text=True,timeout=20)
 allowed=['profile=','reason=','requested=','score=','source=','candidates=']
 print('selector',name,'rc='+str(r.returncode),' '.join(x for x in r.stdout.split() if any(x.startswith(p) for p in allowed)))
 print('cooldown_markers='+str(len(list((temp/'cache').rglob('probe-cooldown-until')))))
module=ast.parse((scripts/'leadv2-quota-read.py').read_text());fn=next(n for n in module.body if isinstance(n,ast.FunctionDef) and n.name=='classify_account_state')
namespace={'ACCOUNT_STATE_OK':'ok','ACCOUNT_STATE_UNMETERED':'unmetered','ACCOUNT_STATE_UNKNOWN':'unknown'};exec(compile(ast.Module(body=[fn],type_ignores=[]),'fixture','exec'),namespace)
for tier in ['team','max']:print('classify_account_state',tier,'401 =>',namespace['classify_account_state'](tier,401))
```

Raw output:

```text
pure_picker six independent equal-unmetered inputs: profile=personal,profile=personal,profile=personal,profile=personal,profile=personal,profile=personal
selector first rc=0 profile=personal score=100 source=unknown reason=all_unknown candidates=2
cooldown_markers=2
selector second rc=0 profile=- reason=single_profile
cooldown_markers=2
selector requested_after_cooldown rc=3 profile=- reason=requested_profile_unavailable requested=work
cooldown_markers=2
classify_account_state team 401 => unmetered
classify_account_state max 401 => unknown
```

This breaks two candidate designs: “removing the unknown penalty creates fair sharing,” and “producer unmetered state alone prevents downstream exclusion.” The current selector admits the first unknown candidate once, then cools both fixture accounts and falls back; an explicit request during cooldown refuses. There is no green production repair in this design lane. The report's proposed design removes usage from this admission path; its implementation requires future tests.

Corroborating source locations in the parity-checked files:

- `lib/leadv2-claude-profile-pick.py:81-104,139-140`: unknown scores 100/101, requires both payload/account `status=ok`, chooses `min(..., key=(score,input-order))`.
- `leadv2-claude-profile-select.sh:450-478,529-562,580-592`: cooldown skip, error-based cooldown write, and `completed == 0` fallback/refusal.
- `leadv2-quota-read.py:412-435`: classifier is team+401 → unmetered, max+401 → unknown.
- `lib/leadv2-route-arbiter.sh:913,955-977`: 50.0 unknown penalty plus an existing unmetered headroom branch. No real arbiter quota probe was run.

### P4. Installed credential/cache implementation

Read-only binary probe: resolve `~/.local/bin/claude`, `read_bytes()`, `re.finditer(re.escape(term), bytes)`, emit bounded printable JavaScript windows and byte offsets. Names are minified and may collide between chunks; the export map disambiguates the OAuth symbols. This is static evidence only.

```text
export-map offset 174360822: Hw as clearOAuthTokenCache
export-map offset 174360850: Use as clearOAuthTokenMemos
export-map offset 174360567: Ss as checkAndRefreshOAuthTokenIfNeeded
export-map offset 174360608: jUe as checkAndRefreshOAuthTokenIfNeededWithOutcome
function offset 158960457: function Use(){age.of(B().host).clear()}
function offset 158961122: function Hw(){if(iH(),M())IQ()}
function offset 158970241: async function Gm(...) {
  ... await Nfe(...); let I=await Qi(...);
  ... if(!I?.refreshToken)return "no_refresh_token";
  ... let D=p??I.accessToken; Hw(); let x=await Qi(...);
  ... if(x.accessToken!==D)return ..., "refreshed";
  ... OAuth refresh lock acquisition ...
}
```

The final function block is an explicitly abbreviated projection of the printed source, not a claim of a callable external API. A separate source window derives the credential service suffix from SHA-256(config-root), first eight hex characters, with a default-root special case; it also references `CLAUDE_SECURESTORAGE_CONFIG_DIR`. That internal variable is not a verified supported way to separate account identity from session/config state. Do not build the delivery on it.

The live documentation check corroborating that derivation was `web.open("https://code.claude.com/docs/en/authentication")`, followed by `web.find(...,"refresh")`, which returned the credential-management section describing config-directory-specific Keychain selection. The token-cache exports and refresh reread were verified against the installed binary independently of the documentation.

### P5. Dispatcher and launcher source trace

Read commands: `sed -n '6390,6445p' plugins/leadv2/scripts/leadv2-dispatch-code.sh`, targeted `rg -n 'requested-profile|CLAUDE_PROFILE'` on that same shell file, and `sed -n '485,610p' plugins/leadv2/scripts/claude-subsession.sh`. These shell-source searches are within the permitted graph-fallback category. Selected raw lines:

```bash
# leadv2-dispatch-code.sh:6413
[[ -n "${requested_profile:-}" ]] && _claude_profile_args=(--requested-profile "${requested_profile}")
# leadv2-dispatch-code.sh:6415-6417, continued invocation
out="$(cd "${WORK_ROOT}" && PROJECT_ROOT="${PROJECT_ROOT}" LEADV2_SUBSESSION_SLIM_MCP="${LEADV2_SUBSESSION_SLIM_MCP:-1}" bash "${SUBSESSION_BIN}" \
       "${_claude_launch_args[@]}" \
       --task-id "dispatch-${sig8}" --mission-file "${mfile}" "${_claude_profile_args[@]}" 2>"${errf}" 9>&-)"; rc=$?
# leadv2-dispatch-code.sh:7721
--requested-profile) [[ $# -ge 2 ]] || { log_err "--requested-profile requires a value"; usage; }
# claude-subsession.sh:566
export CLAUDE_CONFIG_DIR="$dir"
# claude-subsession.sh:590,593-597
leadv2_select_claude_profile
CLAUDE_ARGS=(
  -p "$FINAL_PROMPT"
  --model "$MODEL"
  --session-id "$SESSION_ID"
  --output-format stream-json
```

The enclosing dispatcher case at line 6378 is `sonnet|haiku|opus|fable)`. The displayed array is an excerpt, not an executable script. The dispatcher comments around line 7689 still describe a sonnet-only pin; the actual shared Claude launch branch is the stronger evidence. No complete census of review, repair, resume and nested-agent launchers was performed. No assertion that every Anthropic process already honors the pin is justified.

## Unchecked questions and acceptance gates for implementation

1. **Exact founder incident:** collect the failed command's mode, cwd, label, CLI artifact and sanitized error. Do not read full personal transcripts merely to identify the path. Compare the recorded transcript location with the chosen root. The measured local mechanism may coexist with other failures.
2. **Real OAuth continuation:** one authorized disposable-session acceptance check as described above. Stop after one rejection; no account-switch loop. This decides whether explicit-path recovery is sufficient for the actual provider path.
3. **Live account replacement:** not tested; no supported atomic operation established. Ordinary refresh code does not settle it. Test in disposable processes only if a documented account-transition surface is found.
4. **Session completeness:** test large/compacted histories, tool-call/result pairing, subagent state, duplicate UUIDs, missing files and concurrent writers. The current proof uses a complete two-message fixture only.
5. **Allocator truth:** test simultaneous reservations from both repos, all-unknown equal slots, known lead reservation, process crash/PID reuse, same-account aliases, explicit-pin refusal, both slots cooling, one half-open owner, lost spawn acknowledgement and late result attribution. A provider-wide failure must not be double-counted as two exhausted accounts.
6. **D1 scope:** recheck the merged producer, arbiter and selector together. This report did not inspect D1's worker or assume its final implementation. No production fix was made here.

## Self-check and changed-scope runner

The report itself is the sole deliverable. No shell/Python source files or test suites were added to the repository, so source syntax checks and test registration are not applicable. Temporary probe scripts are embedded above for reproducibility; they do not become installed tests. The red/green CLI falsification is in P2; P3 intentionally demonstrates unresolved production behavior, not a repaired implementation or a mutation-control success.

### Syntax applicability and report whitespace red/green

Commands inspect `git diff --name-only HEAD` and select `.sh` / `.py` suffixes. Raw first check:

```text
changed_shell_files=[]
bash -n: NOT APPLICABLE (no changed shell files)
changed_python_files=[]
python3 -m py_compile: NOT APPLICABLE (no changed Python files)
git diff --check rc=0
docs/audits/seamless-account-switching-astra.md:333: new blank line at EOF.
git diff --cached --check rc=2
```

The actual report defect was the extra blank line at EOF; it was removed with `write_text(read_text().rstrip() + '\n')`, then the exact report path was staged again. `git diff --cached --check` returned no output and rc=0. This is a whitespace red/green repair, not proof of the proposed production design.

Additional bounded syntax check of the three temporary Python helpers (`resume_probe.py`, `profile_probe.py`, `run_changed.py`):

```text
TEMP_PROBE_PY_COMPILE files=3 rc=0
```

Report structure check (explicit staged path equality, expected headings/evidence, and paired Markdown fences):

```text
one_report_only=True
report_heading=True
four_questions=True
raw_resume_error=True
context_oracle_green=True
balance_raw_output=True
probe_sources_embedded=True
fences_balanced=True
REPORT_STRUCTURE_RC=0
```

### tests/run-all.sh --scope changed

The foreground runner used a 360-second deadline. Before invocation, its worktree-local `leadv2-run-all-last-checked-sha` checkpoint was pinned to `git merge-base main HEAD`; it did not previously exist and was removed afterward. This prevents prior-run state from narrowing away lane changes. No base ref or source file was altered.

Raw output:

```text
MERGE_BASE=fe491bffb6df9f3a4ac17e14ac6a2f7ea43c2982
CHECKPOINT_PRIOR_EXISTS=False
COMMAND: bash tests/run-all.sh --scope changed; timeout=360s
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E1-SWITCH-ASTRA/plugins/leadv2/scripts/tests/run-core-offline.sh
run-all: delegating scope=changed to plugins/leadv2/scripts/tests/run-core-offline.sh
[CORE-OFFLINE] scope=changed running 0 of 95 suites (base=main@fe491bffb6, 0 changed files, 0 unmapped)
[CORE-OFFLINE] SCOPE_RESULT selected=0 total=95 base=main@fe491bffb6 changed=0 unmapped=0 verdict=nothing_to_run reason=no_relevant_changed_files
[CORE-OFFLINE] suites passed=0 failed=0 missing=0 verdict=nothing_to_run reason=no_relevant_changed_files repo=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E1-SWITCH-ASTRA
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E1-SWITCH-ASTRA/plugins/leadv2/scripts/tests/run-core-offline.sh
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E1-SWITCH-ASTRA/tests/test-status-surface-bash32.sh
== T1: /bin/bash -n on the renderer ==
  ok   - renderer parses clean under bash 3.2
== T2: /bin/bash -n on the wrapper ==
  ok   - wrapper parses clean under bash 3.2
== T2b: /bin/bash -n on the broad-status composer ==
  ok   - broad-status composer parses clean under bash 3.2
== T3: env -i minimal PATH (the actual SwiftBar launch shape) renders lanes ==
  ok   - wrapper renders 4 lane row(s) under minimal PATH + bash 3.2
== T4: a dead renderer produces the failure title, never a confident 0/0 ==
  ok   - wrapper reports renderer failure, not a confident 0/0
== T5: STATUS-SURFACE-R5-01 — name resolution, unnamed, age-out, limits ==
  ok   - R5-C1: legacy stays unnamed; single-lead may resolve handoff title
  ok   - R5-C2: no-name lane renders exactly 'unnamed' (no dispatch-<sig8> in NAME)
  ok   - R5-C3: age-out boundary — live@100000 + done@899 present, done@901 absent, header counts drop
  ok   - R5-C4: heuristic cap -> 'не измеряется', no fabricated 'claude: N%'

== T6: STATUS-SURFACE-R5-01 round 2 — minimal-env parity (PyYAML-optional reader) ==
  ok   - _t6a: minimal-env render has no broken substring
  ok   - _t6b: lane row-count parity (min=4 full=4)
  ok   - _t6c: urgent parity (min=0 full=0)

== T7: env -i minimal PATH single-lead render (MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01) ==
  ok   - T7: single-lead source-list loop parses/runs under stripped env (rc=0, no ⚠)
== T8: bash 3.2 param-expansion split on the multibyte '·' delimiter ==
  ok   - T8a: multi-field line splits into first field + untouched remainder
  ok   - T8b: line with no ' · ' delimiter leaves remainder equal to the input (no-suffix case)
  ok   - T8c: same split verified under /bin/bash 3.2 runtime

test-status-surface-bash32: 16 passed, 0 failed, 0 skipped
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E1-SWITCH-ASTRA/tests/test-status-surface-bash32.sh
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E1-SWITCH-ASTRA/tests/test-status-surface-single-lead.sh
== single-lead fixture titles ==
  ok   - status-render consumes snapshot single_lead section
  ok   - no-dispatch idle -> ⚪ idle
  ok   - active dispatch -> 🛠 abcdef12 codex 2m
  ok   - bogus state filtered -> 🛠 abcdef12 codex 2m
  ok   - pending question -> ❓1
  ok   - malformed ledger -> ⚠
  ok   - python3 unavailable -> ⚠ (no legacy fallthrough)

== process census (SWIFTBAR-ACTIVE-SOURCE-02) ==
  ok   - (a) live claude-subsession → active with sig8
  ok   - (a-registry) seeded registry label -> 🛠 FIXTURE-REGISTRY sonnet now
  ok   - (a2) human task_id from reservation preferred over sig8
  ok   - (b) worker gone + terminal → idle
  ok   - (c) exactly 3 entries (2 live + 1 reservation-only)
  ok   - (d) glm worker + terminal → idle (no terminal lanes in body)
  ok   - (e) empty everything → idle

== founder-named lanes (human task_id in run-id segment) ==
  ok   - (f) founder-named glm lane → ACTIVE once with human name
  ok   - (g) founder-named codex pid-file → ACTIVE once with human name

== T-term: fresh vs stale terminal rows (Rule R retention) ==
  ok   - (T-term-1) stale terminal (10m) drops the lane entirely
  ok   - (T-term-2) fresh terminal (60s) drops the lane entirely

== T-lead: the lead's own session is never a lane (C3) ==
  ok   - (T-lead-1) lead's own session excluded from lanes
  ok   - (T-lead-2) real codex session-runner still visible (exclusion is targeted)

== T-multi: aggregation across repos (repo label on foreign lanes) ==
  ok   - (T-multi) foreign-repo lane visible with its repo label

== T-unverifiable: repo lacking a terminal ledger contributes zero rows ==
  ok   - (T-unverifiable) repo with unreadable terminals contributes no rows

== T-name: lane_label fallback + architect phase (C4) ==
  ok   - (T-name-1) lane_label resolves the human name + legacy architect phase
  ok   - (T-name-2) no name fields at all -> sig8 fallback (legacy ~ phase)

test-status-surface-single-lead: 24 passed, 0 failed
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E1-SWITCH-ASTRA/tests/test-status-surface-single-lead.sh
[RUN] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E1-SWITCH-ASTRA/tests/test-status-surface-fast-names.sh
== T1: resolve_lane_label fallback chain ==
  ok   - ledger lane_label hit
  ok   - active.yaml worktree fallback
  ok   - mission heading fallback (MISSION-HEADING-TASK — implementation de)
  ok   - miss -> sig8 unchanged
  ok   - lane_label pipe stripped (got 'AB')
== T2: cold cache ==
  ok   - cold cache shows «нет кэша», no spinner
  ok   - cold render <1s (wall 0s)
  ok   - cold render kicked a refresh (lock held)
== T3: warm cache ==
  ok   - warm cache: label in title+row, no sig8 sub-row
  ok   - warm render <1s (wall 1s)
== T4: stale cache ==
  ok   - stale cache -> «⚠️ кэш устарел»
== T5: rename hygiene (SELF_PATH) ==
  ok   - copy-reply bash= path is the .5s.sh and exists (/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E1-SWITCH-ASTRA/plugins/leadv2/scripts/leadv2-status-surface.5s.sh)

test-status-surface-fast-names: 12 passed, 0 failed
[PASS] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/E1-SWITCH-ASTRA/tests/test-status-surface-fast-names.sh
run-all: 4 passed, 0 failed, scope=changed
CHANGED_SCOPE_RC=0
CHECKPOINT_RESTORED=True
```

Interpretation: the runner passed its four selected entries. Core-offline selected **zero executable suites**, correctly reporting `nothing_to_run` for this report-only diff. The other three entries ran their status-surface checks. This is not evidence that the proposed account switch or allocator has been implemented. The local resume and picker evidence is P2/P3.

All foreground probe/runner sessions returned before delivery; loopback servers were shut down and joined. The resulting git write set is the one report. No production implementation, runtime-state edits, new suite registration, merge or push is part of this lane. Final comparison is `git diff --name-only main...HEAD` after commit.
