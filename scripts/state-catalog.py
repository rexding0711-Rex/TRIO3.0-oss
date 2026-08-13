#!/usr/bin/env python3
"""state 目录生成器 + 验证器（dsh gen-persistence-catalog 模式吸收 2026-08-14）

扫描 state/*.jsonl 实际 schema，产出 docs/state-catalog.md。
--check 模式：重新扫描并与已提交目录逐字节比较，任何漂移 → exit 1。

用途：把"该更新 catalog"从人的纪律变成机械红灯——
      命中 dsh 的 verify-persistence-catalog 精神，直接治疗 TRIO 两个真实事故：
      · schema 漂移静默错误重建（decision-log 等）
      · 文件落库偏差（同一文件两个 writer schema 分叉）

用法: python3 scripts/state-catalog.py [--check]
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

TRIO_ROOT = Path(__file__).resolve().parent.parent
STATE_DIR = TRIO_ROOT / "state"
CATALOG = TRIO_ROOT / "docs" / "state-catalog.md"

# 不做 schema 分析的元文件（内部管理，非数据行）
SKIP_FILES = {"archive", "learning-drafts", "runs", "logs.db", "kg-bootstrap.cypher"}


class FileStat:
    """单个 state 文件的扫描统计。"""

    def __init__(self, path: Path) -> None:
        self.name = path.name
        self.rows = 0
        self.key_counts: Counter[str] = Counter()
        self.type_counts: Counter[str] = Counter()
        self.extra_keys: Counter[str] = Counter()  # 漂移行独有字段
        self.drift_rows = 0  # 字段集与多数行不一致的行数
        self.bad_lines = 0   # 非 JSON 且非合法分隔格式的行数
        self.format = "jsonl"  # jsonl / pipe / csv / tsv / unknown

    @property
    def keys(self) -> list[str]:
        """按出现率降序的字段列表。"""
        return sorted(self.key_counts, key=lambda k: (-self.key_counts[k], k))


def detect_format(lines: list[str]) -> str:
    """探测分隔格式：管道/逗号/Tab/未知。"""
    for line in lines[:5]:
        if not line.strip():
            continue
        for sep, name in (("|", "pipe"), ("\t", "tsv"), (",", "csv")):
            if sep in line:
                return name
        return "unknown"
    return "unknown"


def analyze_file(path: Path) -> FileStat:
    """扫描单个 jsonl：行数、字段出现率、type 分布、字段漂移。"""
    stat = FileStat(path)
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise RuntimeError(f"state 文件读取失败: {path}") from exc
    if not lines:
        return stat
    json_ok = 0
    majority = Counter()
    row_key_sets: list[frozenset[str]] = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue  # 非 JSON 行，交由格式检测处理
        if not isinstance(obj, dict):
            continue
        json_ok += 1
        stat.rows += 1
        key_set = frozenset(obj.keys())
        row_key_sets.append(key_set)
        majority[key_set] += 1
        for key, value in obj.items():
            stat.key_counts[key] += 1
            if key == "type" and isinstance(value, str):
                stat.type_counts[value] += 1
    if json_ok == 0:
        # 整个文件非 JSON：识别分隔格式并标注，不报坏行
        stat.format = detect_format(lines)
        stat.rows = len([l for l in lines if l.strip()])
        return stat
    stat.bad_lines = len([l for l in lines if l.strip()]) - stat.rows
    if row_key_sets:
        # 多数字段集 = 出现最多的 key 组合；其余为漂移，收集其独有字段
        ref_key_set = majority.most_common(1)[0][0]
        for ks in row_key_sets:
            if ks != ref_key_set:
                stat.drift_rows += 1
                for key in sorted(ks - ref_key_set):  # frozenset 遍历顺序依赖 hash seed，必须排序
                    stat.extra_keys[key] += 1
    return stat


def coverage(stat: FileStat) -> str:
    """字段出现率，如 182/182。"""
    return f"{stat.key_counts.get(stat.keys[0], 0)}/{stat.rows}" if stat.keys else "-"


def render_catalog(stats: list[FileStat]) -> str:
    """渲染 state-catalog.md。

    只报告 schema 特征（格式/字段/漂移/坏行），不含行数——
    行数随数据追加变化会让 --check 对高频写入文件每次误报。
    """
    lines: list[str] = [
        "# TRIO state 目录（生成文件，勿手编）",
        "",
        "> 由 `scripts/state-catalog.py` 扫描 `state/*.jsonl` 实际 schema 生成。",
        "> 变更 state 写入后运行 `python3 scripts/state-catalog.py` 重新生成并提交。",
        "",
        "## 概览",
        "",
        "| 文件 | 格式 | 漂移行 | 坏行 |",
        "|------|------|--------|------|",
    ]
    for s in sorted(stats, key=lambda x: x.name):
        lines.append(f"| `{s.name}` | {s.format} | {s.drift_rows} | {s.bad_lines} |")
    lines.append("")
    for s in sorted(stats, key=lambda x: x.name):
        if s.format != "jsonl":
            # 格式-扩展名映射：pipe→.psv / csv→.csv / tsv→.tsv
            expected_suffix = {"pipe": "psv", "csv": "csv", "tsv": "tsv"}.get(s.format)
            actual_suffix = s.name.rsplit(".", 1)[-1]
            mismatch = expected_suffix is not None and actual_suffix != expected_suffix
            warn = (
                f"⚠️ 格式与扩展名不符（`{s.format}` 分隔，应为 .{expected_suffix}）——落库偏差。"
                if mismatch
                else f"`{s.format}` 分隔格式，扩展名匹配。"
            )
            lines += [
                f"## `{s.name}`",
                "",
                warn,
                "",
            ]
            continue
        lines += [
            f"## `{s.name}`",
            "",
            "| 字段 | 覆盖 |",
            "|------|------|",
        ]
        for key in s.keys:
            # 全覆盖/部分：只对字段集变化敏感，追加数据不触发 --check 误报
            coverage = "全覆盖" if s.key_counts[key] == s.rows else f"部分({s.key_counts[key]}/{s.rows})"
            lines.append(f"| `{key}` | {coverage} |")
        if s.type_counts:
            lines += ["", "type 分布：" + " · ".join(f"`{t}`×{c}" for t, c in s.type_counts.most_common())]
        if s.drift_rows:
            extra = "、".join(f"`{k}`×{c}" for k, c in s.extra_keys.most_common())
            lines += [
                "",
                f"⚠️ {s.drift_rows} 行字段集与多数行不一致。",
                f"   独有字段（多为合法演进，需核对是否 schema 预期）：{extra or '—'}",
            ]
        if s.bad_lines:
            lines += ["", f"⚠️ {s.bad_lines} 行非 JSON——疑似损坏。"]
        lines.append("")
    return "\n".join(lines) + "\n"


def scan_all() -> list[FileStat]:
    """扫描全部 state 数据文件（jsonl + psv）。"""
    stats: list[FileStat] = []
    for pattern in ("*.jsonl", "*.psv"):
        for path in sorted(STATE_DIR.glob(pattern)):
            stats.append(analyze_file(path))
    return stats


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="state 目录生成/验证")
    parser.add_argument("--check", action="store_true", help="与已提交目录逐字节比较")
    args = parser.parse_args(argv)
    stats = scan_all()
    rendered = render_catalog(stats)
    if args.check:
        try:
            committed = CATALOG.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"❌ 目录不存在，先运行 scripts/state-catalog.py 生成: {CATALOG}")
            return 1
        if committed != rendered:
            print(f"❌ state-catalog.md 过期——运行 `python3 scripts/state-catalog.py` 重新生成")
            return 1
        print("✅ state-catalog.md 最新")
        return 0
    try:
        CATALOG.write_text(rendered, encoding="utf-8")
    except OSError as exc:
        raise RuntimeError(f"目录写入失败: {CATALOG}") from exc
    print(f"✅ 已生成 {CATALOG}")
    for s in sorted(stats, key=lambda x: x.name):
        flag = " ⚠️漂移" if s.drift_rows else ""
        print(f"  {s.name}: {s.rows} 行, {len(s.keys)} 字段{flag}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RuntimeError as exc:
        print(f"❌ {exc}")
        sys.exit(1)
