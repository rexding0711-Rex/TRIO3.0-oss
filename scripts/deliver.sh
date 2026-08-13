#!/bin/bash
# ================================================================
# TRIO 3.0 三件套交付 v1.2
# 输入: Markdown 文件
# 产出: MD(源文件) + PDF(Eisvogel) + HTML(全文+Mermaid交互图)
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INPUT="${1:-}"
if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
    echo "用法: $0 <报告.md> [--theme A]"
    echo "产出: 同名 .md + .pdf + .html 三件套"
    exit 1
fi

THEME="A"
for arg in "$@"; do
    case "$arg" in
        --theme) shift; THEME="${2:-A}"; break ;;
        --theme=*) THEME="${arg#--theme=}" ;;
    esac
done

INPUT_ABS="$(realpath "$INPUT")"
INPUT_DIR="$(dirname "$INPUT_ABS")"
INPUT_NAME="$(basename "$INPUT_ABS" .md)"

echo "📦 TRIO 三件套交付"
echo "   源文件: $INPUT_ABS"
echo ""

# ── 0. 门禁 A：AI 痕迹清除（L0·阻断性·焊死在管道里）──
echo "🔍 门禁 A: AI 痕迹扫描..."
A1=$(grep -c -E 'v[0-9]+|重做版|修订版|审计后|修正版' "$INPUT_ABS" 2>/dev/null) || A1=0
A2=$(grep -c -E '新增章节|与上一版一致|审计后：' "$INPUT_ABS" 2>/dev/null) || A2=0
A3=$(grep -c -E '感谢DeepSeek|感谢Kimi|审计发现|之前漏了|本轮修正|盲区自白|Kimi视角|DeepSeek视角|Claude视角|Phase [0-9]|反证覆盖率|三视角综合判断|可操作建议.*三级' "$INPUT_ABS" 2>/dev/null) || A3=0
A4=$(grep -c -E 'topology-state|v[0-9]+ vs v[0-9]+|修正前后对比|下次更新建议|版本.*v[0-9]+|审计状态' "$INPUT_ABS" 2>/dev/null) || A4=0
A5=$(grep -c -E 'TBD|仅供参考|如有疏漏|能力有限|未完待续' "$INPUT_ABS" 2>/dev/null) || A5=0
A1=${A1:-0}; A2=${A2:-0}; A3=${A3:-0}; A4=${A4:-0}; A5=${A5:-0}
TOTAL=$((A1 + A2 + A3 + A4 + A5))
if [ "$TOTAL" -gt 0 ]; then
    echo "  🛑 门禁 A 阻断 — $TOTAL 处 AI 痕迹 (A1:$A1 A2:$A2 A3:$A3 A4:$A4 A5:$A5)"
    echo "  → 先清除 AI 痕迹再生成 PDF。参考: document-format-rules.md §AI 过程痕迹禁止"
    exit 1
fi
echo "  ✅ 门禁 A 通过 — 零 AI 痕迹"
echo ""

# ── 1. Markdown + Manifest ──
echo "  ✅ [1/4] MD  $INPUT_NAME.md"
MANIFEST_OK=0
python3 "$SCRIPT_DIR/manifest.py" "$INPUT_ABS" 2>/dev/null || true
MANIFEST_RC=1
python3 "$SCRIPT_DIR/manifest-validate.py" "$INPUT_DIR/$INPUT_NAME.manifest.yaml" 2>/dev/null && MANIFEST_RC=0 || MANIFEST_RC=$?
if [ "$MANIFEST_RC" = "0" ]; then
  echo "  ✅ [2/4] Manifest PASS"
elif [ "$MANIFEST_RC" = "1" ]; then
  echo "  ⚠️  [2/4] Manifest WARN — 交付继续·知识回写降级"
else
  echo "  🛑 [2/4] Manifest BLOCK — 结构性失败·检查 manifest.yaml"
fi

# ── 2. PDF（通过pdf-prep.py自动转换→临时MD→pandoc）──
PDF_TMP="/tmp/trio-pdf-$$.md"
python3 "$SCRIPT_DIR/pdf-prep.py" "$INPUT_ABS" "$PDF_TMP"
PDF_OUT="$INPUT_DIR/$INPUT_NAME.pdf"
bash "$SCRIPT_DIR/export-md-to-pdf.sh" --theme "$THEME" "$PDF_TMP" "$PDF_OUT" 2>&1 | grep -v "WARNING" || true
rm -f "$PDF_TMP"
echo "  ✅ [3/4] PDF $INPUT_NAME.pdf"

