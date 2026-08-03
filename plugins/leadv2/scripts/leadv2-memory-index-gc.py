#!/usr/bin/env python3
"""Deterministic index-mode implementation for leadv2-memory-gc."""
import argparse, datetime, hashlib, itertools, json, os, re, shutil, subprocess, sys
from pathlib import Path

STOP = {"the","a","is","to","for","not","and","leadv2","feedback","project","reference"}
ENTRY = re.compile(r"^- \[([^]]+)\]\(([^)]+)\) — (.*)$")

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def toks(e):
    text = " ".join([e["slug"].replace("_", " "), e["title"], e.get("description", "")]).lower()
    return {x for x in re.findall(r"[a-z0-9]+", text) if x not in STOP}
def prefix(a,b): return a["slug"].split("_")[:2] == b["slug"].split("_")[:2] and len(a["slug"].split("_")) >= 2
def yval(text, key):
    m=re.search(r"(?m)^\s*"+re.escape(key)+r"\s*:\s*['\"]?([^\n'\"]+)", text)
    return m.group(1).strip() if m else ""
def active_names(root):
    found=set()
    for name in ("immune-patterns.yaml","leadv2-negative-memory.yaml"):
        p=root/"docs/leadv2"/name
        if not p.exists(): continue
        lines=p.read_text(encoding="utf-8",errors="replace").splitlines()
        active=False
        for line in lines:
            if re.search(r"status:\s*ACTIVE\b",line): active=True
            if active:
                for v in re.findall(r"(?:slug|name|pattern|signature)\s*:\s*['\"]?([^'\"\n]+)",line): found.add(v.strip())
            if line and not line.startswith((" ","-")): active=False
    return found
def parse(mem, root):
    lines=mem.read_text(encoding="utf-8").splitlines(keepends=True); section=""
    active=active_names(root); entries=[]
    for n,line in enumerate(lines,1):
        if line.startswith("## "): section=line[3:].strip()
        m=ENTRY.match(line.rstrip("\n"))
        if not m: continue
        title, target, hook=m.groups(); slug=target[:-3] if target.endswith(".md") else target
        p=mem.parent/(slug+".md"); raw=""; exists=p.is_file()
        if exists: raw=p.read_text(encoding="utf-8",errors="replace")
        desc=yval(raw,"description")[:200]; typ=yval(raw,"type") or "unknown"
        immune=[]
        if "STANDING:" in line or "STANDING:" in raw: immune.append("standing")
        if typ == "user": immune.append("user_type")
        if yval(raw,"memory_gc") == "keep": immune.append("opt_out")
        if not exists: immune.append("orphan_index_line")
        if slug in active or yval(raw,"name") in active: immune.append("active")
        entries.append({"line_no":n,"section":section,"title":title,"slug":slug,"hook":hook.split(". Also:",1)[0],"raw_line":line,"description":desc,"type":typ,"exists":exists,"immune":immune})
    return lines,entries
def similarity(a, b):
    left, right=toks(a),toks(b)
    return (len(left&right)/len(left|right) if left|right else 0)+(0.15 if prefix(a,b) else 0)
