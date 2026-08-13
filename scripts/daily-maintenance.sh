#!/bin/bash
# @layer: infra
# TRIO 3.0 每日维护脚本 v1.0
# 用途: 统一执行所有日常维护任务，由 cron 或 SessionStart 触发
# cron: 57 8 * * * bash "/mnt/d/TRIO 3.0/scripts/daily-maintenance.sh"

set -euo pipefail

TRIO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$TRIO_ROOT/state/maintenance.log"
NOW=$(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M')

exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "══════════════════════════════════════════"
echo "  TRIO 每日维护 — $NOW"
echo "══════════════════════════════════════════"
echo ""

fails=0

run_step() {
    local name="$1"
    local cmd="$2"
    echo "── [$name] ──"
    if eval "$cmd" 2>&1; then
        echo "   ✅ 完成"
    else
        echo "   ⚠️ 跳过（非致命）"
        fails=$((fails + 1))
    fi
    echo ""
}

# 1. 时间戳同步
run_step "时间同步" "bash '$TRIO_ROOT/scripts/time-sync.sh'"

# 2. 数据同步
run_step "数据同步" "bash '$TRIO_ROOT/mgmt.sh' sync"

# 3. Git 自动提交
run_step "Git提交" "cd '$TRIO_ROOT' && git add -A && git diff --cached --quiet || git commit -m 'auto: 每日维护 $(TZ=Asia/Shanghai date +%Y-%m-%d)'"

# 4. 备份
run_step "备份" "bash '$TRIO_ROOT/mgmt.sh' backup 2>/dev/null || echo '   (备份脚本待完善)'"

# 5. 知识库过期检查
run_step "知识库检查" "bash '$TRIO_ROOT/mgmt.sh' kb-refresh list 2>&1 | grep -E '🔴|🟡|过期' || echo '   ✅ 无过期项'"

# 6. Decision Ledger 过期记忆扫描 (2026-07-31 新增 · R10知识库腐化)
run_step "决策账本过期扫描" "python3 -c \"
import sqlite3, json
from datetime import datetime
from pathlib import Path
DB = Path('/mnt/d/Agent文件/TRIO-Stock/state/decision-ledger.db')
if DB.exists():
    conn = sqlite3.connect(str(DB))
    now = datetime.now().strftime('%Y-%m-%d')
    expired = conn.execute(
        'SELECT memory_id, topic, review_at FROM memories WHERE review_at < ? AND lifecycle_status = \\\"active\\\"',
        (now,)
    ).fetchall()
    if expired:
        print(f'🔴 {len(expired)} 条记忆已过期:')
        for mem_id, topic, review_at in expired[:10]:
            print(f'   · {topic} (review_at={review_at})')
        # 写入告警
        alert_msg = f'{now} | Decision Ledger: {len(expired)}条记忆过期'
        with open('/mnt/d/TRIO 3.0/state/alerts.log', 'a') as f:
            f.write(alert_msg + '\\\\n')
    else:
        print('   ✅ 无过期记忆')
    conn.close()
else:
    print('   ℹ️ Decision Ledger 不存在，跳过')
\""

echo ""
echo "═══ [告警检查] ═══"
ALERTS=""
# 拓扑违规过多
if [ -f "$TRIO_ROOT/state/topology-violations.log" ]; then
    V_COUNT=$(grep -c "fail" "$TRIO_ROOT/state/topology-violations.log" 2>/dev/null || echo 0)
    [ "$V_COUNT" -gt 50 ] && ALERTS="$ALERTS⚠️ 拓扑违规 ${V_COUNT} 条（>50）\n"
fi
# 技术债积压
if [ -f "$TRIO_ROOT/state/tech-debt.md" ]; then
    DEBT_OPEN=$(grep -c '📋' "$TRIO_ROOT/state/tech-debt.md" 2>/dev/null || echo 0)
    [ "$DEBT_OPEN" -gt 5 ] && ALERTS="$ALERTS⚠️ 技术债 ${DEBT_OPEN} 项未处理\n"
fi
# 测试失败
if [ -f "$TRIO_ROOT/state/test-results.log" ]; then
    grep -q "FAILED" "$TRIO_ROOT/state/test-results.log" 2>/dev/null && ALERTS="$ALERTS⚠️ pytest 有失败\n"
fi
# 评分退化
python3 -c "
import json
lines = [l for l in open('$TRIO_ROOT/state/run-history.jsonl') if l.strip()]
if len(lines) >= 5:
    scores = [json.loads(l).get('composite_score',0) for l in lines[-5:]]
    drops = sum(1 for i in range(1,len(scores)) if scores[i] < scores[i-1])
    if drops >= 3: print('DEGRADATION')
" 2>/dev/null | grep -q "DEGRADATION" && ALERTS="$ALERTS🚨 评分连续下降（最近5次中3次下跌）\n"
# post_mortem过浅
python3 -c "
import json
lines = [json.loads(l) for l in open('$TRIO_ROOT/state/run-history.jsonl') if l.strip()]
shallow = [r for r in lines[-5:] if len(r.get('post_mortem','')) < 15]
if len(shallow) >= 3: print('SHALLOW')
" 2>/dev/null | grep -q "SHALLOW" && ALERTS="$ALERTS⚠️ 最近5次post_mortem中3次过浅\n"

if [ -n "$ALERTS" ]; then
    echo "🚨 告警:"
    echo -e "$ALERTS"
    echo "[$(date '+%Y-%m-%d %H:%M')] $ALERTS" >> "$TRIO_ROOT/state/alerts.log"
else
    echo "  ✅ 系统健康，无告警"
fi

echo ""
echo "══════════════════════════════════════════"
echo "  完成 — $fails 项非致命跳过"
echo "══════════════════════════════════════════"
