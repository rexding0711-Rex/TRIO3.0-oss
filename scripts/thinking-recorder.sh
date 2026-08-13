#!/bin/bash
# TRIO 思维记录器——自动采集十维画像
# 每次会话结束自动运行→增量更新 user-profile.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIO_ROOT="${TRIO_ROOT:-$(dirname "$SCRIPT_DIR")}"

USER_PROFILE="${TRIO_USER_DIR:-$TRIO_ROOT/state}/user-profile.md"
BEHAVIOR_LOG="${TRIO_USER_DIR:-$TRIO_ROOT/state}/behavior-log.jsonl"
TEMPLATE="$TRIO_ROOT/config/user-profile-template.md"

# 初始化画像（首次使用）
init_profile() {
    [ -f "$USER_PROFILE" ] && return
    cp "$TEMPLATE" "$USER_PROFILE"
    echo "🧠 思维记录器已启动——你的数据只在你本地"
}

# 增量更新各维度
update_profile() {
    local log="$BEHAVIOR_LOG"
    [ ! -f "$log" ] && return

    # 1. 使用概览
    local total=$(wc -l < "$log")
    local first_date=$(head -1 "$log" | python3 -c "import json,sys; print(json.load(sys.stdin)['ts'][:10])" 2>/dev/null)
    local top_scenario=$(grep -oP '"event":"\K[^"]+' "$log" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
    local top_mask=$(grep -oP '"mask":"\K[^"]+' "$log" 2>/dev/null | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

    # 2. 决策风格——基于场景使用频率推断
    local deep_count=$(grep -c "尽调\|逆向\|deconstruct\|due_diligence" "$log" 2>/dev/null || echo 0)
    local quick_count=$(grep -c "速判\|quick" "$log" 2>/dev/null || echo 0)
    local style="平衡"
    [ "$deep_count" -gt $((quick_count * 2)) ] && style="深度分析"
    [ "$quick_count" -gt $((deep_count * 2)) ] && style="快速结论"

    # 3. 质疑倾向——基于DeepSeek使用频率推断
    local ds_count=$(grep -c "deepseek\|审计\|核查\|质疑" "$log" 2>/dev/null || echo 0)
    local total_runs=$(grep -c "run_start\|run_complete\|场景" "$log" 2>/dev/null || echo 1)
    local ds_ratio=$((ds_count * 100 / total_runs))
    local skepticism="平衡"
    [ "$ds_ratio" -gt 80 ] && skepticism="高度质疑"
    [ "$ds_ratio" -lt 20 ] && skepticism="接受型"

    # 4. 信息消化模式——基于行为序列推断
    local sequential=$(grep -c "step1.*step2\|step2.*step3\|顺序" "$log" 2>/dev/null || echo 0)
    local random_jump=$(grep -c "跳\|skip\|跳过" "$log" 2>/dev/null || echo 0)
    local digestion="分段消化"
    [ "$random_jump" -gt "$sequential" ] && digestion="随机跳转"

    # 5. 认知节奏——基于时间戳密度
    local morning=$(grep -c "T0[6-9]:\|T1[0-1]:" "$log" 2>/dev/null || echo 0)
    local afternoon=$(grep -c "T1[2-7]:" "$log" 2>/dev/null || echo 0)
    local night=$(grep -c "T1[8-9]:\|T2[0-3]:" "$log" 2>/dev/null || echo 0)
    local peak="上午"
    [ "$afternoon" -gt "$morning" ] && peak="下午"
    [ "$night" -gt "$afternoon" ] && peak="深夜"

    # 6. 压力反应——基于时间压力下的行为变化
    local rushed=$(grep -c "急\|快\|速\|赶\|deadline" "$log" 2>/dev/null || echo 0)
    local calm=$(grep -c "深思\|慢慢\|仔细\|详细" "$log" 2>/dev/null || echo 0)
    local pressure="不变"
    [ "$rushed" -gt "$calm" ] && pressure="时间压力下更果断"

    # 写入画像
    python3 << PYEOF
import re

with open('$USER_PROFILE') as f:
    profile = f.read()

# 使用概览
profile = re.sub(r'首次使用: \{日期\}', '首次使用: $first_date', profile)
profile = re.sub(r'总次数: \{N\}', '总次数: $total', profile)
profile = re.sub(r'最常用场景: \{场景\}', '最常用场景: $top_scenario', profile)
profile = re.sub(r'最常用面具: \{面具\}', '最常用面具: $top_mask', profile)
profile = re.sub(r'活跃时段: \{.*\}', '活跃时段: $peak', profile)

# 决策风格
profile = re.sub(r'\{数据驱动/直觉驱动/平衡\}', '$style', profile)
profile = re.sub(r'\{深度分析/快速结论/看情况\}', '$style', profile)

# 质疑倾向
profile = re.sub(r'\{高度质疑/接受型/看情况\}', '$skepticism', profile)

# 信息消化
profile = re.sub(r'\{一口气读完/分段消化/随机跳转\}', '$digestion', profile)

# 压力反应
profile = re.sub(r'\{时间压力下更果断/更犹豫/不变\}', '$pressure', profile)

with open('$USER_PROFILE', 'w') as f:
    f.write(profile)

PYEOF
    echo "📝 思维画像已更新"
}

# 显示回传指引
show_export_guide() {
    cat << 'GUIDE'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📤 分享你的思维画像给 用户
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  文件位置: user-data/user-profile.md
  包含内容: 你的使用习惯/思考偏好/知识盲区
  不包含: 你的具体分析内容/聊天记录/个人隐私

  发送方式: 把这个文件发给 用户
  你的收益: 帮助 TRIO 进化——更好地适应你的思维方式

  不想分享? 完全OK——你的数据永远只在你本地。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GUIDE
}

# 主流程
case "${1:-update}" in
    init)  init_profile ;;
    update) init_profile; update_profile ;;
    export) show_export_guide ;;
    *)     echo "用法: thinking-recorder {init|update|export}" ;;
esac
