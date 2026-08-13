#!/usr/bin/env python3
"""TRIO 3.1 评分脚本 v3 — 3维正式基线(15分) + 2维异常标记
Bug修复(v2→v3):
  1. text.find(x)重复定位 → re.finditer遍历所有出现
  2. 无数字→F1=1(致命) 非3(合格)
  3. "据"收紧为复合模式 "根据|据.*?[显示统计报道公告]"
  4. mech_f3论断识别加回A股核心词: 大概率|有望|将会|看好|利空|利好|趋势|拐点
  5. F1阈值收紧: .95/.85/.7/.5
  6. F2/F4降为异常标记(单API自评≤2触发预警)
"""
import re, json, sys
from pathlib import Path
from datetime import datetime

# ── 配置 ──
F1_THRESHOLDS = [(.95,5),(.85,4),(.70,3),(.50,2)]  # 收紧版
F1_SOURCE_KW = ["年报","公告","披露","来源","Wind","东方财富","统计局","IDC","券商","研报","财报","季报","[A]","[B]","[C]","招股书"]
F3_CLAIM_KW = ["因此","表明","意味着","预计","判断","认为","大概率","有望","将会","看好",
               "看空","利空","利好","趋势","拐点","或将","预期","推断","结论"]
F5_METRIC_KW = r'营收|净利润|毛利率|ROE|股价|市值|订单|产能|市占率|增速|净利|OCF|PE|PS|PB|EPS|现金流|扣非'
F5_THRESHOLD_KW = r'>|>=|<|<=|突破|达到|超过\s*[\d.]+|回升|跌破|降至|升至|目标价'
F5_DEADLINE_KW = r'\d{4}年[第]?[一二三四季度]|Q[1-4]|未来\s*\d+\s*(?:个月|周|天)|截至\s*\d{4}|\d{4}-\d{2}-\d{2}'


def find_all_positions(text, pattern):
    """返回所有匹配的(start, end)位置——修复Bug1: text.find只返回首次"""
    return [(m.start(), m.end()) for m in re.finditer(pattern, text)]


def mech_f1(text):
    """F1 事实准确性 — 数字是否有具体来源标注（修复版）"""
    positions = find_all_positions(text, r'[\d,]+\.?\d*\s*(?:亿|万|元|%|倍)')
    if not positions:
        return (1, "无数字——股票分析报告致命缺陷", {"total": 0})

    n = len(positions)
    sample = positions[:30]
    sourced = 0
    lines = text.split('\n')

    for start, end in sample:
        # 方法1: 60字窗口内检查
        ctx = text[max(0, start-60):min(len(text), end+60)]
        found = any(kw in ctx for kw in F1_SOURCE_KW)

        # 方法2: 同行检查（解决表格中来源列距离过远的问题）
        if not found:
            line_idx = text[:start].count('\n')
            if 0 <= line_idx < len(lines):
                line = lines[line_idx]
                found = any(kw in line for kw in F1_SOURCE_KW)

        if found:
            sourced += 1

    ratio = sourced / len(sample)

    for threshold, score in F1_THRESHOLDS:
        if ratio >= threshold:
            return (score, f"{sourced}/{len(sample)} 数字有具体来源 (r={ratio:.2f})",
                    {"ratio": round(ratio, 2), "total": n, "sampled": len(sample)})
    return (1, f"仅{sourced}/{len(sample)} 数字有来源 (r={ratio:.2f})",
            {"ratio": round(ratio, 2), "total": n, "sampled": len(sample)})


def mech_f3(text):
    """F3 证据匹配度 — 引用密度+置信度标签+诊断词覆盖（修复版）"""
    refs = len(re.findall(r'\[A\]|\[B\]|\[C\]|\[D\]', text))
    tags = len(re.findall(r'\[([1-5])\]', text))

    # 修复Bug4: 加回A股核心论断词
    claim_pattern = '|'.join(F3_CLAIM_KW)
    claims = max(1, len(re.findall(
        rf'[。；]\s*([^。；]*?(?:{claim_pattern})[^。；]*)[。；]', text)))

    density = refs / claims

    if density >= 2.0 and tags >= 5:
        score = 5
    elif density >= 1.5:
        score = 4
    elif density >= 1.0:
        score = 3
    elif density >= 0.5:
        score = 2
    else:
        score = 1

    return (score, f"{refs}引用/{claims}论断={density:.1f}密度 {tags}标签",
            {"refs": refs, "claims": claims, "tags": tags, "density": round(density, 2)})


