#!/bin/bash
# ============================================================
# TRIO-Investor 环境安装脚本 v1.0
# 用途：一键配置一级市场投资人的本地 AI 基础设施
# 用法：bash investor-setup.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; WARN=0; FAIL=0

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   TRIO-Investor 环境安装                      ║${NC}"
echo -e "${BOLD}║   一级市场投资人专用 AI 基础设施              ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ═══ 1. 基础依赖检测 ═══
echo -e "${BOLD}[1/7] 基础依赖检测${NC}"

check_cmd() {
    local name="$1"; local cmd="$2"; local fix="$3"
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✅${NC} $name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}❌${NC} $name 未安装"
        echo -e "     ${CYAN}→ $fix${NC}"
        FAIL=$((FAIL + 1))
    fi
}

check_cmd "Node.js ≥18" node "sudo apt install nodejs 或 brew install node"
check_cmd "Python 3.10+" python3 "sudo apt install python3"
check_cmd "Git" git "sudo apt install git"
check_cmd "Claude Code" claude "npm install -g @anthropic-ai/claude-code"
check_cmd "uv (Python 包管理)" uv "pip install uv 或 curl -LsSf https://astral.sh/uv/install.sh | sh"

# ═══ 2. Neo4j 图数据库 ═══
echo ""
echo -e "${BOLD}[2/7] Neo4j 图数据库${NC}"

NEO4J_READY=true
if command -v cypher-shell &>/dev/null; then
    echo -e "  ${GREEN}✅${NC} cypher-shell 已安装"
else
    echo -e "  ${YELLOW}⚠️${NC}  cypher-shell 未安装"
    echo -e "     ${CYAN}→ 安装 Neo4j Desktop: https://neo4j.com/download/${NC}"
    echo -e "     ${CYAN}→ 或 Docker: docker run -d --name neo4j -p 7474:7474 -p 7687:7687 \\${NC}"
    echo -e "     ${CYAN}   -e NEO4J_AUTH=neo4j/你的密码 neo4j:latest${NC}"
    NEO4J_READY=false
fi

# 检测 Neo4j 连接
if [ "$NEO4J_READY" = true ]; then
    if cypher-shell -u neo4j -p "${NEO4J_PASSWORD:-neo4j}" "RETURN 1;" &>/dev/null 2>&1; then
        echo -e "  ${GREEN}✅${NC} Neo4j 连接正常 (bolt://localhost:7687)"
    else
        echo -e "  ${YELLOW}⚠️${NC}  Neo4j 连接失败——请确认服务已启动且密码正确"
        echo -e "     ${CYAN}→ 设置环境变量: export NEO4J_PASSWORD='你的密码'${NC}"
    fi
fi

# 初始化投资图谱 Schema
if [ "$NEO4J_READY" = true ] && [ -f "config/schemas/investor-neo4j-schema.cypher" ]; then
    echo -e "  ${CYAN}→ Schema 文件就绪: config/schemas/investor-neo4j-schema.cypher${NC}"
    echo -e "  ${CYAN}→ 运行以下命令初始化图谱:${NC}"
    echo -e "  ${CYAN}   cypher-shell -u neo4j -p \$NEO4J_PASSWORD -f config/schemas/investor-neo4j-schema.cypher${NC}"
fi

# ═══ 3. PostgreSQL ═══
echo ""
echo -e "${BOLD}[3/7] PostgreSQL（结构化数据）${NC}"

if command -v psql &>/dev/null; then
    echo -e "  ${GREEN}✅${NC} psql 已安装"
    if psql -U rex -d claude_mcp -c "SELECT 1;" &>/dev/null 2>&1; then
        echo -e "  ${GREEN}✅${NC} PostgreSQL 连接正常"
    else
        echo -e "  ${YELLOW}⚠️${NC}  PostgreSQL 连接失败——确认数据库已创建"
        echo -e "     ${CYAN}→ createdb claude_mcp${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️${NC}  psql 未安装"
    echo -e "     ${CYAN}→ sudo apt install postgresql postgresql-client${NC}"
fi

# ═══ 4. API Key 检测 ═══
echo ""
echo -e "${BOLD}[4/7] API Key 检测${NC}"

check_api_key() {
    local name="$1"; local var="$2"; local url="$3"
    if [ -n "${!var:-}" ]; then
        echo -e "  ${GREEN}✅${NC} $name 已设置"
    else
        echo -e "  ${YELLOW}⚠️${NC}  $name 未设置"
        echo -e "     ${CYAN}→ 获取: $url${NC}"
        echo -e "     ${CYAN}→ 设置: export $var='你的key'  # 建议写入 ~/.bashrc${NC}"
        WARN=$((WARN + 1))
    fi
}

check_api_key "DeepSeek API"    DEEPSEEK_API_KEY    "https://platform.deepseek.com/api_keys"
check_api_key "Anthropic API"   ANTHROPIC_API_KEY   "https://console.anthropic.com/"
check_api_key "Firecrawl API"   FIRECRAWL_API_KEY   "https://firecrawl.dev"
check_api_key "Exa API"         EXA_API_KEY         "https://exa.ai"

