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

cmd_behavior() {
    local event="${1:-ping}"
    local note="${2:-}"
    local ts=$(date -Iseconds)
    echo "{\"ts\":\"$ts\",\"event\":\"$event\",\"note\":\"$note\"}" >> "$TRIO_ROOT/state/behavior-log.jsonl"
    echo "📝 $event"
}

cmd_behavior_auto() {
    local log="$TRIO_ROOT/state/behavior-log.jsonl"
    local ref="$TRIO_ROOT/DAILY.md"  # 用DAILY作参考——比DAILY新的就是今天的变更
    local count=0

    # 用find -newer比DAILY.md更可靠(WSL兼容)
# @data-depends: DAILY.md 的mtime(用-newer检测变更)
# @炸点: DAILY.md未被日进化更新 → behavior_auto检测不到任何变更
    local changed=$(find "$TRIO_ROOT" \( -name "*.md" -o -name "*.json" -o -name "*.sh" \) -newer "$ref" 2>/dev/null | grep -v "state/\|.git/\|runs/" | head -30)

    # 检测ADR
    if echo "$changed" | grep -q "docs/adr/"; then
        cmd_behavior "架构决策" "新增或修改了ADR" > /dev/null 2>&1; count=$((count + 1))
    fi

    # 检测guard/layer/layers
    if echo "$changed" | grep -q "guard\|layer"; then
        cmd_behavior "系统防御" "更新了禁区守卫或层依赖规则" > /dev/null 2>&1; count=$((count + 1))
    fi

    # 检测scenario变更
    if echo "$changed" | grep -q "config/scenarios/"; then
        cmd_behavior "场景设计" "新增或修改了场景SOP" > /dev/null 2>&1; count=$((count + 1))
    fi

    # 检测role变更
    if echo "$changed" | grep -q "config/roles/"; then
        cmd_behavior "角色调整" "新增/吸收/修改了角色定义" > /dev/null 2>&1; count=$((count + 1))
    fi

    # 检测protocol变更
    if echo "$changed" | grep -q "config/protocols/"; then
        cmd_behavior "协议升级" "新增或修改了协议" > /dev/null 2>&1; count=$((count + 1))
    fi

    # 检测skills变更
    if echo "$changed" | grep -q "knowledge/skills/"; then
        cmd_behavior "技能沉淀" "从run中提取了可复用技能" > /dev/null 2>&1; count=$((count + 1))
    fi

    # 检测capability-stack
    if echo "$changed" | grep -q "capability-stack"; then
        cmd_behavior "能力栈调整" "修改了TRIO能力栈" > /dev/null 2>&1; count=$((count + 1))
    fi

    # 检测metrics/DAILY
    if echo "$changed" | grep -q "metrics\|DAILY"; then
        cmd_behavior "度量刷新" "更新了系统指标或每日总览" > /dev/null 2>&1; count=$((count + 1))
    fi

    # 检测mgmt.sh变更
    if echo "$changed" | grep -q "mgmt.sh"; then
        cmd_behavior "引擎升级" "修改了mgmt.sh管理脚本" > /dev/null 2>&1; count=$((count + 1))
    fi

    # 检测日进化命令变更
    if echo "$changed" | grep -q "日进化"; then
        cmd_behavior "进化引擎" "更新了日进化流程" > /dev/null 2>&1; count=$((count + 1))
    fi

    # 检测数据库变更(项目/Kimi产出)
    local db_changed=$(find /mnt/d/工作 \( -name "*.md" -o -name "*.json" \) -newer "$ref" 2>/dev/null | head -10)
    if echo "$db_changed" | grep -q "Kimi蒸馏"; then
        cmd_behavior "知识入库" "新增了Kimi蒸馏产出" > /dev/null 2>&1; count=$((count + 1))
    fi
    if echo "$db_changed" | grep -q "项目/"; then
        cmd_behavior "项目推进" "更新了项目文件" > /dev/null 2>&1; count=$((count + 1))
    fi

    echo "📝 自动记录 $count 条行为 (参考点: DAILY.md)"
}

