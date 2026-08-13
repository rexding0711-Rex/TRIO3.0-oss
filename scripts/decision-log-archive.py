#!/usr/bin/env python3
"""decision-log 归档（dsh 吸收 2026-08-14：归档冻结 append-only）

把 decision-log.jsonl 中指定 id 的判断标记为 archived：
- 原文件行加 archived:true + archived_at（不移动行序，兼容校准/读取器）
- 冻结快照写入 state/archived/decision-log/{id}.json（只追加，不覆盖）
- manifest 追加一行（append-only，含原文快照）

用法: python3 scripts/decision-log-archive.py <id> [原因]
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

TRIO_ROOT = Path(__file__).resolve().parent.parent
LEDGER = TRIO_ROOT / "state" / "decision-log.jsonl"
ARCHIVE_DIR = TRIO_ROOT / "state" / "archived" / "decision-log"
MANIFEST = ARCHIVE_DIR / "manifest.jsonl"


def now_iso() -> str:
    """本地时区 ISO 时间戳。"""
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def load_entries() -> list[dict]:
    """读取决策账本全部条目；损坏行抛错而非静默跳过（fail-loud）。"""
    entries: list[dict] = []
    try:
        with LEDGER.open(encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                entries.append(json.loads(line))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"决策账本读取失败: {LEDGER}") from exc
    return entries


def find_entry(entries: list[dict], target_id: str) -> int:
    """定位目标 id；找不到或已归档则报错。"""
    for idx, entry in enumerate(entries):
        if entry.get("id") == target_id:
            if entry.get("archived"):
                raise RuntimeError(f"条目已归档: {target_id}")
            return idx
    raise RuntimeError(f"账本中不存在 id: {target_id}")


def write_back(entries: list[dict]) -> None:
    """重写账本（目标行已通过对象引用修改），先备份原文件。"""
    backup = LEDGER.with_suffix(".jsonl.bak-archiving")
    try:
        if not backup.exists():
            backup.write_text(LEDGER.read_text(encoding="utf-8"), encoding="utf-8")
        with LEDGER.open("w", encoding="utf-8") as f:
            for entry in entries:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError as exc:
        raise RuntimeError(f"账本重写失败，备份在 {backup}") from exc


def freeze_snapshot(entry: dict, reason: str) -> None:
    """写冻结快照 + 追加 manifest（append-only）。"""
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    entry_id = entry["id"]
    snapshot = ARCHIVE_DIR / f"{entry_id}.json"
    try:
        if not snapshot.exists():  # 只写一次，不覆盖
            snapshot.write_text(
                json.dumps(entry, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
        with MANIFEST.open("a", encoding="utf-8") as f:
            f.write(
                json.dumps(
                    {
                        "id": entry_id,
                        "archived_at": now_iso(),
                        "reason": reason,
                        "snapshot": snapshot.name,
                    },
                    ensure_ascii=False,
                )
                + "\n"
            )
    except OSError as exc:
        raise RuntimeError(f"归档快照写入失败: {snapshot}") from exc


def main(argv: list[str]) -> int:
    if len(argv) < 1:
        print("用法: decision-log-archive.py <id> [原因]")
        return 1
    target_id = argv[0]
    reason = " ".join(argv[1:]) or "(未填写归档原因)"
    if not LEDGER.exists():
        print(f"❌ 决策账本不存在: {LEDGER}")
        return 1
    entries = load_entries()
    idx = find_entry(entries, target_id)
    entry = entries[idx]  # 对象引用，后续修改会作用于列表元素
    entry["archived"] = True
    entry["archived_at"] = now_iso()
    entry["archive_reason"] = reason
    write_back(entries)
    freeze_snapshot(entry, reason)
    print(f"✅ 已归档: {target_id} → state/archived/decision-log/")
    print(f"   原因: {reason}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RuntimeError as exc:
        print(f"❌ {exc}")
        sys.exit(1)
