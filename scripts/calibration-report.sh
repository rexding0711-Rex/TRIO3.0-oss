#!/usr/bin/env bash
# ============================================================
# calibration-report.sh — 决策校准回测（P0·飞轮点火器）
# 把 decision-log 的 verified/falsified 决策汇总成校准曲线
# 回答: 我置信度 4/5 的判断,实际命中率有多高?
#
# 用法:
#   calibration-report.sh            # 全量校准报告
#   calibration-report.sh --pending  # 只看待回测队列
#
# 数据源: state/decision-log.jsonl
# 依赖: trio-verify.sh 先标记验证状态(pending→verified/falsified)
# ============================================================
set -euo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8

LOG="/mnt/d/TRIO 3.0/state/decision-log.jsonl"
MODE="${1:-full}"

python3 - "$LOG" "$MODE" << 'PYEOF'
import json, sys, collections

log_path, mode = sys.argv[1:3]
rows = []
legacy = 0
for l in open(log_path, encoding='utf-8'):
    l = l.strip()
    if not l or l.startswith('#'): continue
    try:
        d = json.loads(l)
        # 旧格式检测(mask/decision 字段 = 8-08 schema 迁移前)
        if 'mask' in d or 'decision' in d:
            legacy += 1
            continue
        rows.append(d)
    except Exception as e:
        print(f"⚠️ 损坏行跳过: {e}")
if legacy:
    print(f"⚠️ 跳过 {legacy} 条旧格式记录(缺 persona/claim)——建议运行 schema 迁移")

# 统计分布
total = len(rows)
by_persona = collections.Counter(r.get('persona') for r in rows)
by_claim = collections.Counter(r.get('claim_type') for r in rows)
by_conf = collections.Counter(r.get('confidence') for r in rows)

# 已验证的决策
verified = [r for r in rows if r.get('verification') in ('verified', 'falsified')]
pending = [r for r in rows if r.get('verification', 'pending') == 'pending']

print("=" * 58)
print("TRIO 决策校准回测报告")
print("=" * 58)
print(f"\n📊 决策总量: {total}")
print(f"   面具分布: " + ", ".join(f"{k}={v}" for k, v in by_persona.most_common()))
print(f"   判断类型: " + ", ".join(f"{k}={v}" for k, v in by_claim.most_common()))
print(f"   置信度分布: " + ", ".join(f"{k}:{v}" for k, v in sorted(by_conf.items())))

print(f"\n✅ 已验证: {len(verified)} 条 | 🕓 待验证: {len(pending)} 条")

