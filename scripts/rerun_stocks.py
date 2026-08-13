#!/usr/bin/env python3
"""TRIO-Stock 批量重跑脚本 v1 — 用新模板规则重新生成报告+自动评分"""
import os, sys, json, time, subprocess
from pathlib import Path
from datetime import datetime

API_KEY = os.getenv("DEEPSEEK_API_KEY", "")
if not API_KEY:
    # Try credentials file in both locations
    for cred_path in [
        os.path.expanduser("~/.claude/.credentials.json"),
        "/mnt/c/Users/Rex/.claude/.credentials.json",
        os.path.expanduser("~/.claude/projects/-mnt-c-Users-Rex/.credentials.json"),
    ]:
        try:
            creds = json.load(open(cred_path))
            API_KEY = creds.get("deepseek_api_key", "")
            if API_KEY:
                break
        except:
            continue
if not API_KEY:
    print("❌ 未找到DeepSeek API Key")
    sys.exit(1)

STOCK_DIR = Path("/mnt/d/Agent文件/TRIO-Stock/股票库")
STANDARD = Path("/mnt/d/Agent文件/TRIO-Stock/config/STOCK-ANALYSIS-STANDARD.json")
SCORER = Path("/mnt/d/TRIO 3.0/scripts/score_report.py")
BASELINE_FILE = Path("/mnt/d/Agent文件/TRIO-Stock/state/baseline-scores.json")

# 加载模板规则
with open(STANDARD) as f:
    cfg = json.load(f)
g9_rule = cfg["DELIVERY_RULES"]["inline_source_annotation"]["rule"]
g9_good = cfg["DELIVERY_RULES"]["inline_source_annotation"]["good"]
g9_bad = cfg["DELIVERY_RULES"]["inline_source_annotation"]["bad"]

SYSTEM_PROMPT = """你是TRIO-Stock分析引擎。生成A股深度分析报告。

【🚨 最高优先级—数字溯源规则】
表格中每个数字必须像这样标注来源：
| 营收(亿) | 65.0 (来源:2025年报P12) | +453% (来源:年报) |
| 毛利率 | 55.2% (年报P15) | 56.7%→55.2% |
不是在表格后面加一列"来源"，是把来源直接写在数字后面的括号里。
错误: | 营收 | 65.0 | 年报 |
正确: | 营收 | 65.0 (年报P12) |

非表格中的数字同理:
错误: 营收65.0亿，增长453% [A][5]
正确: 营收65.0亿(来源:2025年报P12)，增长453%

【报告结构—每层一个表格,数字旁注来源】
# 股票名 (代码) · TRIO 全量分析
## 🚩 红色信号清单(表格,数字旁注来源)
## L1 · 生意本质(表格)
## L2 · 财务穿透(核心财务表格,每个数字旁注来源)
## L3 · 竞争格局(表格)
## L4 · 管理层
## L5 · 产业链验证(表格)
## L6 · 估值与预期(三情景表格)
## L7 · 证伪与风险
## 📊 综合判断

每层必须: 数据表格(数字旁括号注来源) + 🚩反常 + [A][B][C]+[1-5] + 反证覆盖率"""

import requests

