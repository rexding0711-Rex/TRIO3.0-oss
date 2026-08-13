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

cmd_kb_refresh_help() {
    cat << 'EOF'
╔══════════════════════════════════════════════════╗
║        TRIO 3.0 知识刷新调度器                   ║
╚══════════════════════════════════════════════════╝

用法: mgmt.sh kb-refresh <子命令> [参数]

子命令:
  next              获取下一个待刷新主题
  done <id>         标记主题刷新完成
  list [filter]     列出所有主题及状态
  reset             检查过期主题
  add <path> <int> <pri> <desc>  添加新主题
  skip <id>         跳过本次刷新
  help              显示此帮助
EOF
}

cmd_kb_refresh_list() {
    local filter="${1:-all}"
    local now; now=$(today)
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "  知识刷新注册表 — $now"
    echo "══════════════════════════════════════════════════════════════════"
    printf "  %-4s %-26s %-10s %6s  %-14s  %s\n" "优先级" "ID" "类别" "间隔天" "上次刷新" "标题"
    echo "  ──────────────────────────────────────────────────────────────────"
    local total=0 overdue=0
    while IFS=$'\t' read -r id path category last_refreshed interval_days priority description; do
        [[ "$id" =~ ^# ]] && continue
        [[ -z "$id" ]] && continue
        local elapsed; elapsed=$(days_since "$last_refreshed")
        local remaining=$(( interval_days - elapsed ))
        local status_icon="🟢"
        if [ "$remaining" -le 0 ]; then
            status_icon="🔴"; (( ++overdue ))
        elif [ "$remaining" -le 7 ]; then
            status_icon="🟡"
        fi
        if [ "$filter" = "overdue" ] && [ "$remaining" -gt 0 ]; then continue; fi
        printf "  %-3s  %-26s %-10s %5s天  %-14s  %s\n" "$status_icon" "$id" "$category" "$interval_days" "$last_refreshed" "$description"
        (( ++total ))
    done < "$TOPICS_FILE"
    echo "  ──────────────────────────────────────────────────────────────────"
    echo "  共 $total 个主题 | 🔴 过期: $overdue | 🟡 即将过期 | 🟢 正常"
    echo ""
}

cmd_kb_refresh_next() {
    local best_id="" best_path="" best_category="" best_last="" best_interval=""
    local best_priority=0 best_score=-9999 best_desc=""
    while IFS=$'\t' read -r id path category last_refreshed interval_days priority description; do
        [[ "$id" =~ ^# ]] && continue; [[ -z "$id" ]] && continue
        local elapsed; elapsed=$(days_since "$last_refreshed")
        local remaining=$(( interval_days - elapsed ))
        local score=$(( priority * 10 - remaining * 2 ))
        [ "$remaining" -le 0 ] && score=$(( score + 1000 ))
        if [ "$score" -gt "$best_score" ]; then
            best_score=$score; best_id="$id"; best_path="$path"; best_category="$category"
            best_last="$last_refreshed"; best_interval="$interval_days"; best_priority="$priority"; best_desc="$description"
        fi
    done < "$TOPICS_FILE"
    if [ -z "$best_id" ]; then
        echo "✅ 所有主题均为最新，无需刷新。"
        return 0
    fi
    local elapsed; elapsed=$(days_since "$best_last")
    local remaining=$(( best_interval - elapsed ))
    if [ "$remaining" -gt 7 ]; then
        echo "✅ 全部最新。下一个过期: $(date -d "$best_last + $best_interval days" '+%Y-%m-%d')"
        return 0
    fi
    cat << INSTRUCTIONS
╔══════════════════════════════════════════════════════════════╗
║  📋 知识刷新任务                                             ║
╚══════════════════════════════════════════════════════════════╝
【主题 ID】   $best_id
【标题】      $best_desc
【目标文件】  $TRIO_ROOT/$best_path
【上次刷新】  $best_last（${elapsed} 天前）
【剩余天数】  ${remaining} 天（$( if [ "$remaining" -le 0 ]; then echo "🔴 已过期"; else echo "🟡 即将过期"; fi)）
INSTRUCTIONS
    log_history "$best_id" "next" "任务已分发，剩余${remaining}天"
}

cmd_kb_refresh_done() {
    local target_id="${1:-}"
    if [ -z "$target_id" ]; then echo -e "${RED}错误: 需要指定主题 ID${NC}"; return 1; fi
    local now=$(today); local found=false; local tmpfile=$(mktemp)
    while IFS=$'\t' read -r id path category last_refreshed interval_days priority description; do
        if [[ "$id" =~ ^# ]] || [[ -z "$id" ]]; then
            echo "$id"$'\t'"$path"$'\t'"$category"$'\t'"$last_refreshed"$'\t'"$interval_days"$'\t'"$priority"$'\t'"$description" >> "$tmpfile"
            continue
        fi
        if [ "$id" = "$target_id" ]; then
            echo "$id"$'\t'"$path"$'\t'"$category"$'\t'"$now"$'\t'"$interval_days"$'\t'"$priority"$'\t'"$description" >> "$tmpfile"
            echo -e "${GREEN}✅ 已标记完成: $target_id${NC}（下次: $(date -d "$now + $interval_days days" '+%Y-%m-%d')）"
            log_history "$target_id" "done" "刷新完成"
            found=true
        else
            echo "$id"$'\t'"$path"$'\t'"$category"$'\t'"$last_refreshed"$'\t'"$interval_days"$'\t'"$priority"$'\t'"$description" >> "$tmpfile"
        fi
    done < "$TOPICS_FILE"
    if [ "$found" = false ]; then echo -e "${RED}错误: 未找到主题 '$target_id'${NC}"; rm "$tmpfile"; return 1; fi
    mv "$tmpfile" "$TOPICS_FILE"
}

cmd_kb_refresh_reset() {
    local now=$(today); local reset_count=0; local warn_count=0
    local expired_json=""; local warning_json=""
    echo "正在扫描过期主题..."
    while IFS=$'\t' read -r id path category last_refreshed interval_days priority description; do
        [[ "$id" =~ ^# ]] && continue; [[ -z "$id" ]] && continue
        local elapsed; elapsed=$(days_since "$last_refreshed")
        if [ "$elapsed" -ge "$interval_days" ]; then
            printf "  🔴 %-26s 上次 %s（%3d 天前，间隔 %d 天）\n" "$id" "$last_refreshed" "$elapsed" "$interval_days"
            expired_json="${expired_json}{\"id\":\"$id\",\"elapsed\":$elapsed},"
            (( ++reset_count ))
        elif [ "$(( elapsed * 2 ))" -ge "$interval_days" ]; then
            warning_json="${warning_json}{\"id\":\"$id\",\"elapsed\":$elapsed},"
            (( ++warn_count ))
        fi
    done < "$TOPICS_FILE"
    if [ "$reset_count" -eq 0 ]; then echo -e "${GREEN}✅ 无过期主题。${NC}"; else echo -e "${YELLOW}📋 共 $reset_count 个过期主题。${NC}"; fi

    # 写入 ISP 专用状态文件 — /日进化 Layer1 只读这个
    cat > "$TRIO_ROOT/state/kb-refresh-status.json" << STATUS
{
  "_layer": "infra",
  "updated": "$now",
  "total": $(grep -cv '^#' "$TOPICS_FILE" | tr -d ' '),
  "expired": $reset_count,
  "warning": $warn_count,
  "expired_list": [${expired_json%,}],
  "warning_list": [${warning_json%,}]
}
STATUS
    log_history "system" "reset" "扫描完成，$reset_count个过期"
}

cmd_kb_refresh_add() {
    local new_path="${1:-}"; local new_interval="${2:-}"; local new_priority="${3:-}"; local new_desc="${4:-}"
    if [ -z "$new_path" ] || [ -z "$new_interval" ] || [ -z "$new_priority" ] || [ -z "$new_desc" ]; then
        echo -e "${RED}用法: mgmt.sh kb-refresh add <路径> <间隔天> <优先级1-5> <描述>${NC}"; return 1
    fi
    local base_name=$(basename "$new_path" .md | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g')
    local new_id="${base_name}"; local now=$(today)
    echo "$new_id"$'\t'"$new_path"$'\t'"custom"$'\t'"$now"$'\t'"$new_interval"$'\t'"$new_priority"$'\t'"$new_desc" >> "$TOPICS_FILE"
    echo -e "${GREEN}✅ 已添加: $new_id${NC}"
    log_history "$new_id" "add" "新主题注册，间隔${new_interval}天"
}

cmd_kb_refresh_skip() {
    local target_id="${1:-}"; local now=$(today); local found=false; local tmpfile=$(mktemp)
    while IFS=$'\t' read -r id path category last_refreshed interval_days priority description; do
        if [[ "$id" =~ ^# ]] || [[ -z "$id" ]]; then
            echo "$id"$'\t'"$path"$'\t'"$category"$'\t'"$last_refreshed"$'\t'"$interval_days"$'\t'"$priority"$'\t'"$description" >> "$tmpfile"
            continue
        fi
        if [ "$id" = "$target_id" ]; then
            echo "$id"$'\t'"$path"$'\t'"$category"$'\t'"$now"$'\t'"$interval_days"$'\t'"$priority"$'\t'"$description" >> "$tmpfile"
            echo -e "${YELLOW}⏭ 已跳过: $target_id${NC}"
            log_history "$target_id" "skip" "推迟刷新"
            found=true
        else
            echo "$id"$'\t'"$path"$'\t'"$category"$'\t'"$last_refreshed"$'\t'"$interval_days"$'\t'"$priority"$'\t'"$description" >> "$tmpfile"
        fi
    done < "$TOPICS_FILE"
    mv "$tmpfile" "$TOPICS_FILE"
}

