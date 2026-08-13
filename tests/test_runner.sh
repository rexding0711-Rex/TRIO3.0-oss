#!/bin/bash
# ============================================================
# runner.sh 状态机自动化测试（C2 完整化 · 2026-08-12）
# 验证: 解析/执行/optional跳过/状态持久化/断点恢复
# 用法: bash tests/test_runner.sh
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0
ok(){ echo "  ✅ $1"; PASS=$((PASS+1)); }
bad(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# ── mock 场景（2 步：步0必选，步1 optional）───────────────
cat > /tmp/mock-scenario.json << 'EOF'
{"id":"test","name":"测试场景","mode":"quick","steps":[
  {"order":0,"mask":"claude","action":"步骤A","optional":false,"acceptance_criteria":"完成A"},
  {"order":1,"mask":"deepseek","action":"步骤B","optional":true,"acceptance_criteria":"完成B"}
]}
EOF

echo "═══ 测试 1: 语法 ═══"
bash -n scripts/runner.sh && ok "runner.sh 语法 OK" || bad "runner.sh 语法错误"

echo "═══ 测试 2: 完整执行（步0执行,步1跳过）═══"
OUT=$(printf 'y\nn\n' | timeout 10 bash scripts/runner.sh /tmp/mock-scenario.json 2>&1 || true)
RUN_ID=$(echo "$OUT" | grep -oP 'run-\S+' | head -1)
[ -n "$RUN_ID" ] && ok "创建 run: $RUN_ID" || bad "未创建 run"
STATE="state/runs/$RUN_ID/state.json"
if [ -f "$STATE" ]; then
  ok "状态文件存在"
  S0=$(python3 -c "import json;print(json.load(open('$STATE'))['steps'].get('step0',{}).get('status',''))" 2>/dev/null)
  S1=$(python3 -c "import json;print(json.load(open('$STATE'))['steps'].get('step1',{}).get('status',''))" 2>/dev/null)
  [ "$S0" = "completed" ] && ok "step0=completed" || bad "step0=$S0 (期望 completed)"
  [ "$S1" = "skipped" ] && ok "step1=skipped (optional 跳过)" || bad "step1=$S1 (期望 skipped)"
else
  bad "状态文件缺失"
fi

echo "═══ 测试 3: 断点恢复（resume 跳过已完成步）═══"
OUT2=$(printf 'y\n' | timeout 10 bash scripts/runner.sh /tmp/mock-scenario.json --resume --run-id "$RUN_ID" 2>&1 || true)
echo "$OUT2" | grep -q "已完成（跳过）" && ok "resume 识别已完成步" || bad "resume 未跳过已完成步"

echo "═══ 测试 4: 场景不存在（应报错）═══"
OUT4=$(bash scripts/runner.sh /tmp/nonexistent.json 2>&1 || true)
echo "$OUT4" | grep -q "场景不存在" && ok "缺场景正确报错" || bad "缺场景未报错"

echo ""
echo "════════════════════════════"
echo "  测试结果: ✅ $PASS 通过 | ❌ $FAIL 失败"
[ $FAIL -eq 0 ] && echo "  🎉 runner 状态机全部通过" || echo "  ❌ 有失败"
exit $FAIL
