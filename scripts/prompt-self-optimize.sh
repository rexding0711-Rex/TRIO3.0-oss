#!/bin/bash
# prompt-self-optimize.sh — TRIO 3.0 Prompt 自优化层
# 用法: ./prompt-self-optimize.sh [--force|--apply evo-N.json [--confirm]]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
RUNS_DIR="${ROOT_DIR}/runs"
EVO_DIR="${ROOT_DIR}/state/evolution"
META_FILE="${RUNS_DIR}/.index-meta.json"
mkdir -p "$EVO_DIR"

MODE="trigger"
[ "${1:-}" = "--force" ] && MODE="force"
[ "${1:-}" = "--apply" ] && MODE="apply"

if [ "$MODE" = "apply" ]; then
    EVO_FILE="${2:-}"; CONFIRM=false
    [ "${3:-}" = "--confirm" ] && CONFIRM=true
    [ ! -f "$EVO_FILE" ] && [ -f "${EVO_DIR}/${EVO_FILE}" ] && EVO_FILE="${EVO_DIR}/${EVO_FILE}"
    [ ! -f "$EVO_FILE" ] && echo "[ERROR] 找不到: $EVO_FILE" && exit 1

    PROPOSAL_COUNT=$(jq '.proposals | length' "$EVO_FILE")
    [ "$PROPOSAL_COUNT" -eq 0 ] && echo "[NO-OP] 无提案: $(jq -r '.no_change_reason // "数据不足"' "$EVO_FILE")" && exit 0

    echo "=== 优化提案 ${PROPOSAL_COUNT}条 $([ "$CONFIRM" = true ] && echo '执行' || echo '预览') ==="
    APPLIED=0
    for i in $(seq 0 $((PROPOSAL_COUNT - 1))); do
        pid=$(jq -r ".proposals[$i].id" "$EVO_FILE")
        target=$(jq -r ".proposals[$i].target_file" "$EVO_FILE")
        desc=$(jq -r ".proposals[$i].description" "$EVO_FILE")
        before=$(jq -r ".proposals[$i].before" "$EVO_FILE")
        after=$(jq -r ".proposals[$i].after" "$EVO_FILE")
        echo ""; echo "[$pid] $desc → $target"
        [ ! -f "${ROOT_DIR}/${target}" ] && echo "  ✗ 文件不存在" && continue
        if ! grep -qF "$before" "${ROOT_DIR}/${target}"; then echo "  ✗ 原文未匹配"; continue; fi
        if [ "$CONFIRM" = true ]; then
            perl -i -p0e "s/\Q${before}\E/${after}/s" "${ROOT_DIR}/${target}"
            echo "  ✓ APPLIED"; APPLIED=$((APPLIED + 1))
        else echo "  - $before"; echo "  + $after"; fi
    done
    [ "$CONFIRM" = true ] && [ $APPLIED -gt 0 ] && cd "$ROOT_DIR" && git add -A 2>/dev/null && git commit -m "evo: $(basename "$EVO_FILE" .json) (${APPLIED} changes)" --quiet 2>/dev/null || true
    [ "$CONFIRM" = true ] && echo "" && echo "✓ ${APPLIED}条已应用·回滚: git revert HEAD" && jq --arg ts "$(date -Iseconds)" --argjson n "$APPLIED" '. + {applied_at:$ts,changes_applied:$n,status:"applied_pending_validation"}' "$EVO_FILE" > "${EVO_FILE}.tmp" && mv "${EVO_FILE}.tmp" "$EVO_FILE"
    [ "$CONFIRM" != true ] && echo "" && echo "确认执行: $0 --apply $(basename "$EVO_FILE") --confirm"
    exit 0
fi

# Trigger/force mode
LAST_EVO=$(find "$EVO_DIR" -name "evo-*.json" -not -name ".*" 2>/dev/null | sort -V | tail -1)
if [ -n "$LAST_EVO" ]; then EVO_NUM=$(($(basename "$LAST_EVO" | grep -oE '[0-9]+') + 1)); LAST_RUN_COUNT=$(jq -r '.trigger.run_count_at_trigger // 0' "$LAST_EVO" 2>/dev/null || echo "0"); else EVO_NUM=1; LAST_RUN_COUNT=0; fi

CURRENT_RUN_COUNT=$(jq -r '.total_runs // 0' "$META_FILE" 2>/dev/null || echo "0")
RUNS_SINCE=$((CURRENT_RUN_COUNT - LAST_RUN_COUNT))

if [ "$MODE" != "force" ] && [ $RUNS_SINCE -lt 10 ] && [ "$(date +%u)" != "1" ]; then
    echo "[SKIP] ${RUNS_SINCE}/10 runs·非周一·用 --force"; exit 0
fi

echo "=== Evolution #${EVO_NUM}·${RUNS_SINCE} runs since last ==="

# Collect recent 10 runs
recent_runs="[]"; count=0
while IFS= read -r dir; do [ -d "$dir" ] || continue; manifest=""; for f in "manifest.json" "run-manifest.json" "meta.json"; do [ -f "$dir/$f" ] && manifest="$dir/$f" && break; done; [ -z "$manifest" ] && continue
    entry=$(jq '{run_id:(.run_id//.title//"?"),date:(.date//.created//"?"),score:(.score//null),engine:(.engine//null),status:(.status//"done")}' "$manifest" 2>/dev/null || echo "{}")
    recent_runs=$(echo "$recent_runs" | jq --argjson e "$entry" '. + [$e]'); count=$((count+1)); [ $count -ge 10 ] && break
done < <(find "$RUNS_DIR" -maxdepth 1 -mindepth 1 -type d | sort -r)

scored=$(echo "$recent_runs" | jq '[.[] | select(.score != null)]')
high=$(echo "$scored" | jq '[.[] | select((.score | tonumber) >= 7)] | length')
low=$(echo "$scored" | jq '[.[] | select((.score | tonumber) < 5)] | length')
avg=$(echo "$scored" | jq 'if length>0 then ([.[].score|tonumber]|add/length|.*10|round/10) else null end')

PROMPT_FILE="${EVO_DIR}/evo-${EVO_NUM}-prompt.md"
cat > "$PROMPT_FILE" << PROMPT
# TRIO 3.0·Prompt自优化·Evolution #${EVO_NUM}
> $(date +'%Y-%m-%d %H:%M')·最近${count}runs($(echo "$scored" | jq 'length')有评分)
## 数据
$(echo "$recent_runs" | jq .)
## 统计
高分(≥7):${high}|低分(<5):${low}|均分:${avg}
## 任务
1. 模式识别:低分run共性？2. 成功因子:高分run做对了什么？3. 提案(最多3条·可0条)
约束:每条<20行·只能改已有文件·禁碰CLAUDE.md L0硬约束和validate-engine-output.sh·必须附回滚条件
输出格式:{"evolution_number":${EVO_NUM},"analysis":{...},"proposals":[{...}],"no_change_reason":null}
不确定比瞎改好——数据不足就 proposals=[]
PROMPT

echo "✓ evo-${EVO_NUM}-prompt.md 已生成"
echo "  1. cat ${PROMPT_FILE} → 喂给 Claude"
echo "  2. 输出存到: state/evolution/evo-${EVO_NUM}.json"
echo "  3. 预览: $0 --apply evo-${EVO_NUM}.json"
echo "  4. 执行: $0 --apply evo-${EVO_NUM}.json --confirm"
