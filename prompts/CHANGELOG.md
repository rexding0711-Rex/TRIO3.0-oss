# Prompt 版本化 — CHANGELOG

> 记录每次 prompt 修改：改了什么、为什么、谁改的。

## 约定
- 文件名: `{名称}_v{MAJOR}.{MINOR}.{PATCH}.md`
- MAJOR: 输出格式/行为根本变化
- MINOR: 新增规则/约束
- PATCH: 修正笔误/措辞

---

## 2026-07-02 — 初始化

### v1.0.0 基线
- Claude 面具: 从 `.claude/commands/claude.md` 迁移（待做）
- Kimi 面具: 从 `.claude/commands/kimi.md` 迁移（待做）
- DeepSeek 面具: 从 `.claude/commands/deepseek.md` 迁移（待做）
- kg-extractor prompt: 位于 `D:\TRIO 3.0\scripts\kg-extractor.py` 的 `EXTRACT_PROMPT` 常量

### 待迁移
- [ ] 三面具 system prompt 从 commands/ 迁移到此目录
- [ ] 建立 5 个 regression test cases
- [ ] 每次改 prompt 后在此文件追加记录
