#!/bin/bash
# TRIO Build Router — 智能选择 LaTeX 或 HTML 管道
# 用法: bash trio-build.sh <report.md> [--latex|--html|--auto]

set -euo pipefail

REPORT="${1:-}"
MODE="${2:---auto}"

if [[ -z "$REPORT" ]]; then
    echo "用法: trio-build.sh <report.md> [--latex|--html|--auto]"
    echo ""
    echo "  --latex  强制 LaTeX + Eisvogel 管道"
    echo "  --html   强制 HTML + Playwright 管道"
    echo "  --auto   自动检测（默认）：有 Mermaid → HTML，否则 → LaTeX"
    exit 1
fi

if [[ ! -f "$REPORT" ]]; then
    echo "❌ 文件不存在: $REPORT"
    exit 1
fi

OUTPUT="${REPORT%.md}.pdf"
TRIO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FONT_PREFLIGHT="$TRIO_ROOT/scripts/font-preflight.sh"
HARDENING="$TRIO_ROOT/design/eisvogel-hardening.tex"

# ── 自动检测 ──
if [[ "$MODE" == "--auto" ]]; then
    if grep -q '```mermaid' "$REPORT" 2>/dev/null; then
        MODE="--html"
        echo "🎨 检测到 Mermaid → HTML + Playwright 管道"
    else
        MODE="--latex"
        echo "📖 纯文字报告 → LaTeX + Eisvogel 管道"
    fi
fi

# ── LaTeX 管道 ──
if [[ "$MODE" == "--latex" ]]; then
    echo ""
    echo "═══════════════════════════════════════"
    echo "  LaTeX + Eisvogel 管道"
    echo "═══════════════════════════════════════"

    # 1. 字体预检
    if [[ -x "$FONT_PREFLIGHT" ]]; then
        bash "$FONT_PREFLIGHT" --ci || {
            echo "❌ 字体预检失败，终止构建"
            exit 1
        }
    else
        echo "⚠️  font-preflight.sh 未找到，跳过预检"
    fi

    # 2. 编译
    PANDOC_OPTS=(
        --pdf-engine=xelatex
        --template=eisvogel
        -V "CJKmainfont=Noto Serif CJK SC"
        -V "CJKsansfont=Noto Sans CJK SC"
        -V "CJKmonofont=Noto Sans Mono CJK SC"
        -V "mainfont=Noto Serif"
        -V "sansfont=Noto Sans"
        -V "monofont=Noto Sans Mono"
        -V colorlinks=true
        --toc --number-sections
    )

    # 加固补丁（如果存在）
    if [[ -f "$HARDENING" ]]; then
        PANDOC_OPTS+=(-H "$HARDENING")
    fi

    echo "🔨 pandoc $REPORT → $OUTPUT"
    pandoc "$REPORT" -o "$OUTPUT" "${PANDOC_OPTS[@]}"

    # 3. 验证
    if [[ -f "$OUTPUT" ]]; then
        echo "✅ PDF 生成成功: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"

        if command -v pdffonts &>/dev/null; then
            echo ""
            echo "── 嵌入字体 ──"
            pdffonts "$OUTPUT" 2>/dev/null | grep -i "CJK\|Noto" || echo "⚠️  未检测到 CJK 字体"
        fi
    else
        echo "❌ PDF 生成失败"
        exit 1
    fi

# ── HTML 管道 ──
elif [[ "$MODE" == "--html" ]]; then
    echo ""
    echo "═══════════════════════════════════════"
    echo "  HTML + Playwright 管道"
    echo "═══════════════════════════════════════"

    HTML_OUT="${REPORT%.md}.html"

    # 1. Markdown → HTML
    echo "🔨 pandoc $REPORT → $HTML_OUT"
    pandoc "$REPORT" \
        -o "$HTML_OUT" \
        --standalone \
        --self-contained \
        --css "$TRIO_ROOT/design/trio-tokens.css" \
        --metadata title="TRIO 分析报告" \
        --highlight-style=tango

    # 2. HTML → PDF (需要 Playwright)
    if command -v npx &>/dev/null; then
        echo "🔨 Playwright $HTML_OUT → $OUTPUT"
        npx playwright pdf "$HTML_OUT" "$OUTPUT" \
            --wait-for-timeout=2000 \
            --format=A4 \
            --print-background 2>/dev/null || {
            echo "⚠️  Playwright 不可用，仅保留 HTML"
            echo "   HTML: $HTML_OUT"
            exit 0
        }
        echo "✅ PDF 生成成功: $OUTPUT"
    else
        echo "⚠️  Node.js/npx 不可用，仅保留 HTML"
        echo "   HTML: $HTML_OUT"
    fi
fi
