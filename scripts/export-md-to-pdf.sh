#!/bin/bash
# ================================================================
# TRIO 3.0 PDF 导出 v8.0 — Eisvogel + 强制主题选择
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THEMES="$SCRIPT_DIR/../config/pdf-themes.json"

# ── 参数解析 ──
THEME=""
INPUT=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --theme|-t) THEME="$2"; shift 2 ;;
        -*) echo "❌ 未知参数: $1"; exit 1 ;;
        *)  [ -z "$INPUT" ] && INPUT="$1" || OUTPUT="$1"; shift ;;
    esac
done

# ── 强制主题选择 ──
if [ -z "$THEME" ]; then
    echo ""
    echo "🎨 请选择 Eisvogel 视觉方案 (--theme)："
    echo ""
    python3 -c "
import json
with open('$THEMES') as f:
    themes = json.load(f)
for k, v in themes.items():
    print(f'  {k} · {v[\"name\"]:8s}  标题页: #{v[\"titlepage-color\"]} → #{v[\"titlepage-text-color\"]}')
"
    echo ""
    echo "用法: $0 --theme A <input.md> [output.pdf]"
    echo ""
    exit 1
fi

THEME_DATA=$(python3 -c "
import json
with open('$THEMES') as f:
    themes = json.load(f)
if '$THEME' not in themes:
    print('INVALID', ', '.join(themes.keys()))
else:
    t = themes['$THEME']
    print(t['titlepage-color'], t['titlepage-text-color'], t['titlepage-rule-color'], t['titlepage-rule-height'])
")

if [[ "$THEME_DATA" == INVALID* ]]; then
    echo "❌ 无效主题: $THEME (可选: ${THEME_DATA#INVALID })"
    exit 1
fi

read -r TC TTC TRC TRH <<< "$THEME_DATA"

# ── 文件 ──
[ -z "$INPUT" ] && { echo "❌ 缺少输入文件"; exit 1; }
[ -f "$INPUT" ] || { echo "❌ 文件不存在: $INPUT"; exit 1; }

INPUT_ABS="$(realpath "$INPUT")"
OUTPUT="${OUTPUT:-${INPUT%.md}.pdf}"
OUTPUT_ABS="$(realpath -m "$OUTPUT")"
# ── 提取元数据（YAML frontmatter 优先，回退到文件名/系统日期）──
TITLE="$(grep '^title:' "$INPUT_ABS" | head -1 | sed 's/^title: *"//;s/"$//;s/^title: *//' || true)"
SUBTITLE="$(grep '^subtitle:' "$INPUT_ABS" | head -1 | sed 's/^subtitle: *"//;s/"$//;s/^subtitle: *//' || true)"
AUTHOR="$(grep '^author:' "$INPUT_ABS" | head -1 | sed 's/^author: *"//;s/"$//;s/^author: *//' || true)"
DATE="$(grep '^date:' "$INPUT_ABS" | head -1 | sed 's/^date: *"//;s/"$//;s/^date: *//' || true)"
[ -z "$TITLE" ] && TITLE="$(head -1 "$INPUT_ABS" | sed 's/^# //')"
[ -z "$SUBTITLE" ] && SUBTITLE=""
[ -z "$AUTHOR" ] && AUTHOR="TRIO 3.0"
[ -z "$DATE" ] && DATE="$(date '+%Y-%m-%d')"

echo "📄 $TITLE  [$THEME · $(python3 -c "import json;print(json.load(open('$THEMES'))['$THEME']['name'])")]"

# ── Emoji 替换：Noto Color Emoji 在 PDF 里渲染效果差，预先转为纯文本 ──
TEMP_MD="$(mktemp /tmp/trio-export-XXXXXXXX.md)"
cp "$INPUT_ABS" "$TEMP_MD"
sed -i \
  -e 's/🟢/\[低\]/g' -e 's/🔴/\[高\]/g' -e 's/🟡/\[中\]/g' \
  -e 's/🟠/\[中高\]/g' -e 's/🔵/\[观察\]/g' \
  -e 's/⚠️//g' -e 's/🚩//g' -e 's/📌//g' \
  -e 's/✅//g' -e 's/❌//g' -e 's/🥇//g' -e 's/🥈//g' -e 's/🥉//g' \
  -e 's/🛡️//g' -e 's/🔍//g' -e 's/🎨//g' -e 's/⭐//g' -e 's/[①②③④⑤⑥⑦⑧⑨⑩]//g' \
  "$TEMP_MD" 2>/dev/null || true

# 清理 sed 后可能残留的双重标签
sed -i \
  -e 's/\[高\] 高 /高风险 /g' \
  -e 's/\[中高\] 中高/中高风险/g' \
  -e 's/\[中\] 中 /中风险 /g' \
  -e 's/^> ! /> /g' \
  "$TEMP_MD" 2>/dev/null || true

# ── 编译 ──
pandoc "$TEMP_MD" \
    --pdf-engine=xelatex \
    --template eisvogel \
    --from markdown \
    --metadata title="$TITLE" \
    --metadata subtitle="$SUBTITLE" \
    --metadata author="$AUTHOR" \
    --metadata date="$DATE" \
    -V titlepage=true \
    -V titlepage-color="$TC" \
    -V titlepage-text-color="$TTC" \
    -V titlepage-rule-color="$TRC" \
    -V titlepage-rule-height="$TRH" \
    -V CJKmainfont='Noto Sans CJK SC' \
    -V CJKsansfont='Noto Sans CJK SC' \
    -V CJKmonofont='Noto Sans Mono CJK SC' \
    -V mainfont='DejaVu Serif' \
    -V monofont='DejaVu Sans Mono' \
    -V geometry:'a4paper, margin=2.5cm, top=2.5cm, bottom=2.2cm' \
    -V colorlinks=false \
    -V linkcolor=black \
    -V urlcolor=black \
    -V citecolor=black \
    -V filecolor=black \
    -V fontsize=11pt \
    -V linestretch=1.3 \
    -V table-use-row-colors=true \
    -V toc=false \
    -V header-left="$TITLE" \
    -o "$OUTPUT_ABS" 2>&1

rm -f "$TEMP_MD"

# ── Mermaid 处理：PDF 里代码块是乱码，替换为文字表 + HTML 引用 ──
MERMAID_COUNT=$(grep -c '```mermaid' "$TEMP_MD" 2>/dev/null || echo 0)
if [ "$MERMAID_COUNT" -gt 0 ]; then
  # 把每个 Mermaid 代码块替换为引用
  sed -i '/```mermaid/,/```/{
    /```mermaid/{s/.*/> **交互版拓扑图**：[点击查看]('"${INPUT%.md}"'-topology.html)  |  此图包含复杂关系网络，PDF 格式无法正确渲染。请打开同名 HTML 文件查看完整交互版。/; N; D;}
    /```/d
  }' "$TEMP_MD" 2>/dev/null || true
  # 清理残留的 Mermaid 内容行
  sed -i '/^[[:space:]]*\(graph\|subgraph\|SX\[\|SL\[\|TS\[\|XA\[\|CO\[\|MIL\[\|ANT\[\|DEBT\[\|NL\[\|SS\[\|TE\[\|XX\[\|style\|end\|-->\|-->\)/d' "$TEMP_MD" 2>/dev/null || true
fi

if [ -f "$OUTPUT_ABS" ]; then
    SIZE=$(stat --printf="%s" "$OUTPUT_ABS" 2>/dev/null || echo 0)
    echo "✅ $OUTPUT_ABS ($(( SIZE / 1024 )) KB)"
else
    echo "❌ 生成失败"; exit 1
fi
