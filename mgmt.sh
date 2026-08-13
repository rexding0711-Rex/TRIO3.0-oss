#!/bin/bash
# @layer: infra
# TRIO 3.0 管理脚本 v3.3 —— 总路由
# 子模块: scripts/{sync,guard,depth,behavior,daily-fill,backup,skills,kb-refresh}.sh
# 共享库: lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIO_ROOT="$SCRIPT_DIR"

# 加载共享库（统一错误处理）
source "$SCRIPT_DIR/lib/common.sh"

# 全局错误 trap（只设一次）
trap 'cmd_error "TRAP" "$?" "${BASH_COMMAND:-unknown}" "${FUNCNAME:-main}"' ERR

# 加载子模块（只含 cmd_* 函数）
source "$SCRIPT_DIR/scripts/sync.sh"
source "$SCRIPT_DIR/scripts/kb-refresh.sh"
source "$SCRIPT_DIR/scripts/guard.sh"
source "$SCRIPT_DIR/scripts/depth.sh"
source "$SCRIPT_DIR/scripts/behavior.sh"
source "$SCRIPT_DIR/scripts/daily-fill.sh"
source "$SCRIPT_DIR/scripts/backup.sh"
source "$SCRIPT_DIR/scripts/skills.sh"
source "$SCRIPT_DIR/scripts/classify.sh"

# pre-delivery: 一键交付前检查 = classify扫描 + topology门禁
cmd_pre_delivery() {
    local file="$1"
    local domain="${2:-general}"
    local fails=0

    echo "📦 TRIO 交付前检查 — $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M')"
    echo ""

    echo "── [1/2] 文件分类扫描 ──"
    cmd_classify scan
    echo ""

    echo "── [2/2] 拓扑检查门禁 (Python v4.0) ──"
    if [ -n "$file" ] && [ -f "$file" ]; then
        python3 "$SCRIPT_DIR/scripts/topology-check.py" "$file" "$domain" --pretty
        local topo_rc=$?
        [ "$topo_rc" -ne 0 ] && fails=$((fails + 1))
    else
        echo "⚠️  文件不存在: ${file:-未提供}"
        echo "用法: mgmt.sh pre-delivery <文件> [领域]"
        fails=$((fails + 1))
    fi

    echo ""
    if [ "$fails" -eq 0 ]; then
        echo "✅ 交付前检查全部通过"
    else
        echo "❌ ${fails} 项未通过 — 修复后重试"
    fi
}

# MAIN — 总路由
case "${1:-help}" in
    sync)             cmd_sync ;;
    post-session)     cmd_post_session
                       bash "$SCRIPT_DIR/scripts/thinking-recorder.sh" update 2>/dev/null || true ;;
    kb-refresh)       case "${2:-help}" in
                          next)   cmd_kb_refresh_next ;;
                          done)   cmd_kb_refresh_done "${3:-}" ;;
                          list)   cmd_kb_refresh_list "${3:-all}" ;;
                          reset)  cmd_kb_refresh_reset ;;
                          add)    cmd_kb_refresh_add "${3:-}" "${4:-}" "${5:-}" "${6:-}" ;;
                          skip)   cmd_kb_refresh_skip "${3:-}" ;;
                          help|*) cmd_kb_refresh_help ;;
                      esac ;;
    layer-check)      cmd_layer_check ;;
    guard)            cmd_guard ;;
    depth)            cmd_depth ;;
    behavior)         cmd_behavior "${2:-}" "${3:-}" ;;
    behavior-auto)    cmd_behavior_auto ;;
    behavior-report)  cmd_behavior_report ;;
    daily-fill)       cmd_daily_fill ;;
    backup)           cmd_backup ;;
    skill-extract)    cmd_skill_extract "${2:-}" "${3:-}" ;;
    time-sync)        bash "$SCRIPT_DIR/scripts/time-sync.sh" ;;
    query)            bash "$SCRIPT_DIR/scripts/query.sh" "${2:-stats}" "${3:-}" ;;
    state-check)      cmd_state_check "${2:-}" ;;
    classify)         cmd_classify "${2:-scan}" "${3:-}" ;;
    topology)         python3 "$SCRIPT_DIR/scripts/topology-check.py" "${2:-}" "${3:-general}" --pretty ;;
    topology-sh)      bash "$SCRIPT_DIR/scripts/topology-check.sh" "${2:-}" "${3:-general}" "${4:-}" ;;
    topology-json)    python3 "$SCRIPT_DIR/scripts/topology-check.py" "${2:-}" "${3:-general}" --json ;;
    topology-log)     cat "$SCRIPT_DIR/state/topology-violations.log" 2>/dev/null; cat "$SCRIPT_DIR/state/topology-scores.jsonl" 2>/dev/null | tail -10 ;;
    topology-reset)   rm "$SCRIPT_DIR/state/topology-violations.log" "$SCRIPT_DIR/state/topology-scores.jsonl" 2>/dev/null && echo "✅ 违规日志已重置" || echo "(无需重置)" ;;
    topology-history) python3 -c "