def clusters(entries, sim, maxc):
    diagnostics={"all_pairs":0,"same_section_type_pairs":0,"eligible_pairs_any":0,"eligible_pairs_same_section_type":0,"max_similarity_any":0.0,"max_similarity_same_section_type":0.0}
    for a,b in itertools.combinations(entries,2):
        score=similarity(a,b); same=a["section"]==b["section"] and a["type"]==b["type"]
        diagnostics["all_pairs"]+=1; diagnostics["max_similarity_any"]=max(diagnostics["max_similarity_any"],score)
        if score>=sim: diagnostics["eligible_pairs_any"]+=1
        if same:
            diagnostics["same_section_type_pairs"]+=1; diagnostics["max_similarity_same_section_type"]=max(diagnostics["max_similarity_same_section_type"],score)
            if score>=sim: diagnostics["eligible_pairs_same_section_type"]+=1
    groups={}
    for e in entries: groups.setdefault((e["section"],e["type"]),[]).append(e)
    result=[]
    for (_, _), es in groups.items():
        parent=list(range(len(es)))
        def find(x):
            while parent[x]!=x: parent[x]=parent[parent[x]]; x=parent[x]
            return x
        def union(a,b):
            a,b=find(a),find(b)
            if a!=b: parent[b]=a
        for i in range(len(es)):
            for j in range(i):
                if similarity(es[i],es[j])>=sim: union(i,j)
        buckets={}
        for i,e in enumerate(es): buckets.setdefault(find(i),[]).append(e)
        for members in buckets.values():
            members.sort(key=lambda x:x["line_no"])
            if len(members)>1 and any(not x["immune"] for x in members): result.append(members)
    result.sort(key=lambda x:x[0]["line_no"])
    kept=result[:maxc]
    diagnostics["clusters_before_limit"]=len(result)
    return kept, max(0,len(result)-len(kept)), diagnostics
def fingerprint(members, sim): return hashlib.sha256(("|".join(sorted(x["slug"] for x in members))+"|"+str(sim)).encode()).hexdigest()
def request_for(cs, cap, current):
    out=[]
    for i,ms in enumerate(cs,1):
        basic=lambda e:{k:e[k] for k in ("slug","title","description")}
        out.append({"cluster_id":f"c{i:02d}","section":ms[0]["section"],"type":ms[0]["type"],"anchors_only":[basic(e) for e in ms if e["immune"]],"absorbable":[dict(basic(e),hook=e["hook"]) for e in ms if not e["immune"]],"_members":ms})
    return out
def load_seen(mem):
    p=mem/".memory-gc-state.yaml"
    if not p.exists(): return set()
    return set(re.findall(r"fingerprint:\s*['\"]?([a-f0-9]{64})",p.read_text(encoding="utf-8",errors="replace")))
class VerdictError(RuntimeError): pass
def verdict_map(data):
    if not isinstance(data,dict) or not isinstance(data.get("verdicts"),list): raise VerdictError("response does not contain a verdicts list")
    result={}
    for item in data["verdicts"]:
        if not isinstance(item,dict) or not isinstance(item.get("cluster_id"),str): raise VerdictError("verdict is missing cluster_id")
        if item["cluster_id"] in result: raise VerdictError("response contains duplicate cluster_id")
        result[item["cluster_id"]]=item
    return result
def json_object(text):
    decoder=json.JSONDecoder()
    for match in re.finditer(r"\{",text):
        try: value,_=decoder.raw_decode(text[match.start():])
        except json.JSONDecodeError: continue
        if isinstance(value,dict) and "verdicts" in value: return value
    raise VerdictError("model result did not contain a JSON verdict object")
def call_model(plan, model):
    binary=os.environ.get("CLAUDE_BIN","claude"); resolved=shutil.which(binary)
    if not resolved: raise VerdictError(f"model CLI not found: {binary}")
    template=Path(__file__).resolve().parent.parent/"prompts"/"memory-gc-verdict.md"
    if not template.is_file(): raise VerdictError(f"prompt template not found: {template}")
    prompt=template.read_text(encoding="utf-8").replace("<<<CLUSTERS_JSON>>>",json.dumps(plan["request"],separators=(",",":")))
    try: timeout=int(os.environ.get("LEADV2_MEMGC_TIMEOUT","45"))
    except ValueError: raise VerdictError("LEADV2_MEMGC_TIMEOUT must be an integer")
    if timeout<=0: raise VerdictError("LEADV2_MEMGC_TIMEOUT must be positive")
    command=[resolved,"-p",prompt,"--model",model,"--max-turns","1","--tools","","--safe-mode","--no-session-persistence","--output-format","json"]
    try: result=subprocess.run(command,capture_output=True,text=True,timeout=timeout,check=False)
    except subprocess.TimeoutExpired: raise VerdictError(f"model call timed out after {timeout}s")
    except OSError as exc: raise VerdictError(f"model call could not start: {exc}")
    if result.returncode:
        detail=(result.stderr or result.stdout).strip().replace("\n"," ")[-500:] or "no error output"
        raise VerdictError(f"model call exited {result.returncode}: {detail}")
    try: envelope=json.loads(result.stdout)
    except json.JSONDecodeError as exc: raise VerdictError(f"model CLI returned invalid JSON: {exc}")
    payload=envelope.get("structured_output") if isinstance(envelope,dict) else None
    if not isinstance(payload,dict):
        raw=envelope.get("result","") if isinstance(envelope,dict) else ""
        payload=json_object(raw if isinstance(raw,str) else json.dumps(raw))
    return verdict_map(payload)
