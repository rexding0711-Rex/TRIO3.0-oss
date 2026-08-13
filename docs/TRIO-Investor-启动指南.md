# TRIO-Investor 启动指南

> **定位**：一级市场投资人的个人 AI 基础设施
> **版本**：v1.0 | **日期**：2026-07-15
> **一句话**：把你看过的所有项目变成知识图谱，用三面具做尽调，一键出投委会备忘录
>
> ⚠️ **入口更新（2026-08-10 收敛）**：独立 `/investor` 命令已归档。文中的 `/investor …` 示例统一改用唯一分析入口 `/all`，如 `/all 一级市场 新项目入库`。

---

## 这是什么

TRIO-Investor 是 TRIO 3.0 的投资者专用版。它解决一个核心痛点：

> **投资人看了几百个项目，但知识散落在微信聊天、Notion、飞书、脑图、Excel 里——没有一个地方能看清"我到底从这些项目里学到了什么"。**

TRIO-Investor 把一切结构化：

```
你聊过的每个项目 → Neo4j 图节点
你的每次判断     → Decision 节点 + 可追溯推理链
你的每次退出     → Lesson 节点 + 模式识别
三面具尽调       → 自动生成投委会备忘录（MD→PDF）
```

**所有数据留在你的本地机器上。** 不上传任何云端。

---

## 5 分钟快速上手

### Step 1：环境检测

```bash
cd /path/to/TRIO\ 3.0
bash scripts/investor-setup.sh
```

这个脚本会检测：Neo4j、PostgreSQL、API Key、MCP 配置。缺什么会告诉你怎么装。

### Step 2：初始化图谱

```bash
# 加载环境变量
source config/investor-env.sh

# 创建图数据库 Schema（约束、索引、节点标签体系）
cypher-shell -u neo4j -p $NEO4J_PASSWORD -f config/schemas/investor-neo4j-schema.cypher
```

### Step 3：启动 Claude Code

```bash
claude
```

### Step 4：进入投资者模式

在 Claude Code 中输入：

```
/investor 帮我入库一个新项目
```

然后按提示输入项目信息。系统会自动：
1. 提取结构化信息
2. 写入 Neo4j 图谱
3. 检测与已有项目的关联
4. 建议下一步动作

---

## 核心工作流

### 工作流 1：管线入库（日常最高频）

**场景**：聊完一个新项目，想把信息存下来。

**操作**：
```
/investor 新项目入库
公司：XX科技
赛道：AI Agent / 企业服务
阶段：A轮
估值：5000万美元
创始人：张三，前阿里P9，清华计算机
核心数据：ARR 200万美元，增速 3x，毛利率 80%
我的判断：团队强但市场有点卷，需要再看看竞品
```

**系统做的事**：
1. 提取 → 结构化 JSON
2. 写入 Neo4j（Company + Founder + Deal 节点）
3. 自动关联（同赛道项目、同创始人网络）
4. 如果信息不全 → 追问

### 工作流 2：深度尽调（投委会前必跑）

**场景**：项目推进到 TS 阶段，需要全面尽调。

**操作**：
```
/investor 尽调 XX科技 --depth deep
```

**系统做的事**：
1. Gate 0：致命缺口扫描（先列不知道的，等你确认再跑）
2. 30-40 轮搜索 + 5 层 OODA 解剖
3. 三面具并行质控（Kimi 洞察 + DeepSeek 审计 + Claude 整合）
4. 生成尽调报告 MD+PDF+HTML 三件套
5. 自动提取关键发现 → 更新 Neo4j

**耗时**：约 15-30 分钟（取决于搜索轮数）

### 工作流 3：投委会备忘录（一键生成）

**场景**：明天上投委会，需要写 memo。

**操作**：
```
/investor 写 XX科技 的投委会 memo
```

**系统做的事**：
1. 从 Neo4j 拉取项目数据
2. 如果做过尽调 → 提取关键发现
3. 如果没做过 → 先跑快速判断
4. 填充 memo 模板 → 生成 MD
5. 走 deliver.sh 管道 → 生成 PDF

### 工作流 4：管线查看（日常监控）

**场景**：想看看整体 portfolio 状态。

**操作**：
```
/investor 看管线
```

**系统做的事**：
1. 查询 Neo4j
2. 输出管线摘要（Pipeline / Portfolio / 统计）
3. 可选：生成交互式 HTML 仪表盘

### 工作流 5：退出复盘（长期积累）

**场景**：一个项目退了，想复盘。

**操作**：
```
/investor 复盘 XX科技 —— 投了300万，3年后以1500万退出，MOIC 5x
```

