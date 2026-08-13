"""
TRIO v2.2 — VPS 迭代精炼推理引擎（含缓存感知计费）
偷师: VPS (April 2026) — 训练无关的 generate→critique→refine 循环
      + DeepSeek V4 Pro Thinking 模式 (LiveCodeBench 93.5% #1 全球)
      + Critic-CoT (ACL 2025) — 批评者也用结构化推理

核心发现 (VPS 论文):
  弱模型 + VPS 迭代精炼 → 可达到 SOTA 水平
  GPT-5.4(Low) + VPS → GPQA Diamond 94.9% (SOTA 94.1%)
  弱 actor 从 11.7% → 63.3% (AIME 2025)

TRIO 方案:
  DeepSeek V4 Pro Thinking (强 supervisor) 批判 + DeepSeek V4 Pro (actor) 修正
  = 用自己批判自己，迭代 2-3 轮
"""
import os, json, asyncio, sys
from dataclasses import dataclass, field
from openai import AsyncOpenAI

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from reasoning_templates import SELF_CHECK
from trio_config import API_KEY, BASE_URL, MODEL, TEMPERATURE, TOP_P, THINKING_ENABLED, THINKING_DISABLED  # noqa: E402
from session_memory import SessionMemory  # noqa: E402
from token_usage import TokenUsage  # noqa: E402

# REMOVED: use env_loader.get_neo4j_uri()
# REMOVED: use env_loader.get_neo4j_auth()

client = AsyncOpenAI(api_key=API_KEY, base_url=BASE_URL)


@dataclass
class RefinementRound:
    """一轮精炼的结果"""
    round_num: int
    role: str           # "generate" | "critique" | "refine"
    content: str
    reasoning: str = ""  # DeepSeek Thinking 模式的推理链
    usage: TokenUsage = field(default_factory=TokenUsage)


