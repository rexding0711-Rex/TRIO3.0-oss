# TRIO 3.0

> version: 3.0.0 | 创建: 2026-06-23 | 技术路线: Claude Code 原生编排
>
> 三重奏自动化分析引擎——认知隔离 / 结构化怀疑 / 自验证闭环三根柱子之上，三面具（Claude 交付 / Kimi 洞察 / DeepSeek 审计）协同的决策操作系统。本仓库为**引擎层**（配置 + 脚本 + 协议 + 门禁）。

## ⚠️ 可移植性声明

本仓库是**单机个人系统快照**，不可直接 clone 即用：

- 斜杠命令真身（`/all`、`/claude` 等）存在于作者本地 Claude Code 环境（`.claude/commands/`），**不在本仓库**
- 敏感数据（决策账本、对标库、爬虫）按安全净化**明确排除**，见 `.gitignore`
- 硬编码路径为 Windows/WSL 本地布局，外部部署需按 `config/paths.conf` 约定迁移

## 快速开始（作者本机）

```
/all <任务描述>     # 唯一分析入口（三面具协同，自动落库）
/TRIO              # 系统启动入口（环境检测 + 状态概览）
/claude            # 工程/架构面具
/kimi              # 内容/洞察面具
/deepseek          # 审计/批判面具
```

## 目录

| 目录 | 用途 |
|------|------|
| `core/` | 核心逻辑（如知识抽取验证器 `validator.py`） |
| `config/` | 11 角色定义、10 场景 SOP、协议（`config/protocols/`）、路径约定（`paths.conf`） |
| `scripts/` | 引擎脚本（门禁 / 账本 / 校准 / 学习草稿 / 目录生成） |
| `skills/` | 技能定义（分析 / 交付 / 摄入 / 元 / 训练） |
| `architecture/` | ADR 决策记录（10 份） |
| `design/` | 设计系统与文档模板 |
| `prompts/` | 提示词模板 |
| `docs/` | 内部文档、吸收报告、state 目录 |

## 架构

- **认知隔离**：三面具并行，互不可见输出；当前为单模型多 prompt（弱隔离），多模型路线见 `config/multi-model-roadmap.md`
- **结构化怀疑**：ABSTAIN 三层门、证据阶梯、可证伪预测、反证必附
- **自验证闭环**：预测注册 → 校准报告 → 经验回灌

核心规范：`CORE.md`（三根柱子 + 硬软宪法 + 上下文预算纪律）· `config/TRIO-CONSTITUTION.md`（宪法）

## 质量门禁

- 统一交付门禁：`bash scripts/delivery-gate.sh <报告.md> [领域]`
- 宪法硬门禁：`python3 scripts/constitution-gate.py --check`（高置信必附反证）
- state schema 目录：`python3 scripts/state-catalog.py --check`
- 全系统验证：`bash scripts/full-system-verify.sh`

## License

[MIT](LICENSE)
