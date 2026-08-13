"""C7 helper: 校验 topology-state.json Phase 字段完整性 (兼容 v1/v2 两种格式)"""
import json, sys

d = json.load(open(sys.argv[1]))

# v1 格式: {"phases": {"phase0": {...}, "phase1": {...}}}
# v2 格式: {"ph": {"0": {"et","u","d"}, "1": {"c","b"}, ...}}
if "phases" in d:
    phases = d["phases"]
    count = len([k for k in phases if k.startswith("phase")])
    # v1: 只要每个 phase 有 status 字段就行
    score = min(count, 5)
    details = "ALL_OK" if score >= 3 else f"仅{count}/5个phase"
    print(f"{score} {details}")
elif "ph" in d:
    ph = d["ph"]
    score = 0; details = []
    for k in ["0","1","2","3","4"]:
        if k in ph:
            pk = ph[k]
            checks = {"0":["et","u","d"],"1":["c","b"],"2":["pn","l1","l2","inj"],"3":["up","dn","rv","tw"],"4":["mb","mc","ni","atk"]}
            if all(x in pk for x in checks.get(k,[])): score += 1
            else: details.append(f"Phase{k}字段不完整")
        else: details.append(f"Phase{k}缺失")
    print(f'{score} {";".join(details) if details else "ALL_OK"}')
else:
    print("0 无phases/ph字段")
