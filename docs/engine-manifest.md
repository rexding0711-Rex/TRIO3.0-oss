# TRIO 引擎能力清单（Engine Manifest · 2026-08-11）

> **用途**：TRIO 引擎能力的统一映射——任何 AI/AI 面具/数码宝贝查此表定位引擎能力。
> **配合**：`docs/asset-index.md`（定位资产）· `scripts/trio-record.sh`（自动落库）· `scripts/asset-locate.sh`（定位资产）
> **状态标注**：✅活跃 / 🟡存在未接 / ❌孤立（DeepSeek 2026-08-11 审计）

---

## 引擎能力总表

| # | 能力 | 脚本 | 调用状态 | 说明 |
|---|------|------|:--:|------|
| E1 | 循环控制器 | `loop-engine.sh` | 🟡 仅 topology-fix | 验证器/断点/停止条件完整，未做通用调度 |
| E2 | 会话记忆 | `session_memory.py` | 🟡 降级进程内 | ADR-010 后进程内 list，接口保留 |
| E3 | 知识刷新 | `kb-refresh.sh` | 🟡 定时 | cron 周一跑，非事件驱动 |
| E4 | Prompt 自优化 | `prompt-self-optimize.sh` | ❌ 孤立 | 读 evo-N.json，从未 apply |
| E5 | 决策账本 | `decision_ledger.py` | 🟡 半接 | decision-log 写入，验证字段缺失 |
| E6 | 评分报告 | `score_report.py` | 🟡 半接 | run-history 评分，未进日常流程 |
| E7 | 引擎缺口检测 | `engine-gap-detector.py` | ❌ 孤立 | 5.0 组合器原型，无人调用 |
| E8 | 指标同步 | `sync_metrics.py` | 🟡 半接 | 指标采集，未联动 |
| E9 | 拓扑检查 | `topology-check.py` | ✅ 活跃 | 交付门禁，每报告触发 |
| E10 | **自动落库** | `trio-record.sh` | ✅ **新增活跃** | 正式分析后强制写 run-history + decision-log |
| E11 | **资产定位** | `asset-locate.sh` | ✅ **新增活跃** | 输入关键词→资产路径 |

---

## 引擎调用链（目标状态）

```
用户请求
   │
   ▼
/all（唯一入口）
   │
   ├─ 正式分析 → trio-record.sh（E10 自动落库）→ asset-locate.sh（E11 定位资产）
   │            → 引擎查 engine-manifest 选 E1-E9
   │            → 交付前 topology-check（E9）
   │
   └─ 简单任务 → 直接答
```

## 引擎健康度（基于审计）

| 状态 | 引擎 | 修复动作 |
|------|------|---------|
| ❌ 孤立 | E4 prompt-self-optimize · E7 engine-gap-detector | 接入主流程：run 后自动触发 |
| 🟡 半接 | E5 决策账本（缺验证字段）· E6 评分（未日常化）· E8 指标 | 阶段二补 verified 字段 + 联动 |
| 🟡 未通用 | E1 loop-engine（仅 topology）· E2 记忆（降级）· E3 知识（定时） | 阶段一统一调度 + 事件驱动 |

---

## 4.0 阶段一待办（从 engine-manifest 派生）

- [ ] E4/E7 接入：run 完成后自动触发 prompt-self-optimize + engine-gap 分析
- [ ] E3 事件驱动：kb-refresh 从定时改为 run 完成触发
- [ ] E5 补验证字段：decision-log 加 verified/falsified/pending
- [ ] 建 `trio-engine.sh`：统一调度入口（调 E1-E11 按需）
- [ ] 数码宝贝读 engine-manifest：了解哪些引擎在运转
