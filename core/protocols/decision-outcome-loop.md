# Decision → Outcome 闭环协议 v1.1

> **定位**：TRIO-Investor 的"记忆系统"。定义投资决策如何被追踪、结果如何被对账、教训如何被提炼、以及如何在下次尽调中自动注入。
> **核心原则**：Outcome ≠ Decision Quality。赚钱不一定判断正确，亏钱不一定判断错误。必须显式建模预期 vs 实际。

---

## 0. 为什么这个协议是必需的

投资行业最大的认知陷阱：

```
赚钱了 → "我当时判断真准"（可能是运气）
亏钱了 → "市场不行"（可能是判断错误）
```

没有结构化对账，投资人会系统性高估自己的判断能力。

这个协议强迫：
1. **投前**：明确写下预期（Expected Outcome）
2. **投后**：记录实际结果（Actual Outcome）
3. **对账**：显式比较预期 vs 实际
4. **提炼**：生成可迁移的 Lesson
5. **注入**：下次尽调自动召回

---

## 1. 数据结构

### 1.1 Decision 节点（投前）

```cypher
CREATE (d:Decision {
  id: "DEC-20260715-001",
  project: "XX科技",
  verdict: "投",              // 投 / 不投 / 跟进入
  confidence: 4,              // 1-5
  thesis_summary: "AI Agent 企业市场快速增长，团队技术壁垒高",
  concerns: "客户集中度偏高(60%来自2个客户)，创始人首次创业",
  date: date("2026-07-15"),

  // === v1.1 新增：结构化预期 ===
  expected_outcomes: [
    {metric: "ARR", target: "3000万", by: "2027-07"},
    {metric: "客户集中度", target: "<30%", by: "2027-07"},
    {metric: "毛利率", target: ">75%", by: "2027-07"},
    {metric: "下一轮估值", target: ">$150M", by: "2027-07"}
  ],
  expected_risks: [
    {risk: "大厂入场", probability: "M", impact: "高"},
    {risk: "创始人离职", probability: "L", impact: "致命"}
  ],
  falsification_conditions: [
    "ARR增速连续两季<30%",
    "最大客户流失",
    "CTO离职"
  ]
})
```

### 1.2 Exit 节点（投后）

```cypher
CREATE (e:Exit {
  id: "EXT-20270715-001",
  type: "并购",
  amount: 15000000,           // 退出金额（万元）
  moic: 3.0,
  irr: 0.28,
  holding_period_months: 24,
  date: date("2027-07-15"),

  // === v1.1 新增：结构化实际结果 ===
  actual_outcomes: [
    {metric: "ARR", actual: "2400万", vs_expected: "-20%"},
    {metric: "客户集中度", actual: "62%", vs_expected: "严重偏离"},
    {metric: "毛利率", actual: "72%", vs_expected: "基本符合"},
    {metric: "下一轮估值", actual: "$120M", vs_expected: "-20%"}
  ],
  actual_events: [
    "2026-Q3: 最大客户续约但砍单30%",
    "2026-Q4: CTO离职，技术路线调整",
    "2027-Q1: 竞品获大厂战略投资"
  ],
  surprise_factors: [
    "大厂入局速度快于预期（预期12个月，实际6个月）",
    "CTO离职不是因为竞业——是因为与CEO在技术路线上分歧"
  ]
})
```

### 1.3 Evaluation 节点（对账）—— v1.1 新增

```cypher
CREATE (ev:Evaluation {
  id: "EVAL-20270720-001",

  // 逐项对账
  thesis_result: "部分成立——市场增长正确，但技术壁垒被高估",
  assumption_results: [
    {assumption: "CTO会留任至少3年", result: "错误——18个月离职"},
    {assumption: "客户会自然分散", result: "错误——集中度反而恶化"},
    {assumption: "毛利率可持续>75%", result: "基本正确"}
  ],

  // 核心判断
  decision_quality: 3,        // 1-5，决策质量 ≠ 赚钱与否
  quality_explanation: "市场方向判断正确(+)，团队稳定性判断错误(-)，客户集中度被系统性低估(-)。MOIC 3x主要受益于赛道热度而非公司自身壁垒",

  // 偏差归因
  overestimated: ["技术壁垒的持续性", "团队稳定性", "客户自然分散"],
  underestimated: ["大厂入局速度", "客户集中度风险", "CTO-CEO关系风险"],

  date: date("2027-07-20")
})
```

