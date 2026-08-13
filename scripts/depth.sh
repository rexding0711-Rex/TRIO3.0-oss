#!/bin/bash
# @layer: infra
# ============================================================
# depth 子模块 — 认知负载评估 & 输出深度控制
# 依赖: lib/common.sh（提供 $TRIO_ROOT、颜色常量、today()）
# 被 mgmt.sh source，不独立执行
# ============================================================

cmd_depth() {
    local load=0

    # 认知负载因子1: Kimi 未读产出（从知识库路径读取，无则跳过）
    local kimi_unread=0
    local kimi_dir="${TRIO_KB_DIR:-/mnt/d/工作/对标库}/knowledge-benchmark/Kimi蒸馏产出"
    if [ -d "$kimi_dir" ]; then
        # wc -l 输出含前导空格，用 xargs 自动 trim（比 ${var// /} 更安全）
        kimi_unread=$(find "$kimi_dir" -name "*.md" -newer "$TRIO_ROOT/DAILY.md" 2>/dev/null | wc -l | xargs)
        kimi_unread=${kimi_unread:-0}
    fi

    # 认知负载因子2: 今日run数
    # @data-depends: behavior-log.jsonl 格式({"ts":...,"event":...,"note":...})
    # @炸点: 字段改名 → depth计算runs_today=0 → 永远不触发降级
    local runs_today=0
    local behavior_log="$TRIO_ROOT/state/behavior-log.jsonl"
    if [ -f "$behavior_log" ]; then
        # grep -c 无匹配时: 输出"0" + exit 1 → || true 只吞 exit code, 不加额外输出
        runs_today=$(grep -c "$(today)" "$behavior_log" 2>/dev/null || true)
        runs_today=${runs_today:-0}
    fi

    # 确保都是数字（防御性）
    kimi_unread=$((kimi_unread + 0))
    runs_today=$((runs_today + 0))
    load=$((kimi_unread + runs_today))

    if [ "$load" -gt 5 ]; then
        echo "📊 Level 1 — 认知负载高($load)。只出核心结论。"
        echo "1" > "$TRIO_ROOT/state/depth-level.txt"
    elif [ "$load" -gt 2 ]; then
        echo "📊 Level 2 — 标准输出。"
        echo "2" > "$TRIO_ROOT/state/depth-level.txt"
    else
        echo "📊 Level 2 — 标准输出（负载低，可深入）。"
        echo "2" > "$TRIO_ROOT/state/depth-level.txt"
    fi

    # 协议v1.1: 防抖动——记录切换历史
    echo "$(date +%s):$load" >> "$TRIO_ROOT/state/depth-history.txt" 2>/dev/null

    # 🔧 修复: 用 if 替代 && 避免 set -e 下 ERR trap 误触发
    #    原代码 [ "$recent" -ge 3 ] && { ... } 当 recent<3 时 [ 返回 1，
    #    被 trap ERR 捕获为"错误"，写入 state/errors.log (code=1)
    local recent
    recent=$(tail -3 "$TRIO_ROOT/state/depth-history.txt" 2>/dev/null | wc -l | xargs)
    recent=${recent:-0}
    if [ "$recent" -ge 3 ]; then
        echo "  ⚠️ 频繁切换→锁定当前Level 30分钟"
        touch "$TRIO_ROOT/state/depth-lock"
    fi
}
