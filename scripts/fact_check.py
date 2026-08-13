"""
TRIO 事实核验器 — 用知识图谱验证主张
偷师: GraphCheck (ACL 2025) — 将主张分解为三元组 → 在图谱中查证

模式：
  主张 → DeepSeek 分解为三元组 → Neo4j Cypher 查证 → 逐条判定
  信源血缘 → 构建引用图 → 检测伪独立验证 → 输出血缘报告

2026-07-31 扩展: 信源血缘追溯 (check_source_lineage) — PDF风险分析 R7
"""
import os, json, asyncio, sys, re
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from openai import AsyncOpenAI

# 实体消歧（同目录）
_script_dir = os.path.dirname(os.path.abspath(__file__))
if _script_dir not in sys.path:
    sys.path.insert(0, _script_dir)
from entity_resolver import EntityResolver  # noqa: E402
from trio_config import API_KEY, BASE_URL, MODEL, TEMPERATURE, TOP_P, THINKING_DISABLED  # noqa: E402

# REMOVED: use env_loader.get_neo4j_uri()
# REMOVED: use env_loader.get_neo4j_auth()
client = AsyncOpenAI(api_key=API_KEY, base_url=BASE_URL)

DECOMPOSE_PROMPT = """将以下主张分解为可验证的三元组（主-谓-宾）。
每个三元组必须能在知识图谱中查询验证。

## 图谱中的节点类型
{node_labels}

## 图谱中的关系类型
{relation_types}

## 主张
{claim}

## 输出格式（严格遵守）
```json
{{
  "triplets": [
    {{"subject": "实体A", "relation": "关系类型", "object": "实体B"}},
    ...
  ]
}}
```

注意：
- 只使用上述节点和关系类型
- 三元组的主语和宾语必须是可从主张中提取的具体实体名称
- 如果主张中无具体实体，返回空数组

只输出 JSON，不要解释。"""


class FactChecker:
    """图谱事实核验器"""

    def __init__(self):
        # ADR-010: Neo4j 已移除。事实核验能力停用，resolver 降级保留。
        self.resolver = EntityResolver()

    def _get_schema_info(self) -> tuple[list[str], list[str]]:
        """ADR-010: Neo4j 已移除，无图谱 schema。"""
        return [], []

    async def decompose(self, claim: str) -> list[dict]:
        """用 LLM 将主张分解为三元组"""
        labels, rels = self._get_schema_info()
        prompt = DECOMPOSE_PROMPT.format(
            node_labels=", ".join(labels),
            relation_types=", ".join(rels),
            claim=claim,
        )
        r = await client.chat.completions.create(
            model=MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=TEMPERATURE,
            extra_body=THINKING_DISABLED,  # 分解任务不需要推理链
        )
        raw = r.choices[0].message.content.strip()
        if "```json" in raw:
            raw = raw.split("```json")[1].split("```")[0]
        return json.loads(raw).get("triplets", [])

    def _resolve_name(self, name: str) -> str | None:
        """用消歧器找到图谱中的规范名称"""
        # 尝试在所有标签中查找
        labels = self._get_schema_info()[0]
        for label in labels:
            result = self.resolver.resolve(name, label)
            if result.action == "merge" and result.matched_node:
                return result.matched_node.get("name")
        return None

    def verify_triplet(self, triplet: dict) -> dict:
        """ADR-010: Neo4j 已移除，图谱核验停用。"""
        subj, rel, obj = triplet["subject"], triplet["relation"], triplet["object"]
        return {
            "triplet": f"{subj} -[{rel}]-> {obj}",
            "status": "❓ KG已移除",
            "evidence": "Neo4j 已移除(ADR-010)，事实核验能力停用",
        }

    async def check(self, claim: str) -> dict:
        """完整核验流程（ADR-010: KG 已移除，核验能力停用，直接短路）"""
        return {
            "claim": claim,
            "triplets": [],
            "verdict": "❓ KG已移除(ADR-010)，事实核验能力停用",
            "stats": {"verified": 0, "indirect": 0, "failed": 0},
        }
        # --- 以下为原 KG 核验流程，ADR-010 后不再执行（保留供 4.0 参考）---
        print(f"🔍 核验主张: {claim[:80]}...")
        print("─" * 50)

        # Step 1: 分解
        print("📝 分解为三元组...")
        triplets = await self.decompose(claim)
        if not triplets:
            return {"claim": claim, "triplets": [], "verdict": "❓ 无法分解为可验证三元组"}

        # Step 2: 逐条验证
        results = []
        for t in triplets:
            r = self.verify_triplet(t)
            results.append(r)
            print(f"  {r['status']} {r['triplet']}")

        # Step 3: 汇总
        verified = sum(1 for r in results if "✅" in r["status"])
        indirect = sum(1 for r in results if "🟡" in r["status"])
        failed = len(results) - verified - indirect

        if verified == len(results):
            verdict = "✅ 全部验证通过"
        elif verified + indirect == len(results):
            verdict = "🟡 部分验证（有间接证据）"
        elif verified > 0:
            verdict = f"🟠 部分验证 ({verified}/{len(results)} 通过)"
        else:
            verdict = f"❌ 无法验证 ({failed}/{len(results)} 条不在图谱中)"

        print("─" * 50)
        print(f"📊 {verdict}")

        return {
            "claim": claim,
            "triplets": results,
            "verdict": verdict,
            "stats": {"verified": verified, "indirect": indirect, "failed": failed},
        }

    def close(self):
        pass


