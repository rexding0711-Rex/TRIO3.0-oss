#!/bin/bash
# @layer: infra
# ============================================================
# daily-fill 子模块 — 自动填充 DAILY.md 每日自问
# 依赖: lib/common.sh（提供 $TRIO_ROOT、today()）
# 被 mgmt.sh source，不独立执行
# @data-depends: DAILY.md 占位符("→ ___ 家","→ ___ 个","→ ___")
# @炸点: 占位符格式改变 → sed替换失败 → 每日自问永远空白
# ============================================================

cmd_daily_fill() {
    local daily="$TRIO_ROOT/DAILY.md"
    local today=$(date +%Y-%m-%d)

    # 1. 逆向了几家 → runs/ 目录中属于今日的 run
    local reverse_count=0
    [ -d "$TRIO_ROOT/runs" ] && reverse_count=$(find "$TRIO_ROOT/runs" -maxdepth 1 -newer "$daily" -type d 2>/dev/null | wc -l | xargs)
    reverse_count=${reverse_count:-0}

    # 2. 跑了几个真实项目 → D:\工作\项目\ 各项目 runs/ 新增
    local project_count=0
    for pr in /mnt/d/工作/项目/*/runs/; do
        [ -d "$pr" ] && project_count=$((project_count + $(find "$pr" -maxdepth 1 -newer "$daily" -type d 2>/dev/null | wc -l | xargs)))
    done
    project_count=${project_count:-0}

    # 3. TRIO比昨天强在哪 → 从 behavior-log 提取今日事件
    local stronger=$(tail -3 "$TRIO_ROOT/state/behavior-log.jsonl" 2>/dev/null | python3 -c "
import json, sys
events = []
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        if d.get('ts','')[:10] == '$today':
            events.append(d.get('event',''))
    except: pass
print(' + '.join(events[:3]) if events else '系统架构持续完善')
" 2>/dev/null)

    # 写入 DAILY.md
    sed -i "s/→ ___ 家/→ ${reverse_count} 家/" "$daily"
    sed -i "s/→ ___ 个/→ ${project_count} 个/" "$daily"
    sed -i "s/→ ___/→ ${stronger:-系统架构持续完善}/" "$daily"
    echo "📝 DAILY自问已填充: 逆向${reverse_count}家 项目${project_count}个 进步:${stronger:-持续完善}"
}
