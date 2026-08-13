
# @data-depends: metrics.md 表格格式 | 列名 | 值 | 目标 |
# @data-depends: DAILY.md 度量表格式同上
# @炸点: 两处任意列名重命名 → sync静默失败 → 数字不对齐

#!/usr/bin/env python3
"""按列名更新 Markdown 表格——替代 sed 正则硬匹配"""
import sys, re

def update_table(filepath, updates):
    """updates = {'列名': '新值', ...}"""
    with open(filepath) as f:
        content = f.read()
    
    for col_name, new_val in updates.items():
        # 匹配 | 列名 | 原值 | ... 格式
        content = re.sub(
            rf'(\|\s*{re.escape(col_name)}\s*\|)\s*\S+\s*(\|)',
            rf'\1 {new_val} \2',
            content
        )
    
    # 更新时间戳
    from datetime import datetime
    ts = datetime.now().strftime('%Y-%m-%d %H:%M')
    content = re.sub(r'^> 最后更新:.*', f'> 最后更新: {ts} | 自动同步', content, flags=re.M)
    
    with open(filepath, 'w') as f:
        f.write(content)
    return True

def update_daily(filepath, updates):
    """更新 DAILY.md —— 使用 key: value 格式（非管道表）。

    DAILY.md 格式示例:
        公司库: 78/100 (78%)    里程碑: ...
        📊 本周 run: 1 个 | 累计: 15 个

    与 metrics.md 的 | 列名 | 值 | 管道表格式不同。
    """
    with open(filepath) as f:
        content = f.read()

    applied = 0
    for col_name, new_val in updates.items():
        if col_name == '公司库':
            try:
                val_int = int(new_val)
                new_text = f'公司库: {val_int}/100 ({val_int}%)'
                if re.search(r'公司库: \d+/\d+ \(\d+%\)', content):
                    content = re.sub(
                        r'公司库: \d+/\d+ \(\d+%\)',
                        new_text,
                        content
                    )
                    applied += 1
            except ValueError:
                pass
        # run数：DAILY.md 中有"本周 run"和"累计 run"两个语义，
        # 无法从单一 run 目录计数推断。由 /日进化 手动维护。
        # 其他未知 key 静默跳过——不报错也不修改。

    # 更新时间戳
    from datetime import datetime
    ts = datetime.now().strftime('%Y-%m-%d %H:%M')
    content = re.sub(
        r'> 最后刷新:.*',
        f'> 最后刷新: {ts} | 自动同步',
        content
    )

    with open(filepath, 'w') as f:
        f.write(content)

    # 返回实际应用的更新数（调用方可判断是否生效）
    return applied

if __name__ == '__main__':
    cmd = sys.argv[1]
    filepath = sys.argv[2]
    updates = dict(arg.split('=') for arg in sys.argv[3:])

    if cmd == 'metrics':
        update_table(filepath, updates)
        print(f'✅ {filepath} 已更新 ({len(updates)} 项)')
    elif cmd == 'daily':
        n = update_daily(filepath, updates)
        if n < len(updates):
            skipped = len(updates) - n
            print(f'✅ {filepath} 已更新 ({n}/{len(updates)} 项, {skipped} 项跳过——DAILY.md 非管道表格式)')
        else:
            print(f'✅ {filepath} 已更新 ({n} 项)')
