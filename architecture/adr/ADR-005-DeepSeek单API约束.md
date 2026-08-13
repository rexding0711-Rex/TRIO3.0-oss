# ADR-005: DeepSeek 单 API 约束
- 日期: 2026-06-25
- 状态: accepted
- 背景: TRIO设计为三面具(Kimi/DeepSeek/Claude)，但实际运行环境只有DeepSeek API一个端点
- 决策: 三个面具全部走DeepSeek API，通过不同system prompt实现角色分化
- 后果: 三面具在共享上下文中运行——无法实现物理隔离。"弱隔离"降级为流程纪律+审计检测(M1 v2.0)
