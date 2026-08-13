#!/usr/bin/env bash
# ============================================================
# branch-index-check.sh — 分支索引健康巡检（loop·2026-08-11）
# 校验 branch-manifest.md 引用的分支入口是否仍存在 + 两库规模变化
# 挂 cron: 每周一检查（与 kb-refresh 同日）
# 用法: bash scripts/branch-index-check.sh [--report]
# ============================================================
set -euo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8

ROOT="/mnt/d/TRIO 3.0"
MANIFEST="$ROOT/config/branch-manifest.md"
MODE="${1:-check}"

echo "══════════════════════════════════════════"
echo "  TRIO 分支索引健康巡检 — $(TZ=Asia/Shanghai date '+%Y-%m-%d %H:%M')"
echo "══════════════════════════════════════════"

# 1. 校验 manifest 引用的分支入口
echo ""
echo "🔎 1. 分支入口完整性:"
python3 - "$MANIFEST" << 'PYEOF'
import re, os, sys
text = open(sys.argv[1], encoding='utf-8').read()
# 只匹配反引号包裹的路径（manifest 表格中的可验证入口）
paths = re.findall(r'`(D:\\(?:Agent文件|工作)\\[^`]+)`', text)
paths = [p for p in paths if '*' not in p]  # 排除通配符
ok = 0; missing = []
for p in paths:
    wsl = '/mnt/d/' + p[2:].replace('\\', '/')
    if os.path.exists(wsl): ok += 1
    else: missing.append(p)
print(f"  ✅ {ok}/{len(paths)} 路径存在")
for m in missing: print(f"  ❌ 缺失: {m}")
if missing:
    print("  ⚠️ 建议: 更新 config/branch-manifest.md 或补充分支目录")
    exit(1) if not os.environ.get('TRIO_ALLOW_MISSING') else None
PYEOF

# 2. 两库规模快照（与 metrics 口径一致）
echo ""
echo "📊 2. 两库规模:"
companies=$(find "/mnt/d/工作/对标库/company-benchmark/" -mindepth 1 -maxdepth 1 -type d ! -name "*.md" 2>/dev/null | wc -l)
people=$(find "/mnt/d/工作/对标库/person-benchmark/" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
branches=$(ls /mnt/d/Agent文件/ 2>/dev/null | grep -c "^TRIO-")
echo "  对标库公司: $companies | 人物: $people | 分支目录: $branches"

# 3. 引用 manifest 是否被 /all 正确接线
echo ""
echo "🔌 3. 接线确认:"
if grep -q "branch-manifest" "/mnt/c/Users/Rex/.claude/commands/all.md"; then
  echo "  ✅ /all 已引用 branch-manifest（Step 1 分支检测）"
else
  echo "  ❌ /all 未接线 branch-manifest"
fi

echo ""
echo "──────────────────────────────────────────"
echo "  巡检完成"
echo "  备注: 分支 manifest 变更 → /all 自动生效（引用的是文件路径）"
echo "  挂 cron 建议: 7 9 * * 1 bash '$ROOT/scripts/branch-index-check.sh' >> '$ROOT/state/cron.log'"
