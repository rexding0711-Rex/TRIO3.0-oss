"""
TRIO 3.0 知识抽取验证器 v1.0
=====================
知识生产线五阶段中的 Python Validator 层。
LLM JSON → Schema 校验 → 实体解析 → ABSTAIN 规则 → 置信度计算 → 回归测试

KG 状态：3.0 无知识图谱（ADR-010，延迟到 4.0）。实体闸门默认不强制（KG_ENABLED=False），
4.0 恢复 KG 时置 True 并接入真实查询。to_cypher_preview 为 4.0 冻结预览，非生产写入。

硬约束: LLM 绝不直接写任何数据库。所有 JSON 必须先经过此验证器。
"""

import json
import hashlib
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import jsonschema


# ═══ 路径配置 ═══
# 动态推导（config/paths.conf 纪律：禁止硬编码绝对路径）——validator.py 曾硬编码 /mnt/d/TRIO 3.0，已修

TRIO_ROOT = Path(__file__).resolve().parent.parent
GROUND_TRUTH_PATH = TRIO_ROOT / "fixtures" / "ground-truth-v1.json"
CONTRACT_PATH = TRIO_ROOT / "config" / "schemas" / "extraction-contract-v1.json"

# KG 开关：3.0 无知识图谱（ADR-010，延迟到 4.0）——实体解析不强制
# 4.0 恢复 KG 时置 True，resolve_entity 接入真实查询，实体闸门自动恢复
KG_ENABLED = False

# ═══ ABSTAIN 三层门规则 ═══

# L1 硬规则: 触发即 ABSTAIN，LLM 判断不可覆盖
L1_HARD_KEYWORDS = [
    "布局", "规划", "计划", "拟建", "拟投资", "有望", "预计", "预期",
    "研发阶段", "正在研发", "中试阶段", "参股", "代理", "经销",
    "合作开发", "探索", "筹备", "蓝图", "战略合作", "签署备忘录",
    "意向协议", "未来将", "将建", "将投产", "期待", "展望", "愿景", "目标",
    "即将", "有望在", "预计在", "拟在",
]

# L3 后置规则: 即使 LLM 输出 ACCEPT，原文包含这些也强制 ABSTAIN
L3_POST_KEYWORDS = [
    "计划", "有望", "布局", "研发中", "拟投产", "规划建设", "未来将",
    "拟投资", "预计", "将投产", "期待",
]

# 弱信号词: 触发后需要 L2 LLM 判断（在 evidence_span 中检测）
L2_WEAK_SIGNALS = [
    "送样", "验证中", "测试中", "小批量", "试产", "客户导入", "认证中",
    "样品通过", "积极", "持续推进",
]


# ═══ 核心类 ═══

