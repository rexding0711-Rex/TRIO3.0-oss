"""
TRIO 统一 LLM 配置
DeepSeek V4 Pro 官方推荐参数（2026）
"""
import os

# ============================================================
# API 配置
# ============================================================
API_KEY = os.environ.get("ANTHROPIC_AUTH_TOKEN", "")
BASE_URL = "https://api.deepseek.com/v1"

# 模型（旧 deepseek-chat 将于 2026-07-24 退役）
MODEL = "deepseek-v4-pro"
MODEL_FAST = "deepseek-v4-flash"  # 简单任务用 Flash，更便宜

# DeepSeek 官方推荐参数（不是 GPT 的 0.7！）
TEMPERATURE = 1.0
TOP_P = 1.0

# Thinking 模式配置
THINKING_ENABLED = {"thinking": {"type": "enabled"}}
THINKING_DISABLED = {"thinking": {"type": "disabled"}}
