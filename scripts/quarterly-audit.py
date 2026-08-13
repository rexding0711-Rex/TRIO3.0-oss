#!/usr/bin/env python3
"""
TRIO 3.0 季度反查脚本 — 框架权威效应的防线

每季度从 Decision Ledger 随机抽取 10% 已归档决策，
输出审计清单——提醒用户用完全不同的 prompt 重跑对比。

用法: python quarterly-audit.py [--json] [--dry-run]
退出码: 0=成功 | 1=Decision Ledger 不可用

设计: PDF风险分析 R12(框架权威效应) → 定期反查机制
"""
from __future__ import annotations

import json, random, sqlite3, sys
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

DB_PATH = Path("/mnt/d/Agent文件/TRIO-Stock/state/decision-ledger.db")
SAMPLE_RATE = 0.10


@dataclass
class AuditTarget:
    memory_id: str
    topic: str
    type: str
    domain: str
    confidence: int
    outcome_status: str
    created_at: str
    review_prompt: str = ""


def get_archived_decisions(db_path: Path) -> list[dict]:
    if not db_path.exists():
        print(f"Decision Ledger 不存在: {db_path}")
        return []
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    rows = conn.execute("""
        SELECT memory_id, topic, type, domain, confidence, outcome_status, created_at
        FROM memories
        WHERE lifecycle_status = 'archived'
           OR outcome_status IN ('validated', 'superseded')
        ORDER BY created_at DESC
    """).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def sample_targets(decisions: list[dict], rate: float = SAMPLE_RATE) -> list[AuditTarget]:
    if not decisions:
        return []
    sample_size = max(1, int(len(decisions) * rate))
    sampled = random.sample(decisions, min(sample_size, len(decisions)))
    targets = []
    for d in sampled:
        _type, _topic = d["type"], d["topic"]
        if _type == "decision":
            prompt = f"重新评估决策'{_topic}'。使用与原始分析完全不同的框架和信源。当时判定正确吗？新信息会改变结论吗？"
        elif _type == "hypothesis":
            prompt = f"回顾假设'{_topic}'。已被证实还是证伪？如有偏差，为什么？"
        elif _type == "assumption":
            prompt = f"挑战假设'{_topic}'。在今天的市场环境下还成立吗？什么条件变了？"
        else:
            prompt = f"重新审视'{_topic}'。用不同视角——当时遗漏了什么？"
        targets.append(AuditTarget(
            memory_id=d["memory_id"], topic=_topic, type=_type,
            domain=d["domain"], confidence=d["confidence"],
            outcome_status=d["outcome_status"], created_at=d["created_at"],
            review_prompt=prompt
        ))
    return targets


def run(json_output: bool = False) -> str:
    decisions = get_archived_decisions(DB_PATH)
    if not decisions:
        msg = "无已归档决策可供反查"
        print(msg)
        return msg
    targets = sample_targets(decisions)
    if json_output:
        return json.dumps({
            "total_archived": len(decisions), "sample_rate": SAMPLE_RATE,
            "sample_size": len(targets),
            "targets": [{"memory_id": t.memory_id, "topic": t.topic, "type": t.type,
                         "domain": t.domain, "confidence": t.confidence,
                         "outcome_status": t.outcome_status, "created_at": t.created_at,
                         "review_prompt": t.review_prompt} for t in targets]
        }, ensure_ascii=False, indent=2)
    lines = [
        "季度反查 — 框架权威效应防线",
        f"已归档决策: {len(decisions)} 条 | 抽样 {SAMPLE_RATE:.0%} | 抽中 {len(targets)} 条",
        "=" * 50, ""
    ]
    if not targets:
        lines.append("无可反查项")
        return "\n".join(lines)
    by_domain: dict[str, list[AuditTarget]] = {}
    for t in targets:
        by_domain.setdefault(t.domain or "unknown", []).append(t)
    for domain, items in sorted(by_domain.items()):
        lines.append(f"## {domain} ({len(items)} 条)")
        for t in items:
            conf_icon = "[高]" if t.confidence >= 4 else "[中]" if t.confidence >= 3 else "[低]"
            lines.append(f"  {conf_icon} [{t.type}] {t.topic}")
            lines.append(f"     创建: {t.created_at} | 状态: {t.outcome_status}")
        lines.append("")
    lines.append("=" * 50)
    lines.append("对以上每条用不同 prompt 和信源重跑。对比结果写入 Decision Ledger。")
    lines.append(f"下次反查: {(datetime.now() + timedelta(days=90)).strftime('%Y-%m-%d')}")
    return "\n".join(lines)


def main():
    json_out = "--json" in sys.argv
    print(run(json_output=json_out))


if __name__ == "__main__":
    main()
