#!/usr/bin/env python3
"""
TRIO 3.0 数值一致性校验器 — 确定性算术检查

不经过模型推理，纯算法验证。检查项：
  1. 百分比求和校验（份额加总不能超过100%）
  2. 单位一致性（USD/RMB/万元/亿 混用检测）
  3. 年份标签检查（跨年数据参与同一计算 → 警告）
  4. 数量级合理性（大数 ≈ 各组成部分之和）

用法: python numeric-consistency.py <分析文件.md> [--json] [--strict]
退出码: 0=通过 | 1=发现不一致 | 2=脚本错误

设计: PDF风险分析 R1(数值一致性) → 确定性防线
"""
from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# ── 常量 ─────────────────────────────────────────

# 人民币单位 → 归一化乘数（以"元"为基准）
CNY_UNITS: dict[str, float] = {
    "万亿": 1e12, "亿": 1e8, "万": 1e4, "万元": 1e4,
    "千": 1e3, "百": 1e2,
}

# 美元单位 → 归一化乘数（以"美元"为基准）
USD_UNITS: dict[str, float] = {
    "trillion": 1e12, "billion": 1e9, "B": 1e9,
    "million": 1e6, "M": 1e6, "thousand": 1e3, "K": 1e3,
}

# 年份模式
YEAR_RE = re.compile(r'(?:FY|FYR?)?(20[12]\d|19\d\d)(?:年|/|Q[1-4]|E|F)?')

# 数字 + 单位 模式（中文）
NUM_CNY_RE = re.compile(
    r'(\d+(?:[,.\s]\d+)?(?:\.\d+)?)\s*'
    r'(万亿|亿|万元|万|千|百)?\s*'
    r'(?:人民币|元|¥|CNY|RMB)?',
    re.IGNORECASE
)

# 数字 + 单位 模式（美元）
NUM_USD_RE = re.compile(
    r'(?:USD|美元|美金|US\$|USD\$)\s*'
    r'(\d+(?:[,.\s]\d+)?(?:\.\d+)?)\s*'
    r'(trillion|billion|million|thousand|[BKMT]bn?)?',
    re.IGNORECASE
)

# 百分比
PCT_RE = re.compile(r'(\d+(?:\.\d+)?)\s*%')

# 同一段落内的数字对（可能是份额+总和关系）
SHARE_PATTERN = re.compile(
    r'(?:占比|份额|市占率?|market\s*share|约占|约为)\s*(\d+(?:\.\d+)?)\s*%',
    re.IGNORECASE
)


@dataclass
class NumericFinding:
    """单个数值"""
    raw: str
    value: float
    unit: str          # "CNY" | "USD" | "pct" | "raw"
    normalized: float  # 归一化后的值
    year: Optional[int] = None
    line: int = 0
    context: str = ""


@dataclass
class ConsistencyIssue:
    """一致性问题"""
    level: str        # "ERROR" | "WARN" | "INFO"
    category: str     # "unit_mix" | "pct_overflow" | "sum_mismatch" | "year_mix" | "order_check"
    detail: str
    fix_hint: str = ""
    findings: list = field(default_factory=list)


