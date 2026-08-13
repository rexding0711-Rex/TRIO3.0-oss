#!/usr/bin/env bash
# TRIO 3.0 统一部署脚本 v1.0
# 用法: bash trio-setup.sh [--minimal|--standard|--full]
# 来源: 吸收 TRIO-Investor v1.1 部署速度设计
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
MODE="${1:---standard}"

echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "${CYAN}  TRIO 3.0 环境部署 — $(date '+%Y-%m-%d %H:%M')${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo ""

# ── 环境检测 ──────────────────────────────────
echo -e "${YELLOW}[1/4] 环境检测${NC}"

check_cmd() { command -v "$1" &>/dev/null && echo -e "  ${GREEN}✅${NC} $1 ($2)" || echo -e "  ${RED}❌${NC} $1 — $2 未安装"; }

check_cmd "python3" "≥3.10"
check_cmd "node" "≥18"
check_cmd "git" "任意"
check_cmd "bash" "≥4.0"

# Claude Code
if command -v claude &>/dev/null; then
    echo -e "  ${GREEN}✅${NC} claude (Claude Code)"
else
    echo -e "  ${YELLOW}⚠️${NC} claude 未安装 — 运行: curl -fsSL https://claude.ai/install.sh | bash"
fi

echo ""

# ── 数据目录 ──────────────────────────────────
echo -e "${YELLOW}[2/4] 数据目录${NC}"

TRIO_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "  TRIO 根目录: ${TRIO_DIR}"

mkdir -p "${TRIO_DIR}/out" "${TRIO_DIR}/runs" "${TRIO_DIR}/state/archive"
echo -e "  ${GREEN}✅${NC} 输出目录已就绪"

echo ""

# ── MCP 配置检查 ──────────────────────────────
echo -e "${YELLOW}[3/4] MCP 配置${NC}"

if [ -f "${TRIO_DIR}/.mcp.json" ]; then
    echo -e "  ${GREEN}✅${NC} .mcp.json 已存在"
else
    echo -e "  ${YELLOW}⚠️${NC} .mcp.json 不存在 — 参考 TRIO-Investor v1.1 §3.2 创建"
fi

if [ -f "${HOME}/.claude/settings.json" ]; then
    echo -e "  ${GREEN}✅${NC} Claude Code 设置已存在"
else
    echo -e "  ${YELLOW}⚠️${NC} Claude Code 设置不存在 — 运行 claude 初始化"
fi

echo ""

# ── 完整模式：数据库（3.0 无 KG——ADR-010，Neo4j 延迟到 4.0）──────────────
if [ "$MODE" = "--full" ]; then
    echo -e "${YELLOW}[4/4] 完整模式：数据库${NC}"
    echo -e "  ${CYAN}注：3.0 无知识图谱（ADR-010），Neo4j 4.0 恢复。以下为 4.0 前瞻检测。${NC}"

    if command -v docker &>/dev/null; then
        if docker ps --format '{{.Names}}' | grep -q "neo4j"; then
            echo -e "  ${GREEN}✅${NC} Neo4j 容器运行中（4.0 前瞻）"
        else
            echo -e "  ${YELLOW}⚠️${NC} Neo4j 容器未运行（4.0 需要时启动）"
            echo "     启动: docker run -d --name neo4j -p 7474:7474 -p 7687:7687 -e NEO4J_AUTH=neo4j/你的密码 neo4j:latest"
        fi
    else
        echo -e "  ${RED}❌${NC} Docker 未安装 — Neo4j 需要 Docker（4.0 才需要）"
    fi

    if command -v psql &>/dev/null; then
        echo -e "  ${GREEN}✅${NC} PostgreSQL 客户端可用"
    else
        echo -e "  ${YELLOW}⚠️${NC} psql 未安装 — sudo apt install postgresql-client"
    fi
else
    echo -e "${CYAN}[4/4] ${MODE} 模式：跳过数据库检测${NC}"
    echo "  需要完整数据库支持？运行: bash trio-setup.sh --full"
fi

echo ""
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  部署完成！${NC}"
echo ""
echo "  下一步："
echo "    1. 确认 API 密钥已配置（.claude/settings.local.json）"
echo "    2. 运行: claude"
echo "    3. 试试: /all 帮我看一下今天的任务"
echo ""
echo "  模式说明："
echo "    --minimal  仅环境检测"
echo "    --standard 环境 + 数据目录 + MCP 检查（默认）"
echo "    --full     环境 + 数据目录 + MCP + Neo4j + PostgreSQL"
echo -e "${CYAN}════════════════════════════════════════${NC}"
