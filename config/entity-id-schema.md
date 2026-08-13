# TRIO 统一实体 ID 规范 v1.0

> 所有子系统（TRIO 3.0 / Stock / Investor）必须使用此 ID 格式。
> 同一实体在不同系统中的 ID 必须一致。

## 格式

```
{type}:{region}:{identifier}
```

| 字段 | 说明 | 示例 |
|------|------|------|
| type | 实体类型 | company / person / product / technology / industry |
| region | ISO国家码 | cn / us / jp / kr / de / global |
| identifier | 唯一标识 | 股票代码 / UUID / 标准化名称 |

## 示例

```
company:cn:300750        # 宁德时代（A股代码）
company:cn:比亚迪         # 比亚迪（无股票代码的实体用标准中文名）
company:us:AAPL           # Apple
person:cn:林倞             # 林倞
person:us:Jensen-Huang    # 黄仁勋
product:cn:RoBridge       # 拓元智慧的RoBridge模型
technology:global:HAST    # HAST试验技术
industry:cn:具身智能       # 具身智能赛道
```

## 规则

1. **已有股票代码的 A 股公司**：用 6 位代码（如 300750）
2. **无股票代码的中国公司**：用标准中文全称（不含"有限公司"后缀）
3. **外国公司**：用英文 ticker（如 AAPL）或无 ticker 时用标准英文名
4. **人物**：用标准中文名或英文名（姓-名格式）
5. **产品/技术**：用标准中文名或英文名

## 使用场景

| 场景 | 示例 |
|------|------|
| Neo4j 节点 | `MATCH (c:Company {id: 'company:cn:300750'})` |
| 对标库目录 | `对标库/company-benchmark/300750-宁德时代/` |
| 报告 manifest | `entities: ['company:cn:300750', 'person:cn:林倞']` |
| 决策日志 | `subject_id: 'company:cn:300750'` |

## 维护

- 新增实体时，先查此表确认 ID 不存在
- ID 冲突时，由 TRIO 3.0 引擎裁决
- 此文件为 SSOT（单一事实来源）——所有子系统引用此文件
