# TRIO 3.0 Design System

> **格式**: Google Stitch DESIGN.md v1
> **用途**: AI 编码代理（Claude Code / Cursor / v0）读取后生成一致 UI
> **吸收来源**: Inkwell (token 分层) + shadcn/ui v4 (@theme inline) + awesome-design-md (Stitch 格式)
> **版本**: v1.0 · 2026-07-15

---

## 1. Visual Theme & Atmosphere

**调性**: 专业分析工具——克制、权威、可读性优先。不为炫技牺牲信息密度。

| 属性 | 值 |
|------|---|
| 密度 | 中高——信息优先，但不拥挤 |
| 气质 | 学术期刊 + 咨询报告之间——比学术暖，比咨询严谨 |
| 设计哲学 | 色彩是指路牌，不是装饰。每种颜色有语义职责 |

---

## 2. Color Palette & Roles

### 2.1 原始色板（Primitives — 不直接在组件中使用）

```
stone-50:  #fafaf9    stone-900: #1c1917
stone-100: #f5f5f4    stone-800: #292524
stone-200: #e7e5e4    stone-700: #44403c
stone-300: #d6d3d1    stone-600: #57534e
white:     #ffffff

blue-500:  #3b82f6    blue-600:  #2563eb    blue-700:  #1d4ed8
amber-500: #f59e0b    amber-600: #d97706    amber-700: #b45309
green-500: #22c55e    green-600: #16a34a
red-500:   #ef4444    red-600:   #dc2626
purple-500:#8b5cf6
```

### 2.2 语义 Token（Semantic — 组件只引用这一层）

| Token | 亮色值 | 暗色值 | 职责 |
|-------|--------|--------|------|
| `--bg-primary` | `stone-50` | `stone-900` | 页面主背景 |
| `--bg-secondary` | `white` | `stone-800` | 卡片/面板背景 |
| `--bg-tertiary` | `stone-100` | `stone-700` | 输入框/代码块背景 |
| `--bg-hover` | `stone-100` | `stone-700` | hover 状态 |
| `--text-primary` | `stone-900` | `stone-50` | 标题/主文字 |
| `--text-secondary` | `stone-600` | `stone-300` | 正文 |
| `--text-tertiary` | `stone-400` | `stone-500` | 辅助文字/placeholder |
| `--accent-primary` | `amber-600` | `amber-500` | 主按钮/链接/强调 |
| `--accent-hover` | `amber-700` | `amber-400` | hover 加深 |
| `--accent-warm` | `amber-500` | `amber-600` | 暖色点缀 |
| `--border-default` | `stone-200` | `stone-700` | 默认边框 |
| `--hairline` | `stone-200` | `stone-700` | 细分割线 |
| `--shadow-sm` | `0 1px 2px rgba(0,0,0,.04)` | `0 1px 2px rgba(0,0,0,.2)` | 浅阴影 |
| `--shadow-md` | `0 4px 12px rgba(0,0,0,.06)` | `0 4px 12px rgba(0,0,0,.3)` | 中等阴影 |
| `--radius-sm` | `4px` | `4px` | 小圆角 |
| `--radius-md` | `8px` | `8px` | 中圆角 |
| `--radius-lg` | `12px` | `12px` | 大圆角 |

### 2.3 语义色（功能色）

| Token | 亮色 | 暗色 | 用途 |
|-------|------|------|------|
| `--color-success` | `green-600` | `green-500` | 正向指标/已完成 |
| `--color-warning` | `amber-600` | `amber-500` | 警告/注意 |
| `--color-danger` | `red-600` | `red-500` | 风险/阻断 |
| `--color-info` | `blue-600` | `blue-500` | 信息/链接 |

### 2.4 主题切换规则

```css
/* 亮色（默认） */
:root, [data-theme="light"] { /* 语义 token → 亮色 primitives */ }

/* 暗色 */
[data-theme="dark"] { /* 语义 token → 暗色 primitives */ }
```

**硬规则**: 组件代码中绝不出现 `stone-500`、`#d97706` 等原始值。只通过 `var(--xxx)` 引用语义 token。

---

## 3. Typography Rules

| 层级 | 字号 | 字重 | 行高 | 用途 |
|------|------|------|------|------|
| Display | 2.5rem (40px) | 700 | 1.2 | Hero 标题 |
| H1 | 1.875rem (30px) | 700 | 1.3 | 页面标题 |
| H2 | 1.5rem (24px) | 600 | 1.4 | 章节标题 |
| H3 | 1.25rem (20px) | 600 | 1.4 | 子节标题 |
| Body | 1rem (16px) | 400 | 1.6 | 正文 |
| Body-Small | 0.875rem (14px) | 400 | 1.5 | 辅助文字 |
| Caption | 0.75rem (12px) | 400 | 1.4 | 标签/备注 |
| Mono | 0.875rem (14px) | 400 | 1.5 | 代码/数据 |

**字体栈**: `system-ui, -apple-system, "Microsoft YaHei", "Segoe UI", sans-serif`
**等宽**: `"Cascadia Code", "JetBrains Mono", "Fira Code", monospace`

---

## 4. Component Stylings

### 4.1 按钮

