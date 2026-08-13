"""验证 env_loader 能正确加载环境变量"""
import pytest


class TestEnvLoader:
    def test_load_returns_dict(self):
        from env_loader import load_trio_env
        env = load_trio_env()
        assert isinstance(env, dict)
        assert "neo4j_uri" in env
        assert "neo4j_user" in env

    def test_get_neo4j_auth_returns_tuple(self):
        from env_loader import get_neo4j_auth
        auth = get_neo4j_auth()
        assert isinstance(auth, tuple)
        assert len(auth) == 2
        assert auth[0] == "neo4j"

    def test_no_hardcoded_password(self):
        """确保 env_loader.py 本身不含硬编码密码"""
        from pathlib import Path
        src = (Path(__file__).parent.parent / "scripts" / "env_loader.py").read_text()
        assert "REDACTED" not in src
        assert "sk-ant" not in src


class TestHardcodingEliminated:
    """确保所有 Python 文件不再包含硬编码密码"""
    def test_all_scripts_password_free(self):
        from pathlib import Path
        import os
        root = Path(__file__).parent.parent
        # 修复 C3: 递归扫 scripts/ + core/（原只扫 scripts/*.py 一层，漏 core/validator.py）
        for dirname in ("scripts", "core"):
            for pyfile in (root / dirname).rglob("*.py"):
                content = pyfile.read_text()
                assert "REDACTED" not in content, f"{pyfile} 仍有硬编码密码!"
                assert "dzj19950711" not in content, f"{pyfile} 仍有明文密码!"
                assert "sk-ant" not in content, f"{pyfile} 疑似 Anthropic key!"
