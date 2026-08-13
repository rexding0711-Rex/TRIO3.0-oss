# TRIO 3.0 协议调用图

## 全局流程

```mermaid
graph TD
    A[SessionStart] --> B[CLAUDE.md L0自检]
    B --> C[用户输入 /all]
    C --> D[Step 0: 致命缺口扫描]
    D --> E[Step 1: 路由判定·FAST/FULL]
    E -->|FAST| F[Step 4: 综合判断]
    E -->|FULL| G[Step 2: 实时搜索]
    G --> H[Step 3: 三面具并行]
    H --> I[Step 3.5: 矛盾暴露+拓扑推演]
    I --> F
    F --> J[Step 5: 终审自疑]
    J --> K[Step 6: 外部审查·可选]
    K --> L[Run 记录+评分]
```

## 协议触发条件

| 协议 | 触发条件 | 触发者 |
|------|---------|--------|
| context-isolation | /all Step 3 | all.md |
| self-verify | 每步完成后 | 自动 |
| topology-thinking | Step 5前 | all.md |
| audit-strictness | 评分时 | run-eval |
| external-review | 声明等级=理论时 | 手动/自动 |
| run-eval | 每次交付后 | Claude |
| talent/competitive-engine | P0信号密度预检通过 | 引擎自动激活规则 |
