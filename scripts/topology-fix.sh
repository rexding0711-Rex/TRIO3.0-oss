#!/usr/bin/env bash
# ============================================================
# @layer: orchestration
# TRIO 3.0 拓扑自动修复 — 安全修复，不改分析内容
# 用法: bash topology-fix.sh <报告.md>
#
# 安全边界（铁律）:
#   ✅ 允许: 补 Mermaid ??? 节点、补反证模板标记、删除冗余词
#   ❌ 禁止: 修改分析结论、数据、推理链、事实性内容
#
# 设计原则: 只做"缺标记→补标记"，不做"错内容→改内容"
# ============================================================
set -euo pipefail

TARGET="${1:-}"
[ -z "$TARGET" ] && { echo "用法: $0 <报告.md>"; exit 1; }
[ ! -f "$TARGET" ] && { echo "❌ 文件不存在: $TARGET"; exit 1; }

FIXES_APPLIED=0

echo "🔧 拓扑自动修复 — $(basename "$TARGET")"
echo ""

# ── 修复 1: 无反脑补标记 → 在第一个 Mermaid 图末尾加 ??? 节点 ──
if ! grep -qP '\?\?\?' "$TARGET" 2>/dev/null; then
    if grep -qP '```mermaid' "$TARGET" 2>/dev/null; then
        python3 -c "
import re
content = open('$TARGET', 'r').read()
match = re.search(r'\`\`\`mermaid\n(.*?)\`\`\`', content, re.DOTALL)
if match:
    block = match.group(0)
    new_block = block.replace('\`\`\`', '    UNKNOWN[\"❓ 待验证\"]\n    UNKNOWN -.->|不确定| N[\"需确认\"]\n\`\`\`', 1)
    content = content.replace(block, new_block, 1)
    open('$TARGET', 'w').write(content)
    print('  ✅ 已添加反脑补标记 (??? 节点 + 虚线边)')
"
        FIXES_APPLIED=$((FIXES_APPLIED + 1))
    else
        echo "  ⚠️ 无 Mermaid 图，跳过反脑补标记（需手动添加拓扑图）"
    fi
fi

# ── 修复 2: 低置信度 [1]/[2] 无反证提示 → 追加模板 ──
# 使用 grep -c 而非 grep -cP，避免 PCRE 多行输出问题
LOW_CONF_COUNT=$(grep -cE '\[1\]|\[2\]' "$TARGET" 2>/dev/null || printf '0')
COUNTER_COUNT=$(grep -cE '反证|为什么不成立|什么条件下不' "$TARGET" 2>/dev/null || printf '0')
# 确保单行数字
LOW_CONF_COUNT=$(echo "$LOW_CONF_COUNT" | head -1)
COUNTER_COUNT=$(echo "$COUNTER_COUNT" | head -1)

if [ "$LOW_CONF_COUNT" -gt 0 ] 2>/dev/null && [ "$COUNTER_COUNT" -eq 0 ] 2>/dev/null; then
    python3 -c "
content = open('$TARGET', 'r').read()
lines = content.split('\n')
for i, line in enumerate(lines):
    if '[1]' in line or '[2]' in line:
        if '反证' not in line:
            lines[i] = line.rstrip() + ' （反证: 什么条件下不成立？）'
        break
open('$TARGET', 'w').write('\n'.join(lines))
print('  ✅ 已追加反证提示模板')
"
    FIXES_APPLIED=$((FIXES_APPLIED + 1))
elif [ "$LOW_CONF_COUNT" -gt 0 ] 2>/dev/null; then
    echo "  ⊘ 反证标记已存在，跳过"
fi

# ── 修复 3: 删除冗余词（CORE.md 规则 8）──
# 使用 Python 统一处理，避免 Shell 循环中的 PCRE/sed 兼容问题
python3 -c "
import re
content = open('$TARGET', 'r').read()
patterns = [
    '以下为(?!图|表|所示)',
    '如下(?!图|表|所示)',
    '值得注意的是',
    '需要指出的是',
    '显而易见',
    '毋庸置疑',
    '众所周知',
    '不难发现',
    '可以看出',
    '我们来看看',
]
removed = 0
for p in patterns:
    matches = len(re.findall(p, content))
    if matches > 0:
        content = re.sub(p, '', content)
        removed += matches
open('$TARGET', 'w').write(content)
if removed > 0:
    print(f'  ✅ 已删除 {removed} 处冗余词汇')
else:
    print('  ⊘ 未检测到冗余词汇')
"
# 检查 Python 脚本是否应用了修复（通过检查 stdout 输出即可）
# FIXES_APPLIED 在这里不增量，因为冗余词删除是美化而非结构修复

# ── 修复 4: 标题含方法论标注 → 清理 ──
python3 -c "
import re
content = open('$TARGET', 'r').read()
new_content = re.sub(r'（topology-state\.json 自动生成）', '', content)
new_content = re.sub(r'（topology-check\.sh[^）]*）', '', new_content)
if new_content != content:
    open('$TARGET', 'w').write(new_content)
    print('  ✅ 已清理方法论标注')
else:
    print('  ⊘ 未检测到方法论标注')
"

echo ""
echo "  ✅ 自动修复完成"
