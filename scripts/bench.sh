#!/bin/bash
# TRIO 对标库检索 v1.0 — grep 级全文搜索
# 用法: bash bench.sh <关键词> [--company|--person|--industry]
set -euo pipefail
BENCH="/mnt/d/工作/对标库"
Q="${1:-}"; [ -z "$Q" ] && { echo "用法: bench.sh <关键词> [--company|--person|--industry]"; echo "示例: bench.sh 供应链 --company"; exit 1; }
TYPE="${2:-}"
DIRS="$BENCH"
[ "$TYPE" = "--company" ] && DIRS="$BENCH/company-benchmark"
[ "$TYPE" = "--person" ] && DIRS="$BENCH/person-benchmark"
[ "$TYPE" = "--industry" ] && DIRS="$BENCH/industry"
grep -rn --include="*.md" --include="*.json" "$Q" $DIRS 2>/dev/null | head -20 || echo "无匹配。试试更宽泛的关键词？"