class VPSReasoner:
    """
    VPS 迭代精炼推理器

    流程:
      Round 1: Thinking 模式生成初始分析
      Round 2: Thinking 模式结构化批判
      Round 3: 根据批判修正分析
      Final:  输出修正后的分析 + 批判摘要 + 置信度
    """

    async def _call_thinking(self, system: str, user: str, max_tokens: int = 2500) -> tuple[str, str, TokenUsage]:
        """调用 DeepSeek V4 Pro Thinking 模式，返回 (content, reasoning, usage)"""
        r = await client.chat.completions.create(
            model=MODEL,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            temperature=TEMPERATURE,
            top_p=TOP_P,
            max_tokens=max_tokens,
            extra_body=THINKING_ENABLED,
        )
        choice = r.choices[0]
        reasoning = getattr(choice.message, "reasoning_content", "") or ""
        content = choice.message.content or ""
        # DeepSeek Thinking 模式有时把内容塞进 reasoning 而非 content
        # 场景1: content 完全空 → 直接用 reasoning
        # 场景2: content 是废骨架（<350字）但 reasoning 有实料（>500字）→ 用 reasoning
        if not content.strip() and reasoning.strip():
            content = f"[注: 模型将分析输出在推理链中]\n\n{reasoning}"
        elif len(content.strip()) < 350 and len(reasoning.strip()) > 500:
            content = f"[注: content仅有骨架({len(content)}字),以下为完整推理链]\n\n{reasoning}"

        # 提取缓存感知 token 用量
        usage = TokenUsage.from_response(r.usage)
        return content, reasoning, usage

    async def _call_fast(self, system: str, user: str, max_tokens: int = 800) -> tuple[str, TokenUsage]:
        """快速调用（non-thinking，用于简单任务），返回 (content, usage)"""
        r = await client.chat.completions.create(
            model=MODEL,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            temperature=0.7,
            max_tokens=max_tokens,
        )
        return r.choices[0].message.content or "", TokenUsage.from_response(r.usage)

    # ================================================================
    # KG 集成（2026-07-02 修复：vps_reason 之前完全没有 KG）
    # ================================================================
    def __init__(self):
        # ADR-010: Neo4j 已移除。KG 上下文停用，记忆降级为进程内。
        self.memory = SessionMemory()  # 进程内记忆层

    def _get_kg_context(self, keywords: list[str] = None) -> str:
        """ADR-010: Neo4j 已移除，KG 上下文停用，返回空。"""
        return ""

    def _kg_verify(self, text: str) -> dict:
        """ADR-010: 图谱实体核验停用；保留纯文本的推断/假设标记统计。"""
        unverified_claims = [
            line.strip()[:120] for line in text.split("\n")
            if "[推断]" in line or "[假设]" in line
        ]
        return {
            "kg_verified_entities": [],
            "kg_entity_count": 0,
            "unverified_inferences": len(unverified_claims),
        }

    def close(self):
        self.memory.close()

    def _is_complex(self, question: str) -> bool:
        """启发式判断问题是否需要 3 轮 VPS 迭代精炼。
        保守策略：不确定时走快速路径。误分析代价 < 误触发代价。"""
        q = question.strip()
        # 太短 → 简单
        if len(q) < 15:
            return False
        # 先排除明确的非分析意图（写作/翻译/格式化/简单列举）
        non_analysis = ["写一", "帮我写", "翻译", "格式化", "排版", "总结一下",
                       "列个清单", "帮我回复", "写邮件", "draft", "write"]
        if any(p in q for p in non_analysis):
            return False
        # 分析型动词 → 复杂
        analysis_verbs = ["分析", "判断", "预测", "对比", "评估", "拆解", "逆向", "审计"]
        if any(v in q for v in analysis_verbs):
            return True
        # 因果推理 → 复杂
        causal = ["为什么", "怎么回事", "什么原因", "驱动因素", "根因"]
        if any(p in q for p in causal):
            return True
        # 战略词汇 → 复杂
        strategic = ["风险", "趋势", "走势", "竞争", "策略", "影响", "前景",
                    "供应链", "护城河", "壁垒", "替代", "颠覆"]
        if any(kw in q for kw in strategic):
            return True
        # 默认 → 简单（保守策略：不确定就不走 VPS）
        return False

    async def analyze(self, question: str, context: str = "", max_rounds: int = 3) -> dict:
        """
        完整的 VPS 迭代精炼管道

        max_rounds: 精炼轮数 (默认 3 = generate + critique + refine)
        """
        # 复杂度门禁：简单问题不走 3 轮
        if not self._is_complex(question):
            print(f"⚡ 复杂度门禁: 问题过于简单，走单轮快速分析")
            result = await self.quick_analyze(question, context)
            return {
                "question": question,
                "rounds": [{"round": 1, "role": "fast", "chars": len(result["analysis"]), "total_tokens": result["tokens"]}],
                "final_analysis": result["analysis"],
                "critique_summary": "(跳过了批判——问题过于简单)",
                "kg_verification": {"kg_verified_entities": [], "kg_entity_count": 0, "unverified_inferences": 0},
                "session_memory": {"session": "fast-path", "total_findings": 0, "avg_confidence": 0},
                "token_usage": result["token_usage"],
                "cost_estimate": result["cost"],
                "reasoning_traces": [{"round": 1, "trace": result["reasoning_trace"][:200] if result["reasoning_trace"] else ""}],
            }
        rounds = []
        cumulative = TokenUsage()  # 累计 token 用量

        # KG 上下文 + 会话记忆
        kg_context = self._get_kg_context()
        memory_context = self.memory.recall(question)
        full_context = f"{context}\n\n{kg_context}\n\n{memory_context}" if context else f"{kg_context}\n\n{memory_context}"

        # ================================================================
        # Round 1: 生成初始分析（Thinking + KG + 会话记忆）
        # ================================================================
        print(f"🧠 Round 1: 生成初始分析 (Thinking + KG + Memory)...")
        content, reasoning, usage = await self._call_thinking(
            system="""你是一位深度分析师。利用知识图谱中的事实作为推理锚点。

## 推理纪律（必须遵守）
1. **置信度标注**: 每个关键声明后标注 [1-5]
   [5]=查证确认 [4]=多源一致 [3]=推理+证据 [2]=推测 [1]=猜测
2. **回溯验证**: 推到关键结论时，回头检查是否偏离了原始问题
3. **矛盾标记**: 如果发现自己的推理存在内部矛盾，标记出来而非悄悄忽略
4. 不确定的事明确说不知道""",
            user=f"""## 分析问题
{question}

## 背景（含 TRIO 知识图谱事实）
{full_context}

## 要求
1. 分步推理，每步标注类型: [事实] [推断] [假设] + 置信度 [1-5]
2. 明确信息缺口
3. 推到结论时回溯检查: 这个结论是否直接回答了原始问题？
4. 列出反例场景""",
        )
        rounds.append(RefinementRound(round_num=1, role="generate", content=content, reasoning=reasoning, usage=usage))
        cumulative.prompt_cache_hit += usage.prompt_cache_hit
        cumulative.prompt_cache_miss += usage.prompt_cache_miss
        cumulative.completion += usage.completion
        # 写入会话记忆
        self.memory.remember("初始分析", content[:300], confidence=3, source="vps-gen")
        print(f"   输出: {len(content)} 字 | 推理: {len(reasoning)} 字 | t: {usage.total}")

        # ================================================================
        # Round 2: 结构化批判（Critic-CoT 风格）
        # ================================================================
        print(f"🔍 Round 2: 结构化批判 (Thinking 模式)...")
        critique, crit_reasoning, crit_usage = await self._call_thinking(
            system="你是一位严格的审计师。你的任务是找出分析中的逻辑漏洞、未证假设、信息缺口和过度推断。使用结构化推理来批判。",
            user=f"""## 原始问题
{question}

## 待批判的分析
{content}

## 批判框架 — 严格按此结构
1. **逻辑链断裂**: 推理步骤之间有没有跳跃？哪一步的前提未证明？
2. **未证假设**: 分析中隐含了什么假设？这些假设是否合理？
3. **信息缺口**: 哪些关键事实缺失？标注严重程度 (高/中/低)
4. **反例遗漏**: 有没有被忽略的反例或替代解释？
5. **置信度校准**: 给出的置信度是否合理？是否有过度自信或过度保守？
6. **总体评分**: 分析质量 0-10 分，并说明扣分项""",
        )
        rounds.append(RefinementRound(round_num=2, role="critique", content=critique, reasoning=crit_reasoning, usage=crit_usage))
        cumulative.prompt_cache_hit += crit_usage.prompt_cache_hit
        cumulative.prompt_cache_miss += crit_usage.prompt_cache_miss
        cumulative.completion += crit_usage.completion
        print(f"   批判: {len(critique)} 字 | 推理: {len(crit_reasoning)} 字 | t: {crit_usage.total} | 缓存命中: {crit_usage.cache_hit_rate:.0%}")

        # ================================================================
        # Round 3: 根据批判修正
        # ================================================================
        print(f"✏️  Round 3: 根据批判修正分析...")
        refined, ref_reasoning, ref_usage = await self._call_thinking(
            system="你是一位深度分析师。根据审计师的批判，修正并改进你的分析。吸收有效批判，解释你不同意某些批判的原因。",
            user=f"""## 原始问题
{question}

## 你的初始分析
{content}

## 审计师的批判
{critique}

## 要求
1. 逐条回应批判（接受/部分接受/拒绝，说明理由）
2. 修正被指出的逻辑漏洞
3. 补充被指出的信息缺口
4. 重新校准置信度
5. 输出修正后的完整分析""",
            max_tokens=3000,
        )
        rounds.append(RefinementRound(round_num=3, role="refine", content=refined, reasoning=ref_reasoning, usage=ref_usage))
        cumulative.prompt_cache_hit += ref_usage.prompt_cache_hit
        cumulative.prompt_cache_miss += ref_usage.prompt_cache_miss
        cumulative.completion += ref_usage.completion
        self.memory.remember("修正分析", refined[:300], confidence=4, source="vps-refine")
        print(f"   修正: {len(refined)} 字 | 推理: {len(ref_reasoning)} 字 | t: {ref_usage.total} | 缓存命中: {ref_usage.cache_hit_rate:.0%}")

        # ================================================================
        # Round 4: KG 事实核验（不调 LLM，纯图谱查询）
        # ================================================================
        print(f"\n📊 Round 4: KG 事实核验...")
        kg_result = self._kg_verify(refined)
        print(f"   KG 锚定实体: {kg_result['kg_entity_count']} 个")
        print(f"   未验证推断: {kg_result['unverified_inferences']} 条")

        # ================================================================
        # 汇总（缓存感知计费）
        # ================================================================
        input_total = cumulative.prompt_cache_hit + cumulative.prompt_cache_miss
        overall_hit_rate = cumulative.prompt_cache_hit / input_total if input_total > 0 else 0
        print(f"\n{'─'*50}")
        print(f"📊 VPS 迭代精炼 + KG 核验 完成")
        print(f"   Token: {cumulative.total} (入 {input_total} | 出 {cumulative.completion})")
        print(f"   缓存命中率: {overall_hit_rate:.0%} (命中 {cumulative.prompt_cache_hit} | 未命中 {cumulative.prompt_cache_miss})")
        print(f"   成本: ${cumulative.cost:.4f}")
        print(f"   KG 锚定: {kg_result['kg_entity_count']} 实体")
        print(f"   Round 1→2→3→4: 生成→批判→修正→KG核验")

        return {
            "question": question,
            "rounds": [
                {
                    "round": r.round_num, "role": r.role,
                    "chars": len(r.content), "total_tokens": r.usage.total,
                    "cache_hit": r.usage.prompt_cache_hit,
                    "cache_miss": r.usage.prompt_cache_miss,
                    "cache_hit_rate": f"{r.usage.cache_hit_rate:.0%}",
                    "cost": f"${r.usage.cost:.5f}",
                }
                for r in rounds
            ],
            "final_analysis": refined,
            "critique_summary": critique[:300] + "..." if len(critique) > 300 else critique,
            "kg_verification": kg_result,
            "session_memory": self.memory.stats(),
            "token_usage": {
                "total": cumulative.total,
                "input_cache_hit": cumulative.prompt_cache_hit,
                "input_cache_miss": cumulative.prompt_cache_miss,
                "completion": cumulative.completion,
                "overall_cache_hit_rate": f"{overall_hit_rate:.0%}",
            },
            "cost_estimate": f"${cumulative.cost:.4f}",
            "reasoning_traces": [
                {"round": r.round_num, "trace": r.reasoning[:200] + "..." if len(r.reasoning) > 200 else r.reasoning}
                for r in rounds if r.reasoning
            ],
        }

    async def quick_analyze(self, question: str, context: str = "") -> dict:
        """快速分析（单轮 Thinking，不迭代）—— 用于对比基线"""
        content, reasoning, usage = await self._call_thinking(
            system="你是一位深度分析师。给出完整的结构化分析，不少于 500 字。",
            user=f"## 问题\n{question}\n\n## 背景\n{context}\n\n## 要求\n1. 分步推理，每步标注: [事实] [推断] [假设]\n2. 给出置信度 (0-100)\n3. 列出主要风险因素\n4. 输出不少于 500 字",
            max_tokens=2000,
        )
        return {
            "question": question,
            "analysis": content,
            "reasoning_trace": reasoning[:500] if reasoning else "",
            "tokens": usage.total,
            "token_usage": {
                "total": usage.total,
                "input_cache_hit": usage.prompt_cache_hit,
                "input_cache_miss": usage.prompt_cache_miss,
                "completion": usage.completion,
                "cache_hit_rate": f"{usage.cache_hit_rate:.0%}",
            },
            "cost": f"${usage.cost:.4f}",
        }


# ============================================================
# CLI
# ============================================================
async def main():
    if len(sys.argv) < 2:
        print("用法: python vps_reason.py '分析问题' [背景信息]")
        print("示例: python vps_reason.py '碳酸锂价格2026H2走势' '澳洲智利新矿Q3投产'")
        return

    question = sys.argv[1]
    context = sys.argv[2] if len(sys.argv) > 2 else ""
    reasoner = VPSReasoner()

    print("="*60)
    print("TRIO v2.1 — VPS 迭代精炼推理")
    print(f"模型: {MODEL} | Thinking 模式 | 3 轮迭代")
    print("="*60)

    result = await reasoner.analyze(question, context)
    print(f"\n📝 最终分析 (前500字):\n{result['final_analysis'][:500]}...")


if __name__ == "__main__":
    asyncio.run(main())