cmd_behavior_report() {
    local log="$TRIO_ROOT/state/behavior-log.jsonl"
    echo "📊 TRIO 行为摘要"
    echo ""
    echo "总事件: $(wc -l < "$log")"
    echo "时间跨度: $(head -1 "$log" | python3 -c "import json,sys; print(json.load(sys.stdin)['ts'][:10])" 2>/dev/null) → $(tail -1 "$log" | python3 -c "import json,sys; print(json.load(sys.stdin)['ts'][:10])" 2>/dev/null)"
    echo ""
    echo "事件分布:"
    grep -oP '"event":"[^"]*"' "$log" | sort | uniq -c | sort -rn | head -10
    echo ""
    echo "最近5条:"
    tail -5 "$log" | while read line; do
        echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"  {d['ts'][:19]} | {d['event']:20s} | {d.get('note','')[:60]}\")" 2>/dev/null
    done
    # 心流检测：1小时内≥5条=心流时段
    echo ""
    python3 -c "
import json
from collections import defaultdict
events = []
with open('$log') as f:
    for line in f:
        try:
            d = json.loads(line.strip())
            events.append(d['ts'][:13])
        except: pass
hour_counts = defaultdict(int)
for e in events: hour_counts[e] += 1
flow_hours = {h:c for h,c in hour_counts.items() if c >= 5}
if flow_hours:
    print('🔥 心流时段:')
    for h, c in sorted(flow_hours.items()):
        print(f'  {h}:00 — {c} 条行为 → 心流达成')
else:
    print('📊 今日无心流时段')
" 2>/dev/null
    # 自动进化建议：异常节奏检测
    echo ""
    # 自适应阈值校准建议
    echo ""
    echo "📐 阈值校准建议 (基于近7天数据):"
    python3 -c "
import json
from datetime import datetime, timedelta
from collections import defaultdict
cutoff = (datetime.now() - timedelta(days=7)).isoformat()[:10]
daily_counts = defaultdict(int)
try:
    with open('') as f:
        for line in f:
            try:
                d = json.loads(line.strip())
                day = d['ts'][:10]
                if day >= cutoff:
                    daily_counts[day] += 1
            except: pass
except: pass
days = len(daily_counts)
if days >= 3:
    total = sum(daily_counts.values())
    avg = total / max(days, 1)
    peak = max(daily_counts.values()) if daily_counts else 0
    print(f'  日均行为: {avg:.1f} 条')
    print(f'  峰值: {peak} 条')
    suggest_high = max(int(avg * 2), 5)
    suggest_low = max(int(avg * 0.8), 2)
    print(f'  📊 建议depth高负载阈值: {suggest_high} (当前: 5)')
    print(f'  📊 建议depth中负载阈值: {suggest_low} (当前: 2)')
else:
    print('  数据不足(需≥3天)——保持当前阈值')
" 2>/dev/null
    # 置信度校准追踪
    echo ""
    echo "🎯 置信度校准 (基于assumption-log事后校验):"
    python3 -c "
import json, os, glob
log_dir = '/mnt/d/工作'
total_checks = 0
total_pass = 0
for f in glob.glob(os.path.join(log_dir, '**/assumption-log.md'), recursive=True):
    try:
        with open(f) as fh:
            content = fh.read()
            checked = content.count('✅成立') + content.count('❌不成立') + content.count('⚠️部分成立')
            passed = content.count('✅成立')
            partial = content.count('⚠️部分成立')
            total_checks += checked
            total_pass += passed + (partial * 0.5)
    except: pass
if total_checks >= 3:
    hit_rate = total_pass / total_checks * 100
    print(f'  总校验: {total_checks} 条假设')
    print(f'  命中率: {hit_rate:.0f}% ({total_pass:.0f}/{total_checks})')
    if hit_rate < 50:
        print(f'  ⚠️ DeepSeek置信度系统性偏乐观——需校准')
    elif hit_rate > 90:
        print(f'  ⚠️ DeepSeek可能过于保守——审视是否漏判风险')
    else:
        print(f'  ✅ 置信度校准合理区间(50-90%)')
else:
    print(f'  数据不足({total_checks}条校验)——需要更多run的假设校验')
" 2>/dev/null
    echo "🔍 异常节奏检测:"
    local anomalies=0
    local start_time=$(date +%s)

    # 1. 连续3天无run?
    local last_run=$(grep -oP '"event":"(?!日进化|SessionEnd|度量刷新|系统防御|引擎升级|场景设计|协议升级|角色调整|技能沉淀|能力栈调整|知识入库|项目推进|ADR更新|读书|架构决策|数据修复|苏格拉底发问|工程师修复)"' "$log" 2>/dev/null | tail -1 | grep -oP '\d{4}-\d{2}-\d{2}')
    if [ -n "$last_run" ]; then
        local days_since_run=$(( ($(date +%s) - $(date -d "$last_run" +%s)) / 86400 ))
        [ "$days_since_run" -ge 3 ] && { echo "  ⚠️  $days_since_run 天无实质性run——要开始吗？"; anomalies=$((anomalies + 1)); }
    fi

    # 2. 技能冷门?
    local cold_skills=$(find "$TRIO_ROOT/knowledge/skills/" -name "*.md" ! -name "INDEX.md" ! -name ".template.md" 2>/dev/null | wc -l)
    [ "$cold_skills" -gt 0 ] && { echo "  📋 $cold_skills 个技能可用——当前使用频率？"; }

    [ "$anomalies" -eq 0 ] && echo "  ✅ 节奏正常——无异常信号"
}

