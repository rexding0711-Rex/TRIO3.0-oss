#!/bin/bash
# TRIO Stop Hook 校验脚本
# 在每次 Claude 回复完成后自动触发，检查常见错误
# Stop hook 传入 JSON: {"stop_reason":"...","last_assistant_message":"..."}

INPUT=$(cat)
MSG=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('last_assistant_message',''))" 2>/dev/null)
REASON=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('stop_reason',''))" 2>/dev/null)
TRIO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERRORS=0
WARNINGS=0

# 跳过用户中断和空消息
[ "$REASON" = "user_interrupt" ] && exit 0
[ -z "$MSG" ] && exit 0

# 1. 检查声明了 PDF 但文件不存在
echo "$MSG" | grep -oP '[^ ,，。\n\)]+\.pdf' 2>/dev/null | while read pdf; do
  if [ ! -f "$pdf" ]; then
    # 搜索常见输出目录
    found=$(find /mnt/d/工作/项目/ /mnt/d/TRIO\ 3.0/ -name "$pdf" 2>/dev/null | head -1)
    if [ -z "$found" ]; then
      echo "❌ PDF缺失: $pdf"
      echo '{"decision": "block", "reason": "PDF文件不存在: '"$pdf"'"}' > /tmp/trio-stop-decision.json
    fi
  fi
done

# 2. 检查文件路径不存在
echo "$MSG" | grep -oP '(?<=`)[Dd]:\\\\[^`]{3,}|(?<=`)/mnt/d/[^`]{3,}' 2>/dev/null | while read path; do
  wsl_path=$(echo "$path" | sed 's|^D:\\\\|/mnt/d/|' | sed 's|\\|/|g')
  if [ ! -e "$wsl_path" ] && [ ! -d "$(dirname "$wsl_path")" ]; then
    echo "❌ 文件不存在: $path"
    echo '{"decision": "block", "reason": "引用文件不存在: '"$path"'"}' > /tmp/trio-stop-decision.json
  fi
done

# 3. 检查时间戳是否为手写（简单启发式）
# 如果消息中有 2026-06-25T 开头的时间戳但后面没跟 +08:00，可能是手写
echo "$MSG" | grep -oP '20\d{2}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}' 2>/dev/null | while read ts; do
  if ! echo "$ts" | grep -q '+08:00'; then
    echo "⚠️  可能手写时间戳: $ts（缺少时区）"
  fi
done

# 最终决定: 有 /tmp/trio-stop-decision.json 则 block
if [ -f /tmp/trio-stop-decision.json ]; then
  cat /tmp/trio-stop-decision.json
  rm /tmp/trio-stop-decision.json
  exit 1
fi

echo '{"decision": "approve"}'
exit 0
