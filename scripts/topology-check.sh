#!/usr/bin/env bash
# ============================================================
# @layer: quality-control
# TRIO 3.0 拓扑检查门禁 — 可执行版本
# 用法: bash topology-check.sh <分析文件> [领域] [--interactive]
# 退出码: 0=全部通过 | 1=不合格(阻断) | 2=脚本错误
#
# v3.1 修复 C5: 反证搜索 + 表格格式支持 + 截断警告 + 交互反馈环
# v3.2 反脑补: ??? 节点 + 虚线边强制检查
# v3.3 过程完整性: C6 Phase覆盖 + C7 自验证痕迹 + C8 反证覆盖率
# v3.7 Bridge Lemma 门禁: C9 防"领域映射≠逻辑绕过"范畴错误
#   Origin: P vs NP 多模型实验 (2026-07-13)
#   8 个模型集体将"换数学工具"等同于"绕过逻辑屏障"
#   屏障限制的是证明的逻辑结构，不是数学领域
#   核心哲学: AI 做逻辑链构建，遇到信息缺失不假设，反向追问用户。
#   武断是思维大忌 —— 不确定就问，别猜。
#   版本规矩: 破坏性变更才跳第一位，功能增量只动第二位。
# ============================================================
set -eu  # 不用 pipefail: grep 无匹配时返回1会打断管道

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
TRIO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VIOLATION_LOG="$TRIO_ROOT/state/topology-violations.log"
TIMESTAMP=$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M')

ANALYSIS_FILE="${1:-}"
DOMAIN="${2:-general}"
INTERACTIVE=false
JSON_MODE=false
# 解析标志
for arg in "$@"; do
    [[ "$arg" == "--interactive" ]] && INTERACTIVE=true
    [[ "$arg" == "--json" ]] && JSON_MODE=true
done
[[ "${2:-}" == "--interactive" ]] && { INTERACTIVE=true; DOMAIN="general"; }
[[ "${2:-}" == "--json" ]] && { JSON_MODE=true; DOMAIN="general"; }
[[ "${3:-}" == "--json" ]] && JSON_MODE=true

if [ -z "$ANALYSIS_FILE" ] || [ ! -f "$ANALYSIS_FILE" ]; then
    echo -e "${RED}❌ 用法: bash topology-check.sh <分析文件> [领域] [--interactive] [--json]${NC}"
    echo "   领域: general|supply_chain|competitive|tech_benchmark|quick"
    echo "   --interactive: 启用交互式追问（C5 约束）"
    echo "   --json: 输出机器可读 JSON（静默人类可读日志）"
    exit 2
fi

# JSON 模式：静默所有人类可读输出，只输出最终 JSON
if $JSON_MODE; then
    exec 3>&1            # 保存原始 stdout
    exec 1>/dev/null     # 静默检查过程中的 echo
fi

# 领域阈值
case "$DOMAIN" in
    supply_chain)  MIN_NODES=15; MIN_EDGES=25; MIN_LAYERS=3; MIN_TIME_EDGES=3 ;;
    competitive)   MIN_NODES=12; MIN_EDGES=20; MIN_LAYERS=2; MIN_TIME_EDGES=2 ;;
    tech_benchmark) MIN_NODES=10; MIN_EDGES=15; MIN_LAYERS=2; MIN_TIME_EDGES=2 ;;
    quick)         MIN_NODES=8;  MIN_EDGES=10; MIN_LAYERS=1; MIN_TIME_EDGES=1 ;;
    *)             MIN_NODES=10; MIN_EDGES=15; MIN_LAYERS=2; MIN_TIME_EDGES=2 ;;
esac

# 安全计数: 使用 /bin/grep（绕过 Claude Code 的 ugrep 函数劫持）
GREP=/bin/grep
count_in_file()  { $GREP -P "$1" "$ANALYSIS_FILE" 2>/dev/null | wc -l; }
count_in_mermaid() { sed -n '/```mermaid/,/```/p' "$ANALYSIS_FILE" 2>/dev/null | $GREP -P "$1" 2>/dev/null | wc -l; }

FAILS=0; WARNS=0; DETAILS=""

# 辅助: 根据文件类型决定 FAIL 还是 WARN
add_c1c4_fail() {
    if $IS_TOPOLOGY_REPORT; then
        FAILS=$((FAILS + 1))
    else
        WARNS=$((WARNS + 1))
    fi
}

echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}  拓扑检查层 v3.1 — 门禁审计 + 交互式追问${NC}"
echo -e "${CYAN}  文件: $(basename "$ANALYSIS_FILE") | 领域: $DOMAIN${NC}"
echo -e "${CYAN}  阈值: ≥${MIN_NODES}节点 ≥${MIN_EDGES}边 ≥${MIN_TIME_EDGES}时间边${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

# 文件类型检测: 非拓扑类报告自动降低 C1-C4 为警告
IS_TOPOLOGY_REPORT=false
HEAD_30=$(head -30 "$ANALYSIS_FILE" 2>/dev/null)
HAS_MERMAID=$($GREP -P '```mermaid' "$ANALYSIS_FILE" 2>/dev/null | wc -l)
if echo "$HEAD_30" | $GREP -qP '(拓扑|供应链|因果|causal|topology|知识图谱|节点.{0,5}边|Mermaid|graph\s+(TB|LR|TD))' 2>/dev/null; then
    IS_TOPOLOGY_REPORT=true
fi
[ "$HAS_MERMAID" -gt 0 ] && IS_TOPOLOGY_REPORT=true

if ! $IS_TOPOLOGY_REPORT; then
    echo -e "${CYAN}  📄 检测到非拓扑类文件（市场报告/尽调/文档）— C1-C4 降级为警告${NC}"
    echo ""
fi

