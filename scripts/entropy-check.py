#!/usr/bin/env python3
"""熵减引擎——计算承诺追踪器的系统熵状态。

用法:
    python3 entropy-check.py <tracker_file> [--update]

输出 (stdout):
    active_count total_entropy trend
    例: "2 45.5 increasing"

选项:
    --update  直接更新 tracker 文件的「系统熵状态」表格
"""
import sys
import re
from datetime import datetime, timedelta


def parse_tracker(filepath: str) -> dict:
    """解析 tracker markdown，返回结构化数据。"""
    with open(filepath) as f:
        content = f.read()

    result = {"active": [], "completed": 0, "content": content}

    in_active = False
    for line in content.split("\n"):
        if line.startswith("## 活跃承诺"):
            in_active = True
            continue
        if in_active and line.startswith("## "):
            break
        if in_active and line.startswith("| C"):
            cols = [c.strip() for c in line.split("|")]
            if len(cols) < 9:
                continue
            cid = cols[1]
            desc = cols[2]
            made = cols[3]
            target = cols[4]
            status = cols[5]
            done_date = cols[6]
            entropy_str = cols[7]

            if status == "✅":
                result["completed"] += 1
                continue

            # 解析熵增速率
            try:
                entropy_rate = int(entropy_str)
            except ValueError:
                entropy_rate = 5  # 默认中等速率

            # 解析承诺日期计算未维护天数
            try:
                made_date = datetime.strptime(f"2026-{made}", "%Y-%m-%d")
            except ValueError:
                made_date = datetime.now()

            days_since = (datetime.now() - made_date).days

            result["active"].append({
                "id": cid,
                "desc": desc,
                "made": made,
                "target": target,
                "status": status,
                "entropy_rate": entropy_rate,
                "days_since_maintained": days_since,
                "current_entropy": entropy_rate * max(days_since, 1),
            })

    return result


def compute_entropy(data: dict) -> tuple:
    """计算系统熵状态。返回 (active_count, total_entropy, trend_str)。"""
    active = data["active"]
    total = sum(c["current_entropy"] for c in active)

    # 趋势：比较最近两项的熵增速率
    if len(active) == 0:
        trend = "stable"
    elif len(active) == 1:
        trend = "stable"
    else:
        rates = [c["entropy_rate"] for c in active]
        avg_rate = sum(rates) / len(rates)
        if avg_rate >= 7:
            trend = "increasing"
        elif avg_rate <= 3:
            trend = "decreasing"
        else:
            trend = "stable"

    trend_labels = {
        "increasing": "📈 上升（系统正在失控）",
        "decreasing": "📉 下降（系统趋于有序）",
        "stable": "➡️ 稳定",
    }

    return len(active), total, trend_labels.get(trend, trend)


def update_tracker(filepath: str, active_count: int, total_entropy: float, trend_label: str) -> bool:
    """更新 tracker 文件的系统熵状态表格。"""
    with open(filepath) as f:
        content = f.read()

    # 更新活跃承诺数
    content = re.sub(
        r"(\| 活跃承诺 \|) .* (\|)",
        rf"\1 {active_count} \2",
        content,
    )
    # 更新系统总熵
    content = re.sub(
        r"(\| 系统总熵 \|) .* (\|)",
        rf"\1 {total_entropy:.1f} \2",
        content,
    )
    # 更新熵趋势
    content = re.sub(
        r"(\| 熵趋势 \|) .* (\|)",
        rf"\1 {trend_label} \2",
        content,
    )

    with open(filepath, "w") as f:
        f.write(content)
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: entropy-check.py <tracker_file> [--update]")
        sys.exit(1)

    tracker_file = sys.argv[1]
    do_update = "--update" in sys.argv

    data = parse_tracker(tracker_file)
    count, entropy, trend = compute_entropy(data)

    if do_update:
        update_tracker(tracker_file, count, entropy, trend)

    print(f"{count} {entropy:.1f} {trend}")