**系统做的事**：
1. 三面具并行复盘（决策质量/市场背景/可迁移教训）
2. 写入 Neo4j（Exit + Lesson 节点）
3. 累积足够退出案例后 → 自动模式识别

---

## 图谱查法速览

在 Claude Code 中直接用自然语言查询：

```
# 查项目
/investor XX科技 在库里吗

# 查赛道
/investor AI Agent 赛道有哪些项目

# 查创始人
/investor 张三 还投过哪些项目

# 查竞争
/investor XX科技 的竞争对手有哪些

# 查统计
/investor 今年入库了多少项目
/investor 按赛道统计
/investor 整体 MOIC 估算
```

也支持直接 Cypher 查询（如果熟悉 Neo4j），在 Claude Code 中说：

```
帮我查 Cypher: MATCH (c:Company)-[:IN_SECTOR]->(s:Sector {name: 'AI Agent'}) RETURN c.name, c.stage, c.valuation
```

---

## 核心能力矩阵

| 能力 | 实现方式 | 输出 |
|------|---------|------|
| 项目信息管理 | Neo4j 图谱 | 节点+关系 |
| 深度尽调 | TRIO 5 层解剖 | MD+PDF+HTML |
| 投委会备忘录 | 模板+图谱数据填充 | MD→PDF |
| 赛道扫描 | 行业全量分析 | 交互式报告 |
| 创始人评估 | 人物尽调协议 | 创始人画像 |
| 退出复盘 | 三面具并行 | 教训提取 |
| 模式识别 | 图谱分析 | 投资偏好/预警信号 |

---

## 安全模型

```
你的数据流：
  项目信息 → Neo4j（本地） → 脱敏 search query → DeepSeek API → 分析结果 → 本地文件

  绝不上云的内容：
  ✗ 公司名称/创始人姓名
  ✗ 财务数据/估值
  ✗ 你的投资判断/notes
  ✗ LP 信息

  经过脱敏后上云的内容：
  ✓ "XX赛道 近期A轮融资事件"（不写公司名）
  ✓ "企业级AI Agent市场规模 2025"（不含具体公司）
```

---

## 与传统工具对比

| 维度 | Notion/飞书 | Excel | TRIO-Investor |
|------|-----------|-------|---------------|
| 项目关系 | 手动打标签 | 无 | 自动图谱关联 |
| 尽调 | 手动写 | 手动算 | 三面具自动尽调 |
| 备忘录 | 手动填模板 | N/A | 一键生成→PDF |
| 退出复盘 | 靠记忆 | 靠公式 | 图谱模式识别 |
| 保密性 | 云端 | 云端/本地 | 纯本地 |
| 搜索 | 关键词 | 筛选 | 自然语言+图谱遍历 |

---

## 常见问题

### Q: 最少需要什么才能用？

A: Claude Code + Neo4j + DeepSeek API Key。三样东西，30 分钟能装完。DeepSeek API 一个月 100-150 元就够了。

### Q: 我是新手，不会用 Neo4j 怎么办？

A: 不需要会。TRIO-Investor 把 Cypher 查询封装在自然语言后面。你说"查 AI 赛道有哪些项目"，系统自动翻译成 Cypher。

### Q: 数据能迁移吗？

A: 能。Neo4j dump → 文件 → 新机器 restore。支持 CSV/JSON 导入导出。

### Q: 能多人协作吗？

A: v1.0 是单人的。v2.0 规划多人图谱共享（同一基金的投资团队）。

### Q: 和 TRIO-Stock（二级市场）什么关系？

A: 共用 TRIO 3.0 基础设施（三面具/拓扑门禁/交付管道），但数据模型和场景不同。一级看管线+尽调+memo，二级看财报+评分+选股。

---

## 文件索引

| 文件 | 内容 |
|------|------|
| `.claude/commands/investor.md` | /investor 命令入口（8-10 已归档，场景并入 /all 路由） |
| `config/scenarios/investor.json` | 投资者场景配置 |
| `config/schemas/investor-neo4j-schema.cypher` | Neo4j 图数据库 Schema |
| `config/investor-mcp.md` | MCP 配置补充说明 |
| `config/investor-env.sh` | 环境变量模板 |
| `scripts/investor-setup.sh` | 一键环境安装脚本 |
| `templates/investor/memo-template.md` | 投委会备忘录模板 |
| `templates/investor/dd-report-template.md` | 尽调报告模板 |

---

> **下一步**：跑 `bash scripts/investor-setup.sh` → 用 /all 说"新项目入库（一级市场）" → 录入你的第一个项目
