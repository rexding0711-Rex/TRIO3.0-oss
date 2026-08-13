# TRIO 研发路线图

> 最后更新: 2026-06-23 | 上次刷新: 2026-06-23 | 3.0 稳定期 → 收集痛点
>
> **刷新间隔**: 30 天 | **下次刷新**: 2026-07-23

---

## 📡 最新动态（2026-06-23 知识刷新）

> 本节由 kb-refresh 系统自动生成，综合多源搜索结果。每项标注置信度 [1-5] 和来源。

### Claude Code 平台演进（与 4.0 Runner 引擎决策相关）

| 动态 | 对 TRIO 的影响 | 置信度 |
|------|---------------|:-----:|
| **Hook 系统重大扩展** — 条件 Hook (`if` 字段)、Elicitation Hook（拦截 MCP 表单响应）、Post-Session Hook（会话结束后触发）已全部上线（v2.1.76–v2.1.169） | 4.0 Runner 引擎的形态选择中，**Claude Code Hook 方案**的可行性大幅提升。Post-Session Hook 是"知识自生长"（run 后自动沉淀）的天然实现路径 | 5 |
| **MCP Tunnels** — Agent 可触达私有网络中的 MCP 服务器而无需暴露公网端口（Research Preview, 2026-05） | 如果 4.0 Runner 选择 MCP Server 形态，Tunnels 解决了远程/私有化部署的联网问题 | 4 |
| **Agent 沙箱强化** — 背景 Agent 保留 `--ide`/`--chrome`/`--bare` 标志，隔离 Worktree 修复 | 多角色并行执行（如 Step 2-4 同时跑）的可靠性提升 | 4 |
| **备用模型链** — 支持配置最多 3 级 fallback model | TRIO 当前用单一 API（DeepSeek V4 Pro），未来可以考虑备用链提升可用性 | 3 |
| **`--safe-mode`** — 禁用所有自定义项启动 | 调试 TRIO 配置冲突时有用 | 2 |