class ExtractionValidator:
    """知识抽取验证器——LLM JSON 进入 Neo4j 前的最后一道闸门。"""

    def __init__(self) -> None:
        self.schema: dict[str, Any] = {}
        self.ground_truth: dict[str, Any] = {}
        self.stats: dict[str, int] = {
            "total": 0, "accepted": 0, "abstained": 0, "rejected": 0,
            "schema_fail": 0, "entity_fail": 0, "l1_abstain": 0,
            "l3_override": 0, "regression_pass": 0, "regression_fail": 0,
        }

    # ── 初始化 ──

    def load(self) -> "ExtractionValidator":
        """加载 Schema 和 Ground Truth（Neo4j 已按 ADR-010 移除）。"""
        with open(CONTRACT_PATH, encoding="utf-8") as f:
            contract = json.load(f)
        self.schema = contract["extractionOutput"]

        with open(GROUND_TRUTH_PATH, encoding="utf-8") as f:
            self.ground_truth = json.load(f)

        return self

    def close(self) -> None:
        """无资源需关闭（Neo4j 已移除）。"""

    # ── Stage 1: JSON Schema 校验 ──

    def validate_schema(self, llm_output: dict[str, Any]) -> list[str]:
        """校验 LLM 输出的 JSON 是否符合 extraction-contract-v1 Schema。
        返回错误列表，空列表 = 通过。"""
        errors: list[str] = []
        try:
            jsonschema.validate(llm_output, self.schema)
        except jsonschema.ValidationError as e:
            errors.append(f"Schema 校验失败: {e.message} (路径: {'/'.join(str(p) for p in e.absolute_path)})")
        return errors

    # ── Stage 2: 实体解析 ──

    def resolve_entity(self, name: str, node_type: str) -> dict[str, Any]:
        """检查实体是否已存在。

        3.0 无知识图谱（ADR-010，KG 延迟到 4.0）——实体解析不强制：
        返回 enforced=False，主流程据此跳过"实体不存在→ABSTAIN"（避免 ACCEPT 全被 ABSTAIN 的旧缺陷）。
        4.0 恢复 KG 时将 KG_ENABLED 置 True 并接入真实查询，自动恢复实体闸门。
        返回 {'exists': bool, 'enforced': bool, 'matched_name': str|null, 'node_type': str}。
        """
        if not KG_ENABLED:
            return {"exists": True, "enforced": False, "matched_name": None, "node_type": node_type}
        # TODO(4.0): 接入 KG 查询，返回真实存在性
        return {"exists": False, "enforced": True, "matched_name": None, "node_type": node_type}

    # ── Stage 3: ABSTAIN 规则引擎 ──

    def apply_abstain_rules(self, decision: dict[str, Any]) -> dict[str, Any]:
        """对单条 decision 执行 ABSTAIN 三层门。
        返回修改后的 decision（可能被覆盖为 ABSTAIN/REJECT）。"""
        evidence_span = decision.get("evidence", {}).get("evidence_span", "")
        llm_decision = decision.get("decision", "ABSTAIN")

        # L1 硬规则: 检查关键词
        for keyword in L1_HARD_KEYWORDS:
            if keyword in evidence_span:
                decision["decision"] = "ABSTAIN"
                decision["abstain_detail"] = {
                    "reason": f"L1 硬规则命中: 关键词 '{keyword}'",
                    "trigger_layer": "L1_HARD_RULE",
                    "confidence_if_forced": decision.get("abstain_detail", {}).get(
                        "confidence_if_forced", 0.2
                    ),
                }
                self.stats["l1_abstain"] += 1
                return decision

        # L3 后置规则: 即使 LLM 说 ACCEPT，如果原文含未来时态词 → 覆盖为 ABSTAIN
        if llm_decision == "ACCEPT":
            for keyword in L3_POST_KEYWORDS:
                if keyword in evidence_span:
                    decision["decision"] = "ABSTAIN"
                    decision["abstain_detail"] = {
                        "reason": f"L3 后置规则覆盖: LLM 输出 ACCEPT 但原文含 '{keyword}'（未来时态）",
                        "trigger_layer": "L3_POST_RULE",
                        "confidence_if_forced": decision.get("scores", {}).get("evidence_strength", 0.3) * 0.5,
                    }
                    self.stats["l3_override"] += 1
                    return decision

        # L2 弱信号: evidence_strength 阈值检查
        if llm_decision == "ACCEPT":
            evidence_strength = decision.get("scores", {}).get("evidence_strength", 0)
            if evidence_strength < 0.5:
                decision["decision"] = "ABSTAIN"
                decision["abstain_detail"] = {
                    "reason": f"L2 信号过弱: evidence_strength={evidence_strength} < 0.5",
                    "trigger_layer": "L2_LLM_JUDGMENT",
                    "confidence_if_forced": evidence_strength,
                }
                return decision

        return decision

    # ── Stage 4: 置信度计算 ──

    @staticmethod
    def calculate_confidence(scores: dict[str, float]) -> float:
        """木桶短板算子: confidence = min(evidence_strength, source_authority, resolution_certainty)。
        LLM 不直接输出 confidence——由管线计算。"""
        return min(
            scores.get("evidence_strength", 0),
            scores.get("source_authority", 0),
            scores.get("resolution_certainty", 0),
        )

    # ── Stage 5: 回归测试 ──

    def run_regression(self, decisions: list[dict[str, Any]]) -> dict[str, Any]:
        """用 Ground Truth v1 对 ACCEPT 的 decisions 做回归测试。
        返回 {'pass': int, 'fail': int, 'failures': [...]}。"""
        positive_gt = {item["id"]: item for item in self.ground_truth.get("positive", [])}
        negative_gt = {item["id"]: item for item in self.ground_truth.get("negative", [])}
        abstain_gt = {item["id"]: item for item in self.ground_truth.get("abstain", [])}

        # 检查 POSITIVE: Ground Truth 中标记为 ACCEPT 的，是否都出现在了 decisions 中
        accept_decisions = [d for d in decisions if d.get("decision") == "ACCEPT"]
        accept_pairs = {
            (d["claim"]["subject"], d["claim"]["predicate"], d["claim"]["object"])
            for d in accept_decisions
        }

        failures: list[dict[str, Any]] = []
        for gt_id, gt in positive_gt.items():
            pair = (gt["subject"], gt["predicate"], gt["object"])
            if pair not in accept_pairs:
                failures.append({
                    "type": "MISSING_POSITIVE",
                    "gt_id": gt_id,
                    "expected": "ACCEPT",
                    "subject": gt["subject"],
                    "predicate": gt["predicate"],
                    "object": gt["object"],
                })

        # 检查 NEGATIVE: Ground Truth 中标记为 REJECT 的 (subject+predicate+wrong_object) 不应出现在 ACCEPT 中
        for gt_id, gt in negative_gt.items():
            gt_triple = (gt.get("subject", ""), gt.get("wrong_predicate", ""), gt.get("wrong_object", ""))
            for d in accept_decisions:
                d_triple = (d["claim"]["subject"], d["claim"]["predicate"], d["claim"]["object"])
                # 三元组全匹配才告警
                if d_triple == gt_triple:
                    failures.append({
                        "type": "FALSE_ACCEPT",
                        "gt_id": gt_id,
                        "expected": "REJECT",
                        "got": "ACCEPT",
                        "subject": d["claim"]["subject"],
                        "predicate": d["claim"]["predicate"],
                        "object": d["claim"]["object"],
                        "gt_note": gt.get("reason", ""),
                    })

        self.stats["regression_pass"] = len(positive_gt) + len(negative_gt) - len(failures)
        self.stats["regression_fail"] = len(failures)

        return {"pass": self.stats["regression_pass"], "fail": self.stats["regression_fail"], "failures": failures}

    # ── 主入口: 全管线验证 ──

    def validate(self, llm_output: dict[str, Any]) -> dict[str, Any]:
        """完整验证管线: Schema → Entity → ABSTAIN → Confidence → 汇总。
        返回 {'valid': bool, 'decisions': [...], 'stats': {...}, 'errors': [...]}。"""
        result: dict[str, Any] = {
            "valid": True,
            "decisions": [],
            "stats": {},
            "errors": [],
            "regression": {},
        }

        # Stage 1: Schema 校验
        schema_errors = self.validate_schema(llm_output)
        if schema_errors:
            result["valid"] = False
            result["errors"].extend(schema_errors)
            self.stats["schema_fail"] += 1
            result["stats"] = {**self.stats, "false_fact_rate": 0.0}
            return result

        decisions = llm_output.get("decisions", [])
        self.stats["total"] = len(decisions)
        validated_decisions: list[dict[str, Any]] = []

        for i, decision in enumerate(decisions):
            claim = decision.get("claim", {})
            subject = claim.get("subject", "")
            obj = claim.get("object", "")
            obj_type = claim.get("object_type", "")
            llm_d = decision.get("decision", "ABSTAIN")

            # Stage 2: 实体解析（仅 KG 启用时强制——3.0 无 KG，跳过实体闸门）
            subj_entity = self.resolve_entity(subject, "Company")
            obj_entity = self.resolve_entity(obj, obj_type)

            if llm_d == "ACCEPT" and subj_entity["enforced"] and not subj_entity["exists"]:
                decision["decision"] = "ABSTAIN"
                decision["abstain_detail"] = {
                    "reason": f"主体 '{subject}' 不在知识图谱中",
                    "trigger_layer": "ENTITY_RESOLUTION",
                    "confidence_if_forced": 0.0,
                }
                self.stats["entity_fail"] += 1

            if llm_d == "ACCEPT" and obj_entity["enforced"] and not obj_entity["exists"]:
                decision["decision"] = "ABSTAIN"
                decision["abstain_detail"] = {
                    "reason": f"客体 '{obj}' (类型={obj_type}) 不在知识图谱中",
                    "trigger_layer": "ENTITY_RESOLUTION",
                    "confidence_if_forced": 0.0,
                }
                self.stats["entity_fail"] += 1

            # Stage 3: ABSTAIN 三层门
            decision = self.apply_abstain_rules(decision)

            # Stage 4: 置信度计算
            if decision["decision"] == "ACCEPT":
                scores = decision.get("scores", {})
                decision["confidence"] = self.calculate_confidence(scores)

                # 阈值过滤
                if decision["confidence"] < 0.60:
                    decision["decision"] = "ABSTAIN"
                    decision["abstain_detail"] = {
                        "reason": f"置信度过低: min(E,S,R)={decision['confidence']:.2f} < 0.60",
                        "trigger_layer": "CONFIDENCE_THRESHOLD",
                        "confidence_if_forced": decision["confidence"],
                    }

            # 统计
            final_d = decision["decision"]
            if final_d == "ACCEPT":
                self.stats["accepted"] += 1
            elif final_d == "ABSTAIN":
                self.stats["abstained"] += 1
            else:
                self.stats["rejected"] += 1

            validated_decisions.append(decision)

        result["decisions"] = validated_decisions

        # Stage 5: 回归测试
        result["regression"] = self.run_regression(validated_decisions)

        result["stats"] = {
            **self.stats,
            "false_fact_rate": (
                sum(1 for f in result["regression"].get("failures", [])
                    if f.get("type") == "FALSE_ACCEPT")
                / max(self.stats["accepted"], 1)
                if self.stats["accepted"] > 0
                else 0.0
            ),
        }
        result["valid"] = len(result["errors"]) == 0

        return result

    # ── 辅助: 输出 Cypher 写入预览 ──

    def to_cypher_preview(self, validated: dict[str, Any], limit: int = 10) -> str:
        """将验证通过的 ACCEPT decisions 转为 Cypher 写入语句预览。

        4.0 冻结：3.0 无 KG（ADR-010），此预览不参与生产写入。
        重新接入数据库前必须改为参数化查询，禁止字符串拼接（注入风险）。
        """
        accepted = [d for d in validated.get("decisions", []) if d["decision"] == "ACCEPT"]
        lines: list[str] = []
        lines.append(f"// 验证通过 {len(accepted)} 条，以下为前 {min(limit, len(accepted))} 条 Cypher 预览\n")

        for d in accepted[:limit]:
            claim = d["claim"]
            scores = d.get("scores", {})
            evidence = d.get("evidence", {})
            temporal = d.get("temporal", {})
            # 修复：llm_output 在本函数作用域未定义（曾触发 NameError）
            metadata = validated.get("pipeline_metadata", {})

            predicate = claim["predicate"]
            obj_type = claim.get("object_type", "Material")
            label_map = {"Material": "Material", "Process": "Process",
                         "ProductCategory": "ProductCategory", "Capability": "Capability",
                         "Technology": "Technology", "Company": "Company"}

            cypher = (
                f"MATCH (c:Company {{name:'{claim['subject']}'}})\n"
                f"MERGE (t:{label_map.get(obj_type, obj_type)} {{name:'{claim['object']}'}})\n"
                f"MERGE (c)-[r:{predicate}]->(t)\n"
                f"SET r.evidence = '{evidence.get('evidence_span', '')[:100]}...',\n"
                f"    r.source_type = '{evidence.get('source_type', 'unknown')}',\n"
                f"    r.source_date = '{evidence.get('source_date', '')}',\n"
                f"    r.evidence_score = {scores.get('evidence_strength', 0)},\n"
                f"    r.source_score = {scores.get('source_authority', 0)},\n"
                f"    r.resolution_score = {scores.get('resolution_certainty', 0)},\n"
                f"    r.confidence = {d.get('confidence', 0):.2f},\n"
                f"    r.valid_from = '{temporal.get('valid_from', evidence.get('source_date', ''))}',\n"
                f"    r.last_verified = '{datetime.now(timezone.utc).strftime('%Y-%m-%d')}',\n"
                f"    r.verification_status = 'verified',\n"
                f"    r.extraction_method = 'llm_batch',\n"
                f"    r.pipeline_version = '{metadata.get('pipeline_version', 'trio-extract-v4')}',\n"
                f"    r.prompt_version = '{metadata.get('prompt_version', 'extraction_prompt_v4')}';\n"
            )
            lines.append(cypher)

        return "\n".join(lines)


