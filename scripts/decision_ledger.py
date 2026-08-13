#!/usr/bin/env python3
"""TRIO 3.0 Decision Ledger v1 — SQLite 决策记忆账本
设计: lifecycle_status(生命周期) × outcome_status(验证结果) 双轨状态机
5种记忆类型: decision / assumption / hypothesis / constraint / lesson

版本: 统一在 TRIO 3.0（曾标注 3.1，版本边界冻结于 3.0，2026-08-14 修复）
路径: 动态推导，禁止硬编码绝对路径（曾指向 /mnt/d/Agent文件/...，违反 paths.conf 纪律）
      可用环境变量 TRIO_LEDGER_DB 覆盖（如 TRIO-Stock 分支指向独立账本）
"""
import os
import sqlite3, json, uuid
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

TRIO_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = Path(os.environ.get("TRIO_LEDGER_DB", str(TRIO_ROOT / "state" / "decision-ledger.db")))

SCHEMA = """
CREATE TABLE IF NOT EXISTS memories (
    memory_id TEXT PRIMARY KEY,
    type TEXT CHECK(type IN ('decision','assumption','hypothesis','constraint','lesson')),

    -- 内容
    topic TEXT NOT NULL,
    content TEXT NOT NULL,
    evidence TEXT,

    -- 分类与权重
    domain TEXT CHECK(domain IN ('stock','architecture','process','methodology')),
    impact_score INTEGER CHECK(impact_score BETWEEN 1 AND 5),
    confidence INTEGER CHECK(confidence BETWEEN 1 AND 5),

    -- 双轨状态机
    lifecycle_status TEXT CHECK(lifecycle_status IN ('proposed','active','archived')) DEFAULT 'proposed',
    outcome_status TEXT CHECK(outcome_status IN ('pending','validated','falsified','superseded','expired')) DEFAULT 'pending',

    -- 关联
    source_session_id TEXT,
    superseded_by TEXT,
    related_memories TEXT,

    -- 时间
    created_at TEXT DEFAULT (datetime('now','localtime')),
    review_at TEXT,
    verified_at TEXT,
    archived_at TEXT,

    -- 学习
    outcome_notes TEXT,
    lesson_extracted TEXT,
    behavior_change TEXT,

    -- 标签
    tags TEXT,
    error_tags TEXT
);

CREATE INDEX IF NOT EXISTS idx_topic ON memories(topic);
CREATE INDEX IF NOT EXISTS idx_lifecycle ON memories(lifecycle_status);
CREATE INDEX IF NOT EXISTS idx_outcome ON memories(outcome_status);
CREATE INDEX IF NOT EXISTS idx_type ON memories(type);
CREATE INDEX IF NOT EXISTS idx_domain ON memories(domain);
"""

