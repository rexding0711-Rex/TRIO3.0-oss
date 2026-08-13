#!/usr/bin/env python3
"""
TRIO 3.0 DOI 验证器 — 学术引用真实性检查

用法: python doi-verify.py <分析文件.md> [--sample 0.2] [--json] [--block]
退出码: 0=全部验证通过 | 1=发现无效DOI | 2=脚本错误

设计: PDF风险分析 R6(伪造信源) → 确定性防线
"""
from __future__ import annotations

import json
import re
import sys
import time
import urllib.request
import urllib.error
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# ── 常量 ─────────────────────────────────────────

DOI_RE = re.compile(
    r'\b(10\.\d{4,}/[^\s\]\[\)\}">]+(?:\.[a-zA-Z]+)?)',
    re.IGNORECASE
)

# 从文字描述中提取的"类DOI"模式（作者+期刊+年份）
PSEUDO_REF_RE = re.compile(
    r'(?:[A-Z][a-z]+(?:\s+[A-Z]\.)?(?:\s+et\s+al\.?)?\s*\(?\d{4}\)?)'
    r'.*?'
    r'(?:Nature|Science|Cell|Lancet|NEJM|IEEE|ACM|arXiv|'
    r'Journal\s+of\s+[A-Z][a-z]+|'
    r'Physical\s+Review|Applied\s+Physics|Advanced\s+Materials)',
    re.IGNORECASE
)

CROSSREF_API = "https://api.crossref.org/works/{}"
REQUEST_TIMEOUT = 10  # 秒


@dataclass
class DoiResult:
    """单个 DOI 验证结果"""
    doi: str
    exists: bool
    title: str = ""
    authors: str = ""
    year: str = ""
    publisher: str = ""
    error: str = ""
    verified: bool = False


@dataclass
class DoiReport:
    """DOI 验证报告"""
    file: str
    total_dois: int
    verified: int
    failed: int
    skipped: int       # 被采样跳过的
    results: list[DoiResult] = field(default_factory=list)
    pseudo_refs: list[str] = field(default_factory=list)  # 未带DOI的学术引用


