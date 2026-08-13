"""三分类 Regression 测试——ABSTAIN Ground Truth 补齐（2026-08-14）。

TRIO 核心安全能力是 ABSTAIN，但旧 regression 只查 positive/negative，
GT 标 ABSTAIN 的 claim 被 ACCEPT 时漏检。本测试固化三分类检查。
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from core.validator import ExtractionValidator


def _accept_decision(span: str) -> dict:
    return {
        "claim": {"subject": "某公司", "predicate": "采用", "object": "某工艺", "object_type": "Process"},
        "decision": "ACCEPT",
        "evidence": {"evidence_span": span, "source_type": "news", "source_date": "2026-08-01"},
    }


def test_abstain_gt_false_accept_detected():
    """含 GT 关键词('投产')的 ACCEPT → 触发 abstain FALSE_ACCEPT（L1/L3 拦不住的词）。"""
    v = ExtractionValidator().load()
    r = v.run_regression([_accept_decision("该公司已完成技术验证并正式投产新产线")])
    abstain_fa = [f for f in r["failures"] if f.get("expected") == "ABSTAIN"]
    assert len(abstain_fa) >= 1
    assert v.stats["abstain_false_accept"] >= 1


def test_abstain_gt_no_false_accept_on_clean():
    """不含 GT 关键词的 ACCEPT → 不触发 abstain FALSE_ACCEPT。"""
    v = ExtractionValidator().load()
    r = v.run_regression([_accept_decision("该公司已完成技术验证并正式量产交付")])
    abstain_fa = [f for f in r["failures"] if f.get("expected") == "ABSTAIN"]
    assert len(abstain_fa) == 0


def test_abstain_gt_loaded():
    """Ground Truth 的 abstain 样本被正确加载（三分类回归覆盖）。"""
    v = ExtractionValidator().load()
    assert len(v.ground_truth.get("abstain", [])) >= 5
