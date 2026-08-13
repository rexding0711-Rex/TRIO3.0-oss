#!/bin/bash
# ============================================================
# 统一交付门禁（外部评测 H6 修复）
# 交付前强制跑：拓扑检查 + CJK 字体 + 报告存在性
# 用法: bash scripts/delivery-gate.sh <报告.md> [领域]
# 接入: /all 交付前 / 终版报告生成后
# ============================================================
set -uo pipefail

TRIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TRIO_ROOT"
REPORT="${1:-}"
DOMAIN="${2:-general}"
FAIL=0
pass(){ echo "  ✅ $1"; }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
warn(){ echo "  ⚠️ $1"; }

[ -n "$REPORT" ] || { echo "用法: delivery-gate.sh <报告.md> [领域]"; exit 1; }

echo "═══ 交付门禁: $REPORT (领域: $DOMAIN) ═══"

# 1. 报告存在性
if [ -f "$REPORT" ]; then
  pass "报告文件存在"
else
  fail "报告文件不存在: $REPORT"; echo "❌ 阻断——报告缺失"; exit 1
fi

# 2. 拓扑检查（分析型交付门禁）
if bash scripts/topology-check.sh "$REPORT" "$DOMAIN" >/dev/null 2>&1; then
  pass "拓扑检查通过"
else
  fail "拓扑检查失败（见 topology-check.sh 详细输出）"
fi

# 3. CJK 字体检查（仅 PDF/HTML 交付适用）
if [[ "$REPORT" == *.pdf || "$REPORT" == *.html ]]; then
  if python3 scripts/check-cjk-fonts.py --strict "$REPORT" >/dev/null 2>&1; then
    pass "CJK 字体检查通过"
  else
    fail "CJK 字体检查失败"
  fi
else
  pass "CJK 检查跳过（非 PDF/HTML）"
fi

# 4. 门禁 A 痕迹扫描（AI 痕迹清除）
TRACE=$(grep -cE '审计|修正|v[0-9]|漏了|感谢|对比|TBD|仅供参考' "$REPORT" 2>/dev/null || true)
TRACE=${TRACE:-0}
if [ "$TRACE" -eq 0 ]; then
  pass "AI 痕迹扫描通过"
else
  fail "AI 痕迹 $TRACE 处（审计/修正/v数字 等）"
fi

# 4b. 变更叙事提示（dsh 吸收：dsh-trim-cot-leakage 中文电池，WARN 提示不阻断）
# 检测"作者会话视角"残留（上一轮/旧版/本版/不再/以前/老的），命中需人工判断清除。
# 误杀面说明：`不再/以前` 有正常用法（"不再需要人工""此前的分析"），故只提示不阻断。
TRACE2=$(grep -cE '上一轮|旧版|本版|不再|以前|老的' "$REPORT" 2>/dev/null || true)
TRACE2=${TRACE2:-0}
if [ "$TRACE2" -eq 0 ]; then
  pass "变更叙事提示通过"
else
  warn "变更叙事 $TRACE2 处（上一轮/旧版/本版/不再/以前/老的——需人工判断是否清除）"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "✅ 交付门禁全部通过——可交付"
  exit 0
else
  echo "❌ 交付门禁 $FAIL 项失败——阻断交付，修复后重跑"
  exit 1
fi
