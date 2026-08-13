# TRIO CLI 适配器

> TRIO 可以在任何 AI CLI 上运行——不只 Claude Code

## 原理

TRIO = 操作系统层(mgmt.sh+config+scripts) + 面具层(prompt+pipe协议)

操作系统层不依赖任何特定CLI。面具层是标准的Markdown Prompt——任何支持System Prompt的AI CLI都能加载。

## 适配方案

| CLI | 面具加载方式 | 场景触发 |
|-----|-----------|---------|
| Claude Code | .claude/commands/*.md（真身在 `C:\Users\Rex\.claude\commands\`） | /all（唯一分析入口）· /TRIO · /claude · /kimi · /deepseek |
| 其他 CLI | 复制到对应技能/规则目录 | 自然语言触发 |
| IDE 插件 | Rules设置→加载面具prompt | @命令触发 |
| 终端+API | 直接cat config/roles/*.md→作为system prompt | bash mgmt.sh |

## 三步迁移

1. 复制 config/ + scripts/ + mgmt.sh 到任何有bash的环境
2. 复制 config/roles/*.md 到你的CLI的技能/规则目录
3. 运行: bash mgmt.sh → 所有场景SOP可用

## 平台检测

mgmt.sh启动时source config/platform.sh→自动识别WSL/Linux/macOS/Windows→路径自动适配