来源：
- [Claude Code Changelog](https://code.claude.com/docs/en/changelog)
- [Claude Code Skills vs MCP vs Plugins Guide 2026](https://www.morphllm.com/claude-code-skills-mcp-plugins)
- [Code w/ Claude London 2026](https://claude.com/blog/code-w-claude-london-2026-rethinking-how-we-build)

### Agent 编排框架格局（与 4.0 技术选型相关）

| 动态 | 对 TRIO 的影响 | 置信度 |
|------|---------------|:-----:|
| **AutoGen → 维护模式** — 微软官方推荐迁移至 Microsoft Agent Framework (MAF) | 如果 TRIO 曾考虑 AutoGen 作为 4.0 Runner 底座，需重新评估 | 5 |
| **LangGraph + Temporal = 生产标配** — 2026 年主流模式是 LangGraph（有状态图）+ Temporal（跨重启持久化） | TRIO 4.0 场景 SOP 天然适合 LangGraph 的 StateGraph 模型。但如果 4.0 继续以 Claude Code Hook 为主，可能不需要外挂 Temporal | 4 |
| **CrewAI 新增 checkpoint/resume**（v1.14.x, 2026-04） | CrewAI 的角色-任务模型与 TRIO 的"角色+场景 SOP"概念高度相似，但其 Python-only 生态与 TRIO 的 bash+Markdown 原生路线不兼容 | 3 |
| **Neo4j Aura Agent GA**（2026-02） — 从知识图谱 Schema 自动生成 Agent，单键部署为 MCP 服务器。底层用 Gemini Flash 2.5 + 微调 text-to-query | **对 5.0 "知识图谱深度融合"有重大启示**。TRIO 未来可直接用 Aura Agent 替代手写 Cypher → MCP 调用，降低图谱查询门槛 | 5 |
| **Agentic GraphRAG** — 多 Agent 系统自动推断 Schema、构建知识图谱、路由查询（Neo4j NODES AI 2026） | 与 5.0 "知识自生长"和"知识冲突自动检测"高度相关。自动从 run 产物中提取实体 → 建图 → 检测冲突的技术路径已有成熟方案 | 4 |
| **Neo4j `neo4j-agent-memory` 包** — 为 Agent 提供短期/长期/推理记忆，自动合并与蒸馏（Python/JS/Go） | 4.0 "跨运行记忆"的存储方案候选。比文件系统方案更强大，但引入 Neo4j 依赖 | 3 |

来源：
- [LangChain: Best AI Agent Frameworks 2026](https://www.langchain.com/resources/ai-agent-frameworks)
- [FutureAGI: Best Multi-Agent Frameworks 2026](https://futureagi.com/blog/best-multi-agent-frameworks-2026/)
- [Neo4j Blog: Aura Agent GA](https://neo4j.com/blog/agentic-ai/neo4j-launches-aura-agent/)
- [Neo4j Blog: Knowledge Layer for Agentic Systems](https://neo4j.com/blog/news/knowledge-layer-agentic-systems-google-cloud/)
- [Neo4j NODES AI 2026: Agentic GraphRAG](https://neo4j.com/videos/nodes-ai-2026-agentic-graphrag-autonomous-knowledge-graph-construction-and-adaptive-retrieval-2/)

### 可能改变优先级的外部事件

| 事件 | 影响评估 | 置信度 |
|------|---------|:-----:|
| **Claude Fable 5 发布**（2026-06-09） — "Mythos-class"模型，声称超越此前所有公开可用模型 | 如果 Fable 5 的推理/规划能力有代际提升，TRIO 的 Step 5（综合判定/Claude 面具）质量可能显著提高。但 TRIO 当前使用 DeepSeek V4 Pro API，不直接依赖 Claude 模型 | 3 |
| **MCP 成为 Agent 互操作事实标准** — Claude、Copilot、Gemini、ADK 均原生支持 MCP | 4.0 Runner 形态如果选择 MCP Server，将天然兼容整个生态，而非仅限 Claude Code | 5 |
| **Document → Knowledge Graph 自动化成熟**（Neo4j Document Intelligence, 2026 Preview） | 5.0 "多模态输入"（扔 PDF → 自动结构化）的技术底座已具备，Neo4j 的 Document Intelligence 可直接将 PDF/DOCX/HTML/EPUB 转为可查询图谱 | 4 |

---

## 3.0 当前版本

## 3.0 当前版本

- 8 核心角色 + 7 JSON 场景 SOP
- 16 斜杠命令（Claude Code 原生）
- 知识资产：client-library / decision-log / evaluation-framework
- 运行时：runs/ + state.json 断点续跑
- 数据资产：D:\工作\知识库\ + D:\工作\项目\

## 4.0 — 「引擎化」（预估 2-3 个月后启动）

核心目标：从"人读脚本手动推进"升级为"引擎自动编排"。

### 4.0 候选特性

| 特性 | 优先级 | 说明 |
|------|--------|------|
| Runner 引擎 | 🔴 | 不再靠 Claude 读 markdown SOP 逐步执行，而是独立 Runner 解析 JSON → 自动推进 |
| 跨运行记忆 | 🔴 | 同一项目/同一领域的多次 run 自动共享上下文 |
| 知识自生长 | 🔴 | run 完成后自动提取方法论、更新知识库、检测冲突（不再依赖手动 /归档） |
| 决策追溯闭环 | 🟡 | 标记每个决策的后续验证状态（已验证/已证伪/待观察），统计命中率 |
| 可组合场景 | 🟡 | `/trio-run` 能根据描述即兴组合 Step 链，不限于 7 个预定义 SOP |
| 角色变体参数 | 🟡 | 核心角色 + 领域参数（如"成本拆解-化工版" vs "成本拆解-SaaS版"） |
| 质量仪表盘 | 🟢 | run 成功率、ESCALATE 频率、各角色 retry 率 |

### 4.0 关键架构决策（待定）

1. Runner 形态：Claude Code Hook？独立 MCP Server？外部脚本？
2. 跨运行记忆存储：文件系统？SQLite？Neo4j？
3. 知识自生长的冲突检测粒度：文件级？实体级？声明级？

---

## 5.0 — 「主动智能」（预估 6-12 个月后）

核心目标：从"被动响应命令"升级为"主动发现机会"。

### 5.0 候选特性

| 特性 | 优先级 | 说明 |
|------|--------|------|
| Signal Monitor | 🔴 | 监控关注赛道 → 行业变化主动推送 |
| Portfolio View | 🔴 | 跨项目关联分析（技术/市场/人才交叉） |
| Decision Twin | 🟡 | 基于历史决策训练推理模型，"过去的Rex会怎么判" |
| 周报自动生成 | 🟡 | 每周汇总：run 数、知识增量、决策验证率 |
| 多模态输入 | 🟢 | 扔 PDF/图片/录音 → 自动提取结构化信息 |
| 知识冲突自动检测 | 🟢 | 跨 D:\工作\知识库\ + TRIO 3.0 一致性扫描 |

---

## 更远的想法（不做承诺）

- 自然语言创建新角色/新场景（不用手写 JSON）
- 与 Neo4j 知识图谱深度融合
- TRIO 作为 MCP Server 供其他工具调用
- 多人协作模式
- Rex 认知偏差检测（"反偏见镜子"）

---

---

## 里程碑 & 触发器

不按日期排，按触发条件排。满足条件 → 进入下一阶段。

### M0 ✅ 3.0 上线（已完成）

- [x] 16 命令入口就绪
- [x] Claude-Driven-Workflow 已退役并物理删除
- [x] research/ 研发中心建立

### M1 🟢 稳定运行期（当前）

**目标**: 在日常使用中积累数据，不主动改架构。

**退出条件**（满足任意一条即进入 M2）:
- [ ] 累计跑完 **10 个 run**（不限场景）
- [ ] 同一场景（如 /尽调）跑了 **5 次**，可以对比分析
- [ ] 出现 **3 次 ESCALATE**（需要人工介入的断点）
- [ ] `research/ideas/` 攒到 **15+ 个想法**

**期间可以做的**:
- 继续用，不碰 config/ 结构
- 遇到痛点 → 扔 ideas/
- 如果某个 SOP 步骤反复 FAIL → 直接修那个 JSON，不算架构改动
- 完善 D:\工作\知识库\ 的内容资产

### M2 🟡 4.0 启动判断

**触发**: M1 任意退出条件满足。

**判断清单**（不是自动进入 4.0，而是评估）:
1. 最频繁的 ESCALATE 原因是什么？→ 决定 Runner 引擎优先解决什么
2. ideas/ 里最高频的关键词是什么？→ 决定 4.0 第一优先级
3. 3.0 的核心架构（config/runs/knowledge 三层）哪里最不够用？
4. Claude Code 平台有没有发布相关新能力（Hook/MCP/Agent 改进）？

**决策**: 满足 ≥2 个明确信号 → 正式启动 4.0 设计。否则继续 M1。

### M3 🔴 4.0 开发

**触发**: M2 决策通过。

**阶段划分**:

| 子阶段 | 内容 | 产出 |
|--------|------|------|
| M3.1 架构设计 | 定 Runner 形态、记忆存储方案、知识自生长粒度 | 设计文档（research/experiments/ 里的原型验证） |
| M3.2 核心引擎 | Runner + 跨运行记忆 | 能自动跑完一个简单 SOP |
| M3.3 知识自生长 | 自动提取 + 冲突检测 | run 完成后自动写知识库 |
| M3.4 质量层 | 决策追溯 + 仪表盘 | 量化指标上线 |

**退出条件**:
- [ ] 一个完整的 /尽调 能在无人干预下从头跑到尾（含知识沉淀）
- [ ] 累计 5 个 run 无 ESCALATE
- [ ] 知识自生长至少成功提取 10 条方法论

### M4 🔵 5.0 启动判断

**前置条件**（全部满足才考虑）:
- [ ] 4.0 稳定运行 ≥ 30 天
- [ ] 决策日志 ≥ 30 条（D-2026-001 ~ D-2026-030+）
- [ ] 至少 5 条决策已完成回溯验证（"已验证"或"已证伪"）
- [ ] 某个具体信号触发了"要是 TRIO 能自己告诉我这个就好了"的瞬间

### M5 ⚪ 5.0 开发

内容待定，等 4.0 跑出来的数据再细化。

---

## 变更日志

| 日期 | 变更 |
|------|------|
| 2026-06-23 | 初始版本，4.0/5.0 方向初稿 |
| 2026-06-23 | 补充分阶段里程碑 + 触发条件 |
