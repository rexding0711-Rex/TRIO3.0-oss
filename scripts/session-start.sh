#!/usr/bin/env bash
# ============================================================
# TRIO 3.0 SessionStart 统一入口
# 替代 3 个分散的 async hook → 一次串行执行
# ============================================================
set -euo pipefail

START_TIME=$(date +%s)

# ── 1. TRIO 状态加载 ──────────────────────────────────────
echo "📊 [1/3] TRIO 状态加载..."
bash "/mnt/d/TRIO 3.0/scripts/trio-state-load.sh" || echo "⚠️ 状态加载失败（非致命）"

# ── 2. 拓扑检查门禁就绪确认 ───────────────────────────────
echo "🕸️  [2/3] 拓扑检查门禁..."
TOPO_SCRIPT="/mnt/d/TRIO 3.0/scripts/topology-check.sh"
VIOLATION_LOG="/mnt/d/TRIO 3.0/state/topology-violations.log"
if [ -x "$TOPO_SCRIPT" ]; then
    echo "  ✅ topology-check.sh 就绪"
else
    echo "  ⚠️  topology-check.sh 不可执行，拓扑门禁未激活"
fi

# 检查违规日志
if [ -f "$VIOLATION_LOG" ]; then
    V_COUNT=$(grep -c '| fail |' "$VIOLATION_LOG" 2>/dev/null || echo 0)
    if [ "$V_COUNT" -gt 0 ]; then
        echo "  ⚠️  拓扑违规: ${V_COUNT} 条未处理"
    fi
fi

# ── 3. M4 训练状态检查 ────────────────────────────────────
echo "🧠 [3/3] M4 思维矫正..."
M4_LOG="/mnt/d/工作/TRIO/training/TRIO-training/training-log-2026-06-25.md"
if [ -f "$M4_LOG" ]; then
    M4_SESSIONS=$(grep -c "^# 迷你训练记录" "$M4_LOG" 2>/dev/null || echo 0)
    M4_LAST=$(grep "^> 训练日期:" "$M4_LOG" 2>/dev/null | tail -1 | sed 's/> 训练日期: //')
    echo "  ✅ M4 训练: ${M4_SESSIONS} 轮 | 最近: ${M4_LAST:-未知}"
else
    echo "  ⚠️  M4 训练日志未找到"
fi

# ── 汇总 ──────────────────────────────────────────────────
ELAPSED=$(( $(date +%s) - START_TIME ))
echo "✅ SessionStart 完成 (${ELAPSED}s)"
echo ""
echo "📌 本次会话提醒:"
echo "  · 分析型交付前 → 运行 topology-check.sh 通过门禁"
echo "  · 对标库分析后 → 追加 M4 训练日志"