### 1.4 Lesson 节点（提炼）

```cypher
CREATE (l:Lesson {
  id: "LSN-20270720-001",
  category: "低估客户集中度",
  summary: "企业服务类项目如果前2大客户占比>50%，即使整体ARR增长，估值也会被集中度折价。本次因客户集中度恶化，退出估值比预期低20%",
  context: {
    sector: "AI Agent",
    stage: "A轮",
    business_model: "企业服务SaaS"
  },
  overestimated_signals: ["技术壁垒", "创始人背景"],
  underestimated_signals: ["客户集中度", "大厂竞争速度"],
  transferable_to: ["AI Agent", "企业服务", "垂直SaaS"],
  confidence_in_transfer: 4,
  created_at: datetime()
})
```

---

## 2. 闭环流程图

```
投前
  Decision 做出
      │
      ├── Thesis（为什么投）
      ├── Expected Outcomes（预期什么结果）
      ├── Expected Risks（预期什么风险）
      └── Falsification Conditions（什么条件推翻判断）
      │
      ▼
投后（12/24/36 个月）
  Exit 发生（或破产/僵尸/继续持有）
      │
      ├── Actual Outcomes（实际结果）
      ├── Actual Events（实际发生的事件）
      └── Surprise Factors（意外因素）
      │
      ▼
对账
  Evaluation
      │
      ├── 逐项对比 Expected vs Actual
      ├── 判断 Decision Quality（≠ 赚钱与否）
      ├── 归因：高估了什么？低估了什么？
      └── 提炼 Lesson
      │
      ▼
注入
  下次同赛道/同阶段尽调
      │
      ├── Cypher 召回相关 Lesson
      ├── 注入尽调提示词
      └── 强制回应："本次项目是否可能重蹈覆辙？"
```

---

## 3. 核心 Cypher 实现

### 3.1 决策-结果关联（退出时执行）

```cypher
// 找到项目的 Decision → Exit 链路
MATCH (e:Exit {id: $exit_id})-[:EXIT_OF]->(c:Company)
MATCH (d:Decision)-[:ON]->(c)
WHERE d.verdict = "投"
RETURN c.name AS 项目,
       d.confidence AS 当时信心,
       d.expected_outcomes AS 预期结果,
       e.actual_outcomes AS 实际结果,
       e.moic AS 实际MOIC,
       e.irr AS 实际IRR
```

### 3.2 生成 Lesson（复盘时执行）

```cypher
// 基于 Evaluation 创建 Lesson
MATCH (ev:Evaluation {id: $eval_id})
MATCH (c:Company)<-[:EXIT_OF]-(e:Exit)
MATCH (c)-[:IN_SECTOR]->(s:Sector)

CREATE (l:Lesson {
  id: "LSN-" + toString(datetime().epochMillis),
  category: $category,
  summary: $summary,
  context: "{sector: '" + s.name + "', stage: '" + c.stage + "'}",
  overestimated_signals: ev.overestimated,
  underestimated_signals: ev.underestimated,
  transferable_to: $transferable_to,
  confidence_in_transfer: $transfer_confidence,
  created_at: datetime()
})

CREATE (l)-[:DERIVED_FROM]->(e)
CREATE (l)-[:APPLIES_TO]->(s)
CREATE (ev)-[:YIELDED]->(l)

RETURN l.id AS 已生成Lesson
```

### 3.3 尽调前召回 Lesson（自动注入）