def verdicts(plan, vf, model):
    if vf:
        try: data=json.loads(Path(vf).read_text(encoding="utf-8"))
        except (OSError,json.JSONDecodeError) as exc: raise VerdictError(f"cannot load verdicts file: {exc}")
        result,status=verdict_map(data),"verdicts-file override"
    else: result,status=call_model(plan,model),f"available (model={model})"
    expected={c["cluster_id"] for c in plan["clusters"]}
    if set(result)!=expected: raise VerdictError(f"verdict IDs do not match request (missing={sorted(expected-set(result))}, unknown={sorted(set(result)-expected)})")
    return result,status
def validate(plan, got):
    accepted=[]; rejected=[]; ids={c["cluster_id"] for c in plan["clusters"]}
    if set(got)-ids or len(got)!=len(ids):
        # unknown or missing decisions are independently kept; unknown is recorded.
        if set(got)-ids: rejected.append({"cluster_id":"?","reason":"unknown_or_duplicated_cluster_id"})
    for c in plan["clusters"]:
        v=got.get(c["cluster_id"]); members=c["_members"]; allsl={e["slug"] for e in members}; absorb={e["slug"] for e in members if not e["immune"]}; immune={e["slug"] for e in members if e["immune"]}
        bad=""; absorbed=[]
        if not v: bad="missing_verdict"
        elif v.get("verdict") not in ("merge","archive","keep"): bad="bad_verdict"
        elif len(str(v.get("rationale","")))>200: bad="rationale_too_long"
        elif v.get("verdict") != "keep":
            into=v.get("into","")
            if into not in allsl: bad="invalid_into"
            elif not next(e for e in members if e["slug"]==into)["exists"]: bad="missing_survivor"
            else:
                for m in v.get("members",[]):
                    if m.get("slug") not in absorb: bad="immune_violation" if m.get("slug") in immune else "invalid_member"; break
                    if m.get("action") not in ("absorb","keep"): bad="bad_action"; break
                    if m.get("action")=="absorb":
                        if m.get("absorbed_by") != into or not m.get("absorbed_by"): bad="invalid_absorbed_by"; break
                        if len(str(m.get("merged_hook","")))>80: bad="hook_too_long"; break
                        absorbed.append(m)
                if into in {m["slug"] for m in absorbed}: bad="absorb_chain"
        if bad: rejected.append({"cluster_id":c["cluster_id"],"reason":bad}); v={"verdict":"keep","members":[],"rationale":"rejected: "+bad}
        accepted.append((c,v))
    # no survivor may be absorbed elsewhere in same run
    absorbed={m["slug"] for _,v in accepted for m in v.get("members",[]) if m.get("action")=="absorb"}
    for i,(c,v) in enumerate(accepted):
        if v.get("verdict")!="keep" and v.get("into") in absorbed:
            rejected.append({"cluster_id":c["cluster_id"],"reason":"absorb_chain"}); accepted[i]=(c,{"verdict":"keep","members":[],"rationale":"rejected: absorb_chain"})
    return accepted,rejected
