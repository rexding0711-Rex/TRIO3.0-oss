#!/bin/bash
# @layer: infra
# ============================================================
# sync 子模块 — 数据同步 & post-session 处理
# 依赖: lib/common.sh（提供 $TRIO_ROOT、$CONFIG_DIR、颜色、today()、log_history()）
# 被 mgmt.sh source，不独立执行
# ============================================================

cmd_sync() {
    local now=$(today)

    echo "═══════════════════════════════════════════════════════════"
    echo "  🔄 TRIO 数据同步 — $now"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # 1. 从文件系统读取真实数据
    local total_runs
    total_runs=$(find "$TRIO_ROOT/runs/" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | xargs)
    total_runs=${total_runs:-0}
    local total_companies
    total_companies=$(find "/mnt/d/工作/对标库/company-benchmark/" -mindepth 1 -maxdepth 1 -type d ! -name "*.md" 2>/dev/null | wc -l | xargs)
    total_companies=${total_companies:-0}
    local total_topics
    total_topics=$(grep -c '^[a-z]' "$TOPICS_FILE" 2>/dev/null || echo "0")
    local total_people
    total_people=$(find "/mnt/d/工作/对标库/person-benchmark/" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | xargs)
    total_people=${total_people:-0}
    local people_cards
    people_cards=$(find "/mnt/d/工作/对标库/person-benchmark/" -name "*.md" 2>/dev/null | wc -l | xargs)
    people_cards=${people_cards:-0}

    echo "  真实数据:"
    echo "    runs: $total_runs"
    echo "    公司: $total_companies"
    echo "    kb-refresh: $total_topics 主题"
    echo "    人物索引: $total_people 人 ($people_cards 张详卡)"
    echo ""

    # 2. 更新 metrics.md（Python按列名匹配，非sed硬正则）
    local metrics_file="$TRIO_ROOT/metrics.md"
    if [ -f "$metrics_file" ]; then
# @data-depends: metrics.md 列名("累计 run 数","累计 /逆向工程 公司数","company-library 公司数")
# @data-depends: DAILY.md 列名("公司库","run数")
# @炸点: 列名更改 → Python regex匹配失败 → 数据不同步
        python3 "$TRIO_ROOT/scripts/sync_metrics.py" metrics "$metrics_file" \
            "累计 run 数=$total_runs" \
            "累计 \`/逆向工程\` 公司数=$total_companies" \
            "company-library 公司数=$total_companies" \
            2>/dev/null || echo "⚠️ metrics同步失败"
        echo "  ✅ metrics.md 已同步"
    fi

    # 3. 更新 DAILY.md
    local daily_file="$TRIO_ROOT/DAILY.md"
    if [ -f "$daily_file" ]; then
        python3 "$TRIO_ROOT/scripts/sync_metrics.py" daily "$daily_file" \
            "公司库=$total_companies" \
            "run数=$total_runs" \
            2>/dev/null || echo "⚠️ DAILY同步失败"
        echo "  ✅ DAILY.md 已同步"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  ✅ 全部同步完成"
    echo "═══════════════════════════════════════════════════════════"
}

cmd_post_session() {
    local now=$(date '+%Y-%m-%d %H:%M')
    local timestamp_file="$CONFIG_DIR/last_session.txt"
    echo "📋 Post-Session 处理 — $now"
    cmd_sync
    if [ -f "$timestamp_file" ]; then
        local new_runs
        new_runs=$(find "$TRIO_ROOT/runs/" -maxdepth 1 -type d -newer "$timestamp_file" 2>/dev/null | wc -l | xargs)
        new_runs=${new_runs:-0}
        echo "  新 run: $new_runs 个"
    fi
    date '+%Y-%m-%d %H:%M' > "$timestamp_file"

    # 承诺追踪器检查
    local tracker_file="$TRIO_ROOT/metrics/commitment-tracker.md"
    if [ -f "$tracker_file" ]; then
        local overdue
        overdue=$(python3 -c "
with open('$tracker_file') as f:
    content = f.read()
today = '$(today)'
overdue_count = 0
# 按列解析表（7列: ID | 内容 | 承诺日 | 目标日 | 状态 | 完成日 | 备注）
# 比 regex 更稳健——不依赖列间空格数量
for line in content.split('\n'):
    if not line.startswith('| C'):
        continue
    cols = [c.strip() for c in line.split('|')]
    if len(cols) < 8:  # 前导空+7列+尾空 = 至少 9 段
        continue
    cid, desc, made, target, status = cols[1], cols[2], cols[3], cols[4], cols[5]
    if status == '🟡' and target < today[5:]:  # 'MM-DD' < today's 'MM-DD'
        overdue_count += 1
print(overdue_count)
" 2>/dev/null || echo 0)
        overdue=${overdue:-0}
        if [ "$overdue" -gt 0 ]; then
            echo "  ⚠️ 承诺追踪器: $overdue 项逾期未完成 → metrics/commitment-tracker.md"
        fi

        # v2 熵减引擎: 计算系统熵状态并更新 tracker
        local entropy_script="$TRIO_ROOT/scripts/entropy-check.py"
        if [ -f "$entropy_script" ]; then
            local entropy_out
            entropy_out=$(python3 "$entropy_script" "$tracker_file" --update 2>/dev/null || echo "0 0.0 stable")
            local e_count e_total e_trend
            read e_count e_total e_trend <<< "$entropy_out"
            echo "  📊 熵减引擎: ${e_count}活跃, 系统总熵=${e_total}, 趋势=${e_trend}"
        fi
    fi

    log_history "system" "post-session" "处理完成"
}