class DecisionLedger:
    def __init__(self, db_path: str = str(DB_PATH)):
        self.db = Path(db_path)
        self.db.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(self.db))
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript(SCHEMA)
        self.conn.commit()

    # ═══ CRUD ═══

    def create(self, type_: str, topic: str, content: str, **kwargs) -> str:
        """创建新记忆。返回 memory_id"""
        mid = f"mem_{uuid.uuid4().hex[:8]}"
        now = datetime.now().isoformat()

        self.conn.execute("""INSERT INTO memories
            (memory_id, type, topic, content, evidence, domain, impact_score,
             confidence, lifecycle_status, outcome_status, source_session_id,
             tags, error_tags, review_at, related_memories)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""", (
            mid, type_, topic, content,
            json.dumps(kwargs.get("evidence", []), ensure_ascii=False),
            kwargs.get("domain", "stock"),
            kwargs.get("impact_score", 3),
            kwargs.get("confidence", 3),
            kwargs.get("lifecycle_status", "proposed"),
            kwargs.get("outcome_status", "pending"),
            kwargs.get("source_session_id", ""),
            json.dumps(kwargs.get("tags", []), ensure_ascii=False),
            json.dumps(kwargs.get("error_tags", []), ensure_ascii=False),
            kwargs.get("review_at", (datetime.now() + timedelta(days=30)).date().isoformat()),
            json.dumps(kwargs.get("related_memories", []), ensure_ascii=False)
        ))
        self.conn.commit()
        return mid

    def activate(self, memory_id: str) -> bool:
        """proposed → active"""
        self.conn.execute("UPDATE memories SET lifecycle_status='active' WHERE memory_id=? AND lifecycle_status='proposed'", (memory_id,))
        self.conn.commit()
        return self.conn.total_changes > 0

    def verify(self, memory_id: str, outcome: str, notes: str = "",
               lesson: str = "", behavior_change: str = "") -> bool:
        """记录验证结果"""
        valid = {"validated","falsified","superseded","expired"}
        if outcome not in valid:
            raise ValueError(f"outcome必须是: {valid}")

        self.conn.execute("""UPDATE memories SET outcome_status=?, verified_at=?,
            outcome_notes=?, lesson_extracted=?, behavior_change=?
            WHERE memory_id=?""",
            (outcome, datetime.now().isoformat(), notes, lesson, behavior_change, memory_id))
        self.conn.commit()
        return True

    def supersede(self, old_id: str, new_id: str, reason: str = "") -> bool:
        """新记忆替代旧记忆"""
        self.conn.execute("""UPDATE memories SET outcome_status='superseded',
            superseded_by=?, outcome_notes=? WHERE memory_id=?""",
            (new_id, reason, old_id))
        self.conn.execute("""UPDATE memories SET lifecycle_status='active',
            outcome_status='pending' WHERE memory_id=?""", (new_id,))
        self.conn.commit()
        return True

    def archive(self, memory_id: str) -> bool:
        """active → archived"""
        self.conn.execute("""UPDATE memories SET lifecycle_status='archived',
            archived_at=? WHERE memory_id=?""", (datetime.now().isoformat(), memory_id))
        self.conn.commit()
        return True

    # ═══ 查询 ═══

    def get_active(self, topic: str = None, domain: str = None, limit: int = 20) -> list[dict]:
        """获取当前活跃记忆（会话启动时注入context）"""
        conditions = ["lifecycle_status='active'"]
        params = []
        if topic:
            conditions.append("topic LIKE ?")
            params.append(f"%{topic}%")
        if domain:
            conditions.append("domain=?")
            params.append(domain)

        rows = self.conn.execute(f"""SELECT * FROM memories WHERE {' AND '.join(conditions)}
            ORDER BY impact_score DESC, created_at DESC LIMIT ?""", (*params, limit)).fetchall()
        return [dict(r) for r in rows]

    def get_due_review(self) -> list[dict]:
        """获取今天需要复核的记忆"""
        today = datetime.now().date().isoformat()
        rows = self.conn.execute("""SELECT * FROM memories
            WHERE review_at <= ? AND lifecycle_status != 'archived'
            ORDER BY impact_score DESC""", (today,)).fetchall()
        return [dict(r) for r in rows]

    def get_by_topic(self, topic: str) -> list[dict]:
        rows = self.conn.execute("""SELECT * FROM memories WHERE topic LIKE ?
            ORDER BY created_at DESC LIMIT 10""", (f"%{topic}%",)).fetchall()
        return [dict(r) for r in rows]

    def calibration_stats(self) -> dict:
        """校准统计：各置信度等级的实际验证率"""
        rows = self.conn.execute("""SELECT confidence,
            COUNT(*) as total,
            SUM(CASE WHEN outcome_status='validated' THEN 1 ELSE 0 END) as validated,
            SUM(CASE WHEN outcome_status='falsified' THEN 1 ELSE 0 END) as falsified
            FROM memories WHERE outcome_status IN ('validated','falsified')
            GROUP BY confidence ORDER BY confidence""").fetchall()

        stats = {}
        for r in rows:
            total = r['validated'] + r['falsified']
            stats[f"confidence_{r['confidence']}"] = {
                "total": total,
                "accuracy": round(r['validated'] / total, 2) if total > 0 else None
            }
        return stats

    def close(self):
        self.conn.close()


# ═══ CLI ═══
if __name__ == "__main__":
    import sys
    ledger = DecisionLedger()

    if len(sys.argv) < 2:
        print("TRIO Decision Ledger v1")
        print("  python decision_ledger.py create <type> <topic> <content>")
        print("  python decision_ledger.py list [topic]")
        print("  python decision_ledger.py due       # 待复核")
        print("  python decision_ledger.py stats     # 校准统计")
        sys.exit(0)

    cmd = sys.argv[1]

    if cmd == "create" and len(sys.argv) >= 5:
        mid = ledger.create(sys.argv[2], sys.argv[3], sys.argv[4])
        ledger.activate(mid)
        print(f"✅ {mid} → active")

    elif cmd == "list":
        topic = sys.argv[2] if len(sys.argv) > 2 else None
        memories = ledger.get_active(topic=topic)
        for m in memories:
            print(f"[{m['type']}] {m['topic']} | impact={m['impact_score']} conf={m['confidence']} | {m['outcome_status']}")
            print(f"  {m['content'][:100]}")

    elif cmd == "due":
        for m in ledger.get_due_review():
            print(f"⏰ [{m['type']}] {m['topic']} | review_at={m['review_at']} | {m['content'][:80]}")

    elif cmd == "stats":
        stats = ledger.calibration_stats()
        print(json.dumps(stats, indent=2, ensure_ascii=False))

    ledger.close()