def report(plan, rows, rejected, llm):
    absorbed=sum(1 for _,v in rows for m in v.get("members",[]) if m.get("action")=="absorb")
    lines=["# Memory index GC plan","",f"llm: {llm}",f"current total lines: {plan['total_lines']}; current entry lines: {plan['entry_lines']}",f"projected post-GC index size: {plan['total_lines']-absorbed} (cap: {plan['cap']})",f"candidate_clusters: {len(plan['clusters'])}",f"deferred_clusters: {plan['deferred']}"]
    if plan.get("clustering"):
        d=plan["clustering"]
        lines.append(f"clustering: {d['eligible_pairs_same_section_type']}/{d['same_section_type_pairs']} same-section/type pairs met sim {plan['sim']}; max={d['max_similarity_same_section_type']:.6f}; all-pair eligible={d['eligible_pairs_any']}/{d['all_pairs']} max={d['max_similarity_any']:.6f}; seen-filtered clusters={d['clusters_filtered_seen']}")
    lines.extend(["","## Per-cluster verdicts"])
    for c,v in rows: lines.append(f"- {c['cluster_id']}: {v.get('verdict','keep')} into={v.get('into','')} — {v.get('rationale','')}")
    for r in rejected: lines.append(f"- rejected_verdict: {r['cluster_id']} {r['reason']}")
    return "\n".join(lines)+"\n", absorbed
