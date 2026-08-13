#!/usr/bin/env bash
# ============================================================
# 记忆权重自校准（magi 吸收 P1-4）
# knowledge 条目 weight/use_count 追踪——使用即强化，纠正即降权
# ============================================================
set -euo pipefail

TRIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE="$TRIO_ROOT/state/memory-weights.psv"
TOUCH() { TZ=Asia/Shanghai date +%Y-%m-%d_%H:%M; }

usage() {
  echo "用法: memory-weight.sh <mark_used|correct|supersede|top|decay> [参数]"
  echo "  mark_used <entry>                     → 使用命中 +0.03 权重"
  echo "  correct <entry>                       → 被纠正 ×0.25 置 disputed"
  echo "  supersede <old> <new>                 → 旧条目被新条目取代（降权）"
  echo "  top [n]                               → 列出权重最高的 n 条（默认10）"
  exit 1
}

# 读取 entry 当前权重，无则初始化 0.5
get_weight() {
  local entry="$1"
  grep "^$(printf '%s' "$entry" | sed 's/[][\\\/.*^$]/\\&/g')|" "$STATE" 2>/dev/null | tail -1 | cut -d'|' -f2
}
entry_exists() {
  grep -q "^$(printf '%s' "$1" | sed 's/[][\\\/.*^$]/\\&/g')|" "$STATE" 2>/dev/null
}

# mark_used: 命中即强化（magi: weight+0.03, use_count+1）
cmd_mark_used() {
  [ $# -ge 1 ] || usage
  local entry="$1" w use=1
  if entry_exists "$entry"; then
    w=$(get_weight "$entry"); w=$(echo "$w + 0.03" | bc 2>/dev/null || echo "$w")
    local oldline=$(grep "^$(printf '%s' "$entry" | sed 's/[][\\\/.*^$]/\\&/g')|" "$STATE" | tail -1)
    local use=$(echo "$oldline" | cut -d'|' -f3)
    use=$(( ${use:-0} + 1 ))
    # 删除旧行，写新行
    sed -i "/^$(printf '%s' "$entry" | sed 's/[][\\\/.*^$]/\\&/g')|/d" "$STATE"
    echo "$entry|$w|$use|active|$(TOUCH)" >> "$STATE"
  else
    echo "$entry|0.53|1|active|$(TOUCH)" >> "$STATE"
  fi
  echo "✅ mark_used: $entry (w=$(get_weight "$entry"), use=$(grep "^$(printf '%s' "$entry" | sed 's/[][\\\/.*^$]/\\&/g')|" "$STATE" | tail -1 | cut -d'|' -f3))"
}

# correct: 被纠正 → 权重 ×0.25, 置 disputed（magi: wrong/stale）
cmd_correct() {
  [ $# -ge 1 ] || usage
  local entry="$1"
  local w=$(get_weight "$entry"); w=${w:-0.5}
  w=$(echo "$w * 0.25" | bc -l 2>/dev/null || echo "0.13")
  if entry_exists "$entry"; then
    sed -i "/^$(printf '%s' "$entry" | sed 's/[][\\\/.*^$]/\\&/g')|/d" "$STATE"
  fi
  echo "$entry|$w|0|disputed|$(TOUCH)" >> "$STATE"
  echo "🚫 correct: $entry → weight×0.25=${w}, disputed"
}

# supersede: 旧条目被新条目取代（magi: supersedes 边，旧降权出检索）
cmd_supersede() {
  [ $# -ge 2 ] || usage
  local old="$1" new="$2"
  local w=$(get_weight "$old"); w=${w:-0.5}
  w=$(echo "$w * 0.2" | bc -l 2>/dev/null || echo "0.10")
  if entry_exists "$old"; then
    sed -i "/^$(printf '%s' "$old" | sed 's/[][\\\/.*^$]/\\&/g')|/d" "$STATE"
  fi
  echo "$old|$w|0|superseded_by_$new|$(TOUCH)" >> "$STATE"
  echo "🔁 supersede: $old → ${w}, 被 $new 取代"
}

# top: 列出权重最高条目
cmd_top() {
  local n="${1:-10}"
  [ -f "$STATE" ] || { echo "权重库空"; return 0; }
  echo "📊 记忆权重 Top $n:"
  sort -t'|' -k2,2rn "$STATE" | head -"$n" | while IFS='|' read -r e w u s t; do
    echo "  [$w] $e (use=$u, $s)"
  done
}

case "${1:-}" in
  mark_used) shift; cmd_mark_used "$@" ;;
  correct)   shift; cmd_correct "$@" ;;
  supersede) shift; cmd_supersede "$@" ;;
  top)       shift; cmd_top "$@" ;;
  *) usage ;;
esac
