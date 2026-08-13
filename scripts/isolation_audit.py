#!/usr/bin/env python3
"""TRIO 3.0 认知隔离审计器——检查 run 产出物中是否存在跨面具引用。
   2026-07-09 Claude原生 L2 方案·轻量版"""

import re, sys, json
from pathlib import Path

CROSS_REFERENCE_PATTERNS = [
    ("kimi", r"(DeepSeek|deepseek|DS).(说|认为|指出|发现|提到)"),
    ("kimi", r"(Claude|claude).(说|认为|指出|发现|建议)"),
    ("deepseek", r"(Kimi|kimi).(说|认为|指出|发现|洞察)"),
    ("deepseek", r"(Claude|claude).(说|认为|指出|发现|建议)"),
    ("claude", r"(Kimi|kimi).(说|认为|指出|发现|洞察)"),
    ("claude", r"(DeepSeek|deepseek|DS).(说|认为|指出|发现|审计)"),
    ("*", r"(上一步|前一个面具|另一个视角已经)"),
]

BLINDSPOT_KEYWORDS = ["盲区", "blind spot", "不确定", "看不到", "可能遗漏"]

def audit_run(run_dir: Path) -> dict:
    results = {"run_id": run_dir.name, "violations": [], "blindspot_check": [], "overall": "PASS"}
    step_files = sorted(run_dir.glob("step*.md"))

    for sf in step_files:
        content = sf.read_text(encoding="utf-8")
        mask = "unknown"
        for m in ["kimi", "deepseek", "claude"]:
            if m in sf.name.lower(): mask = m; break

        for mask_pat, ref_pat in CROSS_REFERENCE_PATTERNS:
            if mask_pat == "*" or mask_pat == mask:
                for m in re.finditer(ref_pat, content):
                    ctx = content[max(0, m.start()-30):m.end()+30]
                    results["violations"].append({
                        "file": sf.name, "mask": mask, "match": m.group(), "context": ctx
                    })

        has_blindspot = any(kw in content.lower() for kw in BLINDSPOT_KEYWORDS)
        results["blindspot_check"].append({"file": sf.name, "mask": mask, "has_blindspot": has_blindspot})

    if results["violations"]:
        results["overall"] = "FAIL"
    if any(not b["has_blindspot"] for b in results["blindspot_check"]):
        results["overall"] = "WARN" if results["overall"] == "PASS" else results["overall"]

    return results


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python isolation-audit.py <run_dir> [--all]")
        sys.exit(1)

    if sys.argv[1] == "--all":
        trio_root = Path(__file__).parent.parent
        runs_dir = trio_root / "runs"
        all_results = []
        for d in sorted(runs_dir.iterdir()):
            if d.is_dir() and (d / "run-state.json").exists():
                r = audit_run(d)
                all_results.append(r)
                icon = "✅" if r["overall"] == "PASS" else "⚠️" if r["overall"] == "WARN" else "❌"
                print(f"  {icon} {r['run_id']}: {r['overall']} ({len(r['violations'])} violations)")

        passed = sum(1 for r in all_results if r["overall"] == "PASS")
        print(f"\n隔离通过率: {passed}/{len(all_results)} ({passed/len(all_results)*100:.0f}%)")
    else:
        result = audit_run(Path(sys.argv[1]))
        print(json.dumps(result, ensure_ascii=False, indent=2))
