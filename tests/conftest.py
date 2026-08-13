"""TRIO 3.0 测试共享 fixtures"""
import pytest, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))


@pytest.fixture
def mock_neo4j(monkeypatch):
    """Mock Neo4j——避免测试依赖真实数据库"""
    class FakeResult:
        def single(self): return {"c": 0}
        def data(self): return []
    class FakeSession:
        def run(self, query, **kwargs): return FakeResult()
        def __enter__(self): return self
        def __exit__(self, *a): pass
    class FakeDriver:
        def session(self): return FakeSession()
        def close(self): pass

    monkeypatch.setattr("neo4j.GraphDatabase.driver", lambda *a, **k: FakeDriver())
    return FakeDriver()
