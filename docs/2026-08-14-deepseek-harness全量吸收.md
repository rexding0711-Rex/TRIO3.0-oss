# DeepSeek Harness 全量吸收（2026-08-14）

> 对象：DeepSeek AI 官方 agent harness（`dsh`）—「万物皆插件」架构，基于 Cordis，开发者预览版。
> 位置：`sandbox/deepseek-harness/deepseek-harness-master/`（7404 文件解压）
> 前序：2026-08-13 已做 5 层解剖质量评估（run-history `run-rgxcho`，注册 9004/9005/9006 三条预测）。本次聚焦**吸收落地**，不重复评估。

## 一、吸收对象概况

- **规模**：7404 文件，50 个 `@deepseek-ai/dsh-*` packages，12 个官方工程 skills，Agent Notes 决策笔记库（implemented 1012 / proposed 50 / rejected 22 / archived 285 篇）
- **本质**：DeepSeek 团队自用的 agent harness（代码库），其工程纪律库（AGENTS.md 15KB + 复盘 + 防御性模式）比代码本身对 TRIO 更有吸收价值
- **反证验证**：magi 前例教训「验代码不轻信文档」——已核实 7404 文件真实存在、AGENTS.md 声称的 scripts/ 门禁均存在对应实现，非空壳

## 二、三面具评估

### Kimi（反例搜索）

| 反例 | 判定 |
|------|------|
| "dsh 是代码库，TRIO 是分析引擎，场景不同" | **病灶同源**：都是「作者会话视角 vs 读者成品视角」。dsh-trim-cot-leakage 直接映射 TRIO 门禁 A（7-21 蔚星教训同款病） |
| "Agent Notes 四状态机为多人协作设计" | 部分成立。TRIO 的 reject 状态已有，archived 冻结单人系统不急 |
| "12 个官方 skills 全吸收" | 否。只挑映射最强的 2-3 个（trim-cot-leakage / postmortem / pre-push-checks） |

### DeepSeek（质疑验证）

- 门禁 A 升级必要？→ **验证通过**：delivery-gate.sh 只扫 8 词，漏「变更叙事」类（上一轮/旧版/不再/以前）
- 检测词误杀面？→ `私有`（私有化）/`端`（前端）/`评审` 在商业报告高频误杀 → **剔除**；`不再`/`以前` 中等误杀 → 降为 WARN 级
- 与已有系统重复？→ learning-draft.sh 的 reject 已实现，**不重复建设**

### Claude（工程交付）

P0 三项落地 + P1/P2 观察（见下）。

## 三、落地清单（P0）

| # | 落地项 | 文件 | 状态 | 说明 |
|---|--------|------|------|------|
| 1 | **门禁 A 升级** | `scripts/delivery-gate.sh` + `~/.claude/CLAUDE.md` 门禁 A | ✅ | ① 新增 `warn()` 函数 + 4b 段「变更叙事提示」（上一轮/旧版/本版/不再/以前/老的，WARN 不阻断）；② CLAUDE.md 门禁 A 追加检测词 + **读者视角测试**语义判断（最终防线） |
| 2 | **Post-Mortem 复盘模板** | `config/protocols/postmortem-template.md` | ✅ | 借 dsh 三标准（Subtle+Systemic+Costly）+ 每条必产护栏 + 与 decision-log/学习草稿衔接 |
| 3 | **吸收报告 + 落库** | 本文 + 学习草稿 + run 记录 | ✅ | 见第五节 |

## 四、P1/P2 观察（记入但不落地）

| 优先级 | 项 | 内容 | 落地时机 |
|--------|-----|------|---------|
| P1 | Model-visible ⟺ logged | 任何进入模型请求的内容必须能从日志重建——强化 TRIO 预测注册 | 下次决策账本迭代 |
| P1 | 分层验证纪律 | dsh-pre-push-checks：本地只跑相关检查，CI 拥有穷尽覆盖 | TRIO 有 full-system-verify 27/0/0 后，拆"相关/全量"两层 |
| P1 | Agent Notes 完整状态机 | implemented/archived 冻结 + 归档门禁 | 决策账本多模型期 |
| P2 | defensive-patterns bug 类 | 高并发生命周期/并发模式 | TRIO 非高并发系统，参考价值低 |
| P2 | 其余工程 skills | dsh-code-review / dsh-doc-sync / dsh-find-simplifications | 面向 TS 代码库，暂不适用 |

## 五、落库记录

- **run**：本次 run 追加至 `state/run-history.jsonl`
- **学习草稿**：读者视角测试法 → `learning-draft.sh new`（pending，待审阅）
- **预测**：本次为系统改动，无新可证伪预测（回顾性判断不注册）；前次 9004/9005/9006 维持

## 六、反证教训

1. **reject 状态已有**——评估时险些重复建设。教训：落地前先核实现状，不凭记忆假设系统缺什么
2. **`grep -c` 是行数语义**——"变更叙事 N 处"显示的是命中行数非次数，与原有 TRACE 一致，属既有约定
3. **误杀词剔除清单**（`私有`/`端`/`评审`）——中文商业报告高频正常用词，机械词表必须按域裁剪
