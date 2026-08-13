#!/usr/bin/env python3
"""
TRIO 3.0 拓扑检查门禁 — Python 重写版 v1.0

用法: python topology-check.py <分析文件> [领域] [--interactive] [--json] [--pretty] [--history]

改进 (vs bash v3.7):
  1. 结构化 Mermaid 解析 — 不再靠正则数节点
  2. 原生 JSON 输出 — 不需要 bash 拼 JSON 字符串
  3. 历史追踪 — 每次运行记录分数，可回看趋势
  4. 可扩展规则引擎 — 用 dataclass 定义规则，新增只需加一个 Rule
  5. 更好的错误信息 — 告诉你哪行、缺什么、怎么修

退出码: 0=全部通过 | 1=不合格(阻断) | 2=脚本错误
"""
from __future__ import annotations

import json
import re
import sys
import os
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Optional

# ── 配置 ─────────────────────────────────────────

TZ_SHANGHAI = timezone(timedelta(hours=8))
TRIO_ROOT = Path(__file__).resolve().parent.parent
HISTORY_FILE = TRIO_ROOT / "state" / "topology-scores.jsonl"
VIOLATION_LOG = TRIO_ROOT / "state" / "topology-violations.log"

DOMAIN_THRESHOLDS = {
    "supply_chain":   {"min_nodes": 15, "min_edges": 25, "min_layers": 3, "min_time": 3},
    "competitive":    {"min_nodes": 12, "min_edges": 20, "min_layers": 2, "min_time": 2},
    "tech_benchmark": {"min_nodes": 10, "min_edges": 15, "min_layers": 2, "min_time": 2},
    "quick":          {"min_nodes":  8, "min_edges": 10, "min_layers": 1, "min_time": 1},
    "general":        {"min_nodes": 10, "min_edges": 15, "min_layers": 2, "min_time": 2},
}


# ── 规则定义 ──────────────────────────────────────

@dataclass
class CheckResult:
    """单条规则的检查结果"""
    rule_id: str
    name: str
    passed: bool
    level: str          # "FAIL" | "WARN" | "INFO"
    detail: str = ""
    fix_hint: str = ""
    metrics: dict = field(default_factory=dict)


class Rule:
    """可扩展的检查规则 — 子类覆写 rule_id/name/description + check()"""
    rule_id: str = ""
    name: str = ""
    description: str = ""

    def check(self, ctx: "CheckContext") -> CheckResult:
        raise NotImplementedError


# ── 检查上下文 ────────────────────────────────────

