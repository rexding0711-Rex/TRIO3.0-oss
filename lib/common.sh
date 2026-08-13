#!/bin/bash
# @layer: infra
# TRIO 3.0 共享库 — 所有子脚本的共同依赖
# 被 mgmt.sh source，不独立执行

# ============================================================
# 路径（依赖 mgmt.sh 已设置 TRIO_ROOT + TRIO_DB）
# ============================================================
ERROR_LOG="$TRIO_ROOT/state/errors.log"
mkdir -p "$(dirname "$ERROR_LOG")"

# kb-refresh 数据文件
CONFIG_DIR="$TRIO_ROOT/config/kb-refresh"
TOPICS_FILE="$CONFIG_DIR/topics.tsv"
HISTORY_FILE="$CONFIG_DIR/history.log"

# 确保必要目录存在
mkdir -p "$TRIO_ROOT/state" "$CONFIG_DIR"

# ============================================================
# 颜色
# ============================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ============================================================
# 错误处理
# ============================================================
cmd_error() {
    local source="$1" code="$2" cmd="$3" func="$4"
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $source | code=$code | $func | $cmd"
    echo "$msg" >> "$ERROR_LOG"
    echo "❌ $func 失败 (code=$code) → 详见 state/errors.log" >&2
}

guard_error() {
    echo "⛔ 禁区违规——TRIO 操作系统被污染。立即清理后再继续。" >&2
    echo "  规则: 项目文件 → ${TRIO_DB:-请先配置 paths.conf}/项目/{项目名}/" >&2
    echo "  违规文件已写入 state/errors.log" >&2
}

# 全局错误 trap（只在 mgmt.sh 设置一次，子脚本不重复设置）
# mgmt.sh 在 source 本文件后设置 trap

# ============================================================
# 日期工具
# ============================================================
today() { date '+%Y-%m-%d'; }

days_since() {
    local d="$1"
    local d_sec=$(date -d "$d" '+%s' 2>/dev/null || echo 0)
    local t_sec=$(date '+%s')
    echo $(( (t_sec - d_sec) / 86400 ))
}

is_overdue() {
    local last_refreshed="$1" interval_days="$2"
    local elapsed; elapsed=$(days_since "$last_refreshed")
    [ "$elapsed" -ge "$interval_days" ]
}

log_history() {
    local id="$1" action="$2" result="$3"
    echo "$(date '+%Y-%m-%d %H:%M')	$id	$action	$result" >> "$HISTORY_FILE"
}