# ============================================================
# 约束 1: 拓扑图检查（支持 Mermaid 代码块 或 嵌入 SVG 图片）
# ============================================================
echo -e "${YELLOW}[约束 1] 拓扑图检查${NC}"

HAS_SVG=$($GREP -P '\.svg' "$ANALYSIS_FILE" 2>/dev/null | wc -l)
NODE_COUNT=$(count_in_mermaid '^\s+[A-Za-z0-9_]+[\[(]')
EDGE_COUNT=$(count_in_mermaid '\-\->|\-\-\-')
HAS_BIDIRECTIONAL=$(count_in_mermaid '<\->|双向|feedback|FEEDS_BACK')
# v3.2: 反脑补检查 — ??? 节点 + 虚线边
HAS_UNKNOWN=$(count_in_mermaid '\?\?\?|unknown|不确定')
HAS_DASHED=$(count_in_mermaid '\.-\->|\.\.->|虚线|dashed|不确定|DASHED')
HAS_COUNTER=$(count_in_file '反证|替代解释|counter.evidence|什么情况下.*错|如果.*则.*不成立')

NODE_COUNT=$((NODE_COUNT))
EDGE_COUNT=$((EDGE_COUNT))

# SVG 嵌入也视为有图（绕过 Mermaid 代码块检测）
if [ "$HAS_MERMAID" -eq 0 ] && [ "$HAS_SVG" -gt 0 ]; then
    echo "  检测到 SVG 嵌入图片（替代 Mermaid 代码块）"
    echo -e "  ${GREEN}✅ 拓扑图已提供（SVG 格式）${NC}"
    echo -e "  ${YELLOW}⚠️  SVG 无法自动统计节点/边数，请人工确认 ≥${MIN_NODES}节点 ≥${MIN_EDGES}边${NC}"
    WARNS=$((WARNS+1))
elif [ "$HAS_MERMAID" -eq 0 ]; then
    echo -e "  ${RED}❌ 未找到 Mermaid 代码块或 SVG 图片${NC}"
    echo "  → 必须输出至少一张拓扑图（Mermaid 或 SVG）"
    echo "  → SVG 渲染: curl -X POST https://kroki.io/mermaid/svg --data-binary @图.mmd -o 图.svg"
    add_c1c4_fail; DETAILS="$DETAILS\n  [C1] 无拓扑图"
else
    echo "  检测到: ${NODE_COUNT} 节点, ${EDGE_COUNT} 边"
    if [ "$NODE_COUNT" -lt "$MIN_NODES" ]; then
        echo -e "  ${RED}❌ 节点数 ${NODE_COUNT} < ${MIN_NODES}${NC}"
        add_c1c4_fail; DETAILS="$DETAILS\n  [C1] 节点不足: ${NODE_COUNT}/${MIN_NODES}"
    else
        echo -e "  ${GREEN}✅ 节点数达标 (${NODE_COUNT} ≥ ${MIN_NODES})${NC}"
    fi
    if [ "$EDGE_COUNT" -lt "$MIN_EDGES" ]; then
        echo -e "  ${RED}❌ 边数 ${EDGE_COUNT} < ${MIN_EDGES}${NC}"
        add_c1c4_fail; DETAILS="$DETAILS\n  [C1] 边数不足: ${EDGE_COUNT}/${MIN_EDGES}"
    else
        echo -e "  ${GREEN}✅ 边数达标 (${EDGE_COUNT} ≥ ${MIN_EDGES})${NC}"
    fi
    if [ "$HAS_BIDIRECTIONAL" -eq 0 ]; then
        echo -e "  ${YELLOW}⚠️  未检测到双向边或反馈环${NC}"; WARNS=$((WARNS+1))
    else
        echo -e "  ${GREEN}✅ 含双向边/反馈环${NC}"
    fi
    # v3.2 反脑补检查（非拓扑类文件不强制，只提示）
    if [ "$HAS_UNKNOWN" -eq 0 ] && [ "$HAS_DASHED" -eq 0 ]; then
        if $IS_TOPOLOGY_REPORT; then
            echo -e "  ${RED}❌ 无反脑补标记（无 ??? 节点、无线边）→ 可能脑补了不确定信息${NC}"
            FAILS=$((FAILS+1)); DETAILS="$DETAILS\n  [C1-反脑补] 无???节点或虚线边"
        else
            echo -e "  ${YELLOW}💡 建议: 添加 ??? 节点标记已知未知、虚线边标记不确定关系（反脑补）${NC}"
        fi
    else
        echo -e "  ${GREEN}✅ 反脑补标记存在 (???节点:${HAS_UNKNOWN} / 虚线边:${HAS_DASHED})${NC}"
    fi
fi
echo ""

# v3.3 内化版: 检查拓扑思维模式，不检查术语标签
# 语义模式: "如果X没了→Y会…→Z会…" 的级联推演
# 而非: 必须出现"移除推演""第1层"等标签
# ============================================================
# 约束 2: 扰动推演检查（内化版）
# ============================================================
echo -e "${YELLOW}[约束 2] 扰动推演检查（内化版: 语义模式，非术语标签）${NC}"

# v3.3 语义模式: "如果X消失/断供/没了 → Y会... → Z会..." 的级联推演
# 不再检查"移除推演""第1层"等标签——检查思维模式是否发生
HAS_REMOVAL=$(count_in_file '(如果|假设|假如|一旦).{0,30}(消失|没了|断供|断裂|退出|崩塌|停产|被禁|出事)')
HAS_CASCADE=$(count_in_file '(会导致|将导致|引发|传导|波及|连累|继而).{0,30}(如果|假设|一旦|→)|(如果|假设|一旦).{0,50}(会导致|将导致|引发)')
HAS_LAYER2_PATTERN=$(count_in_file '(进而|接着|然后|随后).{0,30}(如果|一旦|会导致|将)')
HAS_INJECTION=$(count_in_file '(如果.{0,20}(突然|宣布|进入|推出|收购).{0,20}(会|将|可能)|(新).{0,10}(边|连接|关系|竞争|合作).{0,20}(形成|出现|产生))')

