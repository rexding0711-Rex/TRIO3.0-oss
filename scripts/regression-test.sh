#!/bin/bash
# TRIO Regression Test — 验证模板改动不会破坏 PDF 输出
# 用法: bash regression-test.sh [fixtures/sample.md]
# 产出: out/before.pdf vs out/after.pdf 的文本差异

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

SAMPLE="${1:-fixtures/sample.md}"
OUTDIR="out/regression-$(date +%Y%m%d-%H%M%S)"
BASELINE="out/baseline"

mkdir -p "$OUTDIR" "$BASELINE"

# ── 1. 如果还没有 baseline，先建 ──
if [[ ! -f "$BASELINE/baseline.pdf" ]]; then
    echo "📸 首次运行——建立 baseline..."
    pandoc "$SAMPLE" \
        -o "$BASELINE/baseline.pdf" \
        --pdf-engine=xelatex \
        --template=eisvogel \
        -V CJKmainfont="Noto Serif CJK SC" \
        -V mainfont="Noto Serif" \
        -V colorlinks=true \
        --toc --number-sections \
        -H design/eisvogel-hardening.tex

    pdftotext "$BASELINE/baseline.pdf" "$BASELINE/baseline.txt" 2>/dev/null || true
    echo -e "${GREEN}✅ baseline 已建立${NC}"
    echo "   改模板后重新运行此脚本即可对比。"
    exit 0
fi

# ── 2. 生成新版本 ──
echo "🔨 生成当前版本..."
pandoc "$SAMPLE" \
    -o "$OUTDIR/current.pdf" \
    --pdf-engine=xelatex \
    --template=eisvogel \
    -V CJKmainfont="Noto Serif CJK SC" \
    -V mainfont="Noto Serif" \
    -V colorlinks=true \
    --toc --number-sections \
    -H design/eisvogel-hardening.tex

# ── 3. 提取文本 ──
echo "📝 提取文本..."
if command -v pdftotext &>/dev/null; then
    pdftotext "$BASELINE/baseline.pdf" "$OUTDIR/baseline.txt" 2>/dev/null
    pdftotext "$OUTDIR/current.pdf"  "$OUTDIR/current.txt" 2>/dev/null
    TEXT_DIFF=true
else
    echo "⚠️  pdftotext 未安装 (apt install poppler-utils)，跳过文本对比"
    TEXT_DIFF=false
fi

# ── 4. 检查项 ──
PASS=0
FAIL=0

echo ""
echo "═══════════════════════════════════════"
echo "  TRIO 回归测试"
echo "═══════════════════════════════════════"

# 4a. PDF 是否生成
if [[ -f "$OUTDIR/current.pdf" ]]; then
    echo -e "${GREEN}✅${NC} PDF 生成成功 ($(du -h "$OUTDIR/current.pdf" | cut -f1))"
    ((PASS++))
else
    echo -e "${RED}❌${NC} PDF 生成失败"
    ((FAIL++))
fi

# 4b. 页数对比
BASELINE_PAGES=$(pdfinfo "$BASELINE/baseline.pdf" 2>/dev/null | grep "Pages" | awk '{print $2}' || echo "?")
CURRENT_PAGES=$(pdfinfo "$OUTDIR/current.pdf" 2>/dev/null | grep "Pages" | awk '{print $2}' || echo "?")
if [[ "$BASELINE_PAGES" != "?" ]] && [[ "$CURRENT_PAGES" != "?" ]]; then
    if [[ "$BASELINE_PAGES" -eq "$CURRENT_PAGES" ]]; then
        echo -e "${GREEN}✅${NC} 页数一致 ($CURRENT_PAGES 页)"
        ((PASS++))
    else
        echo -e "${RED}❌${NC} 页数变化: $BASELINE_PAGES → $CURRENT_PAGES"
        ((FAIL++))
    fi
fi

# 4c. 字体嵌入检查
if command -v pdffonts &>/dev/null; then
    CJK_COUNT=$(pdffonts "$OUTDIR/current.pdf" 2>/dev/null | grep -ci "CJK\|Noto" || true)
    if [[ "$CJK_COUNT" -ge 1 ]]; then
        echo -e "${GREEN}✅${NC} CJK 字体已嵌入 ($CJK_COUNT 个)"
        ((PASS++))
    else
        echo -e "${RED}❌${NC} CJK 字体未嵌入"
        ((FAIL++))
    fi
fi

# 4d. Missing character 警告
if pdftotext "$OUTDIR/current.pdf" - 2>/dev/null | grep -q "▯\|□\|�"; then
    echo -e "${RED}❌${NC} 检测到 tofu（方框字符）"
    ((FAIL++))
else
    echo -e "${GREEN}✅${NC} 无 tofu 字符"
    ((PASS++))
fi

# 4e. 文本差异（如果 pdftotext 可用）
if $TEXT_DIFF; then
    DIFF_LINES=$(diff "$OUTDIR/baseline.txt" "$OUTDIR/current.txt" 2>/dev/null | wc -l || echo "0")
    if [[ "$DIFF_LINES" -le 5 ]]; then
        echo -e "${GREEN}✅${NC} 文本差异 ≤ 5 行 (实际 $DIFF_LINES 行)"
        ((PASS++))
    else
        echo -e "${RED}❌${NC} 文本差异 $DIFF_LINES 行 — 请检查 $OUTDIR/"
        ((FAIL++))
    fi
fi

# ── 5. 总结 ──
echo ""
echo "───────────────────────────────────────"
echo "  通过: $PASS  |  失败: $FAIL"
echo "  输出: $OUTDIR/"
echo "───────────────────────────────────────"

if [[ "$FAIL" -eq 0 ]]; then
    echo -e "${GREEN}  回归测试通过 ✅${NC}"
    exit 0
else
    echo -e "${RED}  回归测试失败 — 检查上述 ❌ 项${NC}"
    exit 1
fi
