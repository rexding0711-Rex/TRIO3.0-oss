#!/usr/bin/env bash
# ============================================================
# @layer: orchestration
# TRIO 3.0 Loop Engine v1.0 — 通用循环控制器
# 用法: bash loop-engine.sh <workflow> <target> [--max-iter N] [--auto-fix]
# 工作流: topology-fix | search-quality | debate-quality
#
# 设计原则（来源：Karpathy AutoResearch + Niklaus Harness 实验）:
#   1. 验证器先行 — 每次迭代前后各跑一次验证器，比较得分
#   2. 状态持久化 — 每轮迭代写入状态文件，支持断点恢复
#   3. 停止条件明确 — 全通过/无改善/最大迭代/回归熔断
#   4. 每个修复写文件前显式审批 — 只补标记/模板，不自动改内容（外部评测 2026-08-12）
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
TRIO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

WORKFLOW="${1:-}"; TARGET="${2:-}"; MAX_ITER=3; AUTO_FIX=false
shift 2 2>/dev/null || true
while [ $# -gt 0 ]; do
    case "$1" in
        --max-iter) MAX_ITER="$2"; shift 2 ;;
        --auto-fix) AUTO_FIX=true; shift ;;
        *) shift ;;
    esac
done

if [ -z "$WORKFLOW" ] || [ -z "$TARGET" ]; then
    echo -e "${RED}❌ 用法: bash loop-engine.sh <workflow> <target> [--max-iter N] [--auto-fix]${NC}"
    echo "   workflow: topology-fix | search-quality | debate-quality"
    exit 2
fi

# 状态文件
RUN_ID="loop-$(date +%Y%m%d-%H%M%S)"
STATE_FILE="$TRIO_ROOT/state/${RUN_ID}.json"

# ── 初始化状态 ──
cat > "$STATE_FILE" << STATEEOF
{
  "run_id": "$RUN_ID",
  "workflow": "$WORKFLOW",
  "target": "$TARGET",
  "started_at": "$(date -Iseconds)",
  "completed_at": null,
  "iterations": [],
  "status": "running",
  "stop_reason": "",
  "best_score": 0,
  "best_iteration": 0
}
STATEEOF

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  TRIO Loop Engine v1.0${NC}"
echo -e "${CYAN}  工作流: $WORKFLOW | 目标: $(basename "$TARGET")${NC}"
echo -e "${CYAN}  最大迭代: $MAX_ITER | 自动修复: $AUTO_FIX${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── 工作流路由: 选择验证器 ──
case "$WORKFLOW" in
    topology-fix)
        VALIDATOR_SCRIPT="$TRIO_ROOT/scripts/topology-check.sh"
        FIXER_SCRIPT="$TRIO_ROOT/scripts/topology-fix.sh"
        ;;
    *)
        echo -e "${RED}❌ 未知工作流: $WORKFLOW${NC}"
        exit 2
        ;;
esac

# ── 主循环 ──
for i in $(seq 1 "$MAX_ITER"); do
    echo -e "${YELLOW}═══ 迭代 $i/$MAX_ITER ═══${NC}"

    # 1. 运行验证器 → 得到基线分数
    SCORE_BEFORE=0
    SCORE_FILE="/tmp/trio-loop-score-$$.json"
    if bash "$VALIDATOR_SCRIPT" "$TARGET" --json 2>/dev/null > "$SCORE_FILE"; then
        SCORE_BEFORE=$(python3 -c "import json; d=json.load(open('$SCORE_FILE')); print(d.get('score',0))" 2>/dev/null || echo "0")
        echo -e "  ${GREEN}✅ 验证器通过 (得分: $SCORE_BEFORE)${NC}"
        # 更新状态 → 完成
        python3 -c "
