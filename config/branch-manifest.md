# TRIO 分支能力索引 · Branch Manifest

> 用途: 主系统 `/all` 按领域路由——检测到对应关键词时,加载分支方法论片段进上下文
> 更新: 2026-08-11 建立 | 数据源: `D:\Agent文件\TRIO-*` + `D:\工作\对标库`
> 原则: **平时不常驻,按需加载**(审计共识: 分支按需唤醒,勿全量注入)

---

## 路由规则

`/all` 收到分析任务 → 检测问题领域关键词 → 命中下表 → 加载对应分支的核心方法论入口文件。

**优先级(2026-08-11 实测修正)**: 关键词分**专属词**(强命中,直接加载)与**通用词**(弱命中,慎加载)。专属词优先——避免"材料/估值/物理"等跨领域词污染上下文。命中规则:
- 命中任一专属词 → 🔴 强命中 → 加载该分支
- 仅命中通用词 → 🟡 弱命中 → 仅在无强命中冲突时加载

| 领域 | 分支 | 专属词(强) | 通用词(弱) | 核心入口 |
|------|------|-----------|---------|
| 工程/物理计算 | TRIO-Engineer | F22·量纲·数量级·红外物理·物理合理性·热力学计算·TPMS·Gyroid·散热冷板·微通道·功能梯度·晶格·增材·3D打印 | 材料·电子·机械·化工计算 | `D:\Agent文件\TRIO-Engineer\CORE.md`(E-Gate 1-4) + `methods\TPMS隐式几何与增材制造-方法论` |
| 二级市场/股票 | TRIO-Stock | 股票·市盈率·财报·行情·行业轮动·二级市场·股息率 | 估值·公司 | `D:\Agent文件\TRIO-Stock\config\STOCK-ANALYSIS-STANDARD.json` + `IRON-LAW-STOCK` |
| 一级市场/投资尽调 | TRIO-Investor | 融资·尽调·对赌·BP·投资人·A轮·B轮·C轮·投后 | 估值·竞对·商业模式 | `D:\Agent文件\TRIO-Investor\IRON-LAW.md`(铁律 v1.2) + `delivery-gate.sh` |
| 化学/材料 | TRIO-Chemistry | 高分子·聚合物·陶瓷·溶剂·吸附·薄膜·纤维·复合材料 | 材料·化学 | `D:\Agent文件\TRIO-Chemistry\README.md` |
| 物理 | TRIO-Physics | 电磁·光学·流体力学·固体力学·MEMS·光谱 | 物理 | `D:\Agent文件\TRIO-Physics\README.md` |
| 数学/建模 | TRIO-Mathematics | PDE·TPMS·薄膜光学·金融数学·ML数学 | 建模·计算 | `D:\Agent文件\TRIO-Mathematics\README.md` |
| 商业/供应链 | TRIO-Commercial | 供应链·GTM·市场准入·需求分析·定价策略·竞品情报 | 成本·定价·渠道 | `D:\Agent文件\TRIO-Commercial\README.md` |
| 音乐/乐理 | TRIO-Musician | 乐理·和声·节奏·视唱·复调·曲式 | 音乐·音程 | `D:\Agent文件\TRIO-Musician\README.md` |
| 决策仲裁 | BettaFish | 多代理冲突·仲裁·裁决·ForumEngine·InsightEngine | 冲突·共识 | `D:\Agent文件\BettaFish\README.md` |
| 证据契约 | scientific-agent-skills | 证据等级·反证·可复现性·实验设计 | 证据·验证 | `D:\Agent文件\scientific-agent-skills\README.md` |
| 公司对标 | company-benchmark | 公司分析·行业玩家·竞对画像 | 对标·竞品 | `D:\工作\对标库\company-benchmark\INDEX.md`(182公司) |
| 人物对标 | person-benchmark | 决策模式·历史人物·创始人画像 | 人物·CEO | `D:\工作\对标库\person-benchmark\INDEX.md`(1879人物) |
| 技术对标 | tech-benchmark | 技术路线·colah·karpathy·研究者 | 技术·前沿 | `D:\工作\对标库\tech-benchmark\INDEX.md` |
| 城市治理/政府项目 | TRIO-CityHorizon | 排水·内涝·城市治理·CityHorizon·AI城市管理·白海豚·水务·政府项目 | 环保·交通治理·公共安全·产业政策 | `D:\Agent文件\TRIO-CityHorizon\CORE.md`(治理铁律) + `domains\drainage\README.md` |

---

## 加载方式(接线规则)

1. **检测**: `/all` Step 2 搜索前,扫描问题文本命中上表关键词
2. **加载**: 命中 → 读取该分支入口文件头部(前 50 行方法论摘要),注入上下文
3. **门禁**: 命中 TRIO-Engineer(工程计算)→ 强制跑 E-Gate 1-4(量纲/数量级/材料/安全)
4. **Investor 特殊**: 命中排名/评分/对比分析 → 交付前必须跑 `delivery-gate.sh`
5. **不加载**: 未命中任何分支 → 纯通用分析,不注入(避免上下文膨胀)

## 待办(loop 阶段)

- [ ] 各分支 manifest.json(结构化触发条件,当前为 md 索引表)
- [ ] kb-refresh cron 落地(TRIO 主系统,llms.txt 声称有但实际无)
- [ ] 对标库向量/FTS 索引(1880 人物毫秒检索)
