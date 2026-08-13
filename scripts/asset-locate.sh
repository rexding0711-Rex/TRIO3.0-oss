#!/usr/bin/env bash
# ============================================================
# asset-locate.sh — 定位 TRIO 任何沉淀资产
# 让引擎/AI 通过一句话找到资产位置
# 用法: asset-locate.sh <关键词>
#   例: asset-locate.sh 蔚星 → /mnt/d/工作/项目/蔚星空间科技
#       asset-locate.sh Chemistry → /mnt/d/Agent文件/TRIO-Chemistry
#       asset-locate.sh 猫砂 → 项目 + 对标
# ============================================================
set -euo pipefail

# 中文 grep 稳定（避免 Invalid collation character）
export LC_ALL=C.UTF-8 LANG=C.UTF-8

KEY="${1:-}"
if [ -z "$KEY" ]; then
  echo "❌ 用法: asset-locate.sh <关键词>"
  exit 1
fi

echo "🔍 搜索沉淀: $KEY"
echo

# ── 1. 项目数据 (D:\工作\项目) ──
echo "【项目】D:\\工作\\项目\\"
match=$(ls /mnt/d/工作/项目/ 2>/dev/null | grep -i "$KEY" || true)
if [ -n "$match" ]; then
  echo "$match" | sed 's/^/  → /'
else
  echo "  未匹配"
fi

# ── 2. 方法论分支 (D:\Agent文件) ──
echo "【分支】D:\\Agent文件\\"
branch=$(ls /mnt/d/Agent文件/ 2>/dev/null | grep -i "$KEY" || true)
if [ -n "$branch" ]; then
  echo "$branch" | sed 's/^/  → /'
else
  echo "  未匹配"
fi

# ── 3. 对标库 (D:\工作\对标库) ──
echo "【对标】D:\\工作\\对标库\\"
for lib in company person industry tech; do
  m=$(ls /mnt/d/工作/对标库/${lib}-benchmark/ 2>/dev/null | grep -i "$KEY" || true)
  [ -n "$m" ] && echo "$m" | sed "s/^/  → $lib-benchmark: /"
done

# ── 4. 知识库 (D:\工作\知识库) ──
echo "【知识】D:\\工作\\知识库\\"
k=$(ls /mnt/d/工作/知识库/ 2>/dev/null | grep -i "$KEY" || true)
[ -n "$k" ] && echo "$k" | sed 's/^/  → /' || echo "  未匹配"

echo
echo "📌 若以上未命中，资产可能在 D:\\工作\\项目\\{具体项目}\\ 或 D:\\工作\\归档\\"