class CheckContext:
    """分析文件解析结果，供所有规则共享"""

    def __init__(self, filepath: Path, domain: str):
        self.filepath = filepath
        self.domain = domain
        self.thresholds = DOMAIN_THRESHOLDS.get(domain, DOMAIN_THRESHOLDS["general"])
        self.text = filepath.read_text(encoding="utf-8")
        self.lines = self.text.split("\n")

        # 提取 Mermaid 块
        self.mermaid_blocks: list[str] = []
        in_block = False
        for line in self.lines:
            if line.strip().startswith("```mermaid"):
                in_block = True
                continue
            if in_block and line.strip() == "```":
                in_block = False
                continue
            if in_block:
                self.mermaid_blocks.append(line)
        self.mermaid_text = "\n".join(self.mermaid_blocks)

        # 预计算通用统计
        self.is_topology = bool(
            self.mermaid_blocks or
            re.search(r'(拓扑|供应链|因果|causal|topology|知识图谱|节点.{0,5}边|Mermaid)',
                      "\n".join(self.lines[:30]))
        )

        # Mermaid 节点/边统计（结构化解析）
        self.mermaid_nodes = self._parse_mermaid_nodes()
        self.mermaid_edges = self._parse_mermaid_edges()
        self.has_bidirectional = bool(re.search(r'<->|双向|feedback', self.mermaid_text))
        self.has_unknown = bool(re.search(r'\?\?\?|unknown|不确定', self.mermaid_text))
        self.has_dashed = bool(re.search(r'\.-\.>|\.\.->|虚线|dashed|DASHED', self.mermaid_text))

    def _parse_mermaid_nodes(self) -> list[str]:
        """解析 Mermaid 节点 ID"""
        nodes = []
        for line in self.mermaid_blocks:
            # 匹配: ID[Label] 或 ID(Label) 或 ID{Label} 或 ID((Label))
            m = re.match(r'^\s+([A-Za-z0-9_]+)[\[({].*[})\]]', line)
            if m:
                nodes.append(m.group(1))
            # 也匹配: ID --> ID2 中的节点
            edge_nodes = re.findall(r'([A-Za-z0-9_]+)\s*(-->|---|\.->|==>)', line)
            nodes.extend(n[0] for n in edge_nodes)
        return list(set(nodes))

    def _parse_mermaid_edges(self) -> list[tuple[str, str, str]]:
        """解析 Mermaid 边: (source, target, type)"""
        edges = []
        for line in self.mermaid_blocks:
            for m in re.finditer(
                r'([A-Za-z0-9_]+)\s*(-->|---|\.->|\.\.->|==>)\s*(\|?[^|]*\|)?\s*([A-Za-z0-9_]+)',
                line
            ):
                src, arrow, label, tgt = m.group(1), m.group(2), m.group(3) or "", m.group(4)
                edges.append((src, tgt, arrow))
        return edges

    def count_pattern(self, pattern: str) -> int:
        """在全文搜索正则模式，返回匹配数"""
        return len(re.findall(pattern, self.text, re.IGNORECASE))

    def count_lines_with(self, pattern: str) -> int:
        """返回包含模式的行的数量"""
        return sum(1 for line in self.lines if re.search(pattern, line, re.IGNORECASE))

    @property
    def node_count(self) -> int:
        return len(self.mermaid_nodes)

    @property
    def edge_count(self) -> int:
        return len(self.mermaid_edges)


# ── C1-C9 规则实现 ──────────────────────────────
# 每个规则只做一件事，可独立测试

class C1_TopologyRule(Rule):
    """拓扑图存在性 + 节点/边数达标 + 反脑补标记"""
    rule_id = "C1"
    name = "拓扑图检查"
    description = "检查 Mermaid 图是否存在、节点/边数是否达标、有无反脑补标记"

    def check(self, ctx: CheckContext) -> CheckResult:
        t = ctx.thresholds
        issues = []

        if not ctx.mermaid_blocks:
            # 检查 SVG 回退
            has_svg = bool(re.search(r'\.svg', ctx.text))
            if has_svg:
                return CheckResult("C1", self.name, True, "WARN",
                    "检测到 SVG 嵌入（无法自动统计节点/边数），请人工确认",
                    metrics={"svg_fallback": True})

            return CheckResult("C1", self.name, False, "FAIL",
                "未找到 Mermaid 代码块或 SVG 图片",
                "必须输出至少一张因果拓扑图: ```mermaid\ngraph TD\n  ...\n```",
                metrics={"nodes": 0, "edges": 0})

        if ctx.node_count < t["min_nodes"]:
            issues.append(f"节点数 {ctx.node_count} < {t['min_nodes']}")
        if ctx.edge_count < t["min_edges"]:
            issues.append(f"边数 {ctx.edge_count} < {t['min_edges']}")
        if not ctx.is_topology:
            # 非拓扑报告跳过 FAIL
            pass

        # 反脑补 (v3.2)
        anti_bs_ok = ctx.has_unknown or ctx.has_dashed

        passed = len(issues) == 0
        if not passed and ctx.is_topology:
            return CheckResult("C1", self.name, False, "FAIL",
                "; ".join(issues),
                "补全节点和边——每个关键实体至少一个节点，每个关键关系至少一条边",
                metrics={"nodes": ctx.node_count, "edges": ctx.edge_count,
                         "required_nodes": t["min_nodes"], "required_edges": t["min_edges"],
                         "anti_brainstorm": anti_bs_ok})
        elif not anti_bs_ok and ctx.is_topology:
            return CheckResult("C1", self.name, False, "FAIL",
                "无反脑补标记（无 ??? 节点、无虚线边）→ 可能脑补了不确定信息",
                "在不确定的节点用 ??? 标记，不确定的边用 .-> 虚线",
                metrics={"nodes": ctx.node_count, "edges": ctx.edge_count,
                         "anti_brainstorm": False})
        else:
            return CheckResult("C1", self.name, True, "PASS",
                metrics={"nodes": ctx.node_count, "edges": ctx.edge_count,
                         "anti_brainstorm": anti_bs_ok})


