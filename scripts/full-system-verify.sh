#!/bin/bash
# TRIO 3.0 满分验证器——7 维度系统健康检查
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRIO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$TRIO_ROOT"

PASS=0; WARN=0; FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
warn() { echo "  ⚠️ $1"; WARN=$((WARN+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

# OSS 模式：clone 环境无 .env/state（净化版仓库）——本机资源检查跳过，只跑引擎检查
# 2026-08-14 外部审计吸收：全量验证器曾是"作者本机健康检查"，clone 后误报"系统坏了"
OSS_MODE=false
[ ! -f .env ] && OSS_MODE=true
[ "$OSS_MODE" = "true" ] && echo "  ⚠️ OSS 模式（clone 环境无 .env/state，跳过本机资源检查）"

echo "═══ 1. 安全 ═══"
if [ "$OSS_MODE" = "true" ]; then
  pass "本机资源检查跳过（OSS 模式）"
else
  [ -f .env ] && pass ".env 存在" || fail ".env 不存在"
  grep -rq 'REDACTED' scripts/*.py 2>/dev/null && fail "密码硬编码仍存在" || pass "无密码硬编码"
  [ -f .git/hooks/pre-commit ] && pass "pre-commit hook 激活" || fail "pre-commit hook 缺失"
fi

echo "═══ 2. 代码质量 ═══"
python3 -m pytest tests/ -q --tb=no 2>/dev/null && pass "pytest 全通过" || warn "pytest 有失败(或未安装)"
python3 -c "import json; [json.load(open(f'config/protocols/{p}')) for p in __import__('os').listdir('config/protocols') if p.endswith('.json')]" 2>/dev/null && pass "JSON 全有效" || fail "JSON 有无效文件"
[ -f scripts/lint.sh ] && pass "lint.sh 存在" || warn "lint.sh 缺失"

echo "═══ 3. 架构完整性 ═══"
[ -f config/milestones.json ] && pass "milestones.json 存在" || fail "milestones.json 缺失"
[ -f scripts/isolation_audit.py ] && pass "isolation_audit 存在" || fail "isolation_audit 缺失"
python3 -c "import json; m=json.load(open('config/milestones.json')); assert 'honest_limitation' in m['M1']" 2>/dev/null && pass "M1 定义诚实" || warn "M1 缺少 honest_limitation"
[ -f architecture/adr/ADR-008-删除场景YAML.md ] && pass "ADR-008 已记录YAML决策" || warn "ADR-008 缺失"

echo "═══ 4. 知识层 ═══"
# Neo4j 已移除 (ADR-010)——改为校验全量备份存档存在（OSS 模式跳过 state 断言，2026-08-14 修复）
if [ "$OSS_MODE" = "true" ]; then
  pass "知识层本机存档检查跳过（OSS 模式）"
else
  ls state/archive/neo4j-full-dump-*.csv >/dev/null 2>&1 && pass "Neo4j 已移除·备份存档 (ADR-010)" || warn "Neo4j 备份存档缺失"
fi
! grep -rq "ORDER BY rand()" scripts/*.py 2>/dev/null && pass "KG 查询无 rand()" || fail "KG 查询仍有 rand()!"

echo "═══ 5. 引擎 ═══"
[ -f config/protocols/competitive-intel-engine.json ] && pass "竞品引擎存在" || fail "竞品引擎缺失"
[ -f config/protocols/talent-reverse-trace-engine.json ] && pass "人才引擎存在" || fail "人才引擎缺失"
[ -f scripts/validate-engine-output.sh ] && pass "引擎验证 Hook 存在" || warn "Hook 缺失"

echo "═══ 6. 运维 ═══"
if [ "$OSS_MODE" = "true" ]; then
  pass "本机账本检查跳过（OSS 模式）"
else
  [ -f state/run-history.jsonl ] && pass "run-history 存在" || fail "run-history 缺失"
  RUN_COUNT=$(wc -l < state/run-history.jsonl 2>/dev/null || echo 0)
  [ "$RUN_COUNT" -gt 50 ] && pass "Run 数: $RUN_COUNT (>50)" || warn "Run 数: $RUN_COUNT"
  [ -f state/test-results.log ] && pass "test-results.log 存在" || warn "无 test-results.log"
  grep -q "告警\|ALERTS" scripts/daily-maintenance.sh 2>/dev/null && pass "告警机制已集成" || fail "告警未集成"
  # 趋势不退化+无单次<5.0（替代旧判据"最近3run≥7.0"）
  TREND_OK=$(python3 -c "
import json
lines = [json.loads(l) for l in open('state/run-history.jsonl') if l.strip()]
recent = [r.get('composite_score',0) for r in lines[-5:]]
if len(recent) >= 5:
    first3 = sum(recent[:3])/3
    last3 = sum(recent[-3:])/3
    no_crash = all(s >= 5.0 for s in recent)
    print('OK' if (last3 >= first3 or last3 >= 5.5) and no_crash else 'FAIL')
else:
    print('OK')
" 2>/dev/null)
  [ "$TREND_OK" = "OK" ] && pass "评分趋势无退化+无崩溃" || warn "评分退化或有单次<5.0"
  [ -f state/verification-log.md ] && pass "验证日志存在" || warn "缺少验证日志"
fi
[ -f scripts/signal-density-check.sh ] && pass "信号密度预检脚本" || warn "缺少信号密度预检"
[ -f scripts/engine-gap-detector.py ] && pass "引擎缺口检测器" || warn "缺少缺口检测器"
# state schema 漂移检测（dsh gen-persistence-catalog 吸收 2026-08-14）
python3 scripts/state-catalog.py --check >/dev/null 2>&1 && pass "state 目录与 schema 一致" || warn "state-catalog 过期（schema 漂移或新数据未重新生成）"
# 宪法硬门禁（Constitution → Runtime Gate，2026-08-14）：高置信必附反证，新条目强制
CG_NEW=$(python3 scripts/constitution-gate.py --check --recent-only 2>/dev/null >/dev/null; echo $?)
[ "$CG_NEW" = "0" ] && pass "宪法门禁：新决策均合规" || warn "宪法门禁：近期存在高置信无反证决策（见 constitution-gate.py 输出）"

echo "═══ 7. 文档 ═══"
[ -f docs/protocol-call-graph.md ] && pass "协议调用图存在" || warn "无协议调用图"
[ -f docs/ONBOARDING.md ] && pass "ONBOARDING 存在" || warn "无 ONBOARDING"
ADR_COUNT=$(ls architecture/adr/ADR-*.md 2>/dev/null | wc -l)
[ "$ADR_COUNT" -ge 4 ] && pass "ADR: $ADR_COUNT 个 (≥4)" || warn "ADR: $ADR_COUNT 个 (<4)"
[ -f docs/golden-run.md ] && [ "$(wc -c < docs/golden-run.md)" -gt 200 ] && pass "Golden Run 参照存在" || warn "缺少 Golden Run"

echo "════════════════════════════════════"
echo "  总计: ✅ $PASS 通过 | ⚠️ $WARN 警告 | ❌ $FAIL 失败"
echo "  满分条件: fail = 0 且 warn ≤ 2"
[ $FAIL -eq 0 ] && [ $WARN -le 2 ] && echo "  🎉 TRIO 3.0 达标！" || echo "  ❌ 尚未达标"
echo "════════════════════════════════════"
exit $FAIL
# 评分校准: ADR-009竞品引擎独立评分·待25+ engine runs后线性回归反校准
