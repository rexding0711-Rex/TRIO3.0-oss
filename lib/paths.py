#!/usr/bin/env python3
"""TRIO 唯一路径加载器（终局改造：paths.conf/.pathconfig/env/TRIO_ROOT 收敛为单一来源）

所有 runtime 脚本一律 from lib.paths import paths 获取路径，禁止自行硬编码绝对路径。
优先级: 环境变量 > 默认值（TRIO_ROOT 由本文件位置动态推导，天然可移植）。

用法:
    from lib.paths import paths
    paths.root      # TRIO 根目录
    paths.state     # state/（本机账本）
    paths.config    # config/
    paths.fixtures  # fixtures/
    paths.ledger_db # SQLite 账本路径（TRIO_LEDGER_DB 可覆盖）
"""
from __future__ import annotations

import os
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent


class Paths:
    """集中路径定义——runtime 唯一路径来源。"""

    def __init__(self) -> None:
        self.root: Path = _ROOT
        self.state: Path = _ROOT / "state"
        self.config: Path = _ROOT / "config"
        self.fixtures: Path = _ROOT / "fixtures"
        self.core: Path = _ROOT / "core"
        self.lib: Path = _ROOT / "lib"
        self.ledger_db: Path = Path(os.environ.get("TRIO_LEDGER_DB", str(_ROOT / "state" / "decision-ledger.db")))
        self.decision_log: Path = _ROOT / "state" / "decision-log.jsonl"


paths = Paths()
