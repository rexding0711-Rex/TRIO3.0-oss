# TRIO-Investor 投资本体论 v1.1

> **定位**：不是数据库 DDL，是投资世界的物理定律。定义"什么东西在动、处于什么状态、什么力量推动改变、什么条件触发什么动作、凭什么相信"。
> **读者**：Claude Code（每次 `/investor` 会话自动加载）+ 投资人（理解系统设计哲学）。
> **原则**：不增加技术债务。所有定义可映射到现有 Neo4j Schema，不需要重构数据库。

---

## 0. 设计原则

1. **世界由五种东西组成**：Object（实体）、State（状态）、Event（事件）、Rule（规则）、Evidence（证据）
2. **证据横向贯穿**：每一个 Object、State、Event、Decision、Outcome、Lesson 都必须有证据来源。投资系统与 CRM 的本质区别就在这里
3. **状态变更必须有事件**：不能偷偷改状态。每次状态流转 = 一个 Event 节点，形成完整审计轨迹
4. **可证伪优先**：每个 Thesis 必须附可证伪条件。没有可证伪条件的判断 = 不可靠
5. **Outcome ≠ Decision Quality**：赚钱 ≠ 当时判断正确。亏钱 ≠ 当时判断错误。必须显式建模预期 vs 实际

---

## 1. Object（实体：世界里有什么）

### 1.1 Company（公司）
- **定义**：创造商业价值的实体
- **核心属性**：name, sector, stage, founded_year, headquarters, business_model, description
- **财务属性**：valuation, revenue, growth_rate, gross_margin, employee_count
- **系统属性**：aliases（名称别名数组，用于实体消歧），source（信息来源），created_at

### 1.2 Founder（创始人）
- **定义**：驱动 Company 的人
- **核心属性**：name, education, previous_company, role, linkedin_url
- **评估属性**：strengths, risks, decision_pattern（压力下如何做选择）
- **系统属性**：aliases, source

### 1.3 Deal（交易）
- **定义**：资本与 Company 结合的契约过程。**这是状态的载体**
- **核心属性**：round, amount, valuation, date, status
- **status 枚举**：Pipeline → Screening → DD → IC → TS → Closed → Monitoring → Exit（见 State 章节）
- **决策属性**：lead_investor, co_investors, terms_summary

### 1.4 Thesis（投资命题）—— v1.1 新增
- **定义**：决定投资的核心逻辑假设。**这是系统的灵魂**
- **核心属性**：
  - `hypothesis`：核心假设陈述（如"AI Agent 将在 12 个月内替代 30% 客服人力"）
  - `falsification_conditions`：可证伪条件数组（如["Gartner 下调相关预测至 <$30B", "头部客户续费率 < 80%"]）
  - `time_horizon`：验证周期（如"12个月"）
  - `confidence`：初始置信度 1-5
  - `status`：Active / Validated / Falsified / Expired
- **硬约束**：每个 Thesis 必须包含 ≥2 个可证伪条件。缺少 → 系统拒绝接受。

### 1.5 Evidence（证据）—— v1.1 新增
- **定义**：支持或反驳任何声明的客观事实。**横向贯穿所有层**
- **核心属性**：
  - `source_type`：财报 / 专家访谈 / 客户访谈 / 行业报告 / 工商数据 / 新闻报道 / 个人判断
  - `source_url` 或 `source_file`：可追溯的原始来源
  - `content`：证据内容摘要
  - `credibility`：可信度 1-5（5=多源交叉验证，1=单方声称）
  - `sentiment`：正向 / 负向 / 中性
  - `verified_at`：验证时间
- **硬约束**：重大判断（估值、市场规模、技术壁垒）不能依赖 credibility ≤2 的单源证据

### 1.6 Decision（决策）
- **定义**：投资人在某个时点做出的判断
- **核心属性**：verdict（投/不投/跟进入），confidence（1-5），thesis（关联的 Thesis），concerns（担忧），date
- **v1.1 新增**：
  - `expected_outcomes`：预期结果数组（如 [{metric: "ARR", target: "30M", by: "2026-12"}, {metric: "客户集中度", target: "<30%", by: "2026-12"}]）
  - `falsification_conditions`：关联的可证伪条件

