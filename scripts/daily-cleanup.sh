#!/bin/bash
# ================================================================
# TRIO 3.0 每日自动整理 v1.0
# 用途: 每天会话启动时自动清理 OS 和 D:\工作 的杂物
# 原则: 只删明确垃圾，不确定的只报告不删除
# ================================================================
set -uo pipefail

TRIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_ROOT="/mnt/d/工作"
REPORTS="$WORK_ROOT/TRIO/Reports"
ISSUES=0

echo "🧹 TRIO 每日自动整理"
echo ""

# ── OS 层：TRIO 3.0 ──
echo "  📁 TRIO 3.0"

# 1. 协议文件不能出现在 config/ 根目录（应该都在 config/protocols/）
DUPS=$(find "$TRIO_ROOT/config" -maxdepth 1 -name "*protocol*.json" 2>/dev/null | wc -l)
if [ "$DUPS" -gt 0 ]; then
    echo "    ⚠️  $DUPS 个协议文件在 config/ 根目录（应在 protocols/）"
    find "$TRIO_ROOT/config" -maxdepth 1 -name "*protocol*.json" -exec rm {} \;
    echo "    ✅ 已清理"
    ISSUES=$((ISSUES + 1))
fi

# 2. node_modules 垃圾
NODEMODULES=$(find "$TRIO_ROOT" -maxdepth 3 -name "node_modules" -type d 2>/dev/null | grep -v ".git" | wc -l)
if [ "$NODEMODULES" -gt 0 ]; then
    echo "    ⚠️  发现 $NODEMODULES 个 node_modules"
    find "$TRIO_ROOT" -maxdepth 3 -name "node_modules" -type d -exec rm -rf {} \; 2>/dev/null
    echo "    ✅ 已清理"
    ISSUES=$((ISSUES + 1))
fi

# 3. __pycache__ 垃圾
PYCACHE=$(find "$TRIO_ROOT" -name "__pycache__" -type d 2>/dev/null | wc -l)
if [ "$PYCACHE" -gt 0 ]; then
    find "$TRIO_ROOT" -name "__pycache__" -type d -exec rm -rf {} \; 2>/dev/null
    echo "    ✅ 清理 $PYCACHE 个 __pycache__"
    ISSUES=$((ISSUES + 1))
fi

# 4. 废弃脚本检查
for f in verify_loop.py export-to-pdf.sh md-to-pdf.sh; do
    if [ -f "$TRIO_ROOT/scripts/$f" ]; then
        echo "    ⚠️  废弃脚本仍存在: scripts/$f"
        rm "$TRIO_ROOT/scripts/$f"
        echo "    ✅ 已删除"
        ISSUES=$((ISSUES + 1))
    fi
done

# ── 数据层：D:\工作 ──
echo "  📁 D:\\工作"

# 5. Reports 目录下的垃圾文件
for garbage in package.json package-lock.json node_modules; do
    if [ -f "$REPORTS/$garbage" ] || [ -d "$REPORTS/$garbage" ]; then
        echo "    ⚠️  Reports 下存在: $garbage"
        rm -rf "$REPORTS/$garbage"
        echo "    ✅ 已清理"
        ISSUES=$((ISSUES + 1))
    fi
done

# 6. Reports 下的 .py 文件（应该在 TRIO 3.0 scripts）
PY_FILES=$(find "$REPORTS" -maxdepth 1 -name "*.py" 2>/dev/null | wc -l)
if [ "$PY_FILES" -gt 0 ]; then
    echo "    ⚠️  Reports 下有 $PY_FILES 个 .py 文件"
    for f in $(find "$REPORTS" -maxdepth 1 -name "*.py"); do
        mv "$f" "$TRIO_ROOT/scripts/" 2>/dev/null && echo "    ✅ $(basename $f) → scripts"
    done
    ISSUES=$((ISSUES + 1))
fi

# ── 汇总 ──
echo ""
if [ "$ISSUES" -eq 0 ]; then
    echo "  ✅ OS 和 D:\\工作 均干净，无需整理"
else
    echo "  ✅ 修复了 $ISSUES 项问题"
fi