HAS_CASCADE_TOTAL=$((HAS_CASCADE + HAS_LAYER2_PATTERN))

[ "$HAS_REMOVAL" -eq 0 ] && { echo -e "  ${RED}❌ 未找到扰动推演: 缺少'如果X消失→Y会...'的级联思维${NC}"; add_c1c4_fail; DETAILS="$DETAILS\n  [C2] 无扰动推演(级联思维)"; } || echo -e "  ${GREEN}✅ 扰动推演存在 (条件假设:${HAS_REMOVAL})${NC}"
[ "$HAS_CASCADE_TOTAL" -lt 2 ] && { echo -e "  ${RED}❌ 级联深度不足: 需≥2处传导描述(当前${HAS_CASCADE_TOTAL})${NC}"; add_c1c4_fail; DETAILS="$DETAILS\n  [C2] 级联深度不足: ${HAS_CASCADE_TOTAL}/2"; } || echo -e "  ${GREEN}✅ 级联传导充足 (${HAS_CASCADE_TOTAL}处传导描述)${NC}"
[ "$HAS_INJECTION" -eq 0 ] && { echo -e "  ${YELLOW}⚠️  未检测到'如果X进入/推出Y→网络重组'的新边注入模式${NC}"; WARNS=$((WARNS+1)); } || echo -e "  ${GREEN}✅ 新边注入分析存在${NC}"
echo ""

# ============================================================
# 约束 3: 脆弱点检查（内化版）
# ============================================================
echo -e "${YELLOW}[约束 3] 脆弱点定位检查（内化版: 非直觉脆弱点 > 安全答案）${NC}"

HAS_WEAK_LINK=$(count_in_file '(最脆弱|最危险|最致命|最薄弱|单点故障|命门|软肋).{0,30}(连接|依赖|关系|一环|供应链|通道|命脉)')
HAS_ATTACK=$(count_in_file '(攻击|打击|掐断|切断|挖走|掠夺).{0,20}(这里|这个节点|这条边|这个|就可以|就能)|(如果.{0,10}我是|作为).{0,10}(竞争|对手|攻击者)')
HAS_SAFE_ANSWER=$(count_in_file '(最大客户|单一客户.{0,10}依赖|大客户依赖|CEO.{0,5}离职)')

[ "$HAS_WEAK_LINK" -eq 0 ] && { echo -e "  ${RED}❌ 未找到脆弱点定位: 缺少'最脆弱/最致命的连接/依赖是...'${NC}"; add_c1c4_fail; DETAILS="$DETAILS\n  [C3] 无脆弱点定位"; } || echo -e "  ${GREEN}✅ 脆弱点已定位${NC}"
[ "$HAS_ATTACK" -eq 0 ] && { echo -e "  ${RED}❌ 未找到攻击向量分析: 缺少'如果攻击这里→会...'${NC}"; add_c1c4_fail; DETAILS="$DETAILS\n  [C3] 无攻击向量"; } || echo -e "  ${GREEN}✅ 攻击向量已分析${NC}"
[ "$HAS_SAFE_ANSWER" -gt 0 ] && { echo -e "  ${YELLOW}⚠️  检测到'最大客户依赖'类安全答案——确认不是直觉型而非结构扫描型?${NC}"; WARNS=$((WARNS+1)); }
echo ""

# ============================================================
# 约束 4: 时间维度检查（内化版）
# ============================================================
echo -e "${YELLOW}[约束 4] 时间维度检查（内化版: 趋势+时间窗口）${NC}"

STRENGTHEN_COUNT=$(count_in_file '(扩大|加速|增强|增长|上升|改善|收紧|加强|加深|攀升|还在.{0,5}(涨|扩大)|越来越)')
WEAKEN_COUNT=$(count_in_file '(衰退|减弱|缩小|下降|恶化|松动|脱钩|流失|侵蚀|挤压|收缩|收窄)')
HAS_TIMEWINDOW=$(count_in_file '([0-9]+[-~][0-9]+\s*(个)?月|[0-9]+[-~][0-9]+\s*年|窗口期?|时间窗口)')

echo "  增强趋势: ${STRENGTHEN_COUNT}  衰退趋势: ${WEAKEN_COUNT}  时间窗口: ${HAS_TIMEWINDOW}"

[ "$STRENGTHEN_COUNT" -lt "$MIN_TIME_EDGES" ] && { echo -e "  ${RED}❌ 增强趋势 ${STRENGTHEN_COUNT} < ${MIN_TIME_EDGES}${NC}"; add_c1c4_fail; DETAILS="$DETAILS\n  [C4] 增强趋势不足: ${STRENGTHEN_COUNT}/${MIN_TIME_EDGES}"; } || echo -e "  ${GREEN}✅ 增强趋势达标${NC}"
[ "$WEAKEN_COUNT" -lt "$MIN_TIME_EDGES" ] && { echo -e "  ${RED}❌ 衰退趋势 ${WEAKEN_COUNT} < ${MIN_TIME_EDGES}${NC}"; add_c1c4_fail; DETAILS="$DETAILS\n  [C4] 衰退趋势不足: ${WEAKEN_COUNT}/${MIN_TIME_EDGES}"; } || echo -e "  ${GREEN}✅ 衰退趋势达标${NC}"
[ "$HAS_TIMEWINDOW" -lt 1 ] && { echo -e "  ${YELLOW}⚠️  未检测到时间窗口(如'6-12个月')——趋势缺少时间锚点${NC}"; WARNS=$((WARNS+1)); }

