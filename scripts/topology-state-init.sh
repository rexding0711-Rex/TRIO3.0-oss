#!/usr/bin/env bash
# ============================================================
# @layer: quality-control
# 拓扑状态追踪 — 初始化 run 的 topology-state.json
# 用法: bash topology-state-init.sh <run_id>
# 在分析 run 启动时调用，创建空白状态文件
# ============================================================
set -eu

RUN_ID="${1:-}"
TRIO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$RUN_ID" ]; then
    echo "用法: bash topology-state-init.sh <run_id>"
    echo "  run_id 格式: 项目名-YYYYMMDD"
    echo "  示例: bash topology-state-init.sh 追觅科技-20260702"
    exit 2
fi

STATE_DIR="$TRIO_ROOT/runs/$RUN_ID"
STATE_FILE="$STATE_DIR/topology-state.json"

mkdir -p "$STATE_DIR"

if [ -f "$STATE_FILE" ]; then
    echo "⚠️  $STATE_FILE 已存在，跳过初始化"
    exit 0
fi

TIMESTAMP=$(TZ=Asia/Shanghai date -Iseconds)

cat > "$STATE_FILE" << EOF
{
  "run_id": "$RUN_ID",
  "created": "$TIMESTAMP",
  "phase": "phase_0_seed",
  "nodes": [],
  "edges": [],
  "unknown_nodes": [],
  "dashed_edges": [],
  "insights": [],
  "reflections": {},
  "counter_evidence_coverage": 0
}
EOF

echo "✅ 拓扑状态文件已创建: $STATE_FILE"
echo "   5 阶段追踪: seed → expand → perturb → temporalize → harden"
echo "   反脑补: ???节点 + 虚线边 + 反证覆盖率 已初始化"
