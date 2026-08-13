#!/bin/bash
# TRIO 回复前自动校验脚本
# 拦截: 文件路径不存在、项目名不匹配、日期不对齐
# 用法: bash validate.sh "<回复文本>" 或 piped

TEXT="${1:-$(cat)}"
ERRORS=0
TRIO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. 检查文件路径: 提取所有 D:\... 或 /mnt/d/... 路径，验证存在
while read -r path; do
  # Windows → WSL 路径转换
  wsl_path=$(echo "$path" | sed 's|^D:\\\\|/mnt/d/|' | sed 's|\\|/|g')
  if [ ! -e "$wsl_path" ]; then
    echo "❌ 文件不存在: $path"
    ERRORS=$((ERRORS+1))
  fi
done < <(echo "$TEXT" | grep -oP '(?<=`)[Dd]:\\\\[^`]+|(?<=`)/mnt/d/[^`]+' 2>/dev/null)

# 2. 检查项目名: 提取可能的中文项目名，和 projects.json 对比
KNOWN_PROJS=$(python3 -c "import json;d=json.load(open('$TRIO/config/projects.json'));print('|'.join(d['projects'].keys()))" 2>/dev/null)
while read -r proj; do
  if ! echo "$KNOWN_PROJS" | grep -q "$proj"; then
    echo "⚠️  未知项目: $proj（不在 projects.json 中）"
  fi
done < <(echo "$TEXT" | grep -oP '(罗欣|CMOS|CRX|北化新橡|瑞燃|国能|Forge)' 2>/dev/null)

# 3. 检查日期: 提取 YYYY-MM-DD，不可能是未来日期（>当前+7天）
TODAY=$(TZ=Asia/Shanghai date +%Y-%m-%d)
FUTURE=$(TZ=Asia/Shanghai date -d "+7 days" +%Y-%m-%d)
while read -r dt; do
  if [[ "$dt" > "$FUTURE" ]]; then
    echo "⚠️  可疑日期: $dt（>7天后），确认不是手误？"
  fi
done < <(echo "$TEXT" | grep -oP '20\d{2}-\d{2}-\d{2}' 2>/dev/null)

# 4. 检查 PDF 承诺: 如果文本声称有 PDF，验证对应文件存在
if echo "$TEXT" | grep -q '\.pdf'; then
  while read -r pdf; do
    if [ ! -f "$pdf" ] && [ ! -f "/mnt/d/工作/项目/"*/"$pdf" ]; then
      echo "⚠️  声称的 PDF 可能不存在: $pdf"
    fi
  done < <(echo "$TEXT" | grep -oP '[^ ,，。\n]+\.pdf' 2>/dev/null)
fi

exit $ERRORS
