#!/usr/bin/env bash
# ============================================================
# LearningDraft 学习草稿机制（magi 吸收 P0-1）
# 任务/分析结束后生成可复用经验草稿 → 人工审阅 → 应用入库
# ============================================================
set -euo pipefail

TRIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRAFTS="$TRIO_ROOT/state/learning-drafts"
LEARN_DIR="$TRIO_ROOT/knowledge/methods/learning"

# ── 工具函数 ──────────────────────────────────────────────
date_tag() { TZ=Asia/Shanghai date +%Y%m%d; }
now_ts()  { TZ=Asia/Shanghai date +%Y-%m-%d_%H:%M; }

usage() {
  echo "用法: learning-draft.sh <new|list|apply|reject> [参数]"
  echo "  new '<内容> [--title 标题] [--source 来源]'  → 生成 pending 草稿"
  echo "  list                                        → 列出所有 pending 草稿"
  echo "  apply <id>                                  → 应用草稿到 knowledge/methods/learning/"
  echo "  reject <id>                                 → 标记拒绝"
  exit 1
}

# ── new: 生成学习草稿 ─────────────────────────────────────
cmd_new() {
  [ $# -ge 1 ] || { echo "❌ 缺少草稿内容"; usage; }
  local content="$1"; shift
  local title="未命名经验"; local source="对话"
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --source) source="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  local id="learn-$(date_tag)-$(date +%s | tail -c 5)-$$"
  local file="$DRAFTS/$id.md"
  cat > "$file" <<EOF
# 学习草稿: $title
> id: $id | status: pending | created: $(now_ts)
> source: $source

## 何时使用（When to use）
（这个经验在什么场景/条件下适用？）

## 可复用教训（Reusable lesson）
$content

## 证据（Evidence）
（来自哪个分析/任务？哪些工具结果支撑？）

---
审阅: bash scripts/learning-draft.sh apply $id
EOF
  echo "✅ 已生成 pending 草稿: $file"
}

# ── list: 列出 pending 草稿 ───────────────────────────────
cmd_list() {
  if [ ! -d "$DRAFTS" ] || ! ls "$DRAFTS"/learn-*.md &>/dev/null; then
    echo "📋 无 pending 学习草稿"; return 0
  fi
  echo "📋 pending 学习草稿:"
  for f in "$DRAFTS"/learn-*.md; do
    [ -f "$f" ] || continue
    local id=$(basename "$f" .md)
    local title=$(grep "^# 学习草稿:" "$f" | sed 's/^# 学习草稿: //')
    local status=$(grep "status:" "$f" | head -1 | sed 's/.*status: //')
    echo "  [$id] $status | $title"
  done
}

# ── apply: 应用草稿入库 ───────────────────────────────────
cmd_apply() {
  [ $# -ge 1 ] || { echo "❌ 缺少草稿 id"; usage; }
  local id="$1"
  local file="$DRAFTS/$id.md"
  [ -f "$file" ] || { echo "❌ 草稿不存在: $id"; exit 1; }
  grep -q "status: pending" "$file" || { echo "❌ 草稿非 pending（可能已处理）"; exit 1; }
  mkdir -p "$LEARN_DIR"
  local title=$(grep "^# 学习草稿:" "$file" | sed 's/^# 学习草稿: //' | tr -d ' /\\:*?"<>|')
  local target="$LEARN_DIR/$id-$title.md"
  cp "$file" "$target"
  # 标记 applied
  sed -i "s/status: pending/status: applied @ $(now_ts)/" "$file"
  echo "✅ 已应用: $target"
}

# ── reject: 拒绝草稿 ──────────────────────────────────────
cmd_reject() {
  [ $# -ge 1 ] || { echo "❌ 缺少草稿 id"; usage; }
  local id="$1"; local file="$DRAFTS/$id.md"
  [ -f "$file" ] || { echo "❌ 草稿不存在: $id"; exit 1; }
  sed -i "s/status: pending/status: rejected @ $(now_ts)/" "$file"
  echo "🚫 已拒绝: $id"
}

# ── 入口 ──────────────────────────────────────────────────
case "${1:-}" in
  new)   shift; cmd_new "$@" ;;
  list)  cmd_list ;;
  apply) shift; cmd_apply "$@" ;;
  reject) shift; cmd_reject "$@" ;;
  *) usage ;;
esac
