"""TRIO 3.0 环境变量加载器——从 .env 读取敏感配置"""
from pathlib import Path
import os

_ENV = None

def load_trio_env():
    global _ENV
    if _ENV is not None:
        return _ENV

    env_path = Path(__file__).parent.parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().split("\n"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, val = line.partition("=")
                os.environ.setdefault(key.strip(), val.strip())

    _ENV = {
        "neo4j_uri": os.getenv("NEO4J_URI", "bolt://localhost:7687"),
        "neo4j_user": os.getenv("NEO4J_USER", "neo4j"),
        "neo4j_password": os.getenv("NEO4J_PASSWORD", ""),
        "deepseek_api_key": os.getenv("DEEPSEEK_API_KEY", ""),
    }
    return _ENV


def get_neo4j_auth():
    env = load_trio_env()
    return (env["neo4j_user"], env["neo4j_password"])


def get_neo4j_uri():
    return load_trio_env()["neo4j_uri"]


def get_deepseek_key():
    """返回 DeepSeek API Key，未配置时返回空字符串"""
    return load_trio_env()["deepseek_api_key"]
