# 实体 ID 迁移计划 v1.0

> Schema 有了。这是迁移路线图。

## 现状

| 数据源 | 节点数 | 当前ID格式 | 目标格式 |
|--------|--------|-----------|---------|
| Neo4j | ~220 | 混合（部分裸名·部分旧ID） | `{type}:{region}:{identifier}` |
| 对标库/company-benchmark | 82 | 目录名（中文·不一致） | 同上 |
| 对标库/person-benchmark | 38 | 目录名 | 同上 |
| Stock 标的清单 | 62 | A股代码 | 同上 |
| Investor 标的库 | 未统计 | 项目名 | 同上 |

## 迁移步骤

### Phase 1: 建立权威映射表（本次）

创建 `config/entity-id-registry.json`——所有实体的权威 ID 注册表。
Neo4j 查询、对标库读取、Stock 分析都从此表查 ID。

### Phase 2: Neo4j 节点重命名（本周末）

运行 `scripts/neo4j-migrate-ids.cypher`——批量更新节点属性。
先 dry-run → 确认无冲突 → 执行。

### Phase 3: 对标库目录重命名（下周）

按映射表批量重命名对标库目录。
旧目录保留为 symlink（兼容期 30 天）。

### Phase 4: Stock/Investor 对齐（下下周）

更新 Stock 标的清单、Investor 标的库以使用新 ID。

## 冲突解决规则

- **同一实体多个旧ID** → 以 Neo4j 节点 ID 为准
- **同一实体在对标库和 Neo4j 中名称不同** → 人工裁决·Neo4j 优先
- **新实体** → 先注册到 registry 再使用

## 回滚

每步操作前备份。Neo4j 通过 `neo4j-admin dump` 备份。
