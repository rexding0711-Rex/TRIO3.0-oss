"""
TRIO 共享模块 — DeepSeek V4 Pro 缓存感知 Token 计费
适用：所有调用 DeepSeek API 的模块

DeepSeek 磁盘缓存定价 (USD/1M tokens, 平峰):
  输入缓存命中:   $0.003625  (比未命中便宜 120×)
  输入缓存未命中: $0.435
  输出:           $0.87
  高峰 (9-12, 14-18 北京时间) ×2，当前按平峰计

用法:
  from token_usage import TokenUsage
  u = TokenUsage(prompt_cache_hit=500, prompt_cache_miss=200, completion=300)
  print(u.cost)       # USD 成本
  print(u.cache_hit_rate)  # 输入缓存命中率
"""
from dataclasses import dataclass

# ============================================================
# DeepSeek V4 Pro 定价 (USD / 1M tokens, 平峰时段)
# ============================================================
PRICE_INPUT_CACHE_HIT = 0.003625    # $/1M tokens
PRICE_INPUT_CACHE_MISS = 0.435      # $/1M tokens
PRICE_OUTPUT = 0.87                 # $/1M tokens


@dataclass
class TokenUsage:
    """一次 LLM 调用的 token 明细（区分缓存命中/未命中）"""
    prompt_cache_hit: int = 0      # 缓存命中的输入 token
    prompt_cache_miss: int = 0     # 未命中缓存的输入 token
    completion: int = 0            # 输出 token

    @property
    def total(self) -> int:
        return self.prompt_cache_hit + self.prompt_cache_miss + self.completion

    @property
    def input_total(self) -> int:
        """输入 token 总数"""
        return self.prompt_cache_hit + self.prompt_cache_miss

    @property
    def cache_hit_rate(self) -> float:
        """输入 token 的缓存命中率 (0.0 ~ 1.0)"""
        return self.prompt_cache_hit / self.input_total if self.input_total > 0 else 0.0

    @property
    def cost(self) -> float:
        """按 V4 Pro 平峰定价计算 USD 成本"""
        return (
            self.prompt_cache_hit * PRICE_INPUT_CACHE_HIT
            + self.prompt_cache_miss * PRICE_INPUT_CACHE_MISS
            + self.completion * PRICE_OUTPUT
        ) / 1_000_000

    @classmethod
    def from_response(cls, usage) -> "TokenUsage":
        """从 OpenAI 兼容 API 的 usage 对象构造"""
        return cls(
            prompt_cache_hit=getattr(usage, "prompt_cache_hit_tokens", 0) or 0,
            prompt_cache_miss=getattr(usage, "prompt_cache_miss_tokens", 0) or 0,
            completion=getattr(usage, "completion_tokens", 0) or 0,
        )

    def __add__(self, other: "TokenUsage") -> "TokenUsage":
        """累加两个 TokenUsage（用于多轮汇总）"""
        return TokenUsage(
            prompt_cache_hit=self.prompt_cache_hit + other.prompt_cache_hit,
            prompt_cache_miss=self.prompt_cache_miss + other.prompt_cache_miss,
            completion=self.completion + other.completion,
        )
