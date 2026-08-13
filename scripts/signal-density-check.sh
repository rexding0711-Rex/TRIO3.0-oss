#!/bin/bash
# TRIO 3.0 信号密度预检——引擎 L1 后的硬阻断门禁
set -uo pipefail
# 中文正则 [一-鿿] 依赖 UTF-8 locale；显式锁定避免非 UTF-8 环境失效（2026-08-14 修复）
export LC_ALL=C.UTF-8
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRIO_ROOT="$(dirname "$SCRIPT_DIR")"
INPUT_FILE="${1:?需要 L1 搜索结果文件路径}"
MIN_SOURCES="${2:-3}"

SOURCE_PATTERNS="http|www\.|来源|参考|年报|研报|论文|财报|招股|公告|SEC|10-K"
# 计数改用 grep -o | wc -l：-c/-o 组合跨平台行为不一致，wc -l 恒输出数字（2026-08-14 修复）
# 实体正则用 \p{Han}（PCRE Unicode 属性）替代 [一-鿿] 范围——后者在 UTF-8 collation 下报 Invalid collation character（2026-08-14 修复）
SOURCES_FOUND=$(grep -oiE "$SOURCE_PATTERNS" "$INPUT_FILE" 2>/dev/null | wc -l)
ENTITY_COUNT=$(grep -oP '\p{Han}{2,8}(科技|制药|公司|集团|有限|股份|材料|电子|半导体|新能源)' "$INPUT_FILE" 2>/dev/null | wc -l)
DATA_POINTS=$(grep -oE '[0-9]+[%亿万美元RMB吨GW]|[0-9]+\.[0-9]+' "$INPUT_FILE" 2>/dev/null | wc -l)
TOTAL_CHARS=$(wc -c < "$INPUT_FILE" 2>/dev/null | tr -d '\n')
# 数字校验——非数字置0
[[ "$SOURCES_FOUND" =~ ^[0-9]+$ ]] || SOURCES_FOUND=0
[[ "$ENTITY_COUNT" =~ ^[0-9]+$ ]] || ENTITY_COUNT=0
[[ "$DATA_POINTS" =~ ^[0-9]+$ ]] || DATA_POINTS=0
[[ "$TOTAL_CHARS" =~ ^[0-9]+$ ]] || TOTAL_CHARS=0

echo "📊 信号密度预检: 来源=$SOURCES_FOUND/$MIN_SOURCES 实体=$ENTITY_COUNT 数据=$DATA_POINTS 字数=$TOTAL_CHARS"

BLOCKED=false; REASONS=""
[ "$SOURCES_FOUND" -lt "$MIN_SOURCES" ] 2>/dev/null && BLOCKED=true && REASONS+="有效来源不足($SOURCES_FOUND<$MIN_SOURCES); "
[ "$TOTAL_CHARS" -lt 500 ] 2>/dev/null && BLOCKED=true && REASONS+="内容过少($TOTAL_CHARS字<500); "
[ "$ENTITY_COUNT" -lt 2 ] 2>/dev/null && [ "$DATA_POINTS" -lt 2 ] 2>/dev/null && BLOCKED=true && REASONS+="实体和数据点均不足; "

if [ "$BLOCKED" = true ]; then
    echo "🚫 信号不足——触发引擎拒绝"
    echo "[$(date '+%Y-%m-%d %H:%M')] REJECTED: $INPUT_FILE | $REASONS" >> "$TRIO_ROOT/state/engine-rejections.log"
    exit 2
else
    echo "✅ 信号密度通过"
    exit 0
fi
