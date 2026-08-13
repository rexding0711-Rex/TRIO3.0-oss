"""Decision Runtime 核心测试——验证唯一 commit 路径 + fail closed。

终局改造（2026-08-14）：任何 gate 失败 → 不能 commit。
"""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from core.decision_record import score_to_level
from core import decision_runtime


def _candidate(**overrides) -> dict:
    base = {
        "claim": {"subject": "测试公司", "predicate": "采用", "object": "测试工艺"},
        "confidence": 0.5,  # level 3（0.40-0.59），无需反证
        "decision": "ACCEPT",
    }
    base.update(overrides)
    return base


def test_score_to_level_boundaries():
    """score→level 唯一映射边界（fail closed on invalid）。"""
    assert score_to_level(0.10) == 1
    assert score_to_level(0.30) == 2
    assert score_to_level(0.50) == 3
    assert score_to_level(0.70) == 4
    assert score_to_level(0.90) == 5
    with pytest.raises(ValueError):
        score_to_level(1.5)  # 非法 score，必须抛错不静默


def test_commit_ok_low_confidence():
    """合规候选（level 3 无反证）→ COMMITTED。"""
    rec = decision_runtime.commit_decision(_candidate(), persist="jsonl")
    assert rec.commit_status == "COMMITTED"
    assert all(g.status == "PASS" for g in rec.gates)


def test_commit_denied_high_confidence_no_counter_evidence():
    """违宪候选（level 5 无反证）→ DENIED，不写入。"""
    rec = decision_runtime.commit_decision(
        _candidate(confidence=0.9), persist="jsonl"  # level 5
    )
    assert rec.commit_status == "DENIED"
    assert any(g.name == "constitution" and g.status == "FAIL" for g in rec.gates)


def test_commit_denied_missing_claim():
    """缺 claim 字段 → DENIED（Schema fail closed）。"""
    rec = decision_runtime.commit_decision({"confidence": 0.6}, persist="jsonl")
    assert rec.commit_status == "DENIED"
    assert any(g.name == "schema" and g.status == "FAIL" for g in rec.gates)


def test_commit_ok_with_counter_evidence():
    """高置信但有反证 → 合宪可提交。"""
    rec = decision_runtime.commit_decision(
        _candidate(confidence=0.9, counter_evidence=["市场存在另一解释"]),
        persist="jsonl",
    )
    assert rec.commit_status == "COMMITTED"
