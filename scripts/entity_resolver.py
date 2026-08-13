"""
TRIO 实体消歧模块 — rapidfuzz 模糊匹配（ADR-010: Neo4j 已移除）

原设计从 Neo4j 拉同 label 候选做三层阈值消歧；ADR-010 移除 Neo4j 后，
无图谱候选源 → resolve() 统一返回 create。保留 rapidfuzz 模糊评分算法
(_fuzzy_score) 与对外部候选的匹配能力(match_against)，
供 4.0 KG 重建或外部传入候选时复用。
依赖: rapidfuzz（可选，缺则退 difflib）
"""
from __future__ import annotations
from dataclasses import dataclass

# 优先用 rapidfuzz（更快更准），没有则退到标准库 difflib
try:
    from rapidfuzz import fuzz as _fuzz_lib

    def _fuzzy_score(a: str, b: str) -> float:
        """中文实体名：partial_ratio 处理简称/全称/中英混，WRatio 兜底"""
        pr = _fuzz_lib.partial_ratio(a, b)
        if pr >= 90:
            return pr
        return max(pr, _fuzz_lib.WRatio(a, b))
except ImportError:
    from difflib import SequenceMatcher

    def _fuzzy_score(a: str, b: str) -> float:
        """标准库退路"""
        a_clean = a.lower().replace("(", " ").replace(")", " ")
        b_clean = b.lower().replace("(", " ").replace(")", " ")
        if a_clean.strip() in b_clean.strip() or b_clean.strip() in a_clean.strip():
            return 95.0
        return SequenceMatcher(None, a_clean, b_clean).ratio() * 100


# 三层阈值（可调）
AUTO_MERGE = 95      # ≥95% 自动合并
FLAG_REVIEW = 85     # 85-94% 标记人工审核
# <85% → 创建新节点


@dataclass
class ResolveResult:
    """消歧结果"""
    action: str          # "merge" | "flag" | "create"
    matched_node: dict | None = None
    score: float = 0.0
    reason: str = ""


class EntityResolver:
    """实体消歧器（ADR-010 降级：无 Neo4j 候选源，resolve 恒返回 create）"""

    def __init__(self, auto_merge: int = AUTO_MERGE, flag_review: int = FLAG_REVIEW):
        self.auto_merge = auto_merge
        self.flag_review = flag_review

    def resolve(self, name: str, label: str) -> ResolveResult:
        """ADR-010: Neo4j 已移除，无图谱候选源 → 统一创建新节点。
        下游(fact_check._resolve_name)据此回退到原始名称，不崩。"""
        return ResolveResult(action="create", reason="KG已移除(ADR-010)，无候选源")

    def match_against(self, name: str, candidates: list[str]) -> ResolveResult:
        """对外部传入的候选列表做 rapidfuzz 模糊匹配（保留有用逻辑供复用）。"""
        best, best_score = None, 0.0
        for cname in candidates:
            score = _fuzzy_score(name, cname)
            if score > best_score:
                best_score, best = score, cname
        if best_score >= self.auto_merge:
            return ResolveResult(action="merge", matched_node={"name": best}, score=best_score,
                                 reason=f"模糊匹配 {best_score}% ≥ {self.auto_merge}%")
        elif best_score >= self.flag_review:
            return ResolveResult(action="flag", matched_node={"name": best}, score=best_score,
                                 reason=f"模糊匹配 {best_score}%，需人工确认")
        return ResolveResult(action="create", score=best_score,
                             reason=f"最佳匹配 {best_score}% < {self.flag_review}%")

    def close(self):
        pass


# ============================================================
# CLI 测试
# ============================================================
if __name__ == "__main__":
    r = EntityResolver()
    print("ADR-010: EntityResolver 已降级（无 Neo4j）。rapidfuzz 模糊匹配保留:")
    print(r.match_against("国轩高科", ["国轩高科(Gotion)", "宁德时代(CATL)", "比亚迪"]))
