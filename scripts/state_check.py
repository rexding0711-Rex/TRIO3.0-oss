#!/usr/bin/env python3
"""状态转移校验——检查run的step完整性和顺序。

用法:
    python3 state_check.py <run目录>       # 检查单个run
    python3 state_check.py --all <runs父目录>  # 扫描所有run
"""
import json
import sys
import os
import re
import glob

USAGE = "用法: state_check.py <run目录> | state_check.py --all <runs父目录>"


def check_run(run_dir: str) -> list[str]:
    """检查单个run目录，返回错误列表。"""
    errors: list[str] = []
    run_name = os.path.basename(run_dir.rstrip("/"))

    state_file = os.path.join(run_dir, "state.json")
    if not os.path.exists(state_file):
        return [f"🔴 [{run_name}] state.json不存在"]

    try:
        with open(state_file, encoding="utf-8") as f:
            state = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        return [f"🔴 [{run_name}] state.json 解析失败: {e}"]

    steps = state.get("steps", {})
    step_keys = [k for k in steps if k.startswith("step")]
    step_nums = []
    for k in step_keys:
        m = re.match(r"step(\d+)", k)
        if m:
            step_nums.append(int(m.group(1)))
    step_nums = sorted(set(step_nums))

    # 1. 步骤连续性
    if step_nums:
        for i in range(min(step_nums), max(step_nums) + 1):
            if i not in step_nums:
                errors.append(f"🔴 [{run_name}] 缺失step{i}——可能存在跳步")

    # 2. completed步骤必须有对应文件
    for k, v in steps.items():
        if v == "completed" and k.startswith("step"):
            exact = os.path.join(run_dir, f"{k}.md")
            found = os.path.exists(exact)
            if not found:
                matches = glob.glob(os.path.join(run_dir, f"{k}*.md"))
                found = len(matches) > 0
            if not found:
                errors.append(f"🔴 [{run_name}] {k}标记completed但文件不存在")

    # 3. step_index合理性
    idx = state.get("step_index", 1)
    total = state.get("total_steps", len(steps))
    if idx > total:
        errors.append(f"🟡 [{run_name}] step_index={idx} > total_steps={total}")

    return errors


def main() -> None:
    if len(sys.argv) < 2:
        print(f"❌ 缺少参数\n{USAGE}")
        sys.exit(1)

    if sys.argv[1] == "--all":
        if len(sys.argv) < 3:
            print(f"❌ --all 需要指定 runs 父目录\n{USAGE}")
            sys.exit(1)
        parent_dir = sys.argv[2]
        if not os.path.isdir(parent_dir):
            print(f"❌ 目录不存在: {parent_dir}")
            sys.exit(1)

        # 扫描所有子目录
        subdirs = sorted([
            os.path.join(parent_dir, d)
            for d in os.listdir(parent_dir)
            if os.path.isdir(os.path.join(parent_dir, d))
        ])
        if not subdirs:
            print(f"⚪ {parent_dir} 下无run目录")
            sys.exit(0)

        all_errors: list[str] = []
        ok_count = 0
        for subdir in subdirs:
            errs = check_run(subdir)
            if errs:
                all_errors.extend(errs)
            else:
                ok_count += 1

        print(f"📊 扫描 {len(subdirs)} 个run: {ok_count} OK, {len(all_errors)} 个问题")
        for e in all_errors:
            print(f"  {e}")
        if all_errors:
            sys.exit(1)
    else:
        run_dir = sys.argv[1]
        if not os.path.isdir(run_dir):
            print(f"❌ 目录不存在: {run_dir}")
            sys.exit(1)

        errors = check_run(run_dir)
        if errors:
            print(f"❌ {len(errors)}个问题:")
            for e in errors:
                print(f"  {e}")
            sys.exit(1)
        else:
            # 重新读取state获取统计信息
            try:
                with open(os.path.join(run_dir, "state.json"), encoding="utf-8") as f:
                    state = json.load(f)
            except (json.JSONDecodeError, OSError):
                state = {}
            steps = state.get("steps", {})
            step_keys = [k for k in steps if k.startswith("step")]
            step_nums = sorted(set(
                int(m.group(1)) for k in step_keys
                if (m := re.match(r"step(\d+)", k))
            ))
            idx = state.get("step_index", 1)
            total = state.get("total_steps", len(steps))
            print(f"✅ {len(step_nums)}步连续, step_index={idx}/{total}")


if __name__ == "__main__":
    main()