# ═══ 5. MCP 配置 ═══
echo ""
echo -e "${BOLD}[5/7] MCP 服务器配置${NC}"

MCP_CONFIG="$HOME/.claude/mcpServers.json"
if [ -f "$MCP_CONFIG" ]; then
    echo -e "  ${GREEN}✅${NC} mcpServers.json 已存在"
    echo -e "  ${CYAN}→ 核心 MCP: neo4j, postgres, filesystem, firecrawl, playwright, exa${NC}"
    echo -e "  ${CYAN}→ 检查 mcpServers.json 是否包含以上服务器...${NC}"

    # 检查关键 MCP 配置
    for mcp in neo4j postgres filesystem; do
        if grep -q "\"$mcp\"" "$MCP_CONFIG" 2>/dev/null; then
            echo -e "    ${GREEN}✅${NC} $mcp"
        else
            echo -e "    ${RED}❌${NC} $mcp — 需要手动添加到 $MCP_CONFIG"
        fi
    done
else
    echo -e "  ${RED}❌${NC} mcpServers.json 不存在——请先配置 Claude Code MCP"
fi

# ═══ 6. TRIO 数据目录 ═══
echo ""
echo -e "${BOLD}[6/7] 数据目录初始化${NC}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INVESTOR_DIR="$SCRIPT_DIR/investor"

mkdir -p "$INVESTOR_DIR"/{reports,memos,data,exports,templates}
echo -e "  ${GREEN}✅${NC} 投资者数据目录已创建:"
echo -e "     ├── investor/reports/    尽调报告"
echo -e "     ├── investor/memos/      投委会备忘录"
echo -e "     ├── investor/data/       原始数据"
echo -e "     ├── investor/exports/    导出文件"
echo -e "     └── investor/templates/  文档模板"

# ═══ 7. 环境变量模板 ═══
echo ""
echo -e "${BOLD}[7/7] 环境变量配置${NC}"

ENV_FILE="$SCRIPT_DIR/config/investor-env.sh"
cat > "$ENV_FILE" << 'EOF'
# TRIO-Investor 环境变量
# 使用方法: source config/investor-env.sh
# 建议追加到 ~/.bashrc: echo "source /path/to/TRIO/config/investor-env.sh" >> ~/.bashrc

# === 必填 ===
export NEO4J_URI="bolt://localhost:7687"
export NEO4J_USER="neo4j"
export NEO4J_PASSWORD="你的密码"          # ← 修改为你的 Neo4j 密码

# API Keys
export DEEPSEEK_API_KEY="sk-..."         # ← DeepSeek API Key
export ANTHROPIC_API_KEY="sk-ant-..."    # ← Anthropic API Key

# === 可选 ===
export FIRECRAWL_API_KEY="fc-..."        # ← Firecrawl API Key
export EXA_API_KEY="..."                 # ← Exa API Key

# === PostgreSQL ===
export DATABASE_URL="postgresql://rex:claude123@localhost:5432/claude_mcp"
EOF

echo -e "  ${GREEN}✅${NC} 环境变量模板已生成: config/investor-env.sh"
echo -e "  ${CYAN}→ 编辑此文件填入你的 API Key:${NC}"
echo -e "  ${CYAN}   vim config/investor-env.sh${NC}"
echo -e "  ${CYAN}→ 然后 source:${NC}"
echo -e "  ${CYAN}   source config/investor-env.sh${NC}"

# ═══ 总结 ═══
echo ""
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo -e "  安装结果: ${GREEN}${PASS} 通过${NC}  ${YELLOW}${WARN} 警告${NC}  ${RED}${FAIL} 缺失${NC}"
echo -e "${BOLD}══════════════════════════════════════════════${NC}"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}❌ 缺少 ${FAIL} 项必要依赖。装好后重新运行。${NC}"
    echo ""
    echo "最小可用环境（必须装齐这三样）："
    echo "  1. Claude Code: npm install -g @anthropic-ai/claude-code"
    echo "  2. Neo4j: Docker 或 Desktop 版"
    echo "  3. DeepSeek API Key: https://platform.deepseek.com/api_keys"
    echo ""
elif [ "$WARN" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  环境基本就绪（${WARN} 个建议）。${NC}"
    echo ""
    echo "快速开始："
    echo "  1. source config/investor-env.sh       # 加载环境变量"
    echo "  2. cypher-shell -f config/schemas/investor-neo4j-schema.cypher  # 初始化图谱"
    echo "  3. cd 到 TRIO 目录 && claude            # 启动 Claude Code"
    echo "  4. 在 Claude Code 中输入: /investor      # 进入投资者模式"
    echo ""
else
    echo -e "${GREEN}🎉 环境完美！${NC}"
    echo ""
    echo "快速开始："
    echo "  source config/investor-env.sh && claude"
    echo "  然后输入: /investor 看管线"
    echo ""
fi