### 1.7 Exit（退出）
- **定义**：投资退出的结果
- **核心属性**：type（IPO/并购/转让/清算），amount，moic，irr，holding_period_months，date

### 1.8 Lesson（教训）—— v1.1 新增
- **定义**：从 Decision-Outcome 对比中提炼的系统级记忆。**系统进化的基石**
- **核心属性**：
  - `category`：错误归因类型（高估市场规模 / 低估竞争 / 高估团队 / 低估客户集中度 / 时机错误 / 估值过高 / 其他）
  - `summary`：一句话教训
  - `context`：适用场景（赛道 / 阶段 / 商业模式）
  - `overestimated_signals`：被高估的信号
  - `underestimated_signals`：被低估的信号
  - `transferable_to`：可迁移到的赛道/场景
  - `confidence_in_transfer`：可迁移置信度 1-5

---

## 2. State（状态：实体在时间轴上的位置）

### 2.1 Deal 状态机

```
[Sourcing] ──初筛通过──→ [Screening] ──立项──→ [DD]
    │                        │                    │
    │(放弃)                  │(放弃)              │(发现红线)
    ▼                        ▼                    ▼
[Killed] ←────────────────────────────────── [Killed]
                                                    ▲
[DD] ──DD通过──→ [IC] ──IC否决──────────────────────┘
                   │
              (IC批准)
                   ▼
              [TS] ──交割──→ [Closed] ──→ [Monitoring] ──→ [Exit]
                   │            │
              (TS破裂)     (直接Pass)
                   ▼            ▼
            [Closed_Lost]   [Pass]
```

### 2.2 状态转换规则

| 当前状态 | 可转换到 | 触发事件 | 必填信息 |
|---------|---------|---------|---------|
| Sourcing | Screening, Killed | 初筛通过/放弃 | 一句话判断 |
| Screening | DD, Killed | 立项/放弃 | 1页Memo |
| DD | IC, Killed | DD完成/发现红线 | 尽调报告 |
| IC | TS, Killed | IC通过/否决 | IC决议 |
| TS | Closed, Closed_Lost | 交割/破裂 | 条款摘要 |
| Closed | Monitoring | 打款完成 | 交割文件 |
| Monitoring | Exit, Killed | 退出/破产 | — |
| Exit | (终态) | — | MOIC/IRR |

### 2.3 状态 AI 行为约束

- **Screening**：AI 仅做桌面研究，输出 1 页 Memo。**禁止深度发散**
- **DD**：AI 启动 5 层解剖 + 三视角质控。**必须列出可证伪条件**
- **IC**：AI 将 Evidence 映射到 Thesis，**重点突出可证伪条件的验证情况**
- **Monitoring**：AI 定期对比实际指标 vs 预期指标
- **Killed**：**必须记录 kill_reason，关联到具体 Evidence 或 Thesis 证伪**

---

## 3. Event（事件：推动状态变化的力）

事件是状态的动词。在 Neo4j 中表现为带时间戳的节点。

| 事件 | 触发条件 | 状态转换 | 产出物 |
|------|---------|---------|--------|
| ONBOARD | 用户录入新项目 | → Sourcing | Company + Founder 节点 |
| SCREENED | 初筛完成 | Sourcing → Screening | Screening Memo |
| DD_INITIATED | 决定深度尽调 | Screening → DD | DD 计划 |
| RED_FLAG | 发现致命缺陷 | Any → Killed | 红线报告 |
| THESIS_FALSIFIED | 证据否定核心假设 | DD/IC → Killed | 证伪分析 |
| IC_SCHEDULED | 提交上会材料 | DD → IC | IC Memo 草稿 |
| IC_APPROVED | 投委会通过 | IC → TS | IC 决议记录 |
| WIRED | 资金到账 | TS → Closed | 交割确认 |
| MILESTONE_HIT | 公司达成关键指标 | Monitoring → Monitoring | 投后跟踪 |
| EXITED | 并购/IPO/回购 | Monitoring → Exit | 退出回报 |
| LESSON_EXTRACTED | 复盘完成 | (不改变状态) | Lesson 节点 |

**硬约束**：所有状态转换必须伴随 Event 节点创建。禁止直接修改 status 属性。

---

## 4. Rule（规则：什么条件触发什么动作）

