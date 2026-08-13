#!/bin/bash
# TRIO Font Preflight v1.0
# 用法: bash font-preflight.sh [--ci]
# 退出码: 0=全部通过 | 1=字体缺失 | 2=xelatex 编译失败 | 3=PDF 字体嵌入不完整

set -euo pipefail
CI_MODE=false
[[ "${1:-}" == "--ci" ]] && CI_MODE=true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass() { echo -e "${GREEN}✅${NC} $1"; }
fail() { echo -e "${RED}❌${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️${NC} $1"; }

ERRORS=0

# ── 1. fontconfig 缓存检查 ──
echo "═══════════════════════════════════════"
echo "  TRIO Font Preflight v1.0"
echo "═══════════════════════════════════════"
echo ""

echo "── 1. fontconfig 缓存 ──"
if fc-cache -v &>/dev/null; then
    pass "fontconfig 缓存刷新成功"
else
    fail "fontconfig 缓存刷新失败"
    ((ERRORS++))
fi

# ── 2. 字体文件存在性 ──
echo ""
echo "── 2. 字体文件 ──"

FONT_PATHS=(
    "/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc"
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
    "/usr/share/fonts/opentype/noto/NotoSansMonoCJK-Regular.ttc"
    "/usr/share/fonts/truetype/noto/NotoSerifCJK-Regular.ttc"
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc"
)

FOUND_SERIF=false; FOUND_SANS=false; FOUND_MONO=false

while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if [[ "$path" =~ Serif ]] && ! $FOUND_SERIF; then
        pass "衬线字体: $path"
        FOUND_SERIF=true
    elif [[ "$path" =~ Sans.*Mono ]] && ! $FOUND_MONO; then
        pass "等宽字体: $path"
        FOUND_MONO=true
    elif [[ "$path" =~ Sans ]] && ! $FOUND_SANS; then
        pass "无衬线字体: $path"
        FOUND_SANS=true
    fi
done < <(find /usr/share/fonts -name "*Noto*CJK*" -type f 2>/dev/null | head -20)

if ! $FOUND_SERIF; then
    fail "Noto Serif CJK 未找到"
    warn "运行: sudo apt install -y fonts-noto-cjk fonts-noto-cjk-extra"
    ((ERRORS++))
fi
if ! $FOUND_SANS; then
    fail "Noto Sans CJK 未找到"
    ((ERRORS++))
fi

# ── 3. fc-match 验证 ──
echo ""
echo "── 3. fc-match 匹配 ──"

check_match() {
    local name="$1"
    local match
    match=$(fc-match -s "$name" 2>/dev/null | head -1)
    if echo "$match" | grep -qi "noto"; then
        pass "$name → $match"
        return 0
    else
        fail "$name → $match (不是 Noto 字体)"
        return 1
    fi
}

check_match "Noto Serif CJK SC" || ((ERRORS++))
check_match "Noto Sans CJK SC"   || ((ERRORS++))

# ── 4. xelatex 编译测试 ──
echo ""
echo "── 4. xelatex 编译 ──"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cat > "$TMPDIR/test.tex" << 'TEX'
\documentclass{article}
\usepackage{xeCJK}
\setCJKmainfont{Noto Serif CJK SC}
\setCJKsansfont{Noto Sans CJK SC}
\setCJKmonofont{Noto Sans Mono CJK SC}
\begin{document}
中文测试·English·123456789·\textbf{粗体}·\textit{斜体}
\end{document}
TEX

if xelatex -interaction=nonstopmode -output-directory="$TMPDIR" "$TMPDIR/test.tex" > "$TMPDIR/xelatex.log" 2>&1; then
    pass "xelatex CJK 编译通过"
else
    fail "xelatex CJK 编译失败"
    warn "日志: $TMPDIR/xelatex.log"
    if $CI_MODE; then cat "$TMPDIR/xelatex.log" | tail -20; fi
    ((ERRORS++))
fi

# ── 5. PDF 字体嵌入验证 ──
echo ""
echo "── 5. PDF 字体嵌入 ──"

if [[ -f "$TMPDIR/test.pdf" ]]; then
    if command -v pdffonts &>/dev/null; then
        EMBEDDED=$(pdffonts "$TMPDIR/test.pdf" 2>/dev/null | grep -ci "CJK\|Noto" || true)
        if [[ "$EMBEDDED" -ge 1 ]]; then
            pass "PDF 已嵌入 CJK 字体 ($EMBEDDED 个)"
        else
            fail "PDF 中未检测到嵌入的 CJK 字体"
            warn "pdffonts 输出:"
            pdffonts "$TMPDIR/test.pdf" 2>/dev/null | head -10
            ((ERRORS++))
        fi
    else
        warn "pdffonts 未安装 (apt install poppler-utils)，跳过嵌入验证"
    fi
else
    fail "xelatex 未生成 PDF"
    ((ERRORS++))
fi

# ── 总结 ──
echo ""
echo "═══════════════════════════════════════"
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}  全部通过 — CJK 字体就绪${NC}"
    echo "═══════════════════════════════════════"
    exit 0
else
    echo -e "${RED}  $ERRORS 项失败 — 修复后重跑${NC}"
    echo "═══════════════════════════════════════"
    exit 1
fi
