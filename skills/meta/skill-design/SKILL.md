---
name: skill-design
description: TRIO 技能设计元框架——怎么写一个可预测的、可维护的、不会腐烂的技能。新建或修改任何技能前必须先读此文件。
category: meta
disable-model-invocation: true
---

# 技能设计元框架

技能的存在意义：从随机系统中提取**可预测性**。根德性 = Predictability——agent 每次跑同样的**过程**，不是产出同样的输出。TRIO 的分析任务输出必然不同（不同公司/不同人物），但分析**过程**必须可预测。

**粗体**术语定义在 `skills/GLOSSARY.md`。

> 来源：Matt Pocock 的 writing-great-skills + GLOSSARY.md，针对 TRIO 分析场景适配。
> Matt 原版见 skills-main.zip → `skills/productivity/writing-great-skills/`

---

## 调用轴

两个选择，花不同的货币：

| 类型 | 触发者 | 前端标记 | 成本 | 何时用 |
|------|--------|---------|------|--------|
| **User-Invoked** | 仅人手动输入 | `disable-model-invocation: true` | 零 context load，支付 **cognitive load** | 需要人的判断才能决定是否触发的技能 |
| **Model-Invoked** | Agent 自动或人手动 | 保留 `description` | 支付 **context load** | Agent 必须能自主触发的技能，或被其他技能调用的共享能力 |

**TRIO 专属约束**：Model-invoked 技能在 TRIO 中保守使用。因为 TRIO 做分析（不是写代码），agent 自动选择分析框架 = agent 替用户做认知决策。只有以下条件全部满足才能设为 model-invoked：
1. 触发条件是**可客观检测的**（如"输入包含公司名+财务数据"），不是语义判断
2. 有明确的**回退机制**（触发不当 → 用户可一键关闭）
3. 技能本身不包含**不可逆操作**

---

## 信息层级

技能内容按 agent 需要的紧迫度排列：

```
Steps（inline，最高优先级）
  ↓
Reference（同文件，次级——按需查阅）
  ↓
Disclosed Reference（linked file，按需加载——只有某些 branch 到达）
  ↓
External Reference（技能系统外——如 CORE.md、quality-reference.md）
```

**TRIO 适配**：分析技能的 steps 天然比工程技能长（需要跨域推理）。不追求 66 行——追求每个 step 有清晰的完成标准。

### 何时推到 pointer 后面

**渐进披露**的决策：inline 每个 branch 都需要的 → pointer 后面放只有某些 branch 才需要的。测试：这个材料是每条分析路径都要读的吗？是 → inline。只有尽调才需要？→ pointer。

---

## 完成标准

每个 step 必须以一个 agent 自己能检查的完成条件结束。

**两个属性**：
- **清晰**：agent 能分辨 done vs not-done。❌ "分析完成" ✅ "已列出 ≥3 个可验证的财务反常信号，每个信号附来源 URL"
- **穷尽**：不是"产出一份变更清单"——是"每个修改过的模块都已确认"

**TRIO 当前最痛的点**：现有 commands/ 的 step 描述是模糊的（"分析 X""生成 Y""评估 Z"）。agent 什么时候算"分析完了"？不知道。于是 agent 就往下一步跳——这就是**过早完成**。

---

## 主导词

利用模型预训练中已有的紧凑概念来锚定行为。一个好主导词同时服务：body 里的执行锚定 + description 里的调用锚定。

**TRIO 主导词候选**：
- **认知隔离**（cognitive isolation）——锚定"三面具并行、互不可见"的整套行为
- **结构化怀疑**（structured skepticism）——锚定"每条声明附可证伪条件"
- **少数派保护**（minority protection）——锚定"不消灭分歧、封存标注"
- **致命缺口**（fatal gap）——锚定 Gate 0 扫描的整套逻辑
- **层级追溯**（layer trace）——锚定"组件→整机→认证→市场准入"

---

## 失败模式

用这六个词诊断技能问题：

| 模式 | 症状 | 防御 |
|------|------|------|
| **过早完成** | Step 没做完就跳下一步 | 先磨利完成标准；只有完成标准不可约地模糊 AND 实际观察到 rush → 再隐藏后续步骤 |
| **沉积** | 旧规则层层堆积、从不清理 | 季度修剪 + 每条规则标注"最近触发日期" |
| **臃肿** | 纯长度过长，即使每行都活着 | 信息层级：推 reference 到 pointer，按 branch 拆分 |
| **重复** | 同一含义多处出现 | 单一真相源——每条规则只在一处定义 |
| **空操作** | 告诉 agent 它本来就会做的事 | 空操作测试：删掉这句话 → agent 行为会变吗？不会 → 删除 |
| **否定** | "不要 X"——却激活了 X | 提示正向目标行为，让被禁的那个从未被说出 |

---

## 修剪纪律

1. **单一真相源**：每条规则只在一处定义。改行为 = 一处编辑。
2. **相关性检查**：每一行——它还和这个技能做的事有关吗？
3. **空操作测试**：每一句——删掉它，agent 行为会变吗？不会 → 删。
4. **季度修剪**：每季度一次——统计每个技能/规则的最近触发日期。30 天未触发 → 候选沉积 → 删除或归档。

---

## TRIO 技能模板

```markdown
---
name: <kebab-case-name>
description: <一句话——如果是 model-invoked，加上触发条件>
category: <intake|analysis|delivery|training|meta>
disable-model-invocation: <true|省略>
---

# <中文技能名>

<一句话说明这个技能做什么>

## Steps

### Step 1: <步骤名>
<具体动作描述>

**完成标准**：<agent 能自己检查的条件>

### Step 2: <步骤名>
...

## Reference（如需要）

### <参考主题>
<按需查阅的规则/定义>

## 失败模式

| 模式 | 预防 |
|------|------|
| <可能出现的失败> | <预防机制> |

## 上下文指针

执行前加载：
- `path/to/related-file.md` — <为什么需要它>
```