class DoiVerifier:
    """DOI 验证器"""

    def __init__(self, filepath: str, sample_rate: float = 1.0):
        """
        filepath: 要检查的分析文件
        sample_rate: 抽查比例 (0.0-1.0)。默认 1.0 = 全量检查。
                     建议 0.2 = 随机抽查 20%
        """
        self.filepath = Path(filepath)
        self.sample_rate = max(0.0, min(1.0, sample_rate))
        self.dois: list[str] = []
        self.pseudo_refs: list[str] = []

    def extract(self) -> None:
        """从文件中提取所有 DOI 和类引用"""
        text = self.filepath.read_text(encoding="utf-8")

        # 提取正式 DOI
        self.dois = list(set(DOI_RE.findall(text)))

        # 提取无 DOI 的学术引用
        self.pseudo_refs = list(set(
            m.group(0).strip()[:120]
            for m in PSEUDO_REF_RE.finditer(text)
            if "doi" not in m.group(0).lower()
            and "10." not in m.group(0)
        ))

    def verify_all(self) -> DoiReport:
        """验证所有（或采样后的）DOI"""
        self.extract()

        # 采样
        import random
        total = len(self.dois)
        if total == 0:
            return DoiReport(
                file=str(self.filepath),
                total_dois=0, verified=0, failed=0, skipped=0,
                pseudo_refs=self.pseudo_refs
            )

        sample_size = max(1, int(total * self.sample_rate))
        sampled = random.sample(self.dois, min(sample_size, total)) if sample_size < total else self.dois
        skipped = total - len(sampled)

        results: list[DoiResult] = []
        for doi in sampled:
            result = self._verify_one(doi)
            results.append(result)
            time.sleep(0.1)  # CrossRef 速率限制礼貌间隔

        verified = sum(1 for r in results if r.verified)
        failed = sum(1 for r in results if not r.verified)

        return DoiReport(
            file=str(self.filepath),
            total_dois=total,
            verified=verified,
            failed=failed,
            skipped=skipped,
            results=results,
            pseudo_refs=self.pseudo_refs
        )

    def _verify_one(self, doi: str) -> DoiResult:
        """验证单个 DOI"""
        url = CROSSREF_API.format(urllib.request.quote(doi, safe=""))
        try:
            req = urllib.request.Request(url)
            req.add_header("User-Agent", "TRIO-3.0-DOI-Verifier/1.0 (mailto:rex@trio.dev)")
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
                data = json.loads(resp.read().decode())
                msg = data.get("message", {})
                return DoiResult(
                    doi=doi,
                    exists=True,
                    verified=True,
                    title=(msg.get("title") or [""])[0][:200] if msg.get("title") else "",
                    authors=", ".join(
                        a.get("family", "?") for a in
                        (msg.get("author") or [{}])[:3]
                    ),
                    year=str(msg.get("created", {}).get("date-parts", [[0]])[0][0]),
                    publisher=msg.get("publisher", ""),
                )
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return DoiResult(
                    doi=doi, exists=False, verified=False,
                    error=f"DOI 不存在 (HTTP 404)"
                )
            return DoiResult(
                doi=doi, exists=False, verified=False,
                error=f"HTTP {e.code}: {e.reason}"
            )
        except Exception as e:
            return DoiResult(
                doi=doi, exists=False, verified=False,
                error=f"请求失败: {str(e)[:100]}"
            )

    def report(self, json_output: bool = False) -> str:
        """输出验证报告"""
        report = self.verify_all()

        if json_output:
            return json.dumps({
                "file": report.file,
                "total_dois": report.total_dois,
                "verified": report.verified,
                "failed": report.failed,
                "skipped": report.skipped,
                "sample_rate": self.sample_rate,
                "failed_dois": [
                    {"doi": r.doi, "error": r.error}
                    for r in report.results if not r.verified
                ],
                "pseudo_refs_without_doi": report.pseudo_refs[:10],
                "passed": report.failed == 0
            }, ensure_ascii=False, indent=2)

        lines = [
            f"📚 DOI 验证: {self.filepath.name}",
            f"   DOI 总数: {report.total_dois}",
            f"   已验证: {report.verified} ✅",
            f"   无效: {report.failed} ❌",
            f"   采样跳过: {report.skipped} (抽查率: {self.sample_rate:.0%})",
            ""
        ]

        if report.failed > 0:
            lines.append("❌ 无效 DOI:")
            for r in report.results:
                if not r.verified:
                    lines.append(f"   · {r.doi}")
                    lines.append(f"     → {r.error}")
            lines.append("")

        if report.pseudo_refs:
            lines.append(f"⚠️ 无 DOI 的学术引用 ({len(report.pseudo_refs)} 处):")
            for ref in report.pseudo_refs[:5]:
                lines.append(f"   · {ref}")
            if len(report.pseudo_refs) > 5:
                lines.append(f"   ... 及其他 {len(report.pseudo_refs) - 5} 处")
            lines.append("   → 建议补充 DOI 以便验证")
            lines.append("")

        if report.failed == 0 and report.total_dois > 0:
            lines.append("✅ 所有 DOI 验证通过")
        elif report.total_dois == 0:
            lines.append("ℹ️ 未检测到 DOI——无学术引用或未标注 DOI")

        return "\n".join(lines)


# ── CLI ─────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("用法: python doi-verify.py <分析文件.md> [--sample 0.2] [--json] [--block]")
        print()
        print("选项:")
        print("  --sample N  抽查比例 (默认 1.0 = 全量, 建议 0.2)")
        print("  --json      JSON 输出")
        print("  --block     发现无效 DOI → 退出码 1 (阻断交付)")
        sys.exit(2)

    filepath = sys.argv[1]
    sample_rate = 1.0
    json_out = "--json" in sys.argv
    block = "--block" in sys.argv

    for i, arg in enumerate(sys.argv):
        if arg == "--sample" and i + 1 < len(sys.argv):
            try:
                sample_rate = float(sys.argv[i + 1])
            except ValueError:
                pass

    if not Path(filepath).exists():
        print(f"❌ 文件不存在: {filepath}")
        sys.exit(2)

    verifier = DoiVerifier(filepath, sample_rate=sample_rate)
    print(verifier.report(json_output=json_out))

    report = verifier.verify_all()
    if block and report.failed > 0:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