def rerun_stock(stock_code: str, stock_name: str, old_report_path: str) -> dict:
    """重跑单只股票分析——调用DeepSeek API"""

    # 读取旧报告作为上下文参考
    old_text = ""
    if Path(old_report_path).exists():
        old_text = Path(old_report_path).read_text(encoding="utf-8")[:3000]

    prompt = f"""为{stock_name}({stock_code})生成TRIO全量分析报告。

🚨 最重要的规则——违反此规则报告无效:
报告中每一个数字（营收、利润、增速、市值、比率、百分比）后面，必须在同一表格单元格或同一句话的括号里标注来源。
例如:
  营收 65.0亿(年报P12)  ← 正确
  毛利率 55.2%(年报P15)  ← 正确
  净利 20.6亿(年报P8), +453%(年报)  ← 正确
  市值 320亿(Wind 2026-07-14)  ← 正确

不要这样写:
  营收 65.0亿 [A][5]  ← 错误! [A]不是来源
  | 营收 | 65.0 | 年报 |  ← 错误! 来源在另一列

来源必须和数字在同一个括号里:(年报Pxx) 或 (Wind) 或 (2026Q1季报)

【旧报告参考数据】
{old_text}

【输出格式——直接输出Markdown，不要前言】
# {stock_name} ({stock_code}) · TRIO 全量分析
> 声明等级/审计状态/分析日期/深度级/不构成投资建议

## 🚩 红色信号清单
(表格，所有数字后面括号注来源)

## L1 · 生意本质
## L2 · 财务穿透
(核心财务数据表格，每个单元格=数字(来源))

## L3 · 竞争格局
## L4 · 管理层
## L5 · 产业链验证
## L6 · 估值与预期
## L7 · 证伪与风险
## 📊 综合判断
(反证覆盖率统计)"""

    resp = requests.post(
        "https://api.deepseek.com/v1/chat/completions",
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
        json={
            "model": "deepseek-chat",
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.3,
            "max_tokens": 6000,
        },
        timeout=120
    )

    if resp.status_code != 200:
        return {"error": f"API {resp.status_code}: {resp.text[:200]}"}

    data = resp.json()
    new_report = data["choices"][0]["message"]["content"]

    # 保存新报告
    out_dir = Path(old_report_path).parent
    new_path = out_dir / f"{stock_name}-{stock_code}-analysis-{datetime.now().strftime('%Y-%m-%d')}.md"
    new_path.write_text(new_report, encoding="utf-8")

    # 评分
    r = subprocess.run(["python3", str(SCORER), str(new_path)], capture_output=True, text=True, timeout=15)

    return {
        "stock": f"{stock_name}-{stock_code}",
        "path": str(new_path),
        "status": "done",
        "scoring_output": r.stdout[-500:] if r.stdout else "评分失败"
    }


def get_old_score(report_path: str) -> int:
    """从baseline中获取旧分数"""
    if not BASELINE_FILE.exists():
        return None

    with open(BASELINE_FILE) as f:
        data = json.load(f)

    rid = Path(report_path).stem
    for r in data:
        if r["report_id"] == rid:
            return r["baseline"]["total"]
    return None


def find_stocks():
    """扫描所有待重跑的股票"""
    stocks = []
    for d in sorted(STOCK_DIR.iterdir()):
        if not d.is_dir() or d.name.startswith("_"):
            continue

        # 找最新分析报告(排除unknown)
        reports = sorted(
            [f for f in d.glob("*.md") if "unknown" not in f.name and "analysis" in f.name],
            key=lambda f: f.stat().st_mtime, reverse=True
        )
        if not reports:
            continue

        # 从目录名解析代码和名称
        parts = d.name.rsplit("-", 1)
        if len(parts) == 2:
            name, code = parts
        else:
            name, code = d.name, ""

        stocks.append({
            "name": name,
            "code": code,
            "report": str(reports[0]),
            "dir": str(d)
        })

    return stocks


if __name__ == "__main__":
    stocks = find_stocks()
    print(f"找到 {len(stocks)} 只股票待重跑\n")

    # 模式选择
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"

    if mode == "worst":
        # 从baseline中找最低分
        with open(BASELINE_FILE) as f:
            data = json.load(f)
        ranked = sorted(data, key=lambda r: r["baseline"]["total"])
        worst_ids = {r["report_id"] for r in ranked[:10]}
        stocks = [s for s in stocks if Path(s["report"]).stem in worst_ids]
        print(f"重跑底部 {len(stocks)} 只")

    elif mode == "one":
        stocks = stocks[:1]
        print(f"测试: {stocks[0]['name']}-{stocks[0]['code']}")

    results = []
    for i, s in enumerate(stocks):
        print(f"\n[{i+1}/{len(stocks)}] {s['name']}-{s['code']} ...")

        old_score = get_old_score(s["report"])
        score_str = f"(旧:{old_score}/15)" if old_score else ""
        print(f"  {score_str} → 重跑中...")

        try:
            r = rerun_stock(s["code"], s["name"], s["report"])
            results.append(r)

            if "error" in r:
                print(f"  ❌ {r['error']}")
            else:
                # 提取新评分
                for line in r.get("scoring_output", "").split("\n"):
                    if "基线总分" in line or "正式基线" in line:
                        print(f"  ✅ {line.strip()}")
                        break

        except Exception as e:
            print(f"  ❌ {e}")

        time.sleep(2)  # API限流

    # 汇总
    print(f"\n{'='*60}")
    print(f"完成: {len([r for r in results if 'error' not in r])}/{len(stocks)}")
    print(f"失败: {len([r for r in results if 'error' in r])}")