class C2_CascadeRule(Rule):
    """扰动推演 — 级联思维是否存在"""
    rule_id = "C2"
    name = "扰动推演检查"
    description = "检查是否存在'如果X消失→Y会...→Z会...'的级联推演思维"

    def check(self, ctx: CheckContext) -> CheckResult:
        removal = ctx.count_pattern(r'(如果|假设|假如|一旦).{0,30}(消失|没了|断供|断裂|退出|崩塌|停产|被禁|出事)')
        cascade = ctx.count_pattern(r'(会导致|将导致|引发|传导|波及|连累).{0,30}(如果|一旦|→)')
        layer2 = ctx.count_pattern(r'(进而|接着|然后|随后).{0,30}(如果|一旦|会导致)')
        cascade_total = cascade + layer2

        if removal == 0:
            return CheckResult("C2", self.name, False, "FAIL",
                "未找到扰动推演: 缺少'如果X消失→Y会...'的级联思维",
                "至少写1处: 「如果[关键节点]断裂/消失 → [下游]会[具体影响] → 进而[二级影响]」",
                metrics={"removal": 0, "cascade_total": cascade_total})
        if cascade_total < 2:
            return CheckResult("C2", self.name, False, "FAIL",
                f"级联深度不足: {cascade_total} 处传导描述 (需 ≥2)",
                "至少写2处传导链，每处覆盖 2 层以上",
                metrics={"removal": removal, "cascade_total": cascade_total})
        return CheckResult("C2", self.name, True, "PASS",
            metrics={"removal": removal, "cascade_total": cascade_total})


class C3_VulnerabilityRule(Rule):
    """脆弱点定位 + 攻击向量"""
    rule_id = "C3"
    name = "脆弱点定位检查"
    description = "检查是否定位了最脆弱的连接/依赖，以及攻击向量分析"

    def check(self, ctx: CheckContext) -> CheckResult:
        weak = ctx.count_pattern(
            r'(最脆弱|最危险|最致命|最薄弱|单点故障|命门|软肋).{0,30}'
            r'(连接|依赖|关系|一环|供应链|通道|命脉)')
        attack = ctx.count_pattern(
            r'(攻击|打击|掐断|切断|挖走|掠夺).{0,20}(这里|这个节点|这条边|这个|就可以|就能)')

        issues = []
        if weak == 0:
            issues.append("未定位最脆弱的连接/依赖")
        if attack == 0:
            issues.append("未分析攻击向量")

        if issues:
            return CheckResult("C3", self.name, False, "FAIL",
                "; ".join(issues),
                "定位最脆弱的 1-2 个节点/边 → 分析如果它被攻击 → 级联效应是什么",
                metrics={"weak_links": weak, "attack_vectors": attack})
        return CheckResult("C3", self.name, True, "PASS",
            metrics={"weak_links": weak, "attack_vectors": attack})