if verified:
    print("\n" + "-" * 58)
    print("校准曲线: 置信度 → 实际命中率")
    print("-" * 58)
    print(f"{'置信度':<8}{'总数':<6}{'命中':<6}{'命中率':<10}")
    by_conf_ver = collections.defaultdict(lambda: [0, 0])  # [total, hit]
    for r in verified:
        c = r.get('confidence')
        by_conf_ver[c][0] += 1
        if r.get('verification') == 'verified':
            by_conf_ver[c][1] += 1
    for c in sorted(by_conf_ver):
        total_c, hit_c = by_conf_ver[c]
        rate = hit_c / total_c * 100
        bar = '█' * int(rate / 10)
        print(f"{c:<8}{total_c:<6}{hit_c:<6}{rate:<10.0f}% {bar}")

    hits = sum(1 for r in verified if r.get('verification') == 'verified')
    print(f"\n🎯 Accuracy(预测命中率): {hits}/{len(verified)} = {hits/len(verified)*100:.0f}%")
    # 简单提示: 置信度均值 vs 命中率(理想校准: 置信度4/5 ≈ 命中率80-100%)
    avg_conf = sum(r.get('confidence', 3) for r in verified) / len(verified)
    print(f"   平均置信度: {avg_conf:.1f}/5")
    if hits and avg_conf:
        print(f"   📌 校准提示: 置信度均值 {avg_conf:.1f} vs 命中率 {hits/len(verified)*100:.0f}% —— {'偏保守,可上调置信度' if hits/len(verified)*100 > avg_conf*20 else '偏乐观,建议下调置信度'}")

    # Calibration Error(2026-08-11 吸收自 GOAI 评审)——Accuracy 与 Calibration 是独立 KPI
    print("\n" + "-" * 58)
    print("Calibration Error(校准误差)——Accuracy 之外的第二 KPI")
    print("-" * 58)
    print("   原理: 置信度 [c/5] 理想命中率应为 c/5。实际命中率与理想命中率的偏差 = 校准误差")
    ce_sum = 0.0
    ce_n = 0
    for c in sorted(by_conf_ver):
        total_c, hit_c = by_conf_ver[c]
        ideal = c / 5.0
        actual = hit_c / total_c if total_c else 0
        err = abs(ideal - actual)
        ce_sum += err * total_c
        ce_n += total_c
        print(f"   置信度 {c}/5: 理想 {ideal:.0%} vs 实际 {actual:.0%} → 偏差 {err:.0%}")
    if ce_n:
        ce = ce_sum / ce_n
        print(f"\n   📐 加权 Calibration Error: {ce:.0%}(0%=完美校准, 值越大越不自知)")
        print(f"   → 系统在该样本上的过度自信/保守程度量化。这是'知道自己判断边界'的度量, 与命中率独立")

    # 选择性预测覆盖率(2026-08-11 吸收自 GOAI 评审第三轮)——防"永远说谨慎"的废物系统
    print("\n" + "-" * 58)
    print("选择性预测覆盖率(第四指标)——系统敢给高置信吗")
    print("-" * 58)
    high_conf = sum(v for c, v in by_conf_ver.items() if c >= 4)  # 高置信预测数
    coverage = high_conf / total * 100 if total else 0
    print(f"   高置信预测(≥4): {high_conf}/{total} = {coverage:.0f}%")
    print(f"   → 一个永远说'谨慎'的系统 Accuracy 可能很高但覆盖率低 = '谨慎的废物'")
    print(f"   理想: 高覆盖率 + 低校准误差 = '校准的助手'")

    # 分桶校准(2026-08-11 吸收自 GOAI 评审)——单条总曲线没行动价值
    print("\n" + "-" * 58)
    print("分桶校准: 按判断类型(单条总曲线无行动价值)")
    print("-" * 58)
    by_type_ver = collections.defaultdict(lambda: [0, 0])  # {type: [total, hit]}
    for r in verified:
        t = r.get('claim_type', 'unknown')
        by_type_ver[t][0] += 1
        if r.get('verification') == 'verified':
            by_type_ver[t][1] += 1
    for t, (total_t, hit_t) in sorted(by_type_ver.items()):
        rate_t = hit_t / total_t * 100 if total_t else 0
        print(f"  {t:<25}{total_t:<6}{hit_t:<6}{rate_t:<8.0f}%")
else:
    print("\n⚠️ 尚无已验证决策——校准曲线无法计算。")
    print("   先用 trio-verify.sh 标记验证状态:")
    print("   trio-verify.sh list                    # 列出 pending")
    print("   trio-verify.sh <id> ok|no \"<实际结果>\"  # 回测")

if mode == '--pending':
    print("\n" + "-" * 58)
    print("🕓 待回测队列(按置信度排序,高置信优先回测)")
    print("-" * 58)
    for r in sorted(pending, key=lambda x: -(x.get('confidence') or 0)):
        print(f"  {r.get('id')} | conf={r.get('confidence')} | {str(r.get('claim'))[:50]}")

# 置信度漂移警告: 未打标占比过高
if len(pending) / total > 0.7:
    print("\n⚠️ 待验证占比 >70% —— 飞轮未转起来。")
    print("   校准的前提是持续回测。建议每周抽 10 条 pending 用 trio-verify.sh 回测。")
PYEOF
