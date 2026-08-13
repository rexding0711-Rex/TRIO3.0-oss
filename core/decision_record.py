#!/usr/bin/env python3
"""TRIO Canonical Decision Record（终局改造：唯一决策记录模型）

全系统任何正式 Decision 只通过此模型表达，再统一进 commit_decision()。
JSONL / SQLite / Prediction Registry 都是它的 projection，不是第二账本。

confidence 唯一映射（score ∈ [0,1] → level ∈ {1..5}）：
    0.00–0.19 → 1
    0.20–0.39 → 2
    0.40–0.59 → 3
    0.60–0.79 → 4
    0.80–1.00 → 5
阈值以 calibration 数据为校准来源，但映射函数唯一且可审计。
"""
from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Any

SYSTEM_VERSION = "3.0.0"
SCHEMA_VERSION = "1.0"

# score → level 唯一映射（calibration v1 默认阈值，后续只经版本化 proposal 调整）
_SCORE_LEVELS = ((0.20, 1), (0.40, 2), (0.60, 3), (0.80, 4), (1.01, 5))


def score_to_level(score: float) -> int:
    """唯一 score→level 转换。非法输入 fail closed（抛错，不静默降级）。"""
    if not isinstance(score, (int, float)) or not (0.0 <= score <= 1.0):
        raise ValueError(f"confidence score 非法: {score!r}（必须 ∈ [0,1]）")
    for threshold, level in _SCORE_LEVELS:
        if score < threshold:
            return level
    return 5  # pragma: no cover — 0.80+ 已在上行返回


@dataclass
class GateResult:
    """单个 gate 的结果。"""
    name: str
    status: str  # PASS | FAIL | SKIP
    detail: str = ""


@dataclass
class DecisionRecord:
    """Canonical Decision Record——决策的唯一结构化表达。"""

    claim: dict[str, Any]
    confidence_score: float
    decision: str = "ABSTAIN"  # ACCEPT | REJECT | ABSTAIN
    schema_version: str = SCHEMA_VERSION
    system_version: str = SYSTEM_VERSION
    decision_id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    created_at: str = field(default_factory=lambda: datetime.now(timezone.utc).astimezone().isoformat())
    evidence: list[dict] = field(default_factory=list)
    counter_evidence: list[str] = field(default_factory=list)
    prediction_contract: dict | None = None
    verification: str | None = None  # prediction 验证状态（初始 pending）
    gates: list[GateResult] = field(default_factory=list)
    commit_status: str = "PENDING"  # PENDING | COMMITTED | DENIED

    @property
    def confidence_level(self) -> int:
        return score_to_level(self.confidence_score)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["confidence"] = {"score": self.confidence_score, "level": self.confidence_level}
        return d

    def to_jsonl_line(self) -> str:
        """JSONL projection 序列化。"""
        d = self.to_dict()
        d.pop("gates", None)  # projection 不重复 gate 明细
        return json.dumps(d, ensure_ascii=False)

    @staticmethod
    def from_candidate(candidate: dict[str, Any]) -> "DecisionRecord":
        """从候选 dict 构造（缺失必填字段抛 KeyError——fail closed）。"""
        claim = candidate["claim"]
        if not isinstance(claim, dict) or not claim.get("subject") or not claim.get("object"):
            raise ValueError("candidate 缺少合法 claim（需 subject + object）")
        conf = candidate.get("confidence", 0)
        # 兼容 1-5 制旧字段：confidence 若 >1 视为 level，映射回 score
        score = conf if 0.0 <= conf <= 1.0 else (conf - 0.5) / 5.0
        return DecisionRecord(
            claim=claim,
            confidence_score=max(0.0, min(1.0, score)),
            decision=candidate.get("decision", "ABSTAIN"),
            evidence=candidate.get("evidence", []),
            counter_evidence=candidate.get("counter_evidence", []),
            prediction_contract=candidate.get("prediction_contract"),
            verification=candidate.get("verification"),
        )
