#!/bin/bash
# generate-run-index.sh — TRIO 3.0 Run INDEX 自动生成器
# INDEX.md 是只读派生物——永远由脚本生成，永远不手动编辑
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNS_DIR="${1:-$(dirname "$SCRIPT_DIR")/runs}"
INDEX_FILE="${RUNS_DIR}/INDEX.md"
META_FILE="${RUNS_DIR}/.index-meta.json"

if [ ! -d "$RUNS_DIR" ]; then
    echo "[ERROR] runs 目录不存在: $RUNS_DIR"; exit 1
fi

TOTAL_DIRS=0; WITH_MANIFEST=0; WITHOUT_MANIFEST=0
ORPHAN_DIRS=()
GENERATED_AT=$(date +'%Y-%m-%d %H:%M:%S')

cat > "$INDEX_FILE" << EOF
# Run INDEX (auto-generated)

> ⚠️ 此文件由 generate-run-index.sh 自动生成——请勿手动编辑
> 最后生成: ${GENERATED_AT}

## 统计

EOF

declare -a RUN_ENTRIES=()

while IFS= read -r dir; do
    [ -d "$dir" ] || continue
    TOTAL_DIRS=$((TOTAL_DIRS + 1))
    dirname=$(basename "$dir")

    manifest=""
    for candidate in "run-state.json" "manifest.json" "run-manifest.json" "meta.json"; do
        if [ -f "$dir/$candidate" ]; then
            manifest="$dir/$candidate"; break
        fi
    done

    if [ -n "$manifest" ]; then
        WITH_MANIFEST=$((WITH_MANIFEST + 1))
        run_date=$(jq -r '.date // .created // .timestamp // "—"' "$manifest" 2>/dev/null || echo "—")
        run_title=$(jq -r '.post_mortem // .title // .task_type // "未命名"' "$manifest" 2>/dev/null || echo "未命名")
        run_score=$(jq -r '.composite_score // .score // "—"' "$manifest" 2>/dev/null || echo "—")
        run_engine=$(jq -r '.engines_used[0] // .engine // "—"' "$manifest" 2>/dev/null || echo "—")
        [ ${#run_title} -gt 60 ] && run_title="${run_title:0:57}..."
        RUN_ENTRIES+=("| ${dirname} | ${run_date} | ${run_title} | ${run_score} | ${run_engine} |")
    else
        WITHOUT_MANIFEST=$((WITHOUT_MANIFEST + 1))
        ORPHAN_DIRS+=("$dirname")
        RUN_ENTRIES+=("| ${dirname} | — | ⚠️ 无 manifest | — | — |")
    fi
done < <(find "$RUNS_DIR" -maxdepth 1 -mindepth 1 -type d | sort)

HEALTH_RATE=$(( TOTAL_DIRS > 0 ? WITH_MANIFEST * 100 / TOTAL_DIRS : 0 ))

cat >> "$INDEX_FILE" << EOF
| 指标 | 值 |
|------|-----|
| 总目录数 | ${TOTAL_DIRS} |
| 有 manifest | ${WITH_MANIFEST} |
| 缺 manifest | ${WITHOUT_MANIFEST} |
| 健康率 | ${HEALTH_RATE}% |

## Run 列表

| 目录 | 日期 | 标题 | 评分 | 引擎 |
|------|------|------|------|------|
EOF

for entry in "${RUN_ENTRIES[@]}"; do echo "$entry" >> "$INDEX_FILE"; done

if [ ${#ORPHAN_DIRS[@]} -gt 0 ]; then
    { echo ""; echo "## ⚠️ Orphan 目录"; echo ""; } >> "$INDEX_FILE"
    for orphan in "${ORPHAN_DIRS[@]}"; do echo "- \`${orphan}/\` — 缺少 manifest.json" >> "$INDEX_FILE"; done
fi

cat >> "$INDEX_FILE" << EOF

---
*生成脚本: scripts/generate-run-index.sh · 下次自动生成将覆盖此文件*
EOF

ORPHAN_JSON=$(if [ ${#ORPHAN_DIRS[@]} -gt 0 ]; then printf '%s\n' "${ORPHAN_DIRS[@]}" | jq -R . | jq -s .; else echo "[]"; fi)

jq -n --arg generated_at "$GENERATED_AT" --argjson total "$TOTAL_DIRS" \
    --argjson with_manifest "$WITH_MANIFEST" --argjson without_manifest "$WITHOUT_MANIFEST" \
    --argjson health_rate "$HEALTH_RATE" --argjson orphans "$ORPHAN_JSON" \
    '{generated_at:$generated_at,total_runs:$total,with_manifest:$with_manifest,without_manifest:$without_manifest,health_rate:$health_rate,orphan_dirs:$orphans}' \
    > "$META_FILE"

echo "✓ INDEX.md 已生成 (${TOTAL_DIRS} runs · ${WITHOUT_MANIFEST} orphans)"
[ ${#ORPHAN_DIRS[@]} -gt 0 ] && echo "  ⚠️ ${WITHOUT_MANIFEST} 个 orphan 目录"