```cypher
// 新项目入库或启动尽调时自动执行
MATCH (target:Company {name: $target_name})-[:IN_SECTOR]->(s:Sector)
MATCH (l:Lesson)-[:APPLIES_TO]->(s)
WHERE l.confidence_in_transfer >= 3
OPTIONAL MATCH (l)-[:DERIVED_FROM]->(e:Exit)-[:EXIT_OF]->(past:Company)
RETURN l.category AS 教训类型,
       l.summary AS 教训内容,
       past.name AS 来源项目,
       l.overestimated_signals AS 当时高估了,
       l.underestimated_signals AS 当时低估了
ORDER BY l.confidence_in_transfer DESC, l.created_at DESC
LIMIT 5
```

---

## 4. 提示词注入模板

当上述 Cypher 召回到 Lesson 后，将以下内容注入尽调提示词末尾：

```markdown
## 历史教训注入（自适应层）

以下为本系统在同赛道历史项目中积累的教训。请在本次尽调中逐条回应：

{{#each recalled_lessons}}
### 教训 {{@index}}：{{category}}
**来源**：{{source_project}}（{{outcome_rating}}，MOIC {{actual_moic}}）
**内容**：{{summary}}
**当时高估了**：{{overestimated_signals}}
**当时低估了**：{{underestimated_signals}}
{{/each}}

### 核查要求
1. 对于每条历史教训，必须在尽调报告中明确回应："本次项目是否可能重蹈覆辙？"
2. 如果历史项目高估了"创始人背景"，本次必须增加：核心团队深度访谈、离职员工背调
3. 如果历史项目低估了"客户集中度"，本次必须：逐客户分析续约概率、集中度改善路径
4. 如果历史项目被"大厂入局速度"超预期冲击，本次必须：竞品动态监控、大厂布局分析

### 偏见警示
⚠️ 历史教训是参考框架，不是判决书。禁止"因为上次同赛道失败了，所以这次也否定"的归纳谬误。每条教训必须结合当前项目的具体情况判断适用性。
```

---

## 5. 命令行触发

```bash
# 记录退出事件（投后12-36个月手动触发）
/investor 复盘 XX科技

# 系统自动执行：
# 1. 查找 Decision → 提取 Expected Outcomes
# 2. 对比 Exit.actual_outcomes
# 3. 生成 Evaluation 节点
# 4. 生成 Lesson 节点
# 5. 关联到 Sector
# 6. 输出："已生成 Lesson LSN-xxx。下次同赛道尽调将自动注入以下教训：..."

# 查看历史教训
/investor 教训 AI Agent
# → 列出 AI Agent 赛道所有 Lesson，按可迁移置信度排序
```

---

## 6. 关键设计决策

### 6.1 为什么 Outcome ≠ Decision Quality？

```
案例 A：投了，MOIC 5x
  判断：市场会增长——对了
  判断：团队能执行——对了
  意外：竞品突然倒闭，市场全归我们——运气
  → Decision Quality = 3（判断一般，运气好）

案例 B：投了，MOIC 0.5x
  判断：市场会增长——对了
  判断：团队能执行——对了
  意外：政策突然禁止该赛道——不可抗力
  → Decision Quality = 4（判断正确，运气差）
```

**系统不能把 MOIC 直接映射为决策质量。必须逐假设对账。**

### 6.2 为什么用结构化预期而不是自然语言？

```
❌ "我觉得这家公司12个月后应该不错"
    → 无法对账。什么叫"不错"？

✅ expected_outcomes: [
     {metric: "ARR", target: "3000万", by: "2027-07"},
     {metric: "客户数", target: ">50家", by: "2027-07"}
   ]
    → 12个月后逐项对比。ARR 2400万 = -20%。可量化、可归因。
```

### 6.3 为什么不做自动学习？

系统**不自动**修改投资框架。闭环的工作方式是：

```
发现模式 → 生成 Lesson → 下次尽调注入提示词 → 人类判断是否适用
```

不是：

```
发现模式 → 自动修改规则 → 下次自动应用
```

**投资决策的责任永远在人。系统只负责"提醒你别再踩同一个坑"。**

---

> **依赖**：`core/ontology/investor-ontology.md`（本体论定义）
> **不依赖**：GDS、向量索引、机器学习、新增 MCP
> **v2.0 展望**：累积 ≥10 个 Lesson 后 → 用 Cypher 做模式聚类 → 自动生成"投资人偏差报告"
