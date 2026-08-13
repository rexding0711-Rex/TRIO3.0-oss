#!/usr/bin/env python3
"""硬阻断回归测试——对 9 次引擎实跑输出逐条验证六条硬阻断规则。
   2026-07-09 Claude第三轮审计·Gap 4 最简实现"""

import json, os, re, glob

HARD_BLOCKS = {
    "h1_template_filling": {
        "desc": "模板填充检测——评分缺少公式计算过程",
        "check": lambda text: bool(re.search(r'[0-9.]+\s*[×x*]\s*0\.[0-9]+', text)),
        "fail_msg": "评分未展示公式计算过程——仅有直觉赋分"
    },
    "h2_signal_coverage": {
        "desc": "信号覆盖率检测——N/6类信号标注",
        "check": lambda text: bool(re.search(r'[0-6]/6|覆盖率', text)),
        "fail_msg": "未标注信号覆盖率(N/6)——信号深度不透明"
    },
    "h3_superficial_analysis": {
        "desc": "浅层分析检测——引擎输出与搜索原文重合度",
        "check": lambda text: len(text) > 500,  # 有实质内容即为通过(粗略)
        "fail_msg": "输出过短——可能仅是搜索摘要而非分析"
    },
    "h4_context_bloat": {
        "desc": "上下文膨胀检测——输出文件大小",
        "check": lambda text: len(text) < 8000,  # ~4K tokens ~= 12K chars, 放宽到8K
        "fail_msg": "输出过长——可能加载了过多上下文"
    },
    "h5_score_without_calculation": {
        "desc": "无计算过程评分——评分数字出现但前文无推导",
        "check": lambda text: not (
            bool(re.search(r'[0-9]\.[0-9]/[0-9]|评分.*[0-9]\.[0-9]|综合.*[0-9]\.[0-9]', text))
            and not bool(re.search(r'[×x*]|加权|公式|计算', text))
        ),
        "fail_msg": "出现评分数字但无公式推导——凭直觉赋分"
    },
    "h6_l5_brake": {
        "desc": "L5刹车——关键假设未验证时不应下结论",
        "check": lambda text: not (
            ('样品' in text or '配方' in text or '待测' in text)
            and bool(re.search(r'评分|综合.*[0-9]\.[0-9]', text))
            and '实验' not in text
        ),
        "fail_msg": "关键假设未验证但给出了确定评分——应输出实验方案而非分数"
    }
}

def find_engine_outputs():
    """找到所有引擎实跑输出"""
    patterns = [
        "/mnt/d/工作/项目/*/竞品情报-引擎输出-*.md",
        "/mnt/d/工作/项目/*/人才引擎输出-*.md",
        "/mnt/d/工作/TRIO/Reports/人物分析/*引擎输出*.md",
    ]
    files = []
    for p in patterns:
        files.extend(glob.glob(p))
    return files

def main():
    files = find_engine_outputs()
    if not files:
        print("❌ 未找到引擎输出文件")
        return

    print(f"=== 硬阻断回归测试 ===\n测试文件: {len(files)} 个引擎输出\n")

    total_checks = 0
    total_passed = 0
    blocking_failures = []  # 应该触发阻断但没触发的

    for fpath in sorted(files):
        fname = os.path.basename(fpath)
        with open(fpath) as f:
            text = f.read()

        failures = []
        for hid, block in HARD_BLOCKS.items():
            total_checks += 1
            try:
                if block["check"](text):
                    total_passed += 1
                else:
                    failures.append((hid, block["fail_msg"]))
            except Exception as e:
                failures.append((hid, f"检查异常: {e}"))

        if failures:
            status = "❌"
            blocking_failures.append((fname, failures))
        else:
            status = "✅"

        print(f"{status} {fname}")
        for hid, msg in failures:
            print(f"   🔴 {hid}: {msg}")

    print(f"\n=== 汇总 ===")
    print(f"通过率: {total_passed}/{total_checks} ({total_passed/total_checks*100:.0f}%)")
    print(f"有阻断缺陷的文件: {len(blocking_failures)}/{len(files)}")

    if blocking_failures:
        print(f"\n🛑 发现 {len(blocking_failures)} 个文件存在硬阻断缺陷——引擎被绕过")
        print("建议: 用修复后的引擎重新跑这些 Case")
    else:
        print("✅ 所有文件通过硬阻断检查")

if __name__ == "__main__":
    main()
