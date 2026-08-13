---
name: triage
description: 分析请求分流——判断深度、分配角色、检测盲区。当用户发出分析型请求（尽调/竞品/复盘/决策/赛道洞察/逆向工程/速判/股票分析）时自动触发。也响应 /all 和 /trio-run。
category: intake
---

# triage — 分析请求分流

所有 TRIO 分析任务的唯一入口。在其他任何人执行分析之前，先回答四个问题：**多深？什么类型？谁主导？漏了什么？**

> 为什么需要模型自动触发：用户可能直接说"帮我看看宁德时代"——没有打 `/尽调`，但这就是尽调请求。triage 负责识别这种隐式请求并分配正确的 pipeline。

## Steps

### Step 1: 解析请求

从用户输入中提取四个要素：

| 要素 | 要回答的问题 | 示例 |
|------|------------|------|
| **目标对象** | 分析谁/什么？ | 公司名/人名/产品/行业/事件 |
| **核心问题** | 用户真正想知道什么？ | 与表面措辞可能不同——"这个公司怎么样"可能是"该不该投" |
| **约束条件** | 时间/格式/已有前置分析？ | "快速""深度""对比""给 PPT" |
| **风险等级** | 结论影响什么决策？ | `low`（信息查询）/ `medium`（业务决策）/ `high`（投资/合规/人事） |

**完成标准**：四个要素全部提取完毕，至少给出一个非空的 `core_question`。

### Step 2: 判定深度

```
┌─────────────────────────────────────────────────┐
│ 单问题 + <80 token + 事实查询？                    │
│   └→ FAST: Step 1→4→done，单角色直出              │
│                                                  │
│ 2-4 子问题 或 80-200 token？                      │
│   └→ STANDARD: 三面具并行，6 步标准流程            │
│                                                  │
│ ≥5 子问题 或 >200 token 或 策略/架构/多方分析？     │
│   └→ FULL: 全 8 步 + 链式辩论 + 审计               │
│                                                  │
│ 风险=high（投资/合规/人事）？                       │
│   └→ FULL: 无视其他条件，强制全流程                 │
└─────────────────────────────────────────────────┘
```

特殊情况：
- 用户说"快速"/"速判"/"quick" → 跳过深度流程，只跑 Kimi+DeepSeek 双视角速判
- 用户说"全量"/"深度"/"扒光" → 升级为 5 层 OODA 解剖模式

**完成标准**：depth 字段已赋值（FAST/STANDARD/FULL/DEPTH），赋值逻辑与上表一致。

### Step 3: 分配角色

| 任务类型 | 主导面具 | 审计面具 | 为什么 |
|---------|---------|---------|--------|
| 公司尽调 | Kimi（叙事构建） | DeepSeek（财务核查） | 尽调的难点是叙事一致性——先建叙事，再审计 |
| 竞品对比 | Kimi（洞察发现） | DeepSeek（矛盾检测） | 竞品的难点是差异化判断 |
| 人物评估 | Kimi（画像构建） | DeepSeek（去美化） | 人物分析天然偏正面——需要审计拉回 |
| 技术评估 | Claude（工程判断） | DeepSeek（审计） | 技术是真/假/夸大——工程面具更适合 |
| 行业研究 | Kimi（趋势发现） | DeepSeek（反证） | 趋势判断需要叙事 + 反叙事 |
| 决策支持 | 三面具等权 | DeepSeek（少数派保护） | 决策需要多角度——不能一个视角主导 |
| 快速查询 | Claude | 无 | 快速查询 = 工程交付 |
| 深度解剖 | Kimi 每层主导 | DeepSeek 每层审计 | 5 层 OODA 各有最适角色 |

**完成标准**：lead_role + audit_role + delivery_role 全部赋值。

### Step 4: 盲区检测

在分析启动前，显式列出以下三类盲区：

**已知已知**：知识库中已有数据（如 Neo4j 图谱中已有该公司供应链）
**已知未知**：知道需要但还没有的关键数据——标注为 `???` 节点（如"??? 该公司 2025 Q4 财报"）
**层级追溯**：分析对象的上层约束是否被覆盖？

```
组件/元器件 → 追问：它装进什么整机？
整机/ECU   → 追问：整机需要通过什么认证/标准？
标准/认证   → 追问：哪些市场/法规要求这个认证？

任何一个答案是"不知道" → 标记为 blind 盲区
```

**硬约束**：盲区检测结果必须包含 ≥1 个 `???` 节点 + ≥1 条虚线边（不确定关系）。

**完成标准**：blindspots 三字段（known_knowns/known_unknowns/layer_trace）全部填写，`???` 计数 ≥ 1。

## Output Format

分析完成后，将以下 JSON 写入 `state.json` 的 `triage` 段：

```json
{
  "triage": {
    "depth": "FAST|STANDARD|FULL|DEPTH",
    "type": "company|person|industry|product|event|decision|tech",
    "target": "目标标识",
    "core_question": "用户真正想知道什么",
    "risk_level": "low|medium|high",
    "lead_role": "kimi|deepseek|claude",
    "audit_role": "deepseek|none",
    "delivery_role": "claude",
    "blindspots": {
      "known_knowns": ["已掌握的事实"],
      "known_unknowns": ["??? 需要但缺失的数据"],
      "layer_trace": {
        "asked_layer": "被问到的层级",
        "upper_layer": "上一层名称 或 unknown",
        "upper_layer_status": "covered|blind"
      }
    },
    "timestamp": "ISO 8601"
  }
}
```

## 失败模式

| 模式 | 症状 | 预防 |
|------|------|------|
| **过早深入** | 用户问"X 是什么"→ 触发 FULL | Step 2 先判 FAST——确认需要再升级，不在不确定时默认 FULL |
| **角色错配** | 技术评估分配给 Kimi 主导 | Step 3 对照表强制执行 |
| **层级盲区** | 分析停在组件层，未查上层约束 | Step 4 layer_trace 强制追溯。任何 `upper_layer_status: blind` → 报告中必须标注 ⚠️ |
| **误触发** | 非分析请求被当作分析请求分流 | 仅在检测到目标对象 AND 核心问题都已解析时才触发 |

## Model-Invoked 安全约束

此技能设为 model-invoked 因为它是所有分析任务的必经入口——漏过它比误触发它的代价更大。但以下防错机制必须生效：

1. **误触发检测**：如果用户输入是纯聊天（无目标对象、无核心问题）→ Step 1 四个要素任一无法解析 → 不输出 triage card → 不回写 state.json → 按纯聊天模式回复
2. **回退机制**：用户说"不需要 triage"/"直接做" → 跳过 triage，直接执行用户指定动作
3. **监控指标**：每 10 次 triage 触发后，检查是否有 ≥2 次是误触发。如果是 → 降级为 user-invoked（disable-model-invocation: true）

## 上下文指针

执行前加载：
- `D:\TRIO 3.0\CORE.md` — 三根柱子 + 流水线深度判定规则
- `D:\TRIO 3.0\skills\GLOSSARY.md` — 领域词汇（了解 TRIO 概念体系）
- `D:\TRIO 3.0\config\guard.json` — 深度升级条件（如存在）