import json; import sys
try:
    with open('$SCRIPT_DIR/state/topology-scores.jsonl') as f:
        records = [json.loads(l) for l in f if l.strip()]
    if not records:
        print('(无历史记录)')
        sys.exit(0)
    print(f'{\"时间\":<22} {\"分数\":>5} {\"结果\":<6} {\"领域\":<16} {\"文件\"}')
    print('-' * 80)
    for r in records[-20:]:
        status = '✅' if r['passed'] else '❌'
        print(f'{r[\"timestamp\"][:19]:<22} {r[\"score\"]:>5} {status:<6} {r[\"domain\"]:<16} {r[\"file\"][-40:]}')
    scores = [r['score'] for r in records]
    avg = sum(scores) / len(scores)
    print(f'\\n平均分: {avg:.0f} | 最近: {scores[-1]} | 最高: {max(scores)} | 最低: {min(scores)} | 共 {len(scores)} 次')
except Exception as e:
    print(f'读取历史失败: {e}')
" ;;
    pre-delivery)     cmd_pre_delivery "${2:-}" "${3:-general}" ;;
    loop-status)      for f in "$SCRIPT_DIR/state/loop-"*.json; do
                          [ -f "$f" ] || { echo "(无 Loop 运行记录)"; continue; }
                          python3 -c "
import json; s=json.load(open('$f'))
print(f\"{s['run_id']} | {s['workflow']} | {s['status']} | 最佳得分: {s['best_score']} (第{s['best_iteration']}轮) | {s['stop_reason']}\")
" 2>/dev/null
                      done ;;
    loop-history)     for f in "$SCRIPT_DIR/state/loop-"*.json; do
                          [ -f "$f" ] || { echo "(无 Loop 运行记录)"; continue; }
                          python3 -c "
import json; s=json.load(open('$f'))
print(f\"\\n{'='*60}\")
print(f\"Run: {s['run_id']} | {s['workflow']} | {s['status']}\")
print(f\"目标: {s['target']}\")
print(f\"开始: {s['started_at']} | 结束: {s.get('completed_at','进行中')}\")
for it in s['iterations']:
    arrow = '↑' if it['improved'] else '↓'
    print(f\"  第{it['i']}轮: {it['score_before']} → {it['score_after']} {arrow}\")
print(f\"停止原因: {s['stop_reason']}\")
"
                      done ;;
    optimize)         bash "$SCRIPT_DIR/scripts/loop-engine.sh" topology-fix "${2:-}" --auto-fix ;;
    help|*)
        echo "TRIO 3.5 总路由"
        echo "  sync guard depth backup        核心巡检"
        echo "  time-sync                      时间戳对齐到系统时钟"
        echo "  post-session                   会话结束后处理（含思维记录器）"
        echo "  behavior[-auto|-report]        行为追踪"
        echo "  daily-fill skill-extract       日进化辅助"
        echo "  classify [scan|file]          文件自动分类与搬移"
        echo "  topology <文件> [领域]       拓扑检查门禁 (Python v4.0·默认)"
        echo "  topology-sh <文件> [领域]    拓扑检查门禁 (bash v3.7·回退)"
        echo "  topology-json <文件> [领域]  拓扑检查门禁 (JSON输出·机器消费)"
        echo "  topology-history             查看拓扑分数历史趋势"
        echo "  topology-log                 查看违规日志"
        echo "  topology-reset               重置违规日志+分数历史"
        echo "  pre-delivery <文件> [领域]  一键交付检查 (classify+topology·Python)"
        echo "  optimize <报告.md>            自动循环修复拓扑问题 (Loop Engine)"
        echo "  loop-status                  查看当前 Loop 运行状态"
        echo "  loop-history                 查看 Loop 运行历史详情"
        echo "  state-check layer-check        校验"
        echo "  kb-refresh                     知识刷新"
        ;;
esac
