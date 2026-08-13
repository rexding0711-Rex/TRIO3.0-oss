# TRIO 3.0 · 30 分钟入门


## 前提条件（硬性）
- Claude Code CLI 已安装并可用（需 Anthropic 账户）
- WSL2 环境（Windows）或 macOS/Linux
- Neo4j 已安装（可选——无 KG 时系统仍可运行，仅 KG 查询功能降级）
- .env 文件已配置（复制 .env.example 并填入真实值）
## 一句话
TRIO 是一个单人 AI 参谋系统，用于投研/尽调/竞品分析。核心：三面具结构化多视角 + 引擎/配置分离 + 拓扑检查门禁 + Run 自进化。

## 5 分钟: 环境
```bash
cd /mnt/d/TRIO\ 3.0
ls .env  # 必须存在——含 Neo4j 密码和 API key
python3 -c "from scripts.env_loader import get_neo4j_auth; print(get_neo4j_auth())"  # 验证连接
```

## 10 分钟: 第一个 run
在 Claude Code 中输入 `/all 分析比亚迪的竞争格局`——系统自动执行 Step 0→5 流水线。产出在 `runs/` 下。

## 20 分钟: 理解架构
- 协议调用图: `docs/protocol-call-graph.md`
- 引擎: `config/protocols/*-engine.json`
- 状态: `state/run-history.jsonl`

## 30 分钟: 创建新引擎
`bash scripts/create-engine.sh <引擎名> <步骤1,步骤2>`→编辑领域配置→10分钟投产

## FAQ
- Neo4j 连不上？检查 `.env` 中 NEO4J_PASSWORD
- DeepSeek API 报错？检查 `.env` 中 DEEPSEEK_API_KEY
- 路径问题？所有脚本通过 `$SCRIPT_DIR/../` 计算 TRIO_ROOT
