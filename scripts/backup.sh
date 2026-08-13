#!/bin/bash
# @layer: infra
# ============================================================
# backup 子模块 — TRIO 数据备份
# 依赖: lib/common.sh（提供 $TRIO_ROOT、颜色常量）
# 被 mgmt.sh source，不独立执行
# ============================================================

cmd_backup() {
    local backup_dir="/mnt/d/工作/归档/TRIO-backups"
    mkdir -p "$backup_dir"
    local ts=$(date +%Y%m%d-%H%M)
    local archive="$backup_dir/trio-${ts}.tar.gz"
    (cd /mnt/d/TRIO\ 3.0 && tar -czf "$archive" --exclude=.git --exclude=state . 2>/dev/null)
    if [ -f "$archive" ]; then
        echo "📦 备份完成: trio-${ts}.tar.gz ($(du -h "$archive" | cut -f1))"
        ls -t "$backup_dir"/trio-*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null
    else
        echo "⚠️ 备份失败"
    fi
}