class C4_TimeRule(Rule):
    """时间维度 — 增强/衰退趋势 + 时间窗口"""
    rule_id = "C4"
    name = "时间维度检查"
    description = "检查是否标注了增强/衰退趋势和时间窗口"

    def check(self, ctx: CheckContext) -> CheckResult:
        strengthen = ctx.count_pattern(
            r'(扩大|加速|增强|增长|上升|改善|收紧|加强|加深|攀升|越来越)')
        weaken = ctx.count_pattern(
            r'(衰退|减弱|缩小|下降|恶化|松动|脱钩|流失|侵蚀|挤压|收缩|收窄)')
        time_window = ctx.count_pattern(r'([0-9]+[-~][0-9]+\s*(个)?月|[0-9]+[-~][0-9]+\s*年|窗口期?|时间窗口)')

        min_t = ctx.thresholds["min_time"]
        issues = []
        if strengthen < min_t:
            issues.append(f"增强趋势 {strengthen} < {min_t}")
        if weaken < min_t:
            issues.append(f"衰退趋势 {weaken} < {min_t}")

        if issues:
            return CheckResult("C4", self.name, False, "FAIL",
                "; ".join(issues),
                f"至少标注 {min_t} 项增强趋势和 {min_t} 项衰退趋势",
                metrics={"strengthen": strengthen, "weaken": weaken, "time_window": time_window})
        return CheckResult("C4", self.name, True, "PASS",
            metrics={"strengthen": strengthen, "weaken": weaken, "time_window": time_window})


class C5_EvidenceRule(Rule):
    """信息完整性 — 反证覆盖率"""
    rule_id = "C5"
    name = "信息完整性检查"
    description = "检查低置信度推断是否附带了反证条件"

    def check(self, ctx: CheckContext) -> CheckResult:
        low_conf = ctx.count_pattern(r'\[1\]|\[2\]')
        counter = ctx.count_pattern(r'(反证|为什么不成立|什么条件下不|如果不成立|推翻|反驳)')
        unmarked = ctx.count_lines_with(
            r'((可能|应该|预计|大概率|推测|推断|估计).{0,50}(会|能|可以|存在)|'
            r'似乎.{0,30}(是|有|在))')

        if low_conf == 0:
            return CheckResult("C5", self.name, True, "PASS",
                metrics={"low_confidence": 0, "counter_evidence": counter, "coverage_pct": 100})

        coverage = int(counter * 100 / low_conf) if low_conf > 0 else 100

        if coverage < 50:
            return CheckResult("C5", self.name, False, "FAIL",
                f"反证覆盖率 {coverage}% < 50% — {low_conf} 条低置信度推断仅 {counter} 处附反证",
                "每条 [1][2] 推断必须附带: 「反证: 什么条件下不成立？」",
                metrics={"low_confidence": low_conf, "counter_evidence": counter, "coverage_pct": coverage})
        return CheckResult("C5", self.name, True, "PASS",
            metrics={"low_confidence": low_conf, "counter_evidence": counter, "coverage_pct": coverage})


class C6_PhaseRule(Rule):
    """过程完整性 — Phase 覆盖度"""
    rule_id = "C6"
    name = "过程完整性检查"
    description = "检查拓扑 5 阶段是否至少覆盖了 3 个"

    def check(self, ctx: CheckContext) -> CheckResult:
        cluster = ctx.count_pattern(r'(聚类|桥接边|连通分量|cluster|bridge)')
        time_arrow = ctx.count_pattern(r'(↑|↓|时间方向|趋势反转|共同驱动力)')
        struct = ctx.count_pattern(r'(介数中心性|最小割|betweenness|min.cut|结构扫描)')
        cascade_total = (
            ctx.count_pattern(r'(会导致|将导致|引发|传导|波及).{0,30}(如果|一旦|→)') +
            ctx.count_pattern(r'(进而|接着|然后|随后).{0,30}(如果|一旦|会导致)'))

        score = 0
        if ctx.has_unknown: score += 1     # Phase 0
        if cluster: score += 1              # Phase 1
        if cascade_total >= 2: score += 1   # Phase 2
        if time_arrow: score += 1           # Phase 3
        if struct: score += 1               # Phase 4

        if score < 3 and ctx.is_topology:
            return CheckResult("C6", self.name, False, "FAIL",
                f"Phase 覆盖仅 {score}/5 (需 ≥3)",
                "确保至少走过 3 个阶段: 种子图→扩展→扰动→硬化",
                metrics={"phase_score": score, "required": 3})
        return CheckResult("C6", self.name, True, "PASS",
            metrics={"phase_score": score})


