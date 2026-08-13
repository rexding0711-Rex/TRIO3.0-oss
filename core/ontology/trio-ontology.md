# TRIO 统一本体论 v2.0

> **定位**：不是数据库 DDL，是 TRIO 分析世界的物理定律。定义"什么东西在动、处于什么状态、什么力量推动改变、什么条件触发什么动作、凭什么相信"。
> **读者**：Claude Code（每次分析型会话自动加载）+ 用户（理解系统设计哲学）。
> **覆盖领域**：公司尽调（investment/dd）· 竞品分析（competitive）· 人物评估（talent）· 行业分析（industry）· 供应链（supply_chain）· 通用决策（general）
> **原则**：不增加技术债务。所有定义可映射到现有 Neo4j Schema，不需要重构数据库。
> **v1.1→v2.0**：从投资专属泛化为 TRIO 全领域。Object 加 `domain` 字段、State 加领域子状态机、Rule 用 domain+tags 参数化替换 Sector+Stage。

---

## 0. 设计原则

1. **世界由五种东西组成**：Object（实体）、State（状态）、Event（事件）、Rule（规则）、Evidence（证据）
2. **证据横向贯穿**：每一个 Object、State、Event、Decision、Outcome、Lesson 都必须有证据来源。投资系统与 CRM 的本质区别就在这里
3. **状态变更必须有事件**：不能偷偷改状态。每次状态流转 = 一个 Event 节点，形成完整审计轨迹
4. **可证伪优先**：每个 Thesis 必须附可证伪条件。没有可证伪条件的判断 = 不可靠
5. **Outcome ≠ Decision Quality**：赚钱 ≠ 当时判断正确。亏钱 ≠ 当时判断错误。必须显式建模预期 vs 实际

---

## 1. Object（实体：世界里有什么）

> **v2.0**：所有实体新增 `domain` 字段（枚举：`investment` / `dd` / `competitive` / `talent` / `industry` / `supply_chain` / `general`），标注该实体所属的分析领域。同一实体可跨多个 domain。

### 1.1 Company（公司）— domain: investment, dd, competitive, supply_chain
- **定义**：创造商业价值的实体
- **核心属性**：name, sector, stage, founded_year, headquarters, business_model, description
- **财务属性**：valuation, revenue, growth_rate, gross_margin, employee_count
- **系统属性**：aliases（名称别名数组，用于实体消歧），source（信息来源），created_at，**domain**

### 1.2 Person（人物）— domain: talent, investment, dd（原 Founder，v2.0 泛化）
- **定义**：驱动组织或值得独立评估的个人
- **核心属性**：name, education, previous_org, role, linkedin_url
- **评估属性**：strengths, risks, decision_pattern（压力下如何做选择）
- **系统属性**：aliases, source, **domain**
- **子类型**：Founder（投资语境）、TalentSubject（人才评估语境）、KeyExecutive（尽调语境）

### 1.3 Deal（交易）— domain: investment
- **定义**：资本与 Company 结合的契约过程。**这是状态的载体**（投资领域专属）
- **核心属性**：round, amount, valuation, date, status
- **status 枚举**：Pipeline → Screening → DD → IC → TS → Closed → Monitoring → Exit（见 State 章节）
- **决策属性**：lead_investor, co_investors, terms_summary

### 1.4 Thesis（分析命题）— domain: 全领域
- **定义**：任何分析中的核心逻辑假设。**这是系统的灵魂**
- **核心属性**：
  - `hypothesis`：核心假设陈述
  - `falsification_conditions`：结构化可证伪条件数组（v2.0 升级为 `{metric, target, by}[]` 格式，兼容旧 string[] 格式）
  - `time_horizon`：验证周期
  - `confidence`：初始置信度 1-5
  - `status`：Active / Validated / Falsified / Expired
  - **`domain`**：适用的分析领域
- **硬约束**：每个 Thesis 必须包含 ≥2 个可证伪条件。缺少 → 系统拒绝接受。
- **结构化可证伪条件格式（v2.0）**：
  ```json
  {
    "metric": "ARR",
    "target": "3000万",
    "by": "2027-07"
  }
  ```
  此格式使预期可量化、可对账。旧格式 `"Gartner 下调预测至 <$30B"` 仍兼容但标记为 `deprecated`。

### 1.5 Evidence（证据）
- **定义**：支持或反驳任何声明的客观事实。**横向贯穿所有层、所有 domain**
- **核心属性**：同 v1.1，新增 **`domain`**
- **硬约束**不变：重大判断不能依赖 credibility ≤2 的单源证据