def main():
 p=argparse.ArgumentParser(); sub=p.add_subparsers(dest="cmd",required=True)
 for n in ("prepare","finalize"):
  q=sub.add_parser(n); q.add_argument("--memory-dir",required=True); q.add_argument("--cap",type=int,default=100); q.add_argument("--sim",type=float,default=.34); q.add_argument("--max-clusters",type=int,default=40); q.add_argument("--plan",required=True); q.add_argument("--model",default="haiku"); q.add_argument("--verdicts-file"); q.add_argument("--apply",action="store_true")
 q=sub.add_parser("restore"); q.add_argument("--memory-dir",required=True); q.add_argument("--run-dir",required=True)
 a=p.parse_args(); mem=Path(a.memory_dir).resolve(); index=mem/"MEMORY.md"
 if a.cmd=="restore":
  run=Path(a.run_dir); manifest=run/"manifest.yaml"; data=json.loads(manifest.read_text())
  if sha(index)!=data["index_sha256_post"]: print("restore refused: live index changed",file=sys.stderr); return 6
  shutil.copyfile(run/"MEMORY.md.pre",index)
  for e in data["entries"]: shutil.move(str(run/(e["slug"]+".md")),str(mem/(e["slug"]+".md")))
  print(f"restored {data['run_id']}"); return 0
 if a.cmd=="prepare":
  lines,es=parse(index,mem.parent); plan={"memory_dir":str(mem),"index_sha256_pre":sha(index),"cap":a.cap,"sim":a.sim,"total_lines":len(lines),"entry_lines":len(es),"lines":lines,"entries":es}
  if len(lines)<=a.cap: plan["early_exit"]=True; plan["request"]={"cap":a.cap,"current_lines":len(lines),"clusters":[]}; plan["clusters"]=[]; plan["deferred"]=0
  else:
   cs,defer,diagnostics=clusters(es,a.sim,a.max_clusters); seen=load_seen(mem); before_seen=len(cs); cs=[x for x in cs if fingerprint(x,a.sim) not in seen]; diagnostics["seen_fingerprints"]=len(seen); diagnostics["clusters_filtered_seen"]=before_seen-len(cs); req=request_for(cs,a.cap,len(lines)); plan["clusters"]=req; plan["deferred"]=defer; plan["clustering"]=diagnostics; plan["skip_llm"]=not bool(req); plan["request"]={"cap":a.cap,"current_lines":len(lines),"clusters":[{k:v for k,v in c.items() if k!="_members"} for c in req]}
  Path(a.plan).write_text(json.dumps(plan),encoding="utf-8"); return 0
 plan=json.loads(Path(a.plan).read_text());
 if plan.get("early_exit"):
  print(f"memory-index-gc: no-op (index size {plan['total_lines']}, cap {plan['cap']})"); return 0
 if not plan["clusters"]:
  text,_=report(plan,[],[],"skipped (no candidate clusters)"); (mem/"memory-gc-report.md").write_text(text,encoding="utf-8")
  print(f"memory-index-gc: no-op (no candidate clusters at sim {plan['sim']}; report {mem/'memory-gc-report.md'})"); return 0
 try: got,llm=verdicts(plan,a.verdicts_file,a.model)
 except VerdictError as exc:
  rows,rejected=validate(plan,{}); text,_=report(plan,rows,rejected,"error: "+str(exc)); (mem/"memory-gc-report.md").write_text(text,encoding="utf-8")
  print(f"memory-index-gc: model verdict call failed: {exc}",file=sys.stderr); return 7
 rows,rejected=validate(plan,got); text,absorbed=report(plan,rows,rejected,llm); (mem/"memory-gc-report.md").write_text(text,encoding="utf-8")
 if not a.apply: print(f"memory-index-gc: dry-run report {mem/'memory-gc-report.md'}"); return 0
 if sha(index)!=plan["index_sha256_pre"]: print("index changed during GC",file=sys.stderr); return 5
 moves=[]; changes={}
 for c,v in rows:
  for m in v.get("members",[]):
   if m.get("action")=="absorb": moves.append({"slug":m["slug"],"title":next(e["title"] for e in c["_members"] if e["slug"]==m["slug"]),"action":v["verdict"],"absorbed_by":v["into"],"cluster_id":c["cluster_id"],"rationale":v.get("rationale","")[:200],"from_line":next(e["line_no"] for e in c["_members"] if e["slug"]==m["slug"])}); changes.setdefault(v["into"],[]).append(m)
 stamp=datetime.datetime.now(datetime.timezone.utc).strftime("gc-%Y%m%dT%H%M%SZ"); run=mem/"archive"/stamp; run.mkdir(parents=True); shutil.copyfile(index,run/"MEMORY.md.pre")
 remove={x["slug"] for x in moves}; output=[]
 for line in plan["lines"]:
  m=ENTRY.match(line.rstrip("\n")); slug=(m.group(2)[:-3] if m and m.group(2).endswith('.md') else (m.group(2) if m else ''))
  if slug in remove: continue
  if slug in changes:
   base=line.rstrip("\n"); labels=[f"[{x.get('merged_hook') or x['slug']}]({x['slug']}.md)" for x in changes[slug]]; base += (". Also: " if ". Also:" not in base else ", ")+", ".join(labels); line=base+"\n"
  output.append(line)
 index.write_text("".join(output),encoding="utf-8")
 for e in moves: shutil.move(str(mem/(e["slug"]+".md")),str(run/(e["slug"]+".md")))
 manifest={"run_id":stamp,"run_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"memory_dir":str(mem),"cap":plan["cap"],"sim":plan["sim"],"model":a.model,"index_sha256_pre":plan["index_sha256_pre"],"index_sha256_post":sha(index),"entries":moves,"rejected":rejected,"deferred_clusters":plan["deferred"]}; (run/"manifest.yaml").write_text(json.dumps(manifest,indent=2)+"\n")
 with (mem/"archive"/"ARCHIVE.md").open("a",encoding="utf-8") as f:
  f.write("\n### GC run "+stamp+"\n"+"".join(f"- {e['slug']} → {e['absorbed_by']}\n" for e in moves))
 with (mem/".memory-gc-state.yaml").open("a",encoding="utf-8") as f:
  for c,v in rows:
   if v.get("verdict")=="keep": f.write(f"- fingerprint: {fingerprint(c['_members'],plan['sim'])}\n  verdict: keep\n  run_id: {stamp}\n")
 print(f"memory-index-gc: applied {len(moves)} entries; index size {len(output)}")
 return 0
if __name__=="__main__": sys.exit(main())
