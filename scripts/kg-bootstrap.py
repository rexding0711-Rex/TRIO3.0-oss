#!/usr/bin/env python3
"""TRIO 3.0 KG Bootstrap — 从结构化数据提取实体关系·零LLM调用"""

import json, re, sys
from pathlib import Path

TRIO_ROOT = Path(__file__).parent.parent
OUTPUT = TRIO_ROOT / "state" / "kg-bootstrap.cypher"

def extract_from_run_history():
    nodes, edges = set(), []
    history_file = TRIO_ROOT / "state" / "run-history.jsonl"
    if not history_file.exists(): return nodes, edges

    for line in history_file.read_text(encoding="utf-8").strip().split("\n"):
        if not line.strip(): continue
        r = json.loads(line)
        pm = r.get("post_mortem", "")
        task = r.get("task_type", "")

        cn = re.findall(r'[一-鿿]{2,8}(?:科技|制药|公司|集团|超市|纤维|传感器|陶瓷|药业|材料|技术)', pm)
        for e in cn: nodes.add((e, "Company"))
        en = re.findall(r'[A-Z][A-Za-z]{2,}(?:\s[A-Z][a-z]+)?', pm)
        for e in en: nodes.add((e, "Company"))
        persons = re.findall(r'(?:[一-鿿]{2,3})(?=——|实验室|教授|分析|团队)', pm)
        for p in persons: nodes.add((p, "Person"))

        rid = r.get("run_id", "")
        parts = rid.split("-")
        hint = "-".join(parts[3:-1]) if len(parts) > 4 and parts[-1] in ("dd","intel","trace","search","review","risk","daily","batch","map","evolution","mirror","training") else ""
        if hint and task: edges.append((hint, task, "TRIO_RUN"))

    return nodes, edges

def extract_from_run_states():
    nodes, edges = set(), []
    for d in (TRIO_ROOT / "runs").iterdir():
        if not d.is_dir(): continue
        sf = d / "run-state.json"
        if not sf.exists(): continue
        try: state = json.loads(sf.read_text(encoding="utf-8"))
        except: continue
        proj = state.get("project", "")
        if proj: nodes.add((proj, "Company"))
        for eng in state.get("engines_used", []):
            nodes.add((eng, "Engine"))
            if proj: edges.append((proj, eng, "ANALYZED_BY"))
    return nodes, edges

def generate(nodes, edges):
    lines = ["// TRIO KG Bootstrap", f"// {len(nodes)} nodes, {len(edges)} edges", ""]
    for name, ntype in sorted(nodes):
        safe = name.replace('"', '\\"')
        lines.append(f'MERGE (n:{ntype} {{name: "{safe}"}});')
    lines.append("")
    for src, tgt, rel in edges:
        ss = src.replace('"', '\\"'); tt = tgt.replace('"', '\\"')
        lines.append(f'MATCH (a {{name: "{ss}"}}), (b {{name: "{tt}"}}) MERGE (a)-[:{rel}]->(b);')
    OUTPUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"✅ {OUTPUT}: {len(nodes)} nodes, {len(edges)} edges")

if __name__ == "__main__":
    n1, e1 = extract_from_run_history()
    n2, e2 = extract_from_run_states()
    generate(n1 | n2, e1 + e2)