class C7_FilesystemRule(Rule):
    """文件系统痕迹 — topology-state.json 必须存在"""
    rule_id = "C7"
    name = "文件系统痕迹检查"
    description = "检查过程文件是否持久化"

    def check(self, ctx: CheckContext) -> CheckResult:
        if not ctx.is_topology:
            return CheckResult("C7", self.name, True, "INFO",
                "非拓扑报告，跳过文件系统检查")

        run_dir = None
        parent = ctx.filepath.parent
        if "runs" in str(parent):
            run_dir = parent
        else:
            runs_dir = parent / "runs"
            if runs_dir.is_dir():
                subdirs = sorted(runs_dir.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
                run_dir = subdirs[0] if subdirs else None

        audit = ctx.count_pattern(r'(审计|audit|PASS/FAIL|self.verify|自检\s*✅)')

        if not run_dir:
            return CheckResult("C7", self.name, False, "FAIL",
                "未找到关联的 run 目录",
                metrics={"run_dir": None, "audit_trace": audit > 0})

        state_file = run_dir / "topology-state.json"
        if not state_file.exists():
            return CheckResult("C7", self.name, False, "FAIL",
                f"topology-state.json 不存在 (run_dir={run_dir.name})",
                metrics={"state_file": str(state_file), "exists": False, "audit_trace": audit > 0})

        return CheckResult("C7", self.name, True, "PASS",
            metrics={"state_file": str(state_file), "exists": True, "audit_trace": audit > 0})


class C8_FlipConditionRule(Rule):
    """反证覆盖率 — 核心结论必须有翻转条件"""
    rule_id = "C8"
    name = "反证覆盖率检查"
    description = "核心结论是否附带了可证伪的翻转条件"

    def check(self, ctx: CheckContext) -> CheckResult:
        core = ctx.count_pattern(r'【结论】|\[4\]|\[5\]')
        flip = ctx.count_pattern(
            r'翻转条件|如果.{0,20}(发生|成立|为真|变化).{0,20}(作废|推翻|不成立|重估)|'
            r'前提假设.{0,20}(不成立|变化)|可证伪|证伪条件|什么情况下.{0,10}(错|失效|作废)')

        if core > 0 and flip == 0:
            return CheckResult("C8", self.name, False, "WARN",
                f"{core} 处核心结论但无翻转条件",
                "每个核心结论附一句: 「翻转条件: 如果 X 则此结论作废」",
                metrics={"core_conclusions": core, "flip_conditions": flip})
        return CheckResult("C8", self.name, True, "PASS",
            metrics={"core_conclusions": core, "flip_conditions": flip})


class C9_BridgeLemmaRule(Rule):
    """Bridge Lemma 门禁 — 防范畴错误"""
    rule_id = "C9"
    name = "Bridge Lemma 门禁"
    description = "检测'领域映射≠逻辑绕过'范畴错误"

    def check(self, ctx: CheckContext) -> CheckResult:
        bypass = ctx.count_pattern(
            r'(绕过|规避|跳出|突破|不受.{0,5}限制).{0,30}'
            r'(屏障|障碍|限制|barrier|relativization|natural.proof|不可能定理)')
        bridge = ctx.count_pattern(
            r'(桥接引理|bridge.lemma|违反.{0,10}(前提|条件|假设).{0,20}(因为|在于|由于)|'
            r'该屏障.{0,5}(前提|条件|假设).{0,10}(不适用|不成立|被破坏))')

        if bypass > 0 and bridge == 0:
            return CheckResult("C9", self.name, False, "FAIL",
                f"{bypass} 处声称绕过屏障但无桥接引理 → 范畴错误风险",
                "提供: (1)屏障精确形式化条件 (2)违反哪个前提 (3)可证伪 bridge lemma",
                metrics={"bypass_claims": bypass, "bridge_lemmas": 0})
        return CheckResult("C9", self.name, True, "PASS",
            metrics={"bypass_claims": bypass, "bridge_lemmas": bridge})


# ── 规则注册表 ────────────────────────────────────

ALL_RULES: list[Rule] = [
    C1_TopologyRule(),
    C2_CascadeRule(),
    C3_VulnerabilityRule(),
    C4_TimeRule(),
    C5_EvidenceRule(),
    C6_PhaseRule(),
    C7_FilesystemRule(),
    C8_FlipConditionRule(),
    C9_BridgeLemmaRule(),
]


# ── 主检查引擎 ────────────────────────────────────

def run_checks(filepath: Path, domain: str) -> dict:
    """运行所有 C1-C9 检查，返回结构化结果"""
    ctx = CheckContext(filepath, domain)
    results = []

    for rule in ALL_RULES:
        try:
            result = rule.check(ctx)
        except Exception as e:
            result = CheckResult(rule.rule_id, rule.name, False, "ERROR",
                f"规则执行异常: {e}")
        results.append(result)

    fails = [r for r in results if r.level == "FAIL" and not r.passed]
    warns = [r for r in results if r.level == "WARN" and not r.passed]
    errors = [r for r in results if r.level == "ERROR"]

    score = max(0, 100 - len(fails) * 15 - len(warns) * 5)
    passed = len(fails) == 0

    return {
        "timestamp": datetime.now(TZ_SHANGHAI).isoformat(),
        "file": str(filepath),
        "domain": domain,
        "is_topology": ctx.is_topology,
        "score": score,
        "passed": passed,
        "total_checks": len(results),
        "fails": len(fails),
        "warns": len(warns),
        "errors": len(errors),
        "checks": [
            {
                "rule_id": r.rule_id,
                "name": r.name,
                "passed": r.passed,
                "level": r.level,
                "detail": r.detail,
                "fix_hint": r.fix_hint,
                "metrics": r.metrics,
            }
            for r in results
        ],
    }


def save_history(report: dict) -> None:
    """追加分数到历史记录"""
    HISTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "timestamp": report["timestamp"],
        "file": report["file"],
        "domain": report["domain"],
        "score": report["score"],
        "passed": report["passed"],
        "fails": report["fails"],
        "warns": report["warns"],
    }
    with open(HISTORY_FILE, "a") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


