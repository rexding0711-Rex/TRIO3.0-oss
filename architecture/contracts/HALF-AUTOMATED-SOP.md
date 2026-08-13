# 半自动化 SOP ——「半」到底切在哪

> 外部审查反复追问：「半自动」的「半」在哪？这份 SOP 定义切割线。

## 切割原则

**机器负责「提取+校验」——人负责「裁决」。**
机器不替人做判断。人不替机器做搬运。

## 报告→图谱回写的切割线

```
Step 1 [自动]: manifest.py 提取实体/候选事实 → 生成 manifest.yaml
Step 2 [自动]: manifest-validate.py 校验（ID格式·必填字段·零实体告警）
Step 3 [自动]: 生成 Cypher MERGE 语句 → 写入 staging/ 目录
Step 4 [人工]: Rex 审核 staging/ 中的候选关系 → y/n/q
Step 5 [自动]: 确认的 MERGE 执行 → Neo4j 更新
Step 6 [自动]: 更新 entity-id-registry（如有新实体）
```

**切割点在 Step 4**：机器做完了所有准备，Rex 只做 yes/no 裁决。
裁决应该在 **24 小时内**完成。超过 48 小时 → deliver.sh 下次运行时报警。

## 对标库更新的切割线

```
Step 1 [自动]: manifest.py 标记「此报告涉及对标库实体 X」
Step 2 [自动]: 检查对标库 freshness——>90 天未更新 → 标记 STALE
Step 3 [人工]: Rex 决定是否用新报告内容更新对标库档案
Step 4 [自动]: 更新 freshness-index 中的 last_verified_date
```

## 失败模式

| 失败 | 机器行为 | 人行为 |
|------|---------|--------|
| manifest 提取零实体 | WARN·不阻塞交付 | 人工检查报告是否真的无实体 |
| ID 格式违规 | 阻断（strict mode） | 修复 manifest 或更新 ID schema |
| staging 积压 >10 条 | 终端警告 | 优先处理 backlog |
| Neo4j 不可用 | WARN·跳过回写 | 恢复后手动重跑 |