### 1.6 Decision（决策）— domain: 全领域
- **定义**：分析者在某个时点做出的判断。**不限投资——竞品判断、人物判断、行业方向判断均可**
- **核心属性**：verdict（domain 决定枚举值），confidence（1-5），thesis（关联的 Thesis），concerns（担忧），date
- **verdict 枚举按 domain**：
  - investment：投 / 不投 / 跟进入
  - competitive：领先 / 持平 / 落后 / 威胁
  - talent：强烈推荐 / 推荐 / 保留 / 不推荐
  - general：支持 / 反对 / 观望
- **v2.0 保留**：`expected_outcomes`（`{metric, target, by}[]`）+ `falsification_conditions`

### 1.7 Outcome（结果）— domain: 全领域（原 Exit，v2.0 泛化）
- **定义**：决策的实际结果。**投资是退出回报，竞品是市场格局变化，人物是实际表现**
- **核心属性**：type（domain 决定枚举），actual_outcomes（`{metric, actual, vs_expected}[]`），surprise_factors，date
- **子类型**：Exit（投资退出，保留兼容）、MarketOutcome（竞品）、PerformanceOutcome（人物）

### 1.8 Lesson（教训）
- **定义**：从 Decision-Outcome 对比中提炼的系统级记忆。**系统进化的基石**
- **核心属性**（v2.0 泛化）：
  - `category`：错误归因类型（高估市场规模 / 低估竞争 / 高估团队 / 低估客户集中度 / 时机错误 / 估值过高 / **低估技术难度 / 高估政策支持 / 低估供应链风险** / 其他）
  - `summary`：一句话教训
  - `context`：适用场景（**domain + tags**，不再仅限于赛道+阶段）
  - `overestimated_signals` / `underestimated_signals`
  - `transferable_to`：可迁移到的 domain/tags
  - `confidence_in_transfer`：可迁移置信度 1-5

---

## 2. State（状态：实体在时间轴上的位置）

### 2.1 通用 Pipeline 状态机（v2.0 泛化）

TRIO 中所有分析项目共享一个 8 阶段通用生命周期。各领域有子状态：

```
[Intake] ──分诊通过──→ [Triage] ──立项──→ [Active]
    │                      │                  │
    │(拒绝)                │(拒绝)            │(复审不通过)
    ▼                      ▼                  ▼
[Killed] ←──────────────────────────────── [Killed]
                                                  ▲
[Active] ──复审通过──→ [Gate] ──Gate否决───────────┘
                         │
                    (Gate通过)
                         ▼
                    [Commitment] ──→ [Closed] ──→ [Monitoring] ──→ [Archived]
                         │              │
                    (Commitment破裂)  (直接Pass)
                         ▼              ▼
                  [Closed_Lost]     [Pass]
```

### 2.2 领域子状态映射

| 通用阶段 | investment (Deal) | dd (尽调) | competitive (竞品) | talent (人才) |
|---------|-------------------|-----------|-------------------|---------------|
| Intake | Sourcing | 入库 | Watching | Identified |
| Triage | Screening | 初筛 | Analyzing | Contacted |
| Active | DD | 深度分析 | Tracking | Assessed |
| Gate | IC | 投委会 | Review | 终面 |
| Commitment | TS | 确认 | — | Engaged |
| Closed | Closed | 交付 | Archived | Closed |
| Monitoring | Monitoring | 跟踪 | 持续追踪 | 试用期 |
| Archived | Exit | 复盘 | — | 复盘 |

### 2.3 通用状态转换规则

| 当前状态 | 可转换到 | 触发事件 | 必填信息 |
|---------|---------|---------|---------|
| Intake | Triage, Killed | 初筛通过/放弃 | 一句话判断 |
| Triage | Active, Killed | 立项/放弃 | 1页Memo |
| Active | Gate, Killed | 分析完成/发现致命缺陷 | 分析报告 |
| Gate | Commitment, Killed | 复审通过/否决 | 复审决议 |
| Commitment | Closed, Closed_Lost | 确认/破裂 | 确认摘要 |
| Closed | Monitoring | 交付完成 | 交付确认 |
| Monitoring | Archived, Killed | 完成/终止 | — |
| Archived | (终态) | — | Outcome数据 |

### 2.4 状态 AI 行为约束（v2.0 泛化）

- **Intake**：AI 仅做桌面研究，输出 1 页 Memo。**禁止深度发散**
- **Triage**：AI 做缺口扫描（Gate 0），列出已知未知，等用户决策
- **Active**：AI 启动对应领域的分析协议（DD→5层解剖、竞品→三视角、人才→6维评估）。**必须列出可证伪条件**
- **Gate**：AI 将 Evidence 映射到 Thesis，**重点突出可证伪条件的验证情况**
- **Monitoring**：AI 定期对比实际指标 vs 预期指标（如果绑定了 {metric, target, by}）
- **Killed**：**必须记录 kill_reason，关联到具体 Evidence 或 Thesis 证伪**