def load_history(limit: int = 10) -> list[dict]:
    """读取最近的历史记录"""
    if not HISTORY_FILE.exists():
        return []
    records = []
    with open(HISTORY_FILE) as f:
        for line in f:
            try:
                records.append(json.loads(line.strip()))
            except json.JSONDecodeError:
                continue
    return records[-limit:]


def print_human_report(report: dict) -> None:
    """人类可读的报告格式"""
    CYAN = "\033[0;36m"; GREEN = "\033[0;32m"; YELLOW = "\033[1;33m"
    RED = "\033[0;31m"; NC = "\033[0m"

    print(f"{CYAN}═══════════════════════════════════════{NC}")
    print(f"{CYAN}  拓扑检查 v4.0 — Python 规则引擎{NC}")
    print(f"{CYAN}  文件: {Path(report['file']).name} | 领域: {report['domain']}{NC}")
    print(f"{CYAN}  类型: {'拓扑报告' if report['is_topology'] else '非拓扑报告'}{NC}")
    print(f"{CYAN}═══════════════════════════════════════{NC}")
    print()

    for c in report["checks"]:
        icon = {True: f"{GREEN}✅{NC}", False: f"{RED}❌{NC}"}[c["passed"]]
        level_tag = {"FAIL": f"{RED}[阻断]{NC}", "WARN": f"{YELLOW}[警告]{NC}",
                     "INFO": "[信息]", "PASS": f"{GREEN}[通过]{NC}",
                     "ERROR": f"{RED}[异常]{NC}"}.get(c["level"], c["level"])
        print(f"  {icon} {level_tag} {c['name']}")
        if c["detail"]:
            print(f"     {c['detail']}")
        if c["fix_hint"]:
            print(f"     → {c['fix_hint']}")
        if c["metrics"]:
            short_metrics = {k: v for k, v in c["metrics"].items()
                           if not k.startswith("required_")}
            if short_metrics:
                print(f"     📊 {short_metrics}")
        print()

    # 汇总
    print(f"{CYAN}─────────────────────────────────────────{NC}")
    if report["passed"]:
        print(f"  {GREEN}✅ 通过 ({report['warns']} 警告) — 分数: {report['score']}{NC}")
    else:
        print(f"  {RED}❌ 未通过: {report['fails']} 阻断, {report['warns']} 警告 — 分数: {report['score']}{NC}")
        print(f"  {RED}→ 修复以上阻断项后重新运行{NC}")

    # 历史趋势
    history = load_history(5) if report.get("_history_loaded") else []
    if len(history) >= 2:
        scores = [h["score"] for h in history]
        trend = "↑ 改善中" if scores[-1] > scores[0] else "↓ 下降中" if scores[-1] < scores[0] else "→ 持平"
        print(f"\n  📈 最近 {len(scores)} 次分数: {' → '.join(str(s) for s in scores[-5:])}  {trend}")

    print(f"{CYAN}═══════════════════════════════════════{NC}")