# ============================================================
# 信息增量检查
# ============================================================
echo -e "${YELLOW}[信息增量] 反直觉发现检查${NC}"
HAS_COUNTERINTUITIVE=$(count_in_file '(反直觉|之前没想|画图前.{0,10}(不知|没意识|遗漏)|意外发现)')
[ "$HAS_COUNTERINTUITIVE" -eq 0 ] && { echo -e "  ${YELLOW}⚠️  未检测到反直觉发现——拓扑分析可能没有产生信息增量${NC}"; WARNS=$((WARNS+1)); } || echo -e "  ${GREEN}✅ 反直觉发现已标注${NC}"
echo ""

# ============================================================
# 约束 5: 信息完整性检查 + 交互式追问（v3.1 增强）
# ============================================================
echo -e "${YELLOW}[约束 5] 信息完整性检查 — 防脑补${NC}"

# 5a. 检测低置信度标注 [1] [2]
LOW_CONF=$(count_in_file '\[1\]|\[2\]')
UNVERIFIED=$(count_in_file '⚠️.{0,15}(空信息|未核实|待补充)|空信息需补充')
FLAGGED_MISSING=$(count_in_file '\?\?\?|___\s*$|【待填】')

echo "  低置信度推断: ${LOW_CONF} 条"
echo "  已标注空信息: ${UNVERIFIED} 处"
echo "  未填空白字段: ${FLAGGED_MISSING} 处"

# 5b. 反证强制搜索（v3.1 新增 — DeepSeek 审计要求）
# 每条低置信度推断必须附带反证问题，否则视为脑补风险
LOW_CONF_LINES=$($GREP -ncP '\[1\]|\[2\]' "$ANALYSIS_FILE" 2>/dev/null || echo 0)
HAS_COUNTER=$(count_in_file '(反证|为什么不成立|什么条件下不|如果不成立|推翻|反驳)')
COUNTER_RATIO=0
[ "$LOW_CONF" -gt 0 ] && COUNTER_RATIO=$((HAS_COUNTER * 100 / LOW_CONF))

echo "  低置信度行数: ${LOW_CONF_LINES}"
echo "  反证标记数: ${HAS_COUNTER} (覆盖率 ${COUNTER_RATIO}%)"

# 50% 阈值推导: 太低→脑补风险高(大部分推断未经自我质疑)
# 太高→阻塞正常逻辑推断(低置信度≠需要反证)
# 如果全为高置信度推断(LOW_CONF=0)，覆盖率自然为0不触发
if [ "$LOW_CONF" -gt 0 ] && [ "$COUNTER_RATIO" -lt 50 ]; then
    echo -e "  ${RED}❌ 反证覆盖率 ${COUNTER_RATIO}% < 50% — 每条 [1][2] 推断必须附带反证${NC}"
    echo -e "  ${RED}→ 格式: 「反证: 什么条件下不成立？」或「为什么不成立: ...」${NC}"
    FAILS=$((FAILS + 1))
    DETAILS="$DETAILS\n  [C5] 反证覆盖率仅${COUNTER_RATIO}%(需≥50%)"
elif [ "$LOW_CONF" -gt 0 ]; then
    echo -e "  ${GREEN}✅ 反证覆盖率达标 (${COUNTER_RATIO}%)${NC}"
fi

# 5c. 检测"可能脑补"的信号（v3.1 修复: 不再用减法，改用行级交叉检测）
UNMARKED_INFERENCE=$(count_in_file '((可能|应该|预计|大概率|推测|推断|估计).{0,50}(会|能|可以|存在)|似乎.{0,30}(是|有|在))')
# 不直接减 CONF_MARKERS（DeepSeek: 推断词和置信度标注不在同一行，减法无统计意义）
# 改为: 检测包含推断词但同行无 [1-5] 标注的行
UNMARKED_LINES=$($GREP -nP '((可能|应该|预计|大概率|推测|推断|估计).{0,50}(会|能|可以|存在)|似乎.{0,30}(是|有|在))' "$ANALYSIS_FILE" 2>/dev/null | $GREP -vP '\[([1-5])\]' | wc -l)

if [ "$UNMARKED_LINES" -gt 0 ]; then
    echo -e "  ${YELLOW}⚠️  ${UNMARKED_LINES} 行含推断词但未同行标注置信度 — 存在脑补风险${NC}"
    WARNS=$((WARNS + 1))
else
    echo -e "  ${GREEN}✅ 推断词均有置信度同行标注${NC}"
fi

