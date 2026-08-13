#!/bin/bash
# @layer: infra
# ============================================================
# classify 子模块 — 文件自动分类与搬移
# 依赖: lib/common.sh、config/file-routing.json
# 被 mgmt.sh source，不独立执行
# ============================================================

cmd_classify() {
    local mode="${1:-scan}"
    local routing_json="$TRIO_ROOT/config/file-routing.json"

    case "$mode" in
        scan)   classify_scan ;;
        file)   classify_file "${2:-}" ;;
        help|*) classify_help ;;
    esac
}

classify_scan() {
    local routing_json="$TRIO_ROOT/config/file-routing.json"
    local auto_count=0 ask_count=0

    echo "📂 TRIO 文件分类扫描 — $(date '+%Y-%m-%d %H:%M')"
    echo ""

    # 遍历 routes，逐个匹配
    local route_count=$(python3 -c "import json; print(len(json.load(open('$routing_json'))['routes']))" 2>/dev/null)
    if [ -z "$route_count" ] || [ "$route_count" -eq 0 ]; then
        echo "  ⚠️ 路由表为空或解析失败"
        return 1
    fi

    for i in $(seq 0 $((route_count - 1))); do
        local route_id=$(python3 -c "import json; print(json.load(open('$routing_json'))['routes'][$i]['id'])" 2>/dev/null)
        local auto=$(python3 -c "import json; print(str(json.load(open('$routing_json'))['routes'][$i].get('auto', True)).lower())" 2>/dev/null)
        local desc=$(python3 -c "import json; print(json.load(open('$routing_json'))['routes'][$i]['description'])" 2>/dev/null)
        local dest=$(python3 -c "import json; print(json.load(open('$routing_json'))['routes'][$i]['dest'])" 2>/dev/null)

        # 获取 source_patterns
        local patterns=$(python3 -c "
import json
route = json.load(open('$routing_json'))['routes'][$i]
patterns = route.get('source_patterns', [])
print('\n'.join(patterns))
" 2>/dev/null)

        if [ -z "$patterns" ]; then continue; fi

        # 对每个 pattern 查找匹配文件
        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            # 跳过 forbidden 路由（它匹配所有文件，单独处理）
            [ "$route_id" = "forbidden_in_os" ] && continue

            local found=$(find "$TRIO_ROOT" -path "$TRIO_ROOT/$pattern" -not -path "*/.git/*" -not -path "*/.claude/*" 2>/dev/null | head -20)
            if [ -n "$found" ]; then
                echo "  [$route_id] $desc"
                echo "    目标: ${dest//\\/}"
                while IFS= read -r f; do
                    [ -z "$f" ] && continue
                    local fname=$(basename "$f")
                    local win_dest=$(echo "$dest" | sed "s|{name}|$fname|g" | sed 's|D:\\|/mnt/d/|g' | sed 's|\\|/|g')

                    if [ "$auto" = "true" ]; then
                        mkdir -p "$(dirname "$win_dest")"
                        mv "$f" "$win_dest" 2>/dev/null && echo "    ✅ $fname" || echo "    ❌ 搬移失败: $fname"
                        auto_count=$((auto_count + 1))
                    else
                        echo "    🟡 待确认: $fname → $(echo "$dest" | sed 's|{name}|'"$fname"'|g')"
                        ask_count=$((ask_count + 1))
                    fi
                done <<< "$found"
            fi
        done <<< "$patterns"
    done

    # 检查 forbidden 规则（二进制文件）
    echo ""
    echo "  [forbidden] 扫描禁止的二进制文件..."
    local forbidden=$(python3 -c "import json; p=json.load(open('$routing_json'))['routes']; forbidden=[r for r in p if r['id']=='forbidden_in_os'][0]; print('|'.join([x.replace('*.','.+\.') + '\$' for x in forbidden['source_patterns']]))" 2>/dev/null)
    local bins=$(find "$TRIO_ROOT" -type f -not -path "*/.git/*" -not -path "*/.claude/*" 2>/dev/null | grep -E "$forbidden" | head -10)
    if [ -n "$bins" ]; then
        while IFS= read -r bf; do
            echo "    🔴 违规: $(basename "$bf")"
            ask_count=$((ask_count + 1))
        done <<< "$bins"
    else
        echo "    ✅ 无二进制文件"
    fi

    echo ""
    echo "  📊 汇总: $auto_count 个已自动搬移 | $ask_count 个需用户确认"
}

classify_file() {
    local file="$1"
    if [ -z "$file" ]; then
        echo "用法: mgmt.sh classify file <路径>"
        return 1
    fi
    echo "📎 单文件分类: $file"
    echo "  ⚠️ 尚未实现——请用 mgmt.sh classify scan"
}

classify_help() {
    echo "TRIO classify — 文件自动分类与搬移"
    echo "  mgmt.sh classify scan       全量扫描并分类"
    echo "  mgmt.sh classify file <路径> 单文件分类（开发中）"
    echo ""
    echo "路由规则: config/file-routing.json"
    echo "不确定时输出 ASK 列表，禁止自动搬移"
}

# Auto-classify on session start (quick mode)
classify_quick() {
    local routing_json="$TRIO_ROOT/config/file-routing.json"
    local new_files=0

    # 只检查禁止的二进制文件（快速模式）
    local forbidden=$(python3 -c "
import json
routes = json.load(open('$routing_json'))['routes']
forbidden_route = [r for r in routes if r['id'] == 'forbidden_in_os']
if forbidden_route:
    patterns = forbidden_route[0]['source_patterns']
    print('|'.join([p.replace('*.', '.') for p in patterns]))
" 2>/dev/null)

    if [ -n "$forbidden" ]; then
        local bins=$(find "$TRIO_ROOT" -type f -not -path "*/.git/*" -not -path "*/.claude/*" 2>/dev/null | grep -E "$forbidden" | wc -l)
        if [ "$bins" -gt 0 ]; then
            echo "⚠️ TRIO OS 中有 $bins 个二进制文件待清理。运行: mgmt.sh classify scan"
        fi
    fi
}
