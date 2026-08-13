# TRIO-Investor MCP 配置补充

以下配置需要添加到 `~/.claude/mcpServers.json` 的 `mcpServers` 对象中。

## 1. Neo4j 图数据库（核心——项目图谱）

```json
"neo4j": {
  "command": "npx",
  "args": ["-y", "neo4j-mcp-server"],
  "env": {
    "NEO4J_URI": "bolt://localhost:7687",
    "NEO4J_DATABASE": "neo4j",
    "NEO4J_USER": "neo4j",
    "NEO4J_PASSWORD": "${NEO4J_PASSWORD}"
  },
  "description": "Neo4j 图数据库 — 项目/创始人/赛道/交易图谱"
}
```

## 2. PostgreSQL（结构化数据——LP/基金/财务记录）

```json
"postgres": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-postgres"],
  "env": {
    "DATABASE_URL": "postgresql://rex:claude123@localhost:5432/claude_mcp"
  },
  "description": "PostgreSQL — LP管理/基金财务/结构化数据查询"
}
```

## 3. Firecrawl（网页抓取——竞品官网/融资新闻）

```json
"firecrawl": {
  "command": "npx",
  "args": ["-y", "firecrawl-mcp"],
  "env": {
    "FIRECRAWL_API_KEY": "${FIRECRAWL_API_KEY}"
  },
  "description": "Firecrawl — 网页抓取（工商信息/融资新闻/竞品官网）"
}
```

## 4. Exa（深度搜索——行业数据/海外对标）

```json
"exa": {
  "command": "npx",
  "args": ["-y", "@anthropic/exa-mcp-server"],
  "env": {
    "EXA_API_KEY": "${EXA_API_KEY}"
  },
  "description": "Exa — 深度语义搜索（行业数据/海外对标/技术论文）"
}
```

## 5. Playwright（浏览器自动化——工商查询/LinkedIn）

```json
"playwright": {
  "command": "npx",
  "args": ["-y", "@playwright/mcp"],
  "description": "Playwright — 浏览器自动化（天眼查/企查查/LinkedIn 信息提取）"
}
```

## 6. Filesystem（本地文件管理）

```json
"filesystem": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/rex/projects"],
  "description": "本地文件系统 — 项目管理/报告存储/数据导出"
}
```

## 7. Context7（技术文档——科技类项目尽调）

```json
"context7": {
  "command": "npx",
  "args": ["-y", "@upstash/context7-mcp"],
  "description": "Context7 — 技术文档查询（科技项目尽调时查阅最新框架/API文档）"
}
```

---

## 完整配置检查清单

部署前逐项确认：

```
□ Neo4j 已启动且可连接 (bolt://localhost:7687)
□ cypher-shell 可执行并已初始化 Schema
□ PostgreSQL 已启动 (localhost:5432)
□ DeepSeek API Key 已设置且余额充足
□ Firecrawl API Key 已设置
□ Exa API Key 已设置（可选但推荐）
□ ~/.claude/mcpServers.json 已包含以上 7 个 MCP 服务器
□ config/investor-env.sh 已编辑并 source
□ ~/.bashrc 已追加 source 命令（开机自动加载）
```