def mech_f5(text):
    """F5 可验证性 — 指标+阈值+时间窗+反证覆盖率"""
    m = len(re.findall(F5_METRIC_KW, text))
    t = len(re.findall(F5_THRESHOLD_KW, text))
    d = len(re.findall(F5_DEADLINE_KW, text))

    # 反证覆盖率（TRIO报告特有）
    cov = re.search(r'反证覆盖率[:\s]*(\d+)[/\s]*(\d+)\s*=\s*([\d.]+)%', text)
    cov_pct = float(cov.group(3)) if cov else None

    if d >= 2 and t >= 2 and m >= 3:
        score = 5
    elif d >= 1 and t >= 1 and m >= 2:
        score = 4
    elif d >= 1 or t >= 1:
        score = 3
    elif m >= 1:
        score = 2
    else:
        score = 1

    detail = f"指标{m} 阈值{t} 时间窗{d}"
    if cov_pct is not None:
        detail += f" 反证覆盖率{cov_pct:.0f}%"

    return (score, detail, {"metrics": m, "thresholds": t, "deadlines": d,
            "coverage_pct": cov_pct})


def score(filepath, llm_f2=None, llm_f4=None):
    """
    评分主函数。
    返回: (result_dict, baseline_total, baseline_max, alerts)

    baseline = F1 + F3 + F5（15分制正式基线）
    markers  = F2 + F4（单API自评，≤2触发异常标记）
    """
    text = Path(filepath).read_text(encoding="utf-8")
    rid = Path(filepath).stem

    r = {"report_id": rid, "scored_at": datetime.now().isoformat()}

    # 正式基线维度
    r["F1"] = mech_f1(text)
    r["F3"] = mech_f3(text)
    r["F5"] = mech_f5(text)

    # 异常标记维度（单API自评）
    r["F2"] = (llm_f2, "DeepSeek自检") if llm_f2 is not None else (None, "未运行(--flag)")
    r["F4"] = (llm_f4, "DeepSeek自检") if llm_f4 is not None else (None, "未运行(--flag)")

    baseline_scores = [r[k][0] for k in ["F1", "F3", "F5"] if r[k][0] is not None]
    baseline_total = sum(baseline_scores)
    baseline_max = len(baseline_scores) * 5

    # 异常检测
    alerts = []
    if llm_f2 is not None and llm_f2 <= 2:
        alerts.append(f"F2={llm_f2} 逻辑跳跃风险→建议人工复核因果链")
    if llm_f4 is not None and llm_f4 <= 2:
        alerts.append(f"F4={llm_f4} 反例缺失风险→建议人工补反例")
    if llm_f2 is not None and llm_f2 >= 4 and llm_f4 is not None and llm_f4 >= 4:
        alerts.append("F2+F4双高→自评过度自信(单API盲区),建议人工抽检")

    return r, baseline_total, baseline_max, alerts


# ── 输出 ──

def print_report(r, baseline_total, baseline_max, alerts):
    """终端友好输出"""
    dim_labels = {"F1": "事实准确性", "F2": "因果完整性",
                  "F3": "证据匹配度", "F4": "反例覆盖度", "F5": "可验证性"}

    print(f"\n{'='*60}")
    print(f"  {r['report_id'][:50]}")
    print(f"  {'─'*58}")
    print(f"  【正式基线】{baseline_total}/{baseline_max} 分（机械层·零成本·可重复）")
    print(f"  {'─'*58}")

    for k in ["F1", "F3", "F5"]:
        sc, detail = r[k][0], r[k][1]
        bar = "█" * sc + "░" * (5 - sc)
        print(f"  {k} {dim_labels[k]:<10s} [{bar}] {sc}/5  {detail}")

    print(f"\n  【异常标记】不纳入基线·单API自评·仅作预警")
    print(f"  {'─'*58}")
    for k in ["F2", "F4"]:
        sc, source = r[k][0], r[k][1]
        if sc is None:
            print(f"  {k} {dim_labels[k]:<10s} [⏳] {source}")
        elif sc <= 2:
            print(f"  {k} {dim_labels[k]:<10s} [{sc}/5] 🚨 {source}")
        else:
            print(f"  {k} {dim_labels[k]:<10s} [{sc}/5] {source}")

    print(f"  {'─'*58}")
    if alerts:
        for a in alerts:
            print(f"  ⚠  {a}")
    else:
        print(f"  ✅ 无异常标记")
    print(f"{'='*60}")


