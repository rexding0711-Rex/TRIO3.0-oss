#!/usr/bin/env python3
"""决策提交门（Constitution Gate 前置到 Decision Commit）

把宪法门禁从"事后查 ledger"升级为"写入前硬门"：
  决策候选 → Schema/Constitution Gate → 通过才 commit 进 decision-log.jsonl

审计吸收（2026-08-14）：TRIO 曾"AI 直接 append ledger → 事后 gate 发现违规只 warn"，
现在改为"Commit 不通过就不允许进入 ledger"——Policy enforcement 而非仅 Policy detection。

用法:
  python3 scripts/decision-commit.py <candidate.json> [--force]
    candidate.json: 候选决策（含 ts/persona/claim_type/claim/confidence/basis/upstream/id）
    --force: 跳过宪法检查强制提交（仅调试用，正常流程禁用）

规则（同 constitution-gate.py）:
  R1: confidence >= 4 必须附 counter_evidence（Rule 1: ≥4 置信必须反证）
  R2: prediction_contract 存在时必须含 success_condition + failure_condition + verification_source
  R3: prediction 必须声明 verification（初始 pending，防 hindsight bias）
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

TRIO_ROOT = Path(__file__).resolve().parent.parent
LEDGER = TRIO_ROOT / "state" / "decision-log.jsonl"

REQUIRED_PREDICTION_FIELDS = ("success_condition", "failure_condition", "verification_source")


def constitution_check(entry: dict) -> list[str]:
    """宪法检查，返回违规列表（空 = 合规可提交）。"""
    violations: list[str] = []
    conf = entry.get("confidence", 0)
    if conf >= 4 and not entry.get("counter_evidence"):
        violations.append(f"R1 高置信无反证: confidence={conf} 必须附 counter_evidence")
    pc = entry.get("prediction_contract")
    if isinstance(pc, dict):
        missing = [f for f in REQUIRED_PREDICTION_FIELDS if not pc.get(f)]
        if missing:
            violations.append(f"R2 prediction_contract 缺字段: {','.join(missing)}")
        if not entry.get("verification"):
            violations.append("R3 prediction 未声明 verification（初始应为 pending）")
    return violations


# Schema Gate：候选决策必须含核心字段（缺失 = 结构性无效，拒绝写入）
REQUIRED_FIELDS = ("ts", "persona", "claim_type", "claim", "confidence", "id")


def schema_check(entry: dict) -> list[str]:
    """Schema 检查，返回违规列表（空 = 结构有效）。"""
    return [f"Schema 缺必填字段: {f}" for f in REQUIRED_FIELDS if not entry.get(f)]


def commit(entry: dict) -> bool:
    """原子追加到 ledger（append + flush）。"""
    try:
        with LEDGER.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
            f.flush()
    except OSError as exc:
        raise RuntimeError(f"账本写入失败: {LEDGER}") from exc
    return True


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="决策提交门（写入前宪法检查）")
    parser.add_argument("candidate", help="候选决策 JSON 文件")
    parser.add_argument("--force", action="store_true", help="跳过宪法检查强制提交（调试用）")
    args = parser.parse_args(argv)

    try:
        entry = json.loads(Path(args.candidate).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"❌ 候选读取失败: {exc}")
        return 1

    # Commit Boundary：Schema → Constitution → COMMIT（原子，先过 gate 再写 ledger）
    violations = [] if args.force else schema_check(entry) + constitution_check(entry)
    if violations:
        print("🚫 Commit Boundary 阻断提交（未写入 ledger）：")
        for v in violations:
            print(f"  · {v}")
        print(f"  提示: 补上反证/字段后重新提交；或改 confidence 至 ≤3（R1 仅 ≥4 强制）")
        return 1

    commit(entry)
    print(f"✅ 决策已提交: {entry.get('id', '?')} | confidence={entry.get('confidence')} | 已入 ledger")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RuntimeError as exc:
        print(f"❌ {exc}")
        sys.exit(1)