# ============================================================
# 信源血缘追溯 — 2026-07-31 新增 (PDF风险分析 R7)
# ============================================================

# ── 信源引用模式 ──────────────────────────────────

SOURCE_REF_RE = re.compile(
    r'(?:来源|出处|引用|参考|source|ref|cite|citing|according to|per|基于|参见|详见)'
    r'[：:\s]*'
    r'(.+?)(?:[。，,;\n]|$)',
    re.IGNORECASE
)

# 常见信源去重 —— 同一信源的不同名称
SOURCE_ALIASES: dict[str, str] = {
    "frost sullivan": "Frost & Sullivan",
    "frost & sullivan": "Frost & Sullivan",
    "弗若斯特沙利文": "Frost & Sullivan",
    "gartner": "Gartner",
    "idc": "IDC",
    "mckinsey": "McKinsey",
    "mckinsey global institute": "McKinsey Global Institute",
    "mgi": "McKinsey Global Institute",
    "bcg": "Boston Consulting Group",
    "boston consulting group": "Boston Consulting Group",
    "中信证券": "CITIC Securities",
    "中信": "CITIC Securities",
    "中金": "CICC",
    "中金公司": "CICC",
    "华泰": "Huatai Securities",
    "华泰证券": "Huatai Securities",
    "semi": "SEMI",
    "wsts": "WSTS",
    "sia": "SIA",
    "yole": "Yole Développement",
    "yole développement": "Yole Développement",
    "yole group": "Yole Développement",
}


def normalize_source_name(name: str) -> str:
    """归一化信源名称"""
    name = name.strip().lower().rstrip(".")
    return SOURCE_ALIASES.get(name, name)


@dataclass
class SourceRef:
    """一个信源引用"""
    raw: str               # 原始文本
    normalized: str        # 归一化名称
    line: int              # 所在行
    context: str           # 上下文
    cited_by: list[str] = field(default_factory=list)  # 被哪些段落引用


@dataclass
class LineageViolation:
    """血缘违规"""
    level: str            # "ERROR" | "WARN" | "INFO"
    category: str         # "pseudo_independent" | "circular" | "orphan"
    detail: str
    sources: list[str]