---

## 3. Event（事件：推动状态变化的力）

事件是状态的动词。在 Neo4j 中表现为带时间戳的节点。**v2.0 泛化为通用事件名 + domain 标记**。

| 事件（通用名） | 投资原名 | 触发条件 | 状态转换 | 产出物 |
|------|---------|---------|---------|--------|
| INTAKE | ONBOARD | 用户录入新实体 | → Intake | Entity 节点 |
| SCREENED | SCREENED | 初筛完成 | Intake → Triage | Screening Memo |
| ANALYSIS_STARTED | DD_INITIATED | 决定深度分析 | Triage → Active | 分析计划 |
| RED_FLAG | RED_FLAG | 发现致命缺陷 | Any → Killed | 红线报告 |
| THESIS_FALSIFIED | THESIS_FALSIFIED | 证据否定核心假设 | Active/Gate → Killed | 证伪分析 |
| GATE_SCHEDULED | IC_SCHEDULED | 提交复审材料 | Active → Gate | 复审简报 |
| GATE_APPROVED | IC_APPROVED | 复审通过 | Gate → Commitment | 复审决议 |
| COMMITTED | WIRED | 确认/交割 | Commitment → Closed | 确认记录 |
| MILESTONE_HIT | MILESTONE_HIT | 达成关键指标 | Monitoring → Monitoring | 跟踪记录 |
| CLOSED | EXITED | 完成/退出 | Monitoring → Archived | Outcome 数据 |
| LESSON_EXTRACTED | LESSON_EXTRACTED | 复盘完成 | (不改变状态) | Lesson 节点 |

**硬约束不变**：所有状态转换必须伴随 Event 节点创建。禁止直接修改 status 属性。

---

## 4. Rule（规则：什么条件触发什么动作）—— v2.0 参数化

> **v2.0**：5 条规则从投资专属（Sector+Stage）泛化为 domain+tags。每条规则标注适用范围。

### 4.1 证伪规则（最高优先级）— domain: 全领域
- **触发**：新增 Evidence（credibility ≥3）指向 Thesis 的某个 falsification_condition 为真
- **动作**：Thesis.status → Falsified。关联实体标记 At_Risk。生成 Alert
- **禁止**：AI 自动掩盖或降级此风险

### 4.2 证据交叉验证规则 — domain: 全领域
- **触发**：Gate Review（复审简报）生成时，检查关键 Evidence
- **条件**：核心假设的支撑证据 source_type 仅为"单方声称"（D 级）
- **动作**：AI 必须标注"此核心证据为单方信源，建议补充交叉验证"

### 4.3 停滞规则 — domain: 全领域（阈值可按 domain 调整）
- **触发**：Triage >14 天 / Active >45 天 无状态变更
- **动作**：Alert "该分析项目已停滞 X 天，建议推进或 Kill"

### 4.4 历史教训召回规则 — domain: 全领域（v2.0 参数化）
- **触发**：新实体入库或启动分析时
- **条件**：匹配 **domain + tags**（原：Sector + Stage）
- **动作**：自动查询相关 Lesson → 注入分析提示词
- **tags 示例**：`["AI Agent", "企业服务", "A轮"]` / `["具身智能", "硬件", "天使轮"]`

### 4.5 集中度规则 — domain: investment, competitive
- **触发**：Portfolio/竞品看板查看时
- **条件**：单 domain+tag 组合占比 >40% 或 单阶段占比 >50%
- **动作**：Alert "领域/阶段集中度偏高"

---

## 5. Evidence（证据：凭什么相信）

**Evidence 不是一种 Object——它是横向贯穿所有层的元数据。**

```
Object  ──── Evidence（这个公司真的存在吗？数据来源？）
State   ──── Evidence（凭什么说它现在在 DD 阶段？触发事件是什么？）
Event   ──── Evidence（这个事件真的发生了吗？来源？）
Thesis  ──── Evidence（这个假设有什么数据支撑？）
Decision─── Evidence（当时做这个判断的依据是什么？）
Outcome ──── Evidence（实际结果的数据来源？）
Lesson  ──── Evidence（这个教训基于哪些案例？）
```

### 5.1 证据等级

| 等级 | 定义 | 示例 |
|:--:|------|------|
| A | 多源交叉验证的客观事实 | 财报+工商+客户访谈一致 |
| B | 单一权威来源 | 经审计的财报 |
| C | 非权威但可信 | 行业报告、专家访谈 |
| D | 单方声称 | 公司提供的 BP 数据 |
| E | 推断/猜测 | AI 基于模式的推测 |

