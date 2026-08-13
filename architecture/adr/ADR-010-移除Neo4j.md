# ADR-010: 移除 Neo4j 图数据库依赖

> 日期: 2026-07-10 | 状态: 已接受 | 决策人: Rex | 审计: DeepSeek 面具（防腐层前置）

## 背景

TRIO 3.0 集成 Neo4j 作为知识图谱层，用于推理锚点（vps_reason）、事实核验（fact_check）、会话记忆（session_memory）、实体消歧（entity_resolver）。运行至今图谱为 204 节点 / 53 关系。

## 决策

彻底移除 Neo4j 依赖。KG 能力延迟到 4.0 阶段以时序知识图谱方案重新设计，不修补旧架构。

## 动机（审计证据）

- **零可观测增量**：204 节点从未在任何一次 run 的 post_mortem 中被记录为"因 KG 提供关键关联而使分析更好"。
- **降级无损**：压力测试中 Neo4j 认证失败，系统改用本地文件照样 6/7 PASS。
- **数据是碎片**：bootstrap 62 节点为滑窗抽取碎片（"业深度"/"云超市"/"臭因子"/"岩纤维"），非有效实体；且 bootstrap 关系语句引用的源节点名不在其自身节点集内，实际产出 0 关系。
- **有意义关联≈0**：压力测试验证罗欣×北化、追觅×光超均零关联。
- **维护成本 > 产出**：DeepSeek 审计确认 9 个文件绑定 Neo4j，含隐藏传递依赖 session_memory + entity_resolver。
- **ONBOARDING #1 断裂点**：服务 + 认证 + .env 三重配置，是新环境最易配错的组件。

## 后果

- KG 能力归零（原本也约等于零）。
- 全量备份存于 `state/archive/neo4j-full-dump-20260710.csv`（204 节点 / 53 关系，可恢复）。
- 改动 4 文件：
  - `vps_reason.py` — `_get_kg_context()` 返回空；`_kg_verify()` 保留纯文本推断标记统计；删 driver/resolver；顺带修复 `_is_complex` 缺 return 的既存 bug。
  - `fact_check.py` — `_get_schema_info()` 返回空；`verify_triplet()` 与 `check()` 降级为"KG已移除"。
  - `session_memory.py` — 降级为进程内记忆（接口不变）。
  - `entity_resolver.py` — 去 Neo4j，保留 rapidfuzz 模糊匹配（`match_against`）供复用。
- `.env` 中 `NEO4J_*` 标注为 deprecated（注释保留，便于 4.0 恢复参考）。

## 备选方案（已否决）

- **路 A（修好继续用）**：否决——204 节点用图数据库是过度工程。
- **路 B（降级为 JSON 文件图谱）**：否决——审计发现"保留的数据本身是碎片"，路 B 的核心前提（数据不该丢）不成立；且从 bootstrap.cypher 生成会得 62 节点 / 0 关系，反而丢数据。

## 4.0 重建条件（若届时需要）

数据质量与需求真正清晰后，以时序知识图谱重新设计——实体经消歧校验、关系有明确语义、且每条边能追溯到 run 的 post_mortem 增量。不在旧碎片上修补。