```
Primary:   bg = var(--accent-primary), text = white, radius = var(--radius-md)
            hover: bg = var(--accent-hover), glow: 0 0 20px rgba(accent, 0.3)
Secondary: bg = var(--bg-secondary), border = var(--border-default)
            text = var(--text-primary), hover: bg = var(--bg-hover)
Ghost:     bg = transparent, text = var(--text-secondary)
            hover: bg = var(--bg-hover)
```

### 4.2 卡片

```
Card: bg = var(--bg-secondary), border = 1px var(--border-default)
      radius = var(--radius-lg), shadow = var(--shadow-sm)
      padding = 1.5rem

Card-Highlight: 同 Card，但 border-left = 3px var(--accent-primary)
```

### 4.3 输入框

```
Input: bg = var(--bg-tertiary), border = 1px var(--border-default)
       text = var(--text-primary), placeholder = var(--text-tertiary)
       radius = var(--radius-md), padding = 0.625rem 0.75rem
       focus: border = var(--accent-primary), ring = 2px var(--accent-primary)
```

### 4.4 表格

```
Table:  width = 100%, border-collapse = collapse
Head:   bg = var(--bg-tertiary), text = var(--text-primary), weight = 600
        border-bottom = 2px var(--border-default)
Row:    border-bottom = 1px var(--border-default)
        hover: bg = var(--bg-hover) (交互式表格)
Cell:   padding = 0.5rem 0.75rem
```

### 4.5 导航

```
Header: sticky top-0, bg = var(--bg-primary) with backdrop-blur
        border-bottom = 1px var(--border-default), height = 3.5rem
Link:   text = var(--text-secondary), hover = var(--text-primary)
Active: text = var(--accent-primary), weight = 600
```

---

## 5. Layout Principles

| 属性 | 值 |
|------|---|
| 最大内容宽度 | 1280px (max-w-7xl) |
| 页面内边距 | 1rem (mobile) / 2rem (desktop) |
| 卡片间距 | 1.5rem (gap-6) |
| 章节间距 | 4rem (py-16) |
| 网格 | 12 列，auto-fit minmax(280px, 1fr) |
| 间距单位 | 0.25rem 基准 (4px grid) |

---

## 6. Depth & Elevation

```
Level 0: 页面背景 (bg-primary) — 无阴影
Level 1: 卡片 (bg-secondary) — shadow-sm
Level 2: 弹出层/Modal — shadow-md + backdrop
Level 3: 抽屉/Drawer — shadow-lg + backdrop
```

不使用多层阴影叠加。三层足够区分所有 UI 深度。

---

## 7. Do's and Don'ts

### ✅ Do
- 所有颜色通过 `var(--xxx)` 引用语义 token
- 换主题只改 CSS 变量值，不改任何组件代码
- 亮/暗双模同步维护——新增 token 时同时定义两套值
- 表格必须有表头，链接使用引用格式

### ❌ Don't
- 禁止硬编码 hex 色值到组件中
- 禁止使用 `dark:` Tailwind 前缀——用 `[data-theme="dark"]` 统一管理
- 禁止引入超过 3 个强调色到同一个页面
- 禁止紫色/绿色作为主色调（TRIO 品牌 = 暖金/琥珀系）
- 禁止 AI 痕迹词（"审计""修正""v2""感谢XX"）出现在最终交付物中

---

## 8. Responsive Behavior

| 断点 | 宽度 | 行为 |
|------|------|------|
| Mobile | < 640px | 单列，卡片全宽，字号缩小 1 级 |
| Tablet | 640-1024px | 2 列网格，侧边栏折叠 |
| Desktop | > 1024px | 多列，完整导航，最大宽 1280px |

---

## 9. Theme Bridge: JSON → CSS

TRIO 现有 3 套 JSON 主题（`design/themes/*.json`）。每个主题新增 `cssVars` 字段，由 `theme-bridge.py` 自动生成对应 CSS 文件。

### 示例：consulting-light.json 的 cssVars 扩展

```json
{
  "cssVars": {
    "--bg-primary":    "#FAFBFC",
    "--bg-secondary":  "#FFFFFF",
    "--bg-tertiary":   "#F4F6FA",
    "--text-primary":  "#0F172A",
    "--text-secondary":"#334155",
    "--text-tertiary": "#64748B",
    "--accent-primary":"#0066CC",
    "--accent-hover":  "#0052A3",
    "--border-default":"#DDE1E7",
    "--shadow-sm":     "0 1px 2px rgba(0,0,0,0.04)",
    "--shadow-md":     "0 4px 12px rgba(0,0,0,0.06)",
    "--radius-md":     "8px"
  }
}
```

**使用**: `python theme-bridge.py consulting-light → trio-theme-consulting-light.css`

---

## 10. Agent Prompt Guide

### 快速参考（贴给 AI agent）

```
TRIO 设计系统速查：
- 主色: var(--accent-primary) = 琥珀/金
- 背景: var(--bg-primary) = stone 系
- 字体: system-ui + Microsoft YaHei
- 卡片: 1px border + shadow-sm + radius-lg
- 暗色: [data-theme="dark"] 切换
- 硬禁: 不硬编码色值，不用紫色/绿色做主色，不留 AI 痕迹词

完整规范见: DESIGN.md
CSS 变量定义见: trio-tokens.css
主题桥接脚本: theme-bridge.py
```