# 5d. 交互式追问（仅 --interactive 模式）
INTERACTIVE_OUTPUT="$TRIO_ROOT/state/interactive-questions.txt"
if $INTERACTIVE; then
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│  交互式信息追问                          │${NC}"
    echo -e "${CYAN}│  引擎不会替你做判断——它只会问你:          │${NC}"
    echo -e "${CYAN}│  「你是不是已经有这些信息了？」            │${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────┘${NC}"
    echo ""

    echo -e "${YELLOW}以下推断置信度不足 [≤2]，请逐条确认:${NC}"
    echo ""

    Q_COUNT=0
    TOTAL_LOW=$($GREP -cP '\[1\]|\[2\]' "$ANALYSIS_FILE" 2>/dev/null || echo 0)
    MAX_Q=15  # 提高到15

    # 输出追问清单到文件（供后续反馈环读取）
    echo "# 交互式追问 — $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M')" > "$INTERACTIVE_OUTPUT"
    echo "# 文件: $ANALYSIS_FILE" >> "$INTERACTIVE_OUTPUT"
    echo "" >> "$INTERACTIVE_OUTPUT"

    while IFS= read -r line_num; do
        [ -z "$line_num" ] && continue
        start=$((line_num - 1)); [ "$start" -lt 1 ] && start=1
        end=$((line_num + 1))

        Q_COUNT=$((Q_COUNT + 1))
        echo -e "  ${CYAN}── 追问 #${Q_COUNT} (行 ${line_num}) ──${NC}"
        sed -n "${start},${end}p" "$ANALYSIS_FILE" 2>/dev/null | while IFS= read -r ctx_line; do
            echo "  │ $ctx_line"
        done
        echo ""

        # v3.1 修复: 同时匹配表格格式和段落格式的缺口
        # 表格格式: | 问题描述 | [2] | 验证方法 |
        # 段落格式: ⚠️ 需确认 XXX
        local_missing=$(sed -n "${start},${end}p" "$ANALYSIS_FILE" 2>/dev/null | $GREP -oP '(\|.{0,60}\[([12])\].{0,60}\||⚠️.{0,40}|需.{0,15}(确认|验证|补充)|缺.{0,10}(数据|信息|认证|测试)|未知|待.{0,10}(测|查|确认))' | head -5)
        if [ -n "$local_missing" ]; then
            echo -e "  ${YELLOW}  识别到的信息缺口:${NC}"
            echo "$local_missing" | while IFS= read -r gap; do
                echo "    → $gap"
            done
        else
            # 如果正则没匹配到，至少显示该行所在的表格行
            echo -e "  ${YELLOW}  (表格格式 — 请确认此行的信息状态)${NC}"
        fi

        echo -e "  ${GREEN}  📋 请回答 (y/n/? = 有/没有/不确定):${NC}"
        echo ""

        # 写入追问文件
        echo "Q${Q_COUNT}|行${line_num}|${start}-${end}" >> "$INTERACTIVE_OUTPUT"
    done < <($GREP -nP '\[1\]|\[2\]' "$ANALYSIS_FILE" 2>/dev/null | head -"$MAX_Q" | cut -d: -f1)

    # 截断警告
    if [ "$TOTAL_LOW" -gt "$MAX_Q" ]; then
        echo -e "  ${YELLOW}⚠️  共 ${TOTAL_LOW} 条低置信度推断，仅显示前 ${MAX_Q} 条${NC}"
        echo -e "  ${YELLOW}   剩余 $((TOTAL_LOW - MAX_Q)) 条请在文件中搜索 [1] [2] 手动确认${NC}"
        echo ""
    fi

    if [ "$Q_COUNT" -eq 0 ]; then
        echo -e "  ${GREEN}✅ 未检测到低置信度推断 — 无需追问${NC}"
    else
        echo -e "${CYAN}─────────────────────────────────────────${NC}"
        echo -e "${YELLOW}📋 共 ${Q_COUNT}/${TOTAL_LOW} 条待确认${NC}"
        echo -e "${YELLOW}   追问清单已保存: ${INTERACTIVE_OUTPUT}${NC}"
        echo ""
        echo -e "${CYAN}📝 反馈方式:${NC}"
        echo -e "   编辑上述文件，每行后追加 |y (已有)|n (没有)|? (不确定)"
        echo -e "   然后运行: bash topology-check.sh <文件> <领域> --feedback"
        echo ""
        echo -e "${RED}⚠️  核心原则:${NC}"
        echo -e "   AI 做逻辑链构建 → 人做判断"
        echo -e "   不确定 → 诚实标注「空信息需补充」"
        echo -e "   别猜 → 猜错了比不猜危害更大"
        echo -e "   武断 → 任何一个人思维的大忌"
    fi
