#!/usr/bin/env python3
"""TRIO Constitution 核心逻辑（终局改造：从脚本提取为可调用模块，统一给所有入口）

constitution-gate.py / decision-commit.py / decision_runtime.py 均调用此模块——
宪法规则单一实现，禁止各入口各自复制。
"""
from __future__ import annotations

from typing import Any

# R2 预测契约必填字段
REQUIRED_PREDICTION_FIELDS = ("success_condition", "failure_condition", "verification_source")


def check(record: Any) -> list[str]:
    """对 DecisionRecord 执行宪法检查，返回违规列表（空 = 合宪）。

    R1: confidence level ≥ 4 必须附 counter_evidence（Rule 1: 高置信必须反证）
    R2: prediction_contract 必须含 success/failure/verification_source
    R3: prediction 必须声明 verification（初始 pending，防 hindsight bias）
    """
    violations: list[str] = []

    # R1：使用 record 暴露的 confidence_level（canonical score→level 映射）
    level = getattr(record, "confidence_level", 0)
    counter_evidence = getattr(record, "counter_evidence", []) or []
    if level >= 4 and not counter_evidence:
        violations.append(f"R1 高置信无反证: level={level}（confidence≥4 必须附 counter_evidence）")

    # R2 / R3：prediction_contract 存在时强制
    pc = getattr(record, "prediction_contract", None)
    if isinstance(pc, dict):
        missing = [f for f in REQUIRED_PREDICTION_FIELDS if not pc.get(f)]
        if missing:
            violations.append(f"R2 prediction_contract 缺字段: {','.join(missing)}")
        if not getattr(record, "verification", None):
            violations.append("R3 prediction 未声明 verification（初始应为 pending）")

    return violations
