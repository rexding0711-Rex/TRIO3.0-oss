#!/usr/bin/env bash
# ============================================================
# trio-engine.sh — TRIO 分析型统一入口（阶段一收尾）
# 让 /all 和 AI 在正式分析时，自动完成三件事：
#   ① 定位资产（asset-locate.sh）
#   ② 自动落库（trio-record.sh）
#   ③ 输出引擎建议（engine-manifest.md）
# 用法: trio-engine.sh "<任务描述>" --type <尽调|竞品|逆向|复盘|决策|...> [--score N]
# ============================================================
set -euo pipefail

# 中文 grep 稳定（避免 Invalid collation character）
export LC_ALL=C.UTF-8 LANG=C.UTF-8

ROOT="/mnt/d/TRIO 3.0"
TASK="${1:-}"
TYPE="分析"
SCORE=""

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) TYPE="$2"; shift 2;;
    --score) SCORE="$2"; shift 2;;
    *) if [ -z "$TASK" ]; then TASK="$1"; fi; shift;;
  esac
done

if [ -z "$TASK" ]; then
  echo "❌ 用法: trio-engine.sh '<任务描述>' [--type 类型] [--score N]"
  echo "   例: trio-engine.sh '分析蔚星科技竞争力' --type 竞品 --score 8"
  exit 1
fi

echo "⚙️  TRIO Engine 启动"
echo "──────────────────────────────"
echo "📋 任务: $TASK"
echo "🏷️  类型: $TYPE"
echo

# ── ① 定位资产（辅助，不阻塞） ──
# 定位由 AI 手动调 asset-locate.sh <准确关键词> 完成（bash 中文字符切分不可靠，不强求自动化）
echo "🔍 [1/3] 定位资产..."
echo "  → 建议运行: bash scripts/asset-locate.sh <项目/公司名>"
echo "  → 例: bash scripts/asset-locate.sh 蔚星"

# ── ② 自动落库 ──
echo "📝 [2/3] 自动落库..."
bash "$ROOT/scripts/trio-record.sh" --run "$TYPE: $TASK" --score "$SCORE" --note "$TASK" 2>/dev/null

# ── ③ 引擎建议 ──
echo "🧠 [3/3] 引擎建议（查 engine-manifest）..."
grep -A3 "$TYPE" "$ROOT/docs/engine-manifest.md" 2>/dev/null | head -6 || echo "  （engine-manifest 中无该类型专项，走通用引擎）"
echo
echo "✅ Engine 就绪 — 建议按 /all 管道继续：P0→C0→Step0→O0→三视角→综合"
