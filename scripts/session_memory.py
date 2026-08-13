"""
TRIO 会话记忆层 — 进程内工作记忆（ADR-010: Neo4j 已移除，降级为内存）

原设计用 Neo4j 持久化跨进程记忆(MemGraphRAG/VoG)；ADR-010 移除 Neo4j 后
降级为进程内 list —— 单次分析会话内的 remember→recall 完全够用，
且去掉了 onboarding 的 Neo4j 依赖。
接口(remember/recall/stats/forget_session/close)保持不变，
下游 vps_reason 的调用无需改动。
"""
from datetime import datetime


class SessionMemory:
    """进程内会话工作记忆（原 Neo4j 版降级，ADR-010）"""

    def __init__(self, session_id: str = None):
        self.session_id = session_id or datetime.now().strftime("%Y%m%d-%H%M%S")
        self.step_counter = 0
        self._findings: list[dict] = []

    # ================================================================
    # 写入：把推理步骤的关键发现存入进程内记忆
    # ================================================================
    def remember(self, step_name: str, content: str, entities: list[str] = None,
                 confidence: int = 3, source: str = "vps_reason") -> str:
        """记录一个推理步骤的关键发现。返回 finding_id。"""
        self.step_counter += 1
        finding_id = f"{self.session_id}-step{self.step_counter}"
        summary = content[:200].replace("'", "").replace('"', "").replace("\n", " ")
        self._findings.append({
            "id": finding_id,
            "step": self.step_counter,
            "step_name": step_name,
            "summary": summary,
            "entities": entities or [],
            "confidence": confidence,
            "source": source,
        })
        return finding_id

    # ================================================================
    # 查询：取回相关历史发现
    # ================================================================
    def recall(self, search_terms: str = None, limit: int = 10) -> str:
        """从进程内记忆取回相关发现（search_terms 命中 summary/entities 优先）。"""
        findings = self._findings
        if search_terms:
            terms = search_terms.split()
            filtered = [
                f for f in findings
                if any(t in f["summary"] or t in " ".join(f["entities"]) for t in terms)
            ]
            findings = filtered or self._findings  # 无匹配则回退全部
        findings = sorted(findings, key=lambda f: f["step"], reverse=True)[:limit]
        if not findings:
            return "（无历史发现）"
        lines = [f"## 会话记忆 ({self.session_id}, {len(findings)} 条发现)"]
        for f in findings:
            conf_bar = "🟢" if f["confidence"] >= 4 else "🟡" if f["confidence"] >= 3 else "🔴"
            lines.append(f"- [{f['step_name']}·{f['step']}] {conf_bar} {f['summary'][:150]}")
        return "\n".join(lines)

    # ================================================================
    # 管理：统计、清理
    # ================================================================
    def stats(self) -> dict:
        if not self._findings:
            return {"session": self.session_id, "total_findings": 0, "avg_confidence": 0}
        avg = sum(f["confidence"] for f in self._findings) / len(self._findings)
        return {
            "session": self.session_id,
            "total_findings": len(self._findings),
            "avg_confidence": round(avg, 1),
        }

    def forget_session(self):
        """清空当前 session 的记忆。"""
        self._findings.clear()

    def close(self):
        pass


# ============================================================
# CLI 测试
# ============================================================
if __name__ == "__main__":
    mem = SessionMemory()
    print("📝 模拟长程分析任务（进程内记忆，ADR-010）...")
    mem.remember("初始分析", "碳酸锂供给端: 澳洲Greenbushes和智利Atacama新矿Q3投产,预计新增产能15万吨LCE",
                 entities=["碳酸锂", "澳洲", "智利"], confidence=4)
    mem.remember("需求评估", "电动车增速从30%降至15%,宁德时代Q1电池产量增速放缓至12%",
                 entities=["宁德时代(CATL)", "动力电池"], confidence=3)
    mem.remember("价格判断", "综合供需,碳酸锂价格2026H2预计从8万继续下跌至6-7万区间",
                 entities=["碳酸锂"], confidence=2)
    print("\n🔍 查询记忆...")
    print(mem.recall("碳酸锂 供给 产能"))
    print()
    print(mem.stats())
    mem.close()
    print("\n✅ 会话记忆层就绪（进程内）")
