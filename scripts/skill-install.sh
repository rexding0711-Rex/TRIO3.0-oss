#!/usr/bin/env bash
# ============================================================
# Skill 独立分发（magi 吸收 P1-5）
# 从 GitHub 安装 skill 到 TRIO skills/external/，记录内容寻址
# 用法: skill-install.sh <owner/repo> [subdir] [--name 本地名]
# ============================================================
set -euo pipefail

TRIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTERNAL="$TRIO_ROOT/skills/external"
TMP="/tmp/skill-install-$$"
trap 'rm -rf "$TMP"' EXIT

usage() {
  echo "用法: skill-install.sh <owner/repo> [subdir] [--name 本地名]"
  echo "  例: skill-install.sh some-org/skills --name custom-skill"
  echo "      skill-install.sh some-org/skills analysis/method --name method-skill"
  exit 1
}

install() {
  local repo="$1" subdir="${2:-}" name="${3:-}"
  [ -n "$name" ] || name=$(basename "$repo")
  # 限制 name 为安全字符
  name=$(echo "$name" | tr -cd 'a-zA-Z0-9._-')
  echo "📦 从 GitHub 安装: $repo${subdir:+/$subdir} → skills/external/$name"
  git clone --depth 1 "https://github.com/$repo.git" "$TMP" 2>/dev/null || { echo "❌ clone 失败（仓库或路径错误）"; exit 1; }
  local src="$TMP"
  [ -n "$subdir" ] && src="$TMP/$subdir"
  [ -f "$src/SKILL.md" ] || { echo "❌ 目标位置无 SKILL.md（$subdir 路径是否正确？）"; exit 1; }
  mkdir -p "$EXTERNAL/$name"
  cp -r "$src/"* "$EXTERNAL/$name/"
  # 内容寻址：记录 git commit sha（不可变引用）
  local sha
  sha=$(git -C "$TMP" rev-parse HEAD 2>/dev/null || echo "unknown")
  cat > "$EXTERNAL/$name/.skill-manifest.json" <<EOF
{"source":"$repo","subdir":"${subdir:-.}","sha":"$sha","installed":"$(TZ=Asia/Shanghai date +%Y-%m-%d_%H:%M)"}
EOF
  echo "✅ 已安装: $EXTERNAL/$name"
  echo "   来源: $repo@${sha:0:12} | 清单: .skill-manifest.json"
  echo "   用法: 在 skills/ 索引或 CLAUDE.md 参考文件表引用该 skill"
}

# ── 入口 ──────────────────────────────────────────────────
[ $# -ge 1 ] || usage
repo="$1"; shift
subdir=""; name=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="$2"; shift 2 ;;
    *) if [ -z "$subdir" ]; then subdir="$1"; fi; shift ;;
  esac
done
install "$repo" "$subdir" "$name"
