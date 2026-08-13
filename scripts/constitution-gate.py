#!/usr/bin/env python3
"""宪法硬门禁（dsh 吸收 2026-08-14：Constitution → Runtime Gate）

把 TRIO-CONSTITUTION.md 的规则变成机器强制，治疗 Constitutional Drift
（文档要求"高置信必附反证"，执行层无检查——实测 107 条高置信 104 条无反证）。

规则（R1/R2 对 2026-08-11 之后新增的条目强制；历史条目豁免——grandfather 原则）：
  R1: confidence >= 4 必须附 counter_evidence（Rule 1: ≥4 置信必须反证）
  R2: prediction_contract 存在时必须含 success_condition + failure_condition + verification_source
  R3: verification 初始应为 pending（不允许事后补"对/错"——防 hindsight bias）

用法: python3 scripts/constitution-gate.py [--check] [--recent-only]
  --check        有硬违规则 exit 1（供 full-system-verify / 写入钩子接入）
  --recent-only  只检查 2026-08-11 后的条目（默认全量+标注历史豁免）
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

TRIO_ROOT = Path(__file__).resolve().parent.parent
LEDGER = TRIO_ROOT / "state" / "decision-log.jsonl"

# counter_evidence 规则引入日（GOAI 评审后）：此前的条目豁免（历史字段不存在）
# 用 +08:00 与 decision-log 的 ts 对齐（decision-log 均带 +0800 时区）
RULE_EPOCH = datetime(2026, 8, 11, tzinfo=timezone(timedelta(hours=8)))

REQUIRED_PREDICTION_FIELDS = ("success_condition", "failure_condition", "verification_source")


def parse_ts(ts: str) -> datetime | None:
    """解析 decision-log 的 ts（如 2026-08-13T22:10:00+0800）。"""
    for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(ts.strip(), fmt)
        except ValueError:
            continue
    return None


def check_entry(entry: dict) -> tuple[list[str], bool]:
    """检查单条，返回 (violations, is_recent)。"""
    violations: list[str] = []
    ts = parse_ts(entry.get("ts", ""))
    recent = ts is None or ts >= RULE_EPOCH  # 无法解析视为新条目，从严
    conf = entry.get("confidence", 0)
    if recent and conf >= 4 and not entry.get("counter_evidence"):
        violations.append(
            f"R1 高置信无反证: {entry.get('id', '?')} confidence={conf}"
        )
    pc = entry.get("prediction_contract")
    if recent and isinstance(pc, dict):
        missing = [f for f in REQUIRED_PREDICTION_FIELDS if not pc.get(f)]
        if missing:
            violations.append(
                f"R2 prediction_contract 缺字段: {entry.get('id', '?')} 缺 {','.join(missing)}"
            )
    # R3: 注册时必须声明 verification（初始 pending）；verified/falsified 是校准后的正常结果，不算违规
    # 只检查 prediction_contract 存在但 verification 完全缺失的（注册时未声明 = hindsight 风险）
    if recent and isinstance(pc, dict) and not entry.get("verification"):
        violations.append(
            f"R3 prediction 未声明 verification: {entry.get('id', '?')}"
        )
    return violations, recent


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="宪法硬门禁")
    parser.add_argument("--check", action="store_true", help="有硬违规则 exit 1")
    parser.add_argument("--recent-only", action="store_true", help="只检查 2026-08-11 后条目")
    args = parser.parse_args(argv)

    try:
        entries = [json.loads(l) for l in LEDGER.read_text(encoding="utf-8").splitlines() if l.strip()]
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"决策账本读取失败: {LEDGER}") from exc

    hard: list[str] = []
    grandfathered = 0
    for entry in entries:
        violations, recent = check_entry(entry)
        if not recent:
            grandfathered += 1  # 历史豁免（字段引入前）
            continue
        if violations:
            hard.append(violations[0])

    total = len(entries)
    print(f"═══ 宪法门禁: {total} 条决策 ═══")
    if hard:
        print(f"❌ 硬违规 {len(hard)} 条：")
        for v in hard[:10]:
            print(f"  · {v}")
        if len(hard) > 10:
            print(f"  … 共 {len(hard)} 条")
    else:
        print(f"✅ 无硬违规（2026-08-11 后条目均合规）")
    print(f"ℹ️ 历史条目豁免（字段引入前，grandfather）: {grandfathered} 条")
    return 1 if args.check and hard else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RuntimeError as exc:
        print(f"❌ {exc}")
        sys.exit(1)