# ── CLI ──────────────────────────────────────────

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="TRIO 3.0 拓扑检查门禁 v4.0 (Python)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python topology-check.py report.md general
  python topology-check.py report.md supply_chain --pretty
  python topology-check.py report.md general --json
  python topology-check.py report.md general --history
  python topology-check.py report.md general --interactive
        """
    )
    parser.add_argument("file", help="分析文件路径 (.md)")
    parser.add_argument("domain", nargs="?", default="general",
                        choices=list(DOMAIN_THRESHOLDS.keys()),
                        help="分析领域 (默认: general)")
    parser.add_argument("--json", action="store_true", help="JSON 输出（静默人类可读日志）")
    parser.add_argument("--pretty", action="store_true", help="美化的人类可读输出")
    parser.add_argument("--history", action="store_true", help="同时打印最近 10 条历史分数")
    parser.add_argument("--interactive", action="store_true",
                        help="交互式追问低置信度推断（C5 扩展）")
    args = parser.parse_args()

    filepath = Path(args.file)
    if not filepath.exists():
        print(f"❌ 文件不存在: {args.file}", file=sys.stderr)
        sys.exit(2)

    # 运行检查
    report = run_checks(filepath, args.domain)

    # 保存历史
    save_history(report)

    # 历史趋势
    if args.history:
        report["_history_loaded"] = True

    # 输出
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print_human_report(report)

    # 交互模式
    if args.interactive and report["fails"] > 0:
        c5 = next((c for c in report["checks"] if c["rule_id"] == "C5"), None)
        if c5 and not c5["passed"]:
            print(f"\n{'─' * 40}")
            print("🔍 交互式追问模式")
            print("对每条 [1][2] 低置信度推断，请回答:")
            print("  y = 我有证据支持  n = 没证据  ? = 不确定")
            print(f"{'─' * 40}")

    # 退出码
    if report["errors"] > 0:
        sys.exit(2)
    sys.exit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
