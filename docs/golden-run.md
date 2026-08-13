# Golden Run 参照

> 系统质量基线——参考一次完整成功的 run（2026-08-12 生成）

## 参照 run: run-780af7

- **日期**: 2026-08-11
- **任务**: 吸收4case外部洞察: 10条TRIO没想到的进系统
- **综合评分**: 10.0/10
- **复盘**: 吸收: ①Constitution加6条认知偏差防护(建造者谬误/UNKNOWN≠NEGATIVE/便宜=负信号/可证伪谎言一票否决/不证明有罪也能拒绝/最便宜验证优先) ②/all判断包加M1最便宜验证优先 ③33条洞察存external-insights

## 达标标准（Golden Run 应满足）

1. 全步骤按序完成，状态持久化（runner.sh 状态机）
2. 交付门禁通过（delivery-gate.sh：拓扑 + CJK + 痕迹扫描）
3. 核心判断注册 decision-log（含反证 + 可证伪条件）
4. 可复用经验生成 learning-draft
5. 交付物落库 `D:\工作\项目\`

## 使用

跑 `bash scripts/full-system-verify.sh` 后，对照本参照确认系统健康。
