#!/bin/bash
# @layer: infra
# ============================================================
# guard 子模块 — 层依赖校验 & 禁区扫描
# 依赖: lib/common.sh（提供 $TRIO_ROOT、guard_error()）
# 被 mgmt.sh source，不独立执行
# ============================================================

cmd_layer_check() {
    local layers_json="$TRIO_ROOT/config/layers.json"
    local violations=0

    echo "🔍 层依赖校验 — $(date '+%Y-%m-%d %H:%M')"
    echo ""

    # 规则：检查进化层文件是否引用了知识层内部字段（同层互拷）
    echo "  [1] 进化层 ←→ 知识层 同层互拷检查..."
    if grep -q "metrics" "$TRIO_ROOT/DAILY.md" 2>/dev/null; then
        echo "    ⚠️ DAILY.md(进化层) 引用 metrics.md(进化层同层) — 应通过mgmt.sh"
        violations=$((violations + 1))
    fi

    # 规则：知识层不能引用进化层
    echo "  [2] 知识层 → 进化层 反向依赖检查..."
    local rev_deps=$(grep -rl "DAILY.md\|metrics.md\|ADR-" "$TRIO_ROOT/knowledge/" "$TRIO_ROOT/docs/" 2>/dev/null | grep -v ".jsonl" | head -5)
    if [ -n "$rev_deps" ]; then
        echo "    ⚠️ 知识层文件引用了进化层:"
        echo "$rev_deps" | while read f; do echo "      $f"; done
        violations=$((violations + 1))
    fi

    # 规则：所有新文件必须有 @layer 标签
    echo "  [3] 未标记层归属的文件..."
    local untagged=$(find "$TRIO_ROOT" -name "*.md" -path "*/knowledge/*" -o -name "*.md" -path "*/docs/*" 2>/dev/null | while read f; do
        head -1 "$f" 2>/dev/null | grep -q "@layer:" || echo "      $f"
    done | head -5)
    if [ -n "$untagged" ]; then
        echo "    ⚠️ knowledge/docs 中有文件未标记层:"
        echo "$untagged"
        violations=$((violations + 1))
    fi

    echo ""
    if [ "$violations" -eq 0 ]; then
        echo "  ✅ 层依赖全部合规"
    else
        echo "  🔴 $violations 项违规——修复后才能继续"
    fi
}

cmd_guard() {
    local violations=0
    local guard_json="$TRIO_ROOT/config/guard.json"
    echo "🛡️ TRIO 禁区扫描"
    echo ""

    # 1. 禁止的扩展名
    # @data-depends: guard.json forbidden字段(extensions/patterns/naming_rule)
    # @炸点: 字段重命名 → Python读取失败 → guard静默失效
    local exts=$(python3 -c "import json; print(' '.join(json.load(open('$guard_json'))['forbidden']['extensions']))" 2>/dev/null)
    for ext in $exts; do
        local found=$(find "$TRIO_ROOT" -name "*$ext" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | grep -v "guard.json" | head -5)
        if [ -n "$found" ]; then
            echo "  🔴 非法扩展名 $ext:"
            echo "$found" | while read f; do echo "     $f"; done
            local count
            count=$(echo "$found" | wc -l | xargs)
            count=${count:-0}
            violations=$((violations + count))
        fi
    done

    # 2. 禁止的项目关键词
    local patterns=$(python3 -c "import json; print('|'.join(json.load(open('$guard_json'))['forbidden']['patterns']))" 2>/dev/null | sed 's/\*//g')
    if [ -n "$patterns" ]; then
        local pattern_hits=$(find "$TRIO_ROOT" -type f -name "*.md" -not -path "*/.git/*" -not -path "*/config/*" -not -path "*/.claude/*" -not -path "*/knowledge/lessons-learned/*" 2>/dev/null | xargs -I{} basename {} 2>/dev/null | grep -iE "$patterns" | head -5)
        if [ -n "$pattern_hits" ]; then
            echo "  🟡 可疑项目关键词文件名:"
            echo "$pattern_hits" | while read f; do echo "     $f"; done
            local hit_count
            hit_count=$(echo "$pattern_hits" | wc -l | xargs)
            hit_count=${hit_count:-0}
            violations=$((violations + hit_count))
        fi
    fi

    echo ""
    if [ "$violations" -eq 0 ]; then
        echo "  ✅ TRIO 禁区干净——无项目文件污染"
    else
        echo "  ⛔ $violations 个违规文件——操作系统被污染，立即清理！"
        echo "  规则: 项目文件归 D:\\工作\\项目\\{项目名}\\"
        guard_error
    fi
    # 协议v1.1: 30s超时保护
    return $violations
}
