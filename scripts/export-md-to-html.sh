#!/bin/bash
# ================================================================
# TRIO 3.0 HTML/Web 导出 v1.0 — Vivliostyle
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THEMES="$SCRIPT_DIR/../config/html-themes.json"

# ── 参数 ──
THEME=""
INPUT=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --theme|-t) THEME="$2"; shift 2 ;;
        -*) echo "❌ 未知参数: $1"; exit 1 ;;
        *)  [ -z "$INPUT" ] && INPUT="$1" || OUTPUT_DIR="$1"; shift ;;
    esac
done

# ── 强制主题选择 ──
if [ -z "$THEME" ]; then
    echo ""
    echo "🎨 请选择 Vivliostyle 主题 (--theme)："
    echo ""
    python3 -c "
import json
with open('$THEMES') as f:
    themes = json.load(f)
for k, v in themes.items():
    print(f'  {k:10s} · {v[\"name\"]:6s}  {v[\"bestFor\"]}')
"
    echo ""
    echo "用法: $0 --theme techbook <input.md> [output_dir]"
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
    print(themes['$THEME']['package'], themes['$THEME']['name'])
")

if [[ "$THEME_DATA" == INVALID* ]]; then
    echo "❌ 无效主题: $THEME (可选: ${THEME_DATA#INVALID })"
    exit 1
fi

read -r THEME_PKG THEME_NAME <<< "$THEME_DATA"

# ── 文件 ──
[ -z "$INPUT" ] && { echo "❌ 缺少输入文件"; exit 1; }
[ -f "$INPUT" ] || { echo "❌ 文件不存在: $INPUT"; exit 1; }

INPUT_ABS="$(realpath "$INPUT")"
INPUT_DIR="$(dirname "$INPUT_ABS")"
INPUT_BASE="$(basename "$INPUT_ABS" .md)"

OUTPUT_DIR="${OUTPUT_DIR:-$INPUT_DIR/$INPUT_BASE-web}"
mkdir -p "$OUTPUT_DIR"

TITLE="$(grep '^title:' "$INPUT_ABS" 2>/dev/null | head -1 | sed 's/^title: *"//;s/"$//' || head -1 "$INPUT_ABS" | sed 's/^# //')"

echo "📄 $TITLE  [$THEME · $THEME_NAME]"
echo "📂 $OUTPUT_DIR"

# ── 构建 ──
TMP_DIR="/tmp/vivliostyle-build-$$"
mkdir -p "$TMP_DIR"
cp "$INPUT_ABS" "$TMP_DIR/manuscript.md"

cat > "$TMP_DIR/vivliostyle.config.js" << EOF
module.exports = {
  entry: 'manuscript.md',
  output: '$OUTPUT_DIR/index.html',
  size: 'A4',
  theme: '$THEME_PKG',
};
EOF

cd "$TMP_DIR"
vivliostyle build 2>&1 | grep -E 'SUCCESS|ERROR|FAILED' || true

# ── 验证 ──
HTML_FILE="$OUTPUT_DIR/index.html/manuscript.html"
PDF_FILE="$OUTPUT_DIR/$INPUT_BASE.pdf"
if [ -f "$HTML_FILE" ]; then
    echo "✅ HTML: $HTML_FILE"
else
    echo "⚠️  HTML 未生成"
fi

rm -rf "$TMP_DIR"