class SourceLineageChecker:
    """信源血缘检查器——检测伪独立验证和信源循环污染"""

    def __init__(self, filepath: str):
        self.filepath = Path(filepath) if isinstance(filepath, str) else filepath
        self.sources: dict[str, SourceRef] = {}
        self.violations: list[LineageViolation] = []

    def extract_sources(self) -> dict[str, SourceRef]:
        """从分析文件中提取所有信源引用"""
        text = self.filepath.read_text(encoding="utf-8")
        lines = text.split("\n")

        for i, line in enumerate(lines, 1):
            for m in SOURCE_REF_RE.finditer(line):
                raw = m.group(1).strip()
                if len(raw) < 3 or len(raw) > 200:
                    continue
                normalized = normalize_source_name(raw)
                if normalized not in self.sources:
                    self.sources[normalized] = SourceRef(
                        raw=raw, normalized=normalized,
                        line=i, context=line.strip()[:120]
                    )
                self.sources[normalized].cited_by.append(f"L{i}")

        return self.sources

    def check_all(self) -> list[LineageViolation]:
        """执行所有血缘检查"""
        self.extract_sources()
        self._check_source_count()
        self._check_diversity()
        return self.violations

    def _check_source_count(self) -> None:
        """检查信源数量是否充足"""
        count = len(self.sources)
        if count == 0:
            self.violations.append(LineageViolation(
                level="ERROR", category="orphan",
                detail="未检测到任何信源引用——所有数据声明无出处",
                sources=[]
            ))
        elif count < 3:
            self.violations.append(LineageViolation(
                level="WARN", category="orphan",
                detail=f"仅检测到 {count} 个信源引用——信源数量不足，建议 ≥3 个独立信源",
                sources=list(self.sources.keys())
            ))

    def _check_diversity(self) -> None:
        """检查信源多样性——同一机构的不同品牌是否被计为多源"""
        domains = defaultdict(list)
        for name in self.sources:
            # 提取信源的机构域名/机构名
            domain_hint = name.split()[0] if " " in name else name
            domains[domain_hint].append(name)

        # 同一机构被计为多个信源的情况
        for domain, names in domains.items():
            if len(names) >= 3:
                self.violations.append(LineageViolation(
                    level="INFO", category="pseudo_independent",
                    detail=f"机构 '{domain}' 的 {len(names)} 个不同名称被引用: "
                           f"{', '.join(names[:5])}。检查是否为同一上游的多个下游出口",
                    sources=names
                ))

    def report(self, json_output: bool = False) -> str:
        """输出血缘报告"""
        if json_output:
            return json.dumps({
                "file": str(self.filepath),
                "total_sources": len(self.sources),
                "source_list": list(self.sources.keys()),
                "violations": [
                    {"level": v.level, "category": v.category,
                     "detail": v.detail, "sources": v.sources}
                    for v in self.violations
                ],
                "passed": len(self.violations) == 0,
                "pseudo_independence_risk": "检查以下信源是否共享上游: "
                    + ", ".join(
                        name for name in self.sources
                        if any(alias in name.lower() for alias in
                              ["frost", "gartner", "idc", "mckinsey", "中信", "华泰", "中金"])
                    ) or "无"
            }, ensure_ascii=False, indent=2)

        lines = [
            f"🔗 信源血缘检查: {self.filepath.name}",
            f"   信源总数: {len(self.sources)}",
            f"   违规项: {len(self.violations)}",
            ""
        ]

        if not self.violations:
            lines.append("✅ 信源血缘检查通过")
            return "\n".join(lines)

        for level in ["ERROR", "WARN", "INFO"]:
            level_items = [v for v in self.violations if v.level == level]
            if not level_items:
                continue
            icon = {"ERROR": "🔴", "WARN": "🟡", "INFO": "🔵"}[level]
            lines.append(f"{icon} {level} ({len(level_items)} 项):")
            for v in level_items:
                lines.append(f"   [{v.category}] {v.detail}")
            lines.append("")

        # 信源清单
        if self.sources:
            lines.append("📋 信源清单:")
            for name, ref in sorted(self.sources.items()):
                lines.append(f"   · {name} (引用: {len(ref.cited_by)} 处)")
            lines.append("")
            lines.append("⚠️ 手动检查: 上述信源中如有共享同一上游的情况 → 标注「伪独立验证」")

        return "\n".join(lines)


def check_source_lineage(filepath: str) -> str:
    """便捷函数——对分析文件执行信源血缘检查"""
    checker = SourceLineageChecker(filepath)
    checker.check_all()
    return checker.report()


# ============================================================
# CLI
# ============================================================
async def main():
    if len(sys.argv) < 2:
        print("用法: python fact_check.py '需要核验的主张'")
        print("示例: python fact_check.py '国轩高科生产磷酸铁锂电池并供应给大众汽车'")
        return

    claim = sys.argv[1]
    checker = FactChecker()
    result = await checker.check(claim)
    print("\n" + json.dumps(result, ensure_ascii=False, indent=2))
    checker.close()


if __name__ == "__main__":
    asyncio.run(main())