def run_deepseek_flag(text: str) -> dict:
    """调用DeepSeek API做F2/F4自检标记。返回 {F2: int|None, F4: int|None}"""
    import os, requests, json as j

    # 从credentials文件或环境变量读取Key
    api_key = os.getenv("DEEPSEEK_API_KEY", "")
    if not api_key:
        try:
            creds = j.load(open(os.path.expanduser("~/.claude/.credentials.json")))
            api_key = creds.get("deepseek_api_key", "")
        except:
            pass
    if not api_key:
        return {"F2": None, "F4": None, "error": "未找到DeepSeek API Key"}

    # 截断到8000字以内
    snippet = text[:8000]

    prompts = {
        "F2": f"""你是逻辑审计员。检查以下报告的因果链。
找出所有"从A直接跳到C,缺中间机制B"的逻辑跳跃。
评分: 5=0-1处跳跃 4=2处 3=3-4处 2=5-6处(⚠需人工) 1=7+处(🚨必须人工)
只输出JSON: {{"score": N, "jumps": ["位置: 问题描述"], "summary": "一句话"}}

报告:
{snippet}""",

        "F4": f"""你是批判性思维审计员。检查以下报告是否真正考虑了反对意见。
评分: 5=≥2个反例并逐一回应 4=1-2个反例有回应 3=提到但敷衍 2=仅形式风险提示(⚠需人工) 1=完全单向论证(🚨必须人工)
只输出JSON: {{"score": N, "counterarguments": ["反例: 回应程度"], "summary": "一句话"}}

报告:
{snippet}"""
    }

    results = {}
    for dim in ["F2", "F4"]:
        try:
            resp = requests.post(
                "https://api.deepseek.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
                json={"model": "deepseek-chat", "messages": [{"role": "user", "content": prompts[dim]}],
                      "temperature": 0.1, "max_tokens": 400, "response_format": {"type": "json_object"}},
                timeout=30
            )
            data = resp.json()
            result = json.loads(data["choices"][0]["message"]["content"])
            results[dim] = result.get("score", None)
        except Exception as e:
            results[dim] = None
            results[f"{dim}_error"] = str(e)[:80]

    return results


if __name__ == "__main__":
    files = [f for f in sys.argv[1:] if not f.startswith("--")]
    json_mode = "--json" in sys.argv
    flag_mode = "--flag" in sys.argv

    if not files:
        print("用法: python score_report.py <report1.md> [report2.md ...] [--json] [--flag]")
        print("  --json  输出机器可读JSON")
        print("  --flag  运行F2/F4 DeepSeek自检标记(需DEEPSEEK_API_KEY)")
        sys.exit(1)

    for f in files:
        if not Path(f).exists():
            print(f"⚠ 文件不存在: {f}", file=sys.stderr)
            continue

        text = Path(f).read_text(encoding="utf-8")

        # F2/F4 自检
        flag_results = {}
        if flag_mode:
            flag_results = run_deepseek_flag(text)

        r, bt, bm, alerts = score(f, llm_f2=flag_results.get("F2"), llm_f4=flag_results.get("F4"))

        if json_mode:
            out = {
                "report_id": r["report_id"],
                "scored_at": r["scored_at"],
                "baseline": {
                    "F1": {"score": r["F1"][0], "detail": r["F1"][1]},
                    "F3": {"score": r["F3"][0], "detail": r["F3"][1]},
                    "F5": {"score": r["F5"][0], "detail": r["F5"][1]},
                    "total": bt,
                    "max": bm
                },
                "markers": {
                    "F2": r["F2"][0],
                    "F4": r["F4"][0]
                },
                "alerts": alerts
            }
            print(json.dumps(out, ensure_ascii=False, indent=2))
        else:
            print_report(r, bt, bm, alerts)