class NumericConsistencyChecker:
    """数值一致性校验器"""

    def __init__(self, filepath: str, strict: bool = False):
        self.filepath = Path(filepath)
        self.strict = strict
        self.issues: list[ConsistencyIssue] = []
        self.findings: list[NumericFinding] = []

    # ── 解析 ───────────────────────────────────

    def parse(self) -> None:
        """从 Markdown 文件中提取所有数值"""
        text = self.filepath.read_text(encoding="utf-8")
        lines = text.split("\n")

        # 跳过代码块
        in_code_block = False
        for i, line in enumerate(lines, 1):
            if line.strip().startswith("```"):
                in_code_block = not in_code_block
                continue
            if in_code_block:
                continue

            self._extract_cny(line, i)
            self._extract_usd(line, i)
            self._extract_pct(line, i)

    def _extract_cny(self, line: str, lineno: int) -> None:
        for m in NUM_CNY_RE.finditer(line):
            raw = m.group(0).strip()
            num_str = m.group(1).replace(",", "").replace(" ", "")
            try:
                val = float(num_str)
            except ValueError:
                continue
            unit_word = m.group(2) or ""
            mult = CNY_UNITS.get(unit_word, 1.0)
            year = self._guess_year(line)
            self.findings.append(NumericFinding(
                raw=raw, value=val, unit="CNY",
                normalized=val * mult, year=year,
                line=lineno, context=line.strip()[:120]
            ))

    def _extract_usd(self, line: str, lineno: int) -> None:
        for m in NUM_USD_RE.finditer(line):
            raw = m.group(0).strip()
            num_str = m.group(1).replace(",", "").replace(" ", "")
            try:
                val = float(num_str)
            except ValueError:
                continue
            unit_word = (m.group(2) or "").lower()
            mult = USD_UNITS.get(unit_word, 1.0)
            self.findings.append(NumericFinding(
                raw=raw, value=val, unit="USD",
                normalized=val * mult, year=self._guess_year(line),
                line=lineno, context=line.strip()[:120]
            ))

    def _extract_pct(self, line: str, lineno: int) -> None:
        for m in PCT_RE.finditer(line):
            raw = m.group(0)
            val = float(m.group(1))
            if val > 100 and "增长" not in line and "增速" not in line and "increase" not in line.lower():
                # 可能是异常百分比（如 150% 市占率不可能）
                continue
            self.findings.append(NumericFinding(
                raw=raw, value=val, unit="pct",
                normalized=val, year=self._guess_year(line),
                line=lineno, context=line.strip()[:120]
            ))

    def _guess_year(self, text: str) -> Optional[int]:
        m = YEAR_RE.search(text)
        return int(m.group(1)) if m else None

    # ── 检查 ───────────────────────────────────

    def check_all(self) -> list[ConsistencyIssue]:
        """执行所有检查，返回问题列表"""
        self.parse()
        self._check_unit_mixing()
        self._check_pct_sum()
        self._check_year_mixing()
        self._check_order_of_magnitude()
        return self.issues

    def _check_unit_mixing(self) -> None:
        """检查 USD/CNY 混用"""
        cny_findings = [f for f in self.findings if f.unit == "CNY"]
        usd_findings = [f for f in self.findings if f.unit == "USD"]

        if cny_findings and usd_findings:
            # 检查是否在同一段落中混用
            close_pairs = []
            for c in cny_findings:
                for u in usd_findings:
                    if abs(c.line - u.line) <= 3:  # 3行以内视为同一语境
                        close_pairs.append((c, u))

            if close_pairs:
                examples = [f"L{cn.line}:{cn.raw} vs L{us.line}:{us.raw}"
                           for cn, us in close_pairs[:3]]
                self.issues.append(ConsistencyIssue(
                    level="WARN",
                    category="unit_mix",
                    detail=f"CNY/USD 在相邻行混用 ({len(close_pairs)} 处)。"
                           f"检查是否做了汇率换算: {', '.join(examples)}",
                    fix_hint="标注换算汇率。若无换算 → 数值不可比 → 标注「⚠️ 单位不一致」"
                ))

        # 检查中文大单位混用（亿/万在同一段落）
        yi = [f for f in self.findings if f.unit == "CNY" and f.normalized >= 1e8 and "亿" in f.raw]
        wan = [f for f in self.findings if f.unit == "CNY" and 1e4 <= f.normalized < 1e8 and "万" in f.raw]
        if yi and wan:
            close = []
            for y in yi:
                for w in wan:
                    if abs(y.line - w.line) <= 5:
                        close.append((y, w))
            if close:
                examples = [f"L{y.line}:{y.raw} vs L{w.line}:{w.raw}"
                           for y, w in close[:3]]
                self.issues.append(ConsistencyIssue(
                    level="INFO",
                    category="unit_mix",
                    detail=f"亿/万混用 ({len(close)} 处): {', '.join(examples)}",
                    fix_hint="统一单位以降低误读风险"
                ))

    def _check_pct_sum(self) -> None:
        """检查百分比求和是否超过100%"""
        pcts = [f for f in self.findings if f.unit == "pct" and f.value <= 100]

        # 按段落分组（5行内视为同一组）
        groups: list[list[NumericFinding]] = []
        sorted_pcts = sorted(pcts, key=lambda x: x.line)
        current_group = []
        last_line = -10

        for f in sorted_pcts:
            if f.line - last_line <= 5:
                current_group.append(f)
            else:
                if len(current_group) >= 2:
                    groups.append(current_group)
                current_group = [f]
            last_line = f.line

        if len(current_group) >= 2:
            groups.append(current_group)

        for group in groups:
            total = sum(f.value for f in group)
            if total > 105:  # 留5%容差
                lines = [f"L{f.line}:{f.raw}" for f in group]
                self.issues.append(ConsistencyIssue(
                    level="ERROR",
                    category="pct_overflow",
                    detail=f"份额求和={total:.1f}%，超过100%。"
                           f"可能口径不一致或数据错误。相关行: {', '.join(lines[:5])}",
                    fix_hint="检查是否TAM/SAM/SOM混用。检查是否含重叠市场。"
                ))
            elif total > 100:
                lines = [f"L{f.line}:{f.raw}" for f in group]
                self.issues.append(ConsistencyIssue(
                    level="WARN",
                    category="pct_overflow",
                    detail=f"份额求和={total:.1f}%，略超100%（可能在容差范围内）。"
                           f"相关行: {', '.join(lines[:5])}",
                    fix_hint="确认四舍五入误差。若因口径重叠→标注"
                ))

    def _check_year_mixing(self) -> None:
        """检查不同年份数据参与同一计算"""
        yearly: dict[int, list[NumericFinding]] = {}
        for f in self.findings:
            if f.year:
                yearly.setdefault(f.year, []).append(f)

        years = sorted(yearly.keys())
        if len(years) >= 2:
            # 检查相邻行中不同年份数据同时出现
            pairs_with_mixed_years = []
            for i in range(len(self.findings) - 1):
                a, b = self.findings[i], self.findings[i + 1]
                if a.year and b.year and a.year != b.year and abs(a.line - b.line) <= 2:
                    pairs_with_mixed_years.append((a, b))

            if pairs_with_mixed_years:
                examples = [
                    f"L{p[0].line}:{p[0].raw}({p[0].year}) "
                    f"vs L{p[1].line}:{p[1].raw}({p[1].year})"
                    for p in pairs_with_mixed_years[:3]
                ]
                self.issues.append(ConsistencyIssue(
                    level="WARN",
                    category="year_mix",
                    detail=f"不同年份数据在相邻行出现 ({len(pairs_with_mixed_years)} 处): "
                           f"{'; '.join(examples)}",
                    fix_hint="确认这些数据是否参与同一计算。若是→标注年份差异。"
                             "不同年份数据不可直接比较而不标注。"
                ))

    def _check_order_of_magnitude(self) -> None:
        """粗略的数量级检查——大数是否大致等于各组分之合"""
        cny = [f for f in self.findings if f.unit == "CNY"]
        usd = [f for f in self.findings if f.unit == "USD"]

        for currency, findings in [("CNY", cny), ("USD", usd)]:
            if len(findings) < 3:
                continue

            sorted_f = sorted(findings, key=lambda x: x.normalized, reverse=True)
            largest = sorted_f[0]
            rest_sum = sum(f.normalized for f in sorted_f[1:])

            # 如果最大数组远超其余之和（10倍以上），且最大数出现在"市场总规模"语境中
            if largest.normalized > 0 and rest_sum > 0:
                ratio = largest.normalized / (rest_sum + 1)
                if ratio > 20:
                    # 检查语境——是不是市场总量 vs 细分
                    if any(kw in largest.context for kw in ["总", "整体", "市场", "规模", "market"]):
                        self.issues.append(ConsistencyIssue(
                            level="INFO",
                            category="order_check",
                            detail=f"最大数 ({largest.raw}) 是其余数据之和的 {ratio:.0f} 倍。"
                                   f"若这是市场总量 vs 细分→合理。若这是竞品比较→检查单位。",
                            fix_hint="确认子项是否完整列出。确认单位一致。"
                        ))

    # ── 输出 ───────────────────────────────────

    def report(self, json_output: bool = False) -> str:
        """输出检查报告"""
        if json_output:
            return json.dumps({
                "file": str(self.filepath),
                "total_findings": len(self.findings),
                "issues": [
                    {"level": i.level, "category": i.category,
                     "detail": i.detail, "fix_hint": i.fix_hint}
                    for i in self.issues
                ],
                "passed": len(self.issues) == 0
            }, ensure_ascii=False, indent=2)

        lines = [
            f"📊 数值一致性检查: {self.filepath.name}",
            f"   提取数值: {len(self.findings)} 个",
            f"   发现问题: {len(self.issues)} 个",
            ""
        ]

        if not self.issues:
            lines.append("✅ 未发现数值一致性问题")
            return "\n".join(lines)

        for level in ["ERROR", "WARN", "INFO"]:
            level_issues = [i for i in self.issues if i.level == level]
            if not level_issues:
                continue
            icon = {"ERROR": "🔴", "WARN": "🟡", "INFO": "🔵"}[level]
            lines.append(f"{icon} {level} ({len(level_issues)} 项):")
            for issue in level_issues:
                lines.append(f"   [{issue.category}] {issue.detail}")
                if issue.fix_hint:
                    lines.append(f"   → {issue.fix_hint}")
            lines.append("")

        error_count = len([i for i in self.issues if i.level == "ERROR"])
        if error_count > 0:
            lines.append(f"🛑 {error_count} 个 ERROR——建议修复后再交付")
        else:
            lines.append("⚠️ 无阻断级错误——可在报告中标注后交付")

        return "\n".join(lines)


# ── CLI ─────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("用法: python numeric-consistency.py <分析文件.md> [--json] [--strict]")
        sys.exit(2)

    filepath = sys.argv[1]
    json_out = "--json" in sys.argv
    strict = "--strict" in sys.argv

    if not Path(filepath).exists():
        print(f"❌ 文件不存在: {filepath}")
        sys.exit(2)

    checker = NumericConsistencyChecker(filepath, strict=strict)
    checker.check_all()
    print(checker.report(json_output=json_out))

    errors = len([i for i in checker.issues if i.level == "ERROR"])
    if strict:
        sys.exit(1 if errors > 0 else 0)
    else:
        sys.exit(1 if errors > 0 else 0)


if __name__ == "__main__":
    main()
