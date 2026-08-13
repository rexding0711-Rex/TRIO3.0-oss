# TRIO Artifact Rules — AI Agent 文档生成约束

> 每次 Claude Code 或其他 AI agent 生成文档前，读取此文件。
> 这不是"建议"——是硬约束。违反任一条 = 返工。

---

## 0. 身份声明

你不是"文档生成器"。你是：
- 信息设计师（information designer）
- 编辑排版总监（editorial art director）
- 前端工程师（frontend engineer）
- 视觉 QA 审查员（visual QA reviewer）

你的任务不是"写出能用的代码"。你的任务是**产出一份视觉上有意图的交付物**。

---

## 1. 格式铁律

### HTML 是唯一母版

```
内容 (Markdown)
    ↓
HTML (设计系统 + 内容填充)
    ↓
├── 网页展示 → HTML 原样
├── PDF → Playwright/WeasyPrint 渲染
├── DOCX → Pandoc + reference.docx
└── 长图 → Playwright 全页截图
```

- ✅ 所有文档从 HTML 出发
- ❌ 禁止直接生成 PDF（绕过 HTML 样式层 = CJK 乱码 + 排版失控）
- ❌ 禁止直接生成 DOCX（除非是纯数据表格型文档）

### 输出格式

- HTML: 单文件，内联 CSS（生产环境可外链 `trio-tokens.css`）
- 图表: SVG 优先（矢量），Canvas 备选（位图）
- 交互: Alpine.js（轻量），禁止 React/Vue（除非已有项目框架）

---

## 2. 设计系统硬约束

### 颜色

- 所有颜色通过 `var(--xxx)` 引用，禁止硬编码 hex
- 每页最多 3 个强调色
- 禁止紫色渐变、蓝紫渐变（AI 模板重灾区）
- TRIO 默认主题: 琥珀/暖金 accent + stone 系背景

### 字体

- 中文: Microsoft YaHei（PDF 安全）或 system-ui（Web）
- 英文: system-ui, -apple-system, Segoe UI
- 等宽: Cascadia Code, JetBrains Mono
- 标题/正文比例 ≥ 2:1.5:1
- 禁止使用 Inter（AI 默认字体第一名）
- 禁止使用没有明确理由的 Playfair Display（"看起来很高级"不是理由）

### 布局

- 不对称 > 居中堆叠
- 12 列网格系统
- 有意图的留白——不是"没东西"，是"呼吸"
- 内容本身就是布局——不要让内容填充模板

### 组件

- 卡片: 1px 实线边框（不是阴影堆叠）
- 按钮: 最多 2 种变体（primary + secondary）
- 表格: 三线表或斑马纹，必须有表头
- 不使用默认 shadcn/ui 圆角（除非有理由）

---

## 3. 反 AI 模板机制

### 生成前自问

1. 如果把品牌名删掉，这还认得出是我们的东西吗？
2. 如果我是用户，第一眼看到的是什么？那是我想要的第一眼吗？
3. 有没有任何元素"只是好看但没用"？

### 生成后必做

1. 删掉至少一个元素（删除测试：删了反而更强 = 就该删）
2. 找出三个最像"互联网模板"的地方
3. 至少改掉一个

### 禁止清单（AI 模板指纹）

- ❌ 深色 Hero + 紫色/蓝色渐变 CTA
- ❌ 三个并排卡片 + 图标 + 标题 + 描述
- ❌ "AI / Future / Innovation" 氛围词堆砌
- ❌ 无意义的几何装饰图形
- ❌ 过度玻璃拟态（glassmorphism）——最多 2 处
- ❌ 发光边框堆叠（glow border）——最多 1 处
- ❌ Inter 字体 + 紫色渐变 + 12px 圆角（AI 生成三板斧）

---

## 4. 渲染闭环（不可跳过）

```
生成代码 → 渲染 → 截图/预览 → 检查 → 修改 → 重新渲染 → 最终输出
```

不是: `Prompt → Code → Done`

是: `Prompt → Code → Render → See → Critique → Fix → Render → Done`

### PDF 专项

- 每页必须有 PAGE INTENT（这页要传达什么）
- 分页处表格/代码块不被截断
- 字体嵌入（CJK 不乱码）
- 页眉: Logo + 章节名 | 页脚: 页码 + 日期

---

## 5. 生成前 checklist（2 分钟）

在写任何代码之前，先回答：

1. 受众是谁？场景是什么？（屏幕阅读 / 打印 / 投影）
2. 视觉概念是什么？（一句话——"像 XX 但更 XX"）
3. 内容层级：什么必须第一眼看到？
4. 颜色约束：主色/强调色/禁用色？
5. 页数/长度预期？
6. 参考是什么？（URL / 截图 / 描述）

---

## 6. 与 TRIO 管线的接点

```
DESIGN.md          ← AI agent 读取（设计规范）
ARTIFACT_RULES.md  ← AI agent 读取（本文件，生成约束）
QUALITY_GATE.md    ← AI agent 生成后自检
trio-tokens.css    ← 所有 HTML 的基础样式
theme-bridge.py    ← 切换主题时运行
deliver.sh         ← 最终交付管道
```
