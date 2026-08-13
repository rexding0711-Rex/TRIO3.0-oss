#!/usr/bin/env python3
"""engine-gap-detector.py — 从 Run 标签分布中发现'高频无引擎覆盖的任务类型'
   50 行·第十轮审计·5.0 引擎组合器最简原型"""

import json
from pathlib import Path
from collections import defaultdict

TRIO_ROOT = Path(__file__).parent.parent
HISTORY = TRIO_ROOT / "state" / "run-history.jsonl"
THRESHOLD = 3
EXCLUDE_TYPES = {"决策", "M4训练", "综合交付", "自指审计", "系统维护"}

def detect_gaps():
    runs = [json.loads(l) for l in HISTORY.read_text().strip().split("\n") if l.strip()]
    type_stats = defaultdict(lambda: {"count": 0, "engine_covered": 0, "post_mortems": []})

    for r in runs:
        t = r.get("task_type", "unknown")
        type_stats[t]["count"] += 1
        if r.get("engines_used") or r.get("engines"):
            type_stats[t]["engine_covered"] += 1
        pm = r.get("post_mortem", "")
        if pm: type_stats[t]["post_mortems"].append(pm[:100])

    gaps = []
    for t, stats in type_stats.items():
        if t in EXCLUDE_TYPES:
            continue
        if stats["count"] >= THRESHOLD and stats["engine_covered"] == 0:
            gaps.append({
                "task_type": t, "occurrences": stats["count"],
                "sample_post_mortems": stats["post_mortems"][:3],
                "suggested_steps": infer_steps(t, stats["post_mortems"]),
            })
    gaps.sort(key=lambda x: x["occurrences"], reverse=True)
    return gaps

def infer_steps(task_type: str, post_mortems: list) -> list:
    all_text = " ".join(post_mortems)
    steps = ["search_web"]
    if any(kw in all_text for kw in ["赛道", "行业", "市场", "规模", "玩家"]):
        steps.append("market_sizing")
    if any(kw in all_text for kw in ["技术", "路线", "专利", "论文"]):
        steps.append("tech_landscape")
    if any(kw in all_text for kw in ["公司", "竞争", "对标"]):
        steps.append("competitor_mapping")
    if any(kw in all_text for kw in ["风险", "壁垒", "护城河"]):
        steps.append("risk_assessment")
    steps.append("synthesize")
    steps.append("topology_check")
    return steps

if __name__ == "__main__":
    gaps = detect_gaps()
    if not gaps:
        print("✅ 当前无高频未覆盖任务类型")
    else:
        print(f"🔍 发现 {len(gaps)} 个引擎缺口：\n")
        for g in gaps:
            print(f"  📌 {g['task_type']} ({g['occurrences']} 次·零引擎覆盖)")
            print(f"     建议步骤: {' → '.join(g['suggested_steps'])}")
            print(f"     样本: {g['sample_post_mortems'][0][:60]}...")
            print()
