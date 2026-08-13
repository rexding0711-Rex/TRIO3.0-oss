#!/usr/bin/env python3
"""TRIO Decision Runtime（终局改造核心：唯一、不可绕过的 commit 边界）

全系统正式 Decision 只允许通过 commit_decision() 进入持久层。
任何 gate 失败 → commit_status = DENIED，不写入。
例外/schema 缺失/未知状态一律 fail closed（抛错或拒绝），不静默降级。

流程:
    candidate
      → DecisionRecord.from_candidate (Schema Gate, fail closed on missing)
      → constitution.check (Constitution Gate)
      → persist (JSONL projection; SQLite 经 ledger.append_committed 接入)
      → COMMITTED
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from core.decision_record import DecisionRecord, GateResult
from core import constitution
from lib.paths import paths


def _persist_jsonl(record: DecisionRecord) -> None:
    """JSONL projection 持久化（audit export 用；SQLite 为 canonical source，经 ledger 接入）。"""
    ledger = paths.decision_log
    ledger.parent.mkdir(parents=True, exist_ok=True)
    with ledger.open("a", encoding="utf-8") as f:
        f.write(record.to_jsonl_line() + "\n")
        f.flush()


def _persist_sqlite(record: DecisionRecord) -> None:
    """SQLite canonical 持久化——经 decision_ledger.append_committed（其内部拒绝非 COMMITTED）。

    当前 SQLite 账本在 scripts/，core 不直接依赖；此 hook 供接入层调用。
    若 ledger 不可用，fail closed（抛错）而非静默降级到仅 JSONL。
    """
    try:
        sys.path.insert(0, str(paths.root / "scripts"))
        from decision_ledger import DecisionLedger  # 延迟导入避免循环
        ledger = DecisionLedger()
        ledger.append_committed(record)
        ledger.close()
    except Exception as exc:
        # SQLite 是 canonical source——不可用时不允许 commit（fail closed）
        raise RuntimeError(f"SQLite 账本不可用，commit 拒绝: {exc}") from exc


def commit_decision(candidate: dict[str, Any], *, persist: str = "jsonl") -> DecisionRecord:
    """唯一决策提交入口。persist: jsonl | sqlite | both。失败返回 DENIED record 或抛错。"""
    # ── Schema Gate ─────────────────────────────────────────────
    try:
        record = DecisionRecord.from_candidate(candidate)
    except (KeyError, ValueError) as exc:
        denied = DecisionRecord(claim={}, confidence_score=0.0, commit_status="DENIED")
        denied.gates = [GateResult("schema", "FAIL", str(exc))]
        return denied
    record.gates = [GateResult("schema", "PASS")]

    # ── Constitution Gate ───────────────────────────────────────
    violations = constitution.check(record)
    if violations:
        record.commit_status = "DENIED"
        record.gates.append(GateResult("constitution", "FAIL", "; ".join(violations)))
        return record
    record.gates.append(GateResult("constitution", "PASS"))

    # ── Persistence ─────────────────────────────────────────────
    try:
        if persist in ("jsonl", "both"):
            _persist_jsonl(record)
        if persist in ("sqlite", "both"):
            _persist_sqlite(record)
    except Exception as exc:
        record.commit_status = "DENIED"
        record.gates.append(GateResult("persist", "FAIL", str(exc)))
        return record

    record.commit_status = "COMMITTED"
    record.gates.append(GateResult("persist", "PASS"))
    return record
