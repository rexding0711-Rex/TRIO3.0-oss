#!/bin/bash
# @layer: infra
# TRIO 3.0 时间戳同步脚本 v1.0
# 用途: 将所有元时间戳字段对齐到系统当前时间，禁止手写
# 调用: SessionStart hook / mgmt.sh time-sync / 手动

set -euo pipefail

NOW=$(TZ=Asia/Shanghai date '+%Y-%m-%dT%H:%M:%S+08:00')
TRIO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 需要同步的文件和字段
# 格式: "文件路径|jq路径|字段名"
# jq路径: jq 可写的过滤表达式

sync_timestamp() {
    local file="$1"
    local jq_filter="$2"
    local field_name="$3"

    if [ ! -f "$file" ]; then
        echo "⚠️  跳过(不存在): $file"
        return 1
    fi

    # 用 jq 原地更新（临时文件方案，兼容性好）
    local tmp="${file}.tmp.$$"
    if jq "$jq_filter = \"$NOW\"" "$file" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$file"
        echo "✅ $field_name → $NOW  ($(basename "$file"))"
    else
        rm -f "$tmp"
        echo "❌ jq 失败: $file ($field_name)"
        return 1
    fi
}

# 可选: 只检查不修改
if [ "${1:-}" = "--check" ]; then
    echo "🔍 时间戳对齐检查 — $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M')"
    fails=0
    for target in \
        "$TRIO_ROOT/state.json|._updated|state.json::_updated" \
        "$TRIO_ROOT/config/projects.json|.last_updated|projects.json::last_updated"; do
        IFS='|' read -r file jq_filter label <<< "$target"
        current=$(jq -r "$jq_filter" "$file" 2>/dev/null || echo "ERROR")
        echo "  $label = $current"
    done
    echo ""
    echo "  系统时间 = $NOW"
    exit 0
fi

echo "🕐 TRIO 时间同步 — $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M')"
echo ""

# 核心元时间戳
sync_timestamp "$TRIO_ROOT/state.json"              "._updated"           "state.json::_updated"
sync_timestamp "$TRIO_ROOT/config/projects.json"    ".last_updated"       "projects.json::last_updated"

echo ""
echo "✅ 时间同步完成 — $NOW"
