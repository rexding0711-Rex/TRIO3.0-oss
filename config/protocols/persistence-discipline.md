# 持久化纪律（TRIO 版）

> **吸收自 dsh（DeepSeek Harness）session-persistence** 2026-08-14。
> 定位：`state/*.jsonl` 的写入/读取/演进规范。治疗两个真实事故：schema 漂移静默错误重建、文件落库偏差。
> 配套工具：`scripts/state-catalog.py`（生成式目录 + --check 验证）。

## 一、先跑目录，再改数据

- 任何 `state/*.jsonl` 写入逻辑变更后 → 运行 `python3 scripts/state-catalog.py` 重新生成目录。
- CI/启动钩子 → `python3 scripts/state-catalog.py --check`，过期即红灯。
- 目录是**生成文件勿手编**；它从实际行扫描，是"落库偏差"的机械检测器。

## 二、写纪律（原子性）

| 操作 | 正确姿势 | 禁止 |
|------|---------|------|
| 追加 | `open('a') → write → flush → fsync` | 原地改写整个文件 |
| 整体替换 | 写 temp 文件 → `os.replace()`（POSIX 原子） | `rename` 静默覆盖、先删后写 |
| 备份 | 交给原子写纪律，废弃手工 `.bak` | 手动 copy 留档 |

规则：**文件要么是旧版要么是新版，中间态不落盘。**

## 三、格式纪律

- **后缀名 = 实际格式**：`.jsonl` 必须是 JSON 每行一个对象。管道/CSV/TSV 数据不得用 `.jsonl` 后缀（`memory-weights.jsonl` 即违规实例，已被 state-catalog 标注）。
- **每文件首行可放 header**（版本/创建时间），版本放 header 不放数据行。
- **错误必须响亮**：读取时遇到无法解析的行 → 报错并指明文件/行号，绝不静默跳过（静默跳 = 错误重建）。

## 四、未来演进：envelope 化（有真实迁移需求时再做）

当前 state 为裸行。若未来出现格式演进需求，按 dsh 契约升级：

```json
{ "type": "decision/made", "seq": 181, "time": 1755123456789, "data": { "...": "..." } }
```

- **seq** 每文件单调连续——读取时校验，缺口 = 中断写入信号
- **版本**：单一整型（不 split major/minor），writer 决定 bump，bump 判据 = "旧 reader 能否语义正确读"
- **ignorable 标记默认 required**：未知类型无 `ignorable:true` → 响亮拒绝，不静默跳过
- **torn tail**：读时发现末行不完整 → 截断到最后一个完整行并报修复日志

> 当前不强制 envelope 化（TRIO 是裸 JSONL 兼容已有读取器）；此规范为未来迁移预留边界。

## 五、坏行处理

- 写：永不产生半行（追加前构造完整行 + `\n`）
- 读：state-catalog 每文件统计坏行；坏行 > 0 → 目录中标注 ⚠️，须人工核查
