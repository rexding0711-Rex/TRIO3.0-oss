"""验证隔离审计器能正确检测跨面具引用"""
import pytest, tempfile, json
from pathlib import Path


class TestIsolationAudit:
    def test_clean_run_passes(self):
        """无跨引用的 run 应 PASS"""
        from isolation_audit import audit_run
        with tempfile.TemporaryDirectory() as td:
            run_dir = Path(td)
            (run_dir / "step1-kimi.md").write_text("# Kimi分析\n独立洞察。盲区：未考虑供应链因素。")
            (run_dir / "step2-deepseek.md").write_text("# DeepSeek审计\n盲区：财务数据缺失。")
            (run_dir / "step3-claude.md").write_text("# Claude综合\n综合判断。盲区：技术可行性待验证。")
            result = audit_run(run_dir)
            assert result["overall"] == "PASS"
            assert len(result["violations"]) == 0

    def test_cross_reference_detected(self):
        """跨面具引用应被检测为 FAIL"""
        from isolation_audit import audit_run
        with tempfile.TemporaryDirectory() as td:
            run_dir = Path(td)
            (run_dir / "step2-deepseek.md").write_text(
                "# DeepSeek审计\nKimi 说对了一半，但我发现..."
            )
            result = audit_run(run_dir)
            # DeepSeek 引用了 Kimi——应该检测到
            assert len(result["violations"]) >= 1

    def test_missing_blindspot_warns(self):
        """缺少盲区自白应触发 WARN"""
        from isolation_audit import audit_run
        with tempfile.TemporaryDirectory() as td:
            run_dir = Path(td)
            (run_dir / "step1-kimi.md").write_text("# Kimi分析\n一切都很完美，没有任何问题。")
            result = audit_run(run_dir)
            # 没有盲区声明——应该 WARN
            assert result["overall"] == "WARN"