### 4.1 证伪规则（最高优先级）
- **触发**：新增 Evidence（credibility ≥3）指向 Thesis 的某个 falsification_condition 为真
- **动作**：Thesis.status → Falsified。关联 Deal 标记 At_Risk。生成 Alert
- **禁止**：AI 自动掩盖或降级此风险

### 4.2 证据交叉验证规则
- **触发**：IC Memo 生成时，检查关键 Evidence
- **条件**：核心假设的支撑证据 source_type 仅为"公司方提供"
- **动作**：AI 必须标注"此核心证据为单方信源，建议补充交叉验证"

### 4.3 停滞规则
- **触发**：Screening >14 天 / DD >45 天 无状态变更
- **动作**：Alert "该 Deal 已停滞 X 天，建议推进或 Kill"

### 4.4 历史教训召回规则
- **触发**：新 Deal 入库或启动尽调时
- **条件**：同赛道（Sector） + 同阶段（Stage）
- **动作**：自动查询相关 Lesson → 注入尽调提示词

### 4.5 集中度规则
- **触发**：Pipeline 查看时
- **条件**：单赛道占比 >40% 或 单阶段占比 >50%
- **动作**：Portfolio Alert "赛道/阶段集中度偏高"

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

### 6.1 节点标签

```
:Company, :Founder, :Deal, :Thesis, :Evidence, :Decision, :Exit, :Lesson,
:PipelineState, :HealthState, :AlertRule, :FalsificationCondition
```

### 6.2 核心关系

```cypher
(:Founder)-[:FOUNDED]->(:Company)
(:Company)-[:IN_SECTOR]->(:Sector)
(:Deal)-[:INVESTMENT_IN]->(:Company)
(:Deal)-[:LED_BY]->(:Fund)
(:Decision)-[:ON]->(:Company)
(:Decision)-[:BASED_ON]->(:Thesis)
(:Thesis)-[:SUPPORTED_BY {weight}]->(:Evidence)
(:Thesis)-[:FALSIFIED_BY {weight}]->(:Evidence)
(:Exit)-[:EXIT_OF]->(:Company)
(:Exit)-[:CONTRADICTS|:CONFIRMS]->(:Thesis)
(:Decision)-[:YIELDED]->(:Lesson)
(:Exit)-[:YIELDED]->(:Lesson)
(:Lesson)-[:APPLIES_TO]->(:Sector)
(:Company)-[:CURRENT_STATE]->(:PipelineState)
(:Evidence)-[:ABOUT]->(:Company|:Founder|:Deal|:Thesis)
```

### 6.3 本体约束（Cypher 检查）

```cypher
// 约束1：每个 Company 必须有唯一状态
MATCH (c:Company)
OPTIONAL MATCH (c)-[:CURRENT_STATE]->(ps:PipelineState)
WITH c, count(ps) as cnt
WHERE cnt <> 1
RETURN c.name, cnt, "状态异常——必须唯一"

// 约束2：Decision 必须关联 Thesis
MATCH (d:Decision)
OPTIONAL MATCH (d)-[:BASED_ON]->(t:Thesis)
WITH d, count(t) as cnt
WHERE cnt < 1
RETURN d.project, "缺失 Thesis——违反可证伪原则"

// 约束3：Exit 必须能回溯到 Decision
MATCH (e:Exit)-[:EXIT_OF]->(c:Company)
OPTIONAL MATCH (d:Decision)-[:ON]->(c)
WITH e, c, collect(d) as decisions
WHERE size(decisions) = 0
RETURN c.name, "退出无对应决策记录"
```

---

## 7. AI 交互协议

Claude Code 在处理 `/investor` 命令时，必须遵循：

1. **状态流转必须人类确认**：AI 可以建议状态变更，但不能自动执行
2. **绝不编造 Evidence**：所有声明必须关联来源。无来源 → 标注置信度 ≤2
3. **绝不隐藏证伪风险**：Thesis 被证伪时，必须在输出中红色高亮
4. **Must Fix Before Proceed**：检测到本体约束违规 → 阻断 → 等人类修复

---

> **文件版本**：v1.1 | **依赖**：Neo4j 5.x | **不依赖**：GDS、向量索引、新增 MCP
> **下一个要读的文件**：`core/protocols/decision-outcome-loop.md`（决策闭环协议）