### 5.2 证据约束

- **D 级证据**不能单独支撑核心 Thesis
- **E 级证据**必须标注"推断，待验证"
- 任何 Claim 如果没有 Evidence 关联 → 标注"⚠️ 无证据支撑"

---

## 6. 图 Schema 映射

### 6.1 节点标签（v2.0 泛化）

```
基础标签: :Entity, :Person, :Organization, :Deal, :Thesis, :Evidence, :Decision, :Outcome, :Lesson
领域特化: :Company, :Founder, :TalentSubject, :Competitor, :Exit
状态标签: :PipelineState, :HealthState, :AlertRule, :FalsificationCondition
```

### 6.2 核心关系（v2.0 泛化）

```cypher
// 人与组织
(:Person)-[:AFFILIATED_WITH {role, period}]->(:Organization)
(:Person)-[:FOUNDED {date}]->(:Organization)

// 组织间
(:Organization)-[:COMPETES_WITH {intensity}]->(:Organization)
(:Organization)-[:SUPPLIER_TO {product}]->(:Organization)

// 领域归属
(:Entity)-[:IN_DOMAIN {weight}]->(:Domain)         // v2.0 新：domain + tags 替代 Sector

// 分析与决策
(:Decision)-[:ON]->(:Entity)
(:Decision)-[:BASED_ON]->(:Thesis)
(:Thesis)-[:SUPPORTED_BY {weight}]->(:Evidence)
(:Thesis)-[:FALSIFIED_BY {weight}]->(:Evidence)
(:Outcome)-[:OUTCOME_OF]->(:Entity)
(:Outcome)-[:CONTRADICTS|:CONFIRMS]->(:Thesis)

// 学习闭环
(:Decision)-[:YIELDED]->(:Lesson)
(:Outcome)-[:YIELDED]->(:Lesson)
(:Lesson)-[:APPLIES_TO_DOMAIN {confidence}]->(:Domain)  // v2.0 新：domain+tags 替代 Sector

// 状态追踪
(:Entity)-[:CURRENT_STATE]->(:PipelineState)
(:Evidence)-[:ABOUT]->(:Entity|:Person|:Organization|:Thesis)
```

### 6.3 本体约束（Cypher 检查，v2.0 泛化）

```cypher
// 约束1：每个 Entity 必须有唯一状态
MATCH (e:Entity)
OPTIONAL MATCH (e)-[:CURRENT_STATE]->(ps:PipelineState)
WITH e, count(ps) as cnt
WHERE cnt <> 1
RETURN e.name, cnt, "状态异常——必须唯一"

// 约束2：Decision 必须关联 Thesis
MATCH (d:Decision)
OPTIONAL MATCH (d)-[:BASED_ON]->(t:Thesis)
WITH d, count(t) as cnt
WHERE cnt < 1
RETURN d.project, "缺失 Thesis——违反可证伪原则"

// 约束3：Outcome 必须能回溯到 Decision
MATCH (o:Outcome)-[:OUTCOME_OF]->(e:Entity)
OPTIONAL MATCH (d:Decision)-[:ON]->(e)
WITH o, e, collect(d) as decisions
WHERE size(decisions) = 0
RETURN e.name, "Outcome无对应Decision记录"
```

---

## 7. AI 交互协议（v2.0 泛化）

Claude Code 在处理任何分析型命令（`/all`、`/尽调`、`/竞品`、`/investor`、`/逆向工程`）时，必须遵循：

1. **状态流转必须人类确认**：AI 可以建议状态变更，但不能自动执行
2. **绝不编造 Evidence**：所有声明必须关联来源。无来源 → 标注置信度 ≤2
3. **绝不隐藏证伪风险**：Thesis 被证伪时，必须在输出中红色高亮
4. **Must Fix Before Proceed**：检测到本体约束违规 → 阻断 → 等人类修复
5. **v2.0 新增 — Domain 感知**：AI 必须识别当前分析的 domain，加载对应的子状态机和 verdict 枚举
6. **v2.0 新增 — 可证伪结构化**：confidence ≥3 的结论必须附加 `{metric, target, by}` 格式的可证伪条件

---

> **文件版本**：v2.0 | **依赖**：Neo4j 5.x | **不依赖**：GDS、向量索引、新增 MCP
> **v1.1→v2.0 变更**：Object 加 domain 字段 + Person/Outcome 泛化 + Pipeline 状态机通用化 + Rule domain+tags 参数化 + falsification_conditions 结构化
> **下一个要读的文件**：`core/protocols/decision-outcome-loop.md`（决策闭环协议）
