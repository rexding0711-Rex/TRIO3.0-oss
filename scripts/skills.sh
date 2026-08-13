#!/bin/bash
# @layer: infra
# ============================================================
# TRIO 3.0 管理脚本 — mgmt.sh v3.1
# ============================================================
# 新增: sync — 自动从文件系统同步所有数据到 metrics/INDEX/llms/DAILY
# ============================================================

set -euo pipefail

# ============================================================
# 显式错误处理（§6.2）
# ============================================================
TRIO_ROOT="${TRIO_ROOT:-$(dirname "$(readlink -f "$0")")}"
ERROR_LOG="$TRIO_ROOT/state/errors.log"
mkdir -p "$(dirname "$ERROR_LOG")"
trap 'cmd_error "TRAP" "$?" "${BASH_COMMAND:-unknown}" "${FUNCNAME:-main}"' ERR

cmd_error() {
    local source="$1" code="$2" cmd="$3" func="$4"
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $source | code=$code | $func | $cmd"
    echo "$msg" >> "$ERROR_LOG"
    echo "❌ $func 失败 (code=$code) → 详见 state/errors.log" >&2
}

guard_error() {
    echo "⛔ 禁区违规——TRIO 操作系统被污染。立即清理后再继续。" >&2
    echo "  规则: 项目文件 → D:\\工作\\项目\\{项目名}\\" >&2
    echo "  违规文件已写入 state/errors.log" >&2
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIO_ROOT="$SCRIPT_DIR"
CONFIG_DIR="$TRIO_ROOT/config/kb-refresh"
# @data-depends: topics.tsv TSV格式(7列: id path category last_refreshed interval_days priority description)
# @炸点: 列顺序改变或分隔符改变 → kb-refresh全部子命令失效
TOPICS_FILE="$CONFIG_DIR/topics.tsv"
HISTORY_FILE="$CONFIG_DIR/history.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

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

# ============================================================
# SYNC — 自动同步所有数据文件
# ============================================================

cmd_state_check() {
    local run_dir="${1:-}"
    [ -z "$run_dir" ] && { echo "用法: mgmt.sh state-check <run_dir>"; return 1; }
    python3 "$TRIO_ROOT/scripts/state_check.py" "$run_dir"
    return $?
}

cmd_skill_extract() {
    local run_id="${1:-}"
    local scenario="${2:-deconstruct}"
    local skills_dir="$TRIO_ROOT/knowledge/skills"
    local template="$skills_dir/.template.md"
    
    [ -z "$run_id" ] && { echo "用法: mgmt.sh skill-extract <run_id> [scenario]"; return 1; }
    # 协议v1.1: 技能提取失败不阻塞主流程
    [ ! -f "$template" ] && { echo "⚠️ 模板缺失——技能提取跳过（不阻塞run完成）"; return 0; }
    
    echo "📝 技能提取 — $run_id ($scenario)"

# MAIN
# ============================================================

case "${1:-help}" in
    sync) cmd_sync ;;
    post-session) cmd_post_session ;;
    kb-refresh)
        case "${2:-help}" in
            next)   cmd_kb_refresh_next ;;
            done)   cmd_kb_refresh_done "${3:-}" ;;
            list)   cmd_kb_refresh_list "${3:-all}" ;;
            reset)  cmd_kb_refresh_reset ;;
            add)    cmd_kb_refresh_add "${3:-}" "${4:-}" "${5:-}" "${6:-}" ;;
            skip)   cmd_kb_refresh_skip "${3:-}" ;;
            help|*) cmd_kb_refresh_help ;;
        esac
        ;;
    layer-check) cmd_layer_check ;;
    guard) cmd_guard ;;
    depth) cmd_depth ;;
    behavior) cmd_behavior "${2:-}" "${3:-}" ;;
    behavior-auto) cmd_behavior_auto ;;
    behavior-report) cmd_behavior_report ;;
    daily-fill) cmd_daily_fill ;;
    skill-extract) cmd_skill_extract "${2:-}" "${3:-}" ;;
    state-check) cmd_state_check "${2:-}" ;;
    backup) cmd_backup ;;
    help|*)
        echo "TRIO 3.0 管理脚本 v3.2"
        echo "  sync            从文件系统同步所有数据文件"
        echo "  post-session    会话后处理（含自动同步）"
        echo "  kb-refresh      知识刷新调度器"
        echo "  layer-check     校验层依赖方向"
        echo "  guard           扫描TRIO禁区——禁止项目文件污染"
        echo "  depth           认知负载检测→优雅降级"
        echo "  behavior[-auto|-report]  行为追踪"
        echo "  daily-fill      自动填充DAILY自问"
        echo "  skill-extract   从run提取技能→写入skills/"
        ;;
esac

# ============================================================
# 层依赖校验
# ============================================================
cmd_layer_check() {
    local layers_json="$TRIO_ROOT/config/layers.json"
    local violations=0

    echo "🔍 层依赖校验 — $(date '+%Y-%m-%d %H:%M')"
    echo ""

    # 规则：检查进化层文件是否引用了知识层内部字段（同层互拷）
    echo "  [1] 进化层 ←→ 知识层 同层互拷检查..."
    if grep -q "metrics" "$TRIO_ROOT/DAILY.md" 2>/dev/null; then
        echo "    ⚠️ DAILY.md(进化层) 引用 metrics.md(进化层同层) — 应通过mgmt.sh"
        violations=$((violations + 1))
    fi

    # 规则：知识层不能引用进化层
    echo "  [2] 知识层 → 进化层 反向依赖检查..."
    local rev_deps=$(grep -rl "DAILY.md\|metrics.md\|ADR-" "$TRIO_ROOT/knowledge/" "$TRIO_ROOT/docs/" 2>/dev/null | grep -v ".jsonl" | head -5)
    if [ -n "$rev_deps" ]; then
        echo "    ⚠️ 知识层文件引用了进化层:"
        echo "$rev_deps" | while read f; do echo "      $f"; done
        violations=$((violations + 1))
    fi

    # 规则：所有新文件必须有 @layer 标签
    echo "  [3] 未标记层归属的文件..."
    local untagged=$(find "$TRIO_ROOT" -name "*.md" -path "*/knowledge/*" -o -name "*.md" -path "*/docs/*" 2>/dev/null | while read f; do
        head -1 "$f" 2>/dev/null | grep -q "@layer:" || echo "      $f"
    done | head -5)
    if [ -n "$untagged" ]; then
        echo "    ⚠️ knowledge/docs 中有文件未标记层:"
        echo "$untagged"
        violations=$((violations + 1))
    fi

    echo ""
    if [ "$violations" -eq 0 ]; then
        echo "  ✅ 层依赖全部合规"
    else
        echo "  🔴 $violations 项违规——修复后才能继续"
    fi
}

    echo "  模板: $template"
    echo "  输出: $skills_dir/${scenario}-*.md"
    echo "  ✅ 技能提取就绪 — 由场景Step 10自动调用"
}

