# TRIO 3.0 设计资产库

## 为什么需要这个

每次生成 PPT/HTML/PDF 时，配色、间距、字体层级全靠记忆临时决定——结果不可控。
这个库把"已验证有效"的设计参数固化为可复用的资产。
**v2.0 新增**: CSS 变量系统 + Tailwind v4 集成 + AI Agent 可读的 DESIGN.md。

## 目录结构

```
design/
├── README.md                    ← 你在这里
├── BRIEF.md                     ← 每次生成前必填的 2 分钟 checklist
├── DESIGN.md                    ← [NEW] Google Stitch 格式，AI agent 可读
├── trio-tokens.css              ← [NEW] 两层 CSS 变量系统 (primitives → semantic)
├── trio-report-template.html    ← [NEW] HTML 报告骨架模板
├── theme-bridge.py              ← [NEW] JSON 主题 → CSS + Tailwind v4 自动转换
├── themes/                      ← 配色方案（JSON，可直接 import）
│   ├── consulting-light.json        麦肯锡白底风 — 投资人沟通首选
│   ├── tech-deep.json               深色科技风 — 大型发布会/Keynote
│   └── data-heavy.json              数据看板风 — 表格密集的行业报告
├── generated/                   ← [NEW] theme-bridge.py 自动生成
│   ├── trio-theme-*.css             纯 CSS 主题文件
│   └── tailwind-v4-*.css            Tailwind v4 @theme inline 代码
├── pages/                       ← 页类型设计规范
│   ├── cover.md                     封面
│   ├── exec-summary.md              执行摘要
│   ├── content-table.md             目录页
│   ├── content-card.md              卡片式内容页
│   ├── chapter-divider.md           章节分隔页
│   └── closing.md                   尾页
└── inspiration/                 ← 外部参考截图 + 配色提取
    ├── INDEX.md
    ├── consulting-light/
    ├── tech-deep/
    └── data-heavy/
```

## 使用流程

### Web/HTML 报告（新增）

1. 链接 `trio-tokens.css` (提供所有 CSS 变量)
2. 使用 `trio-report-template.html` 作为骨架
3. 所有颜色通过 `var(--xxx)` 引用，不硬编码 hex
4. 主题切换: `[data-theme="dark"]` 自动覆写

### PPT/PDF 报告（原有）

1. **生成前**：填 `BRIEF.md` → 选主题 → 选页类型
2. **编码时**：`require('./theme.json')` 导入配色和参数
3. **生成后**：截图 2-3 页关键页 → 和 `inspiration/` 对比 → 调整

### Tailwind v4 项目

1. `python theme-bridge.py --tailwind consulting-light` 生成 @theme inline 代码
2. 复制到项目 `index.css`，放在 `@import "tailwindcss"` 之后
3. 获得 `bg-background`, `text-primary`, `bg-accent` 等 utility class

## 配色选择速查

| 场景 | 推荐主题 | 背景 | 核心色 |
|------|---------|------|--------|
| 投资人BP/白皮书 | consulting-light | 白/浅灰 | 蓝 #0066CC |
| 大型发布会 | tech-deep | 深蓝黑 | 青 #00D4FF |
| 行业数据报告 | data-heavy | 白 | 蓝+橙双色系 |
| **TRIO 默认** | **amber-stone (trio-tokens.css)** | **stone-50** | **琥珀 #d97706** |

## 吸收来源 (v2.0)

| 来源 | 吸收了 | 体现在 |
|------|--------|--------|
| Hygge 逆向 | CSS 变量设计系统、主题切换 | `trio-tokens.css` |
| Inkwell | 两层 token 架构 (primitives → semantic) | `trio-tokens.css` Layer 1/2 |
| shadcn/ui v4 | `@theme inline` 模式 | `theme-bridge.py --tailwind` |
| awesome-design-md | Google Stitch DESIGN.md 格式 | `DESIGN.md` |
| design.md CLI | URL → 设计 token 自动提取 | `theme-bridge.py` 设计理念 |

## 硬规则

- 组件代码中绝不出现硬编码 hex 色值
- 只通过 `var(--xxx)` 引用语义 token
- 换主题只改变 CSS 变量值，不改组件代码
- AI 痕迹词（"审计""修正""v2""感谢XX"）禁止出现在最终交付物中
