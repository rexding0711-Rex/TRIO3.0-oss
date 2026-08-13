#!/bin/bash
# @layer: infra
# TRIO 3.0 Cron 安装脚本 v1.0
# 用法: bash scripts/trio-cron-setup.sh [install|show|remove]

set -euo pipefail

TRIO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRIO_ROOT_WIN="D:\\\\TRIO 3.0"
MARKER="# TRIO-3.0-auto"

cron_install() {
    echo "📅 安装 TRIO cron 任务..."
    local tmpfile=$(mktemp)
    crontab -l 2>/dev/null | grep -v "$MARKER" > "$tmpfile" || true

    cat >> "$tmpfile" << 'CRONEOF'
# TRIO-3.0-auto: 每日维护 (8:57)
57 8 * * * bash "/mnt/d/TRIO 3.0/scripts/daily-maintenance.sh" 2>&1 | tee -a "/mnt/d/TRIO 3.0/state/cron.log"
# TRIO-3.0-auto: 能力镜像提醒 (每周三 9:03)
3 9 * * 3 echo "[TRIO] 能力镜像到期 — 运行 /claude → /能力镜像" >> "/mnt/d/TRIO 3.0/state/cron-reminders.log"
# TRIO-3.0-auto: 知识库刷新检查 (每周一 9:07)
7 9 * * 1 bash "/mnt/d/TRIO 3.0/mgmt.sh" kb-refresh list 2>&1 | grep -E "🔴|过期" >> "/mnt/d/TRIO 3.0/state/cron-reminders.log" || true
CRONEOF

    crontab "$tmpfile"
    rm "$tmpfile"
    echo "✅ cron 已安装"
    echo ""
    crontab -l | grep "$MARKER"
}

cron_show() {
    echo "📋 当前 TRIO cron:"
    crontab -l 2>/dev/null | grep "$MARKER" || echo "(无 TRIO cron)"
}

cron_remove() {
    echo "🗑 移除 TRIO cron..."
    local tmpfile=$(mktemp)
    crontab -l 2>/dev/null | grep -v "$MARKER" > "$tmpfile" || true
    crontab "$tmpfile"
    rm "$tmpfile"
    echo "✅ 已移除"
}

case "${1:-install}" in
    install) cron_install ;;
    show)    cron_show ;;
    remove)  cron_remove ;;
    *)       echo "用法: $0 [install|show|remove]" ;;
esac