elif [ "${3:-}" == "--feedback" ] || [ "${2:-}" == "--feedback" ]; then
    # 反馈环: 读取用户回复并重新评估
    echo -e "  ${CYAN}📥 反馈环 — 读取用户回复...${NC}"
    if [ -f "$INTERACTIVE_OUTPUT" ]; then
        YES_COUNT=$($GREP -c '|y$' "$INTERACTIVE_OUTPUT" 2>/dev/null || echo 0)
        NO_COUNT=$($GREP -c '|n$' "$INTERACTIVE_OUTPUT" 2>/dev/null || echo 0)
        UNSURE_COUNT=$($GREP -c '|\?$' "$INTERACTIVE_OUTPUT" 2>/dev/null || echo 0)
        echo "  已有信息: ${YES_COUNT} | 没有: ${NO_COUNT} | 不确定: ${UNSURE_COUNT}"
        if [ "$YES_COUNT" -gt 0 ]; then
            echo -e "  ${GREEN}  → ${YES_COUNT} 条可升级置信度，请在源文件中将 [1]/[2] 改为 [4]/[5]${NC}"
        fi
        if [ "$NO_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}  → ${NO_COUNT} 条确认无信息，请在源文件中标注「空信息需补充」${NC}"
        fi
        if [ "$UNSURE_COUNT" -gt 0 ]; then
            echo -e "  ${YELLOW}  → ${UNSURE_COUNT} 条不确定，建议标注「待采集」并附采集计划${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  未找到追问清单，请先运行 --interactive${NC}"
    fi
else
    # 非交互模式: 只检测，不追问
    if [ "$LOW_CONF" -gt 0 ] && [ "$UNVERIFIED" -eq 0 ]; then
        echo -e "  ${RED}❌ ${LOW_CONF} 条低置信度推断，但未标注「空信息需补充」${NC}"
        echo -e "  ${RED}→ 可能存在脑补。请用 --interactive 模式追问确认${NC}"
        FAILS=$((FAILS + 1))
        DETAILS="$DETAILS\n  [C5] ${LOW_CONF}条推断未标注空信息"
    elif [ "$LOW_CONF" -gt 0 ]; then
        echo -e "  ${GREEN}✅ 低置信度推断已标注空信息 (${LOW_CONF}推断 / ${UNVERIFIED}标注)${NC}"
    else
        echo -e "  ${GREEN}✅ 未检测到低置信度推断${NC}"
    fi
fi

echo ""

# ============================================================
# 约束 6: 过程完整性 — 防"漂亮报告绕过核心SOP"(v3.3)
# ============================================================
echo -e "${YELLOW}[约束 6] 过程完整性检查 — 防绕过核心 SOP${NC}"

# 6a. Phase 覆盖度: 5 Phase 至少 3 个有独立产出痕迹(非关键词堆砌)
HAS_CLUSTER=$(count_in_file '(聚类|桥接边|连通分量|cluster|bridge)')
HAS_TIME_ARROW=$(count_in_file '(↑|↓|时间方向|趋势反转|共同驱动力)')
HAS_STRUCT_SCAN=$(count_in_file '(介数中心性|最小割|betweenness|min.cut|结构扫描)')
PHASE_SCORE=0
[ "$HAS_UNKNOWN" -gt 0 ] && PHASE_SCORE=$((PHASE_SCORE + 1))      # Phase 0 种子
[ "$HAS_CLUSTER" -gt 0 ] && PHASE_SCORE=$((PHASE_SCORE + 1))       # Phase 1 扩展
[ "$HAS_CASCADE_TOTAL" -ge 2 ] && PHASE_SCORE=$((PHASE_SCORE + 1)) # Phase 2 扰动
[ "$HAS_TIME_ARROW" -gt 0 ] && PHASE_SCORE=$((PHASE_SCORE + 1))    # Phase 3 时间
[ "$HAS_STRUCT_SCAN" -gt 0 ] && PHASE_SCORE=$((PHASE_SCORE + 1))   # Phase 4 硬化

echo "  Phase 覆盖: ${PHASE_SCORE}/5 (需≥3)"
if [ "$PHASE_SCORE" -lt 3 ] && $IS_TOPOLOGY_REPORT; then
    echo -e "  ${RED}❌ Phase 覆盖不足——报告可能跳过了拓扑5阶段过程${NC}"
    FAILS=$((FAILS+1)); DETAILS="$DETAILS\n  [C6] Phase覆盖仅${PHASE_SCORE}/5"
else
    echo -e "  ${GREEN}✅ Phase 覆盖达标 (${PHASE_SCORE}/5)${NC}"
fi

# 6b. 自验证痕迹: 审计表或审计文件引用
HAS_AUDIT=$(count_in_file '(审计\|audit\|PASS/FAIL\|step.*audit\|自检\s*✅\|acceptance_criteria)')
if [ "$HAS_AUDIT" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠️  未检测到自验证审计痕迹——可能跳过了 self-verify 协议${NC}"
    WARNS=$((WARNS+1))
else
    echo -e "  ${GREEN}✅ 自验证痕迹存在${NC}"
fi

# 6c. CORE.md 引用: 是否读过核心 SOP
HAS_CORE_REF=$(count_in_file 'CORE\.md|核心SOP|初始化检查清单')
if [ "$HAS_CORE_REF" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠️  未引用 CORE.md——可能未执行初始化检查清单${NC}"
    WARNS=$((WARNS+1))
else
    echo -e "  ${GREEN}✅ CORE.md 引用存在${NC}"
fi

echo ""

# ============================================================
# 约束 7: 文件系统痕迹 — 防"报告写了但文件没建"(v3.4)
# ============================================================
echo -e "${YELLOW}[约束 7] 文件系统痕迹检查 — 过程文件必须存在${NC}"

# 从分析文件路径推导 run 目录
ANALYSIS_DIR=$(dirname "$ANALYSIS_FILE")
ANALYSIS_BASENAME=$(basename "$ANALYSIS_FILE")

# 策略1: 分析文件在 runs/{run_id}/ 下
if echo "$ANALYSIS_DIR" | $GREP -q 'runs/'; then
    RUN_DIR="$ANALYSIS_DIR"
else
    # 策略2: 分析文件同级有 runs/ 子目录
    if [ -d "$ANALYSIS_DIR/runs" ]; then
        # 找最近的 run 目录
        RUN_DIR=$(ls -dt "$ANALYSIS_DIR/runs"/*/ 2>/dev/null | head -1)
    else
        RUN_DIR=""
    fi
fi

# 7a. topology-state.json 深度验证（v3.5 字段级校验）
if [ -n "$RUN_DIR" ] && [ -f "$RUN_DIR/topology-state.json" ]; then
    HAS_PHASES=$(python3 "$TRIO_ROOT/scripts/_c7_validate.py" "$RUN_DIR/topology-state.json" 2>/dev/null || echo "0 PARSE_ERROR")
    PHASE_SCORE_JSON=$(echo "$HAS_PHASES" | awk '{print $1}')
    PHASE_DETAIL=$(echo "$HAS_PHASES" | cut -d' ' -f2-)

    if [ "$PHASE_SCORE_JSON" -ge 3 ]; then
        echo -e "  ${GREEN}✅ topology-state.json Phase覆盖 ${PHASE_SCORE_JSON}/5 (JSON字段校验)${NC}"
    elif [ "$PHASE_SCORE_JSON" -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️  topology-state.json Phase覆盖仅 ${PHASE_SCORE_JSON}/5 — ${PHASE_DETAIL}${NC}"
        WARNS=$((WARNS+1))
    else
        echo -e "  ${RED}❌ topology-state.json Phase字段为空或解析失败 — ${PHASE_DETAIL}${NC}"
        FAILS=$((FAILS+1)); DETAILS="$DETAILS\n  [C7] topology-state.json内容不完整"
    fi
elif $IS_TOPOLOGY_REPORT; then
    echo -e "  ${RED}❌ 未找到 topology-state.json——拓扑5阶段过程未持久化${NC}"
    FAILS=$((FAILS+1)); DETAILS="$DETAILS\n  [C7] topology-state.json缺失"
else
    echo -e "  ${CYAN}⊘ 非拓扑报告，跳过 topology-state.json 检查${NC}"
fi

# 7b. state.json 或 todo.md 必须存在（断点恢复能力）
if [ -n "$RUN_DIR" ] && [ -f "$RUN_DIR/state.json" ]; then
    RUN_STATUS=$(python3 -c "import json; d=json.load(open('$RUN_DIR/state.json')); print(d.get('status','?'))" 2>/dev/null || echo '?')
    echo -e "  ${GREEN}✅ state.json 存在 (status=${RUN_STATUS})${NC}"
elif [ -n "$RUN_DIR" ] && [ -f "$RUN_DIR/todo.md" ]; then
    echo -e "  ${GREEN}✅ todo.md 存在（轻量状态追踪）${NC}"
elif $IS_TOPOLOGY_REPORT; then
    echo -e "  ${RED}❌ 未找到 state.json 或 todo.md——无断点恢复能力${NC}"
    FAILS=$((FAILS+1)); DETAILS="$DETAILS\n  [C7] 状态文件缺失"
else
    echo -e "  ${CYAN}⊘ 非拓扑报告，跳过状态文件检查${NC}"
fi

echo ""

# ============================================================
# 约束 8: 反证覆盖率 — 核心结论翻转条件（v3.6 · WARN 级）
# 反证从深度模式扩展到所有引擎 run。现为 WARN——待【结论】显式标记写作规范定义后再议升级 FAIL。
# 纯附加：不触碰 C1-C7 任何变量/逻辑，只增 WARNS，不改退出码。
# ============================================================
echo -e "${YELLOW}[约束 8] 反证覆盖率 — 核心结论翻转条件（WARN 级）${NC}"

# 核心结论锚点(启发式): 高置信标记 [4][5] 或显式【结论】标记
CORE_CONCL=$(count_in_file '【结论】|\[4\]|\[5\]')
# 翻转条件语言
FLIP_COND=$(count_in_file '翻转条件|如果.{0,20}(发生|成立|为真|变化).{0,20}(作废|推翻|不成立|重估)|前提假设.{0,20}(不成立|变化)|可证伪|证伪条件|什么情况下.{0,10}(错|失效|作废)')
CORE_CONCL=$((CORE_CONCL))
# v3.8: 结构化可证伪格式 {metric, target, by}
STRUCTURED_FALSIFY=$(count_in_file '\{.{0,5}"metric".{0,30}"target".{0,30}"by"')
STRUCTURED_FALSIFY=$((STRUCTURED_FALSIFY))
FLIP_COND=$((FLIP_COND))

echo "  核心结论标记: ${CORE_CONCL}  翻转条件: ${FLIP_COND}  结构化: ${STRUCTURED_FALSIFY}"
if [ "$CORE_CONCL" -gt 0 ] && [ "$FLIP_COND" -eq 0 ] && [ "$STRUCTURED_FALSIFY" -eq 0 ]; then
    echo -e "  ${YELLOW}[WARN] ${CORE_CONCL} 处核心结论无翻转条件——建议 {metric, target, by} 格式${NC}"
    WARNS=$((WARNS+1))
elif [ "$STRUCTURED_FALSIFY" -gt 0 ]; then
    echo -e "  ${GREEN}[PASS] 结构化可证伪条件已标注 (${STRUCTURED_FALSIFY} 处)${NC}"
elif [ "$FLIP_COND" -gt 0 ]; then
    echo -e "  ${GREEN}[PASS] 反证/翻转条件已标注 (${FLIP_COND} 处)${NC}"
else
    echo -e "  ${CYAN}⊘ 未检测到核心结论标记，跳过 C8${NC}"
fi

echo ""

# ============================================================
# 约束 9: Bridge Lemma 门禁 — 防"领域映射≠逻辑绕过"范畴错误 (v3.7 · FAIL 级)
# Origin: P vs NP 多模型 TRIO 实验 (2026-07-13)
# 诊断: 8 个模型集体犯范畴错误——声称"用拓扑/几何绕过 Natural Proofs"
#   但屏障限制的是证明的逻辑结构(Constructivity/Largeness)，不是数学领域
#   换数学工具 ≠ 绕过逻辑屏障。要求桥接引理而非领域映射。
# ============================================================
echo -e "${YELLOW}[约束 9] Bridge Lemma 门禁 — 防范畴错误（领域映射≠逻辑绕过）${NC}"

# 检测"声称绕过屏障"的语言模式
HAS_BYPASS_CLAIM=$(count_in_file '(绕过|规避|跳出|突破|不受.{0,5}限制).{0,30}(屏障|障碍|限制|barrier|relativization|natural.proof|algebrization|不可能定理)')
# 检测是否提供了形式化桥接引理: 必须明确说出违反了屏障的哪个前提条件
HAS_BRIDGE_LEMMA=$(count_in_file '(桥接引理|bridge.lemma|违反.{0,10}(前提|条件|假设).{0,20}(因为|在于|由于)|该屏障.{0,5}(前提|条件|假设).{0,10}(不适用|不成立|被破坏))')

echo "  屏障绕过声称: ${HAS_BYPASS_CLAIM}  桥接引理: ${HAS_BRIDGE_LEMMA}"

if [ "$HAS_BYPASS_CLAIM" -gt 0 ] && [ "$HAS_BRIDGE_LEMMA" -eq 0 ]; then
    echo -e "  ${RED}❌ 检测到 ${HAS_BYPASS_CLAIM} 处声称绕过屏障，但未提供桥接引理${NC}"
    echo -e "  ${RED}→ 范畴错误风险: 「领域映射≠逻辑绕过」${NC}"
    echo -e "  ${RED}→ 要求提供: (1)屏障精确形式化条件 (2)违反哪个前提 (3)可证伪 bridge lemma${NC}"
    echo -e "  ${RED}→ 如无法回答(2)，标注「⚠️ 未建立桥接引理——此路径的绕过声称不成立」${NC}"
    FAILS=$((FAILS + 1))
    DETAILS="$DETAILS\n  [C9] ${HAS_BYPASS_CLAIM}处屏障绕过声称缺少桥接引理"
elif [ "$HAS_BYPASS_CLAIM" -gt 0 ]; then
    echo -e "  ${GREEN}✅ 屏障绕过声称附带了桥接引理 (${HAS_BRIDGE_LEMMA})${NC}"
else
    echo -e "  ${CYAN}⊘ 未检测到屏障绕过声称，跳过 C9${NC}"
fi

echo ""

# ============================================================
# JSON 输出（--json 模式，供 loop-engine 消费）
# ============================================================
SCORE=$(( 100 - FAILS * 15 - WARNS * 5 ))
[ "$SCORE" -lt 0 ] && SCORE=0

# 构建 fails/warns 数组
FAILS_JSON="["
WARNS_JSON="["
if [ -n "$DETAILS" ]; then
    FAILS_JSON+=$(echo -e "$DETAILS" | grep -oP '\[C\d[^\]]*\]' | sed 's/.*/"&"/' | paste -sd, -)
fi
FAILS_JSON+="]"
WARNS_JSON+="]"

CHECKS_JSON="{"
CHECKS_JSON+="\"C1_topology\":{\"pass\":$([ "$NODE_COUNT" -ge "$MIN_NODES" ] && [ "$EDGE_COUNT" -ge "$MIN_EDGES" ] && echo true || echo false),\"nodes\":$NODE_COUNT,\"edges\":$EDGE_COUNT},"
CHECKS_JSON+="\"C2_cascade\":{\"pass\":$([ "$HAS_CASCADE_TOTAL" -ge 2 ] && echo true || echo false),\"found\":$HAS_CASCADE_TOTAL,\"required\":2},"
CHECKS_JSON+="\"C3_vulnerability\":{\"pass\":$([ "$HAS_WEAK_LINK" -gt 0 ] && [ "$HAS_ATTACK" -gt 0 ] && echo true || echo false)},"
CHECKS_JSON+="\"C4_time\":{\"pass\":$([ "$STRENGTHEN_COUNT" -ge "$MIN_TIME_EDGES" ] && [ "$WEAKEN_COUNT" -ge "$MIN_TIME_EDGES" ] && echo true || echo false),\"strengthen\":$STRENGTHEN_COUNT,\"weaken\":$WEAKEN_COUNT},"
CHECKS_JSON+="\"C5_counter_evidence\":{\"pass\":$([ "$LOW_CONF" -eq 0 ] || [ "$COUNTER_RATIO" -ge 50 ] && echo true || echo false),\"coverage\":$COUNTER_RATIO},"
CHECKS_JSON+="\"C6_phase\":{\"pass\":$([ "$PHASE_SCORE" -ge 3 ] && echo true || echo false),\"score\":$PHASE_SCORE},"
CHECKS_JSON+="\"C7_filesystem\":{\"pass\":$([ "$HAS_AUDIT" -gt 0 ] && echo true || echo false)},"
CHECKS_JSON+="\"C8_reverse_evidence\":{\"warn_only\":true,\"core_conclusions\":$CORE_CONCL,\"flip_conditions\":$FLIP_COND},"
CHECKS_JSON+="\"C9_bridge_lemma\":{\"pass\":$([ "$HAS_BYPASS_CLAIM" -eq 0 ] || [ "$HAS_BRIDGE_LEMMA" -gt 0 ] && echo true || echo false),\"bypass_claims\":$HAS_BYPASS_CLAIM,\"bridge_lemmas\":$HAS_BRIDGE_LEMMA}"
CHECKS_JSON+="}"

if $JSON_MODE; then
    # 恢复 stdout，输出 JSON
    exec 1>&3
    python3 -c "
import json
print(json.dumps({
    'score': $SCORE,
    'fails': $FAILS,
    'warns': $WARNS,
    'checks': json.loads('''$CHECKS_JSON'''),
    'details': '$DETAILS'
}, ensure_ascii=False, indent=2))
" 2>/dev/null || echo "{\"score\":$SCORE,\"fails\":$FAILS,\"warns\":$WARNS,\"error\":\"json_gen_failed\"}"
    # JSON 模式下不输出人类可读汇总，直接退出
    [ "$FAILS" -eq 0 ] && exit 0 || exit 1
fi

# ============================================================
# 汇总
# ============================================================
echo -e "${CYAN}═══════════════════════════════════════${NC}"

if [ "$FAILS" -eq 0 ] && [ "$WARNS" -eq 0 ]; then
    echo -e "  ${GREEN}✅ 拓扑检查全部通过${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    exit 0
elif [ "$FAILS" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠️  通过 (${WARNS} 警告) — 建议修复${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    exit 0
else
    echo -e "  ${RED}❌ 未通过: ${FAILS} 项失败, ${WARNS} 项警告${NC}"
    echo -e "  ${RED}→ 禁止进入结论/交付阶段${NC}"
    echo -e "  ${RED}→ 缺失:${DETAILS}${NC}"

    # 自动记录违规
    mkdir -p "$(dirname "$VIOLATION_LOG")"
    echo "[$TIMESTAMP] $(basename "$ANALYSIS_FILE") | fail | ${FAILS}项失败 | 领域=$DOMAIN" >> "$VIOLATION_LOG"

    TOTAL_VIOLATIONS=$(wc -l < "$VIOLATION_LOG" 2>/dev/null || echo 0)
    if [ "$TOTAL_VIOLATIONS" -ge 3 ]; then
        echo -e "  ${RED}⚠️  累计违规 ${TOTAL_VIOLATIONS} 次 → 触发强制复盘${NC}"
    fi

    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    exit 1
fi