import json
s=json.load(open('$STATE_FILE'))
s['status']='completed'; s['stop_reason']='all_pass'
s['completed_at']='$(date -Iseconds)'
json.dump(s, open('$STATE_FILE','w'), ensure_ascii=False, indent=2)
"
        rm -f "$SCORE_FILE"
        echo -e "${GREEN}✅ 全部通过——循环结束${NC}"
        exit 0
    else
        SCORE_BEFORE=$(python3 -c "import json; d=json.load(open('$SCORE_FILE')); print(d.get('score',0))" 2>/dev/null || echo "0")
        FAIL_COUNT=$(python3 -c "import json; d=json.load(open('$SCORE_FILE')); print(len(d.get('fails',[])))" 2>/dev/null || echo "?")
        echo -e "  ${RED}❌ 验证器未通过 (得分: $SCORE_BEFORE, 失败: $FAIL_COUNT 项)${NC}"
    fi

    # 2. 修复（--auto-fix 模式）——每个修复写文件前显式审批（外部评测要求）
    if $AUTO_FIX; then
        # 修复前备份
        cp "$TARGET" "$TARGET.bak.$(date +%s)"

        # Level 1: topology-fix.sh（安全修补标记）——审批门
        read -p "  🔧 应用 topology-fix 修复 $(basename "$TARGET")？(y/n) " fix_ans
        if [ "$fix_ans" = "y" ] || [ "$fix_ans" = "Y" ]; then
            echo "  ✅ 用户批准 Level 1——应用标记补全..."
            bash "$FIXER_SCRIPT" "$TARGET" 2>&1 | sed 's/^/    /'
        else
            echo "  ⏭️  用户拒绝 Level 1——跳过"
        fi

        # Level 2: 如果Level 1后分数未变→DeepSeek API补充缺失（2026-07-09新增）——审批门
        SCORE_AFTER_L1=$(python3 -c "import json; d=json.load(open('$SCORE_FILE')); print(d.get('score',0))" 2>/dev/null || echo "$SCORE_BEFORE")
        if [ "$SCORE_AFTER_L1" = "$SCORE_BEFORE" ] && [ -n "${DEEPSEEK_API_KEY:-}" ]; then
            MISSING=$(bash "$VALIDATOR_SCRIPT" "$TARGET" 2>&1 | grep "FAIL" | head -3 | tr '\n' ';')
            if [ -n "$MISSING" ]; then
                read -p "  🔧 Level 2: DeepSeek 补充缺失维度并追加到文件？(y/n) " l2_ans
                if [ "$l2_ans" = "y" ] || [ "$l2_ans" = "Y" ]; then
                    echo "  ✅ 用户批准 Level 2——API 补充..."
                    CONTENT=$(curl -s https://api.deepseek.com/v1/chat/completions \
                        -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
                        -H "Content-Type: application/json" \
                        -d "{\"model\":\"deepseek-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"以下文件缺少拓扑要素：${MISSING}。只输出需要补充的内容（Markdown格式），追加到文件末尾。不超过500字。\"}],\"max_tokens\":1000}" | \
                        python3 -c "import sys,json;print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null)
                    [ -n "$CONTENT" ] && echo -e "\n\n---\n## [DeepSeek自动补充]\n\n$CONTENT" >> "$TARGET" && echo "    ✅ Level 2 已补充" || echo "    ⚠️ Level 2 API调用失败"
                else
                    echo "  ⏭️  用户拒绝 Level 2——跳过"
                fi
            fi
        elif [ "$SCORE_AFTER_L1" != "$SCORE_BEFORE" ]; then
            echo "    ✅ Level 1 已改进 (${SCORE_BEFORE}→${SCORE_AFTER_L1})，跳过Level 2"
        fi
    else
        echo -e "  ${YELLOW}⚠️  自动修复未启用。手动修复后重新运行，或用 --auto-fix${NC}"
        rm -f "$SCORE_FILE"
        exit 1
    fi

    # 3. 重新验证 → 得到新分数
    SCORE_AFTER=0
    if bash "$VALIDATOR_SCRIPT" "$TARGET" --json 2>/dev/null > "$SCORE_FILE"; then
        SCORE_AFTER=$(python3 -c "import json; d=json.load(open('$SCORE_FILE')); print(d.get('score',0))" 2>/dev/null || echo "0")
    else
        SCORE_AFTER=$(python3 -c "import json; d=json.load(open('$SCORE_FILE')); print(d.get('score',0))" 2>/dev/null || echo "0")
    fi
    echo -e "  修复后得分: $SCORE_BEFORE → $SCORE_AFTER"

    # 4. 更新状态文件
    python3 -c "
import json
s = json.load(open('$STATE_FILE'))
improved = $SCORE_AFTER > $SCORE_BEFORE
s['iterations'].append({
    'i': $i,
    'score_before': $SCORE_BEFORE,
    'score_after': $SCORE_AFTER,
    'improved': improved
})
# 追踪最佳迭代
if $SCORE_AFTER > s['best_score']:
    s['best_score'] = $SCORE_AFTER
    s['best_iteration'] = $i

# 停止条件检查
if $SCORE_AFTER == 100:
    s['status'] = 'completed'; s['stop_reason'] = 'all_pass'
elif len(s['iterations']) >= 2:
    last2 = s['iterations'][-2:]
    if not last2[0]['improved'] and not last2[1]['improved']:
        s['status'] = 'stopped'; s['stop_reason'] = 'no_improvement_2x'
    # 回归熔断: 得分下降 > 20%
    elif s['iterations'][-1]['score_after'] < s['best_score'] * 0.8:
        s['status'] = 'stopped'; s['stop_reason'] = 'regression'
        print('⚠️ 回归熔断触发——得分下降超过20%')
json.dump(s, open('$STATE_FILE','w'), ensure_ascii=False, indent=2)
"
    rm -f "$SCORE_FILE"

    # 检查停止状态
    STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['status'])")
    if [ "$STATUS" != "running" ]; then
        REASON=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['stop_reason'])")
        echo -e "  ${CYAN}⏹ 循环停止: $REASON${NC}"
        break
    fi
    echo ""
done

# ── 达到最大迭代 ──
FINAL_STATUS=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['status'])")
if [ "$FINAL_STATUS" = "running" ]; then
    python3 -c "
import json; s=json.load(open('$STATE_FILE'))
s['status']='max_iter'; s['stop_reason']='max_iter_$MAX_ITER'
s['completed_at']='$(date -Iseconds)'
json.dump(s,open('$STATE_FILE','w'), ensure_ascii=False, indent=2)
"
    echo -e "${YELLOW}⏹ 达到最大迭代次数 ($MAX_ITER)${NC}"
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  状态文件: $STATE_FILE"
echo -e "  最终状态: $(python3 -c "import json; s=json.load(open('$STATE_FILE')); print(f\"{s['status']} ({s['stop_reason']})\")")"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
