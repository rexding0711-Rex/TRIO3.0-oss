# TRIO 模型路由表（magi 吸收 P0-2）

> 用途: 多模型接入时的角色→模型映射 + 按任务类型路由打分
> 来源: magi `classifyTask + scoreCandidate + pickSubAgentAlias`（硬编码规则，非模型判断）
> 状态: 设计基线——当前单模型(DeepSeek)运行时部分生效，多模型接入后全量生效

---

## 一、角色 → 模型 alias 映射（对齐 magi pickSubAgentAlias）

| TRIO 角色 | alias | 建议模型 | 理由 |
|-----------|-------|---------|------|
| Kimi（探索/发散/反例） | `fast` | 便宜高速模型（haiku 级） | 发散/检索量大，低成本优先 |
| DeepSeek（审计/批判） | `audit` | **独立 API 模型** | 真隔离审计，必须独立权重 |
| Claude（工程/交付） | `main` | 主力模型（sonnet 级） | 综合工程交付 |
| 深度模式 L4 机密层 | `deep` | 最强模型（opus 级） | 高难度综合判定 |
| 快速判断/速判 | `fast` | 便宜高速 | 轻量任务省钱 |
| Plan 模式 | `deep` | 最强模型 | 计划质量决定执行质量 |

**硬约束**：DeepSeek 审计角色必须映射到独立 API（真隔离），禁止与 Kimi/Claude 共享模型权重——否则认知隔离退化为伪多元。

---

## 二、任务分类（classifyTask 适配 TRIO）

按 prompt 特征分类（关键词正则 + 上下文阈值，确定性规则）：

| 任务类型 | 触发特征 | 路由 alias |
|---------|---------|-----------|
| `deep_dive` | 全量/深度/彻底/5层 | `deep` |
| `audit` | 审计/验证/质疑/复核 | `audit`（独立） |
| `quick` | 短问题(<280字符)/速判 | `fast` |
| `planning` | 方案/计划/想清楚再动 | `deep` |
| `content` | 报告/文档/白皮书 | `main` |
| `research` | 搜索/调研/扫描 | `fast` |
| `reasoning` | 因果/判断/为什么 | `main` |
| `long_context` | 上下文>阈值 或 长输入 | `deep` |
| `tool_heavy` | 多工具/脚本/爬取 | `main` |

---

## 三、打分表（scoreCandidate——按任务给模型加分）

| 模型族 | deep_dive | audit | quick | planning | content | research | reasoning |
|--------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| opus 级（最强） | **+30** | +28 | +8 | **+30** | +22 | +12 | +26 |
| sonnet 级（主力） | +24 | +22 | +20 | +24 | **+28** | +18 | **+28** |
| haiku 级（便宜） | +10 | +10 | **+30** | +12 | +18 | **+26** | +16 |
| deepseek 独立 | +20 | **+30** | +16 | +20 | +20 | +20 | +24 |

**规则**：
- 上下文窗口 ≥ 1M 恒 +24（长上下文任务）
- 经济性在打分里体现：quick/research 偏好便宜模型
- 最高分 alias 胜出；平局 → main

---

## 四、fallback 链（对齐 magi resolveFallbackChain）

```
main:   [primary, fallback1, fallback2]  # 例: [deepseek-v4, claude-sonnet, gpt-4o]
fast:   [haiku, deepseek-quick]
deep:   [opus, deepseek-v4]
audit:  [独立模型]  # 无 fallback（保隔离）
```

**失败策略**（对齐 magi）：
- **死端点快速失败**：DNS/拒连/无效 URL → 立即切换，不重试（见 `lib/fail-fast.sh`）
- 其他错误：指数退避重试（网络 10s 封顶/慢速 30s）→ 榨干后切 fallback
- retryable 类型：timeout / rate-limit / server-error / model-unavailable / network

---

## 五、接入点

- `/all` 路由判定时：若配置多模型，按任务分类选 alias
- 子代理（Explore/Plan/Audit）：固定 alias 映射（表一）
- 审计角色：强制独立 API，禁止 fallback 到共享权重模型

> 落地状态: 规则基线已定。当前单模型运行时，DeepSeek 审计保持独立 API（已有）；多模型接入时按本表配置。