# ── 4. HTML（使用独立TRIO设计系统CSS）──
HTML_OUT="$INPUT_DIR/$INPUT_NAME.html"
TITLE="$(head -1 "$INPUT_ABS" | sed 's/^# //')"
TRIO_CSS="$TRIO_ROOT/design/trio-design.css"
HEADER_FILE="/tmp/trio-html-header-$$.html"

cat > "$HEADER_FILE" << HEADEREOF
<style>
$(cat "$TRIO_CSS")
</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>mermaid.initialize({startOnLoad:true, theme:'default', securityLevel:'loose'});</script>
HEADEREOF

CUR_DATE=$(TZ=Asia/Shanghai date '+%Y-%m-%d')
pandoc "$INPUT_ABS" \
    --from markdown \
    --to html5 \
    --standalone \
    --metadata title="$TITLE" \
    --metadata date="$CUR_DATE" \
    --include-in-header="$HEADER_FILE" \
    -o "$HTML_OUT" 2>&1

rm -f "$HEADER_FILE"

# 注入TRIO设计系统header/footer wrapper
python3 -c "
import re
html = open('$HTML_OUT', 'r').read()
# 在<body>后插入header
html = html.replace('<body>', '<body>\n<div class=\"trio-header\"><div class=\"trio-header-inner\"><span class=\"trio-brand\">TRIO 3.0</span><button class=\"trio-theme-btn\" onclick=\"(function(){var h=document.documentElement;var n=h.getAttribute(\\'data-theme\\')===\\'dark\\'?\\'light\\':\\'dark\\';h.setAttribute(\\'data-theme\\',n);this.textContent=n===\\'dark\\'?\\'亮色\\':\\'暗色\\';}).call(this)\">暗色</button></div></div>\n<div class=\"trio-body\">')
# 在</body>前插入footer和闭合div
html = html.replace('</body>', '</div>\n<footer class=\"trio-footer\"><p>TRIO 3.0</p></footer>\n</body>')
open('$HTML_OUT', 'w').write(html)
"

# Pandoc 把 Mermaid 代码块渲染成 <pre><code class="language-mermaid">，但 Mermaid.js 只认 <div class="mermaid">
# 用 Python 做精准替换
python3 -c "
import re
html = open('$HTML_OUT', 'r').read()
# 找到所有 <pre class=\"mermaid\"><code>...</code></pre> 或 <pre><code class=\"language-mermaid\">...</code></pre>
# 替换为 <div class=\"mermaid\">...</div>
html = re.sub(r'<pre[^>]*class=\"[^\"]*mermaid[^\"]*\"[^>]*><code[^>]*>(.*?)</code></pre>', r'<div class=\"mermaid\">\n\1\n</div>', html, flags=re.DOTALL)
html = re.sub(r'<pre><code class=\"language-mermaid\">(.*?)</code></pre>', r'<div class=\"mermaid\">\n\1\n</div>', html, flags=re.DOTALL)
open('$HTML_OUT', 'w').write(html)
"

echo "  ✅ [3/3] HTML $INPUT_NAME.html (全文 + Mermaid 交互图)"

# ── 4. 深度拓扑图（如果 topology-state.json 存在）──
TOPOLOGY_JSON="$INPUT_DIR/runs/$(basename "$INPUT_ABS" .md)/topology-state.json"
# 尝试 find 定位
if [ ! -f "$TOPOLOGY_JSON" ]; then
    TOPOLOGY_JSON=$(find "$INPUT_DIR" -name "topology-state.json" -path "*/$(basename "$INPUT_ABS" .md)*" 2>/dev/null | head -1)
fi
if [ -n "$TOPOLOGY_JSON" ] && [ -f "$TOPOLOGY_JSON" ]; then
    python3 "$SCRIPT_DIR/topology-render.py" "$TOPOLOGY_JSON" > "/tmp/trio-deep-mermaid-$$.txt" 2>/dev/null && {
        echo ""
        echo "  🌐 深度拓扑图已生成 (topology-state.json → Mermaid 5阶段)"
    } || true
fi

# ── 汇总 ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  📦 交付完成"
echo "  📝 $INPUT_ABS"
echo "  📄 $PDF_OUT"
echo "  🌐 $HTML_OUT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