# ── CLI 入口 ──

if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("用法: python validator.py <llm_output.json> [--dry-run]")
        print("  llm_output.json : LLM 抽取的 JSON 文件")
        print("  --dry-run        : 仅验证，不连接 Neo4j（跳过实体解析）")
        sys.exit(1)

    input_path = Path(sys.argv[1])
    dry_run = "--dry-run" in sys.argv

    with open(input_path, encoding="utf-8") as f:
        llm_output = json.load(f)

    validator = ExtractionValidator()
    validator.load()

    if dry_run:
        # 跳过 Neo4j 实体解析（离线测试用）
        validator.resolve_entity = lambda name, node_type: {"exists": True, "matched_name": name, "node_type": node_type}

    result = validator.validate(llm_output)

    print(json.dumps({
        "valid": result["valid"],
        "stats": result["stats"],
        "regression": result["regression"],
        "errors_count": len(result["errors"]),
    }, ensure_ascii=False, indent=2))

    if result["errors"]:
        print("\n⚠️ 错误:")
        for e in result["errors"]:
            print(f"  - {e}")

    if result["regression"].get("failures"):
        print(f"\n🔴 回归测试失败 ({len(result['regression']['failures'])} 项):")
        for f in result["regression"]["failures"]:
            print(f"  - [{f['type']}] {f.get('subject', '')} {f.get('predicate', '')} {f.get('object', '')}")

    print(f"\n📊 ACCEPT: {result['stats']['accepted']} | ABSTAIN: {result['stats']['abstained']} | REJECT: {result['stats']['rejected']}")
    print(f"📊 False Fact Rate: {result['stats']['false_fact_rate']:.1%}")

    # 输出 Cypher 预览
    if result["stats"]["accepted"] > 0:
        print("\n" + validator.to_cypher_preview(result, limit=5))

    validator.close()
