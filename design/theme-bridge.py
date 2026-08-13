#!/usr/bin/env python3
"""
TRIO 3.0 Theme Bridge — JSON 主题 → CSS Variables
吸收: design.md CLI (sunil-dsb) 的自动提取思路 + Inkwell 两层架构

用法:
  python theme-bridge.py <theme-name>          → 生成 trio-theme-{name}.css
  python theme-bridge.py --all                 → 生成全部主题
  python theme-bridge.py --tailwind <name>     → 生成 Tailwind v4 @theme inline 代码
  python theme-bridge.py --list                → 列出可用主题

示例:
  python theme-bridge.py consulting-light
  python theme-bridge.py --tailwind data-heavy
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from datetime import datetime, timezone, timedelta

TZ = timezone(timedelta(hours=8))
DESIGN_DIR = Path(__file__).resolve().parent
THEMES_DIR = DESIGN_DIR / "themes"
OUTPUT_DIR = DESIGN_DIR / "generated"

# 现有 3 套主题的语义 token 映射（从 JSON 字段 → CSS 变量）
# 如果 JSON 里新增了 cssVars 字段则优先使用；否则用此映射自动推导
FALLBACK_MAP = {
    "pageBg":      "--bg-primary",
    "white":       "--bg-secondary",
    "cardBg":      "--bg-tertiary",
    "dark":        "--color-stone-900",
    "textMain":    "--text-primary",
    "textBody":    "--text-secondary",
    "textMuted":   "--text-tertiary",
    "blue":        "--accent-primary",
    "amber":       "--accent-warm",
    "green":       "--color-success",
    "red":         "--color-danger",
    "tblHead":     "--bg-tertiary",
    "tblRow1":     "--bg-secondary",
    "tblRow2":     "--bg-tertiary",
    "line":        "--border-default",
}


def load_theme(name: str) -> dict:
    """加载 JSON 主题文件"""
    path = THEMES_DIR / f"{name}.json"
    if not path.exists():
        print(f"❌ 主题不存在: {name}")
        available = [p.stem for p in THEMES_DIR.glob("*.json")]
        print(f"   可用: {', '.join(available)}")
        sys.exit(1)
    return json.loads(path.read_text(encoding="utf-8"))


def theme_to_css_vars(theme: dict) -> str:
    """将 JSON 主题转换为 CSS 变量定义"""
    # 优先使用显式 cssVars
    if "cssVars" in theme:
        vars_lines = []
        for var_name, var_value in theme["cssVars"].items():
            vars_lines.append(f"  {var_name}: {var_value};")
        return "\n".join(vars_lines)

    # 否则用映射表自动推导
    colors = theme.get("colors", {})
    vars_lines = []
    for json_key, css_var in FALLBACK_MAP.items():
        if json_key in colors:
            vars_lines.append(f"  {css_var}: #{colors[json_key]};")

    # 补充硬编码的默认值
    defaults = {
        "--shadow-sm": "0 1px 2px rgba(0,0,0,0.04)",
        "--shadow-md": "0 4px 12px rgba(0,0,0,0.06)",
        "--radius-sm": "4px",
        "--radius-md": "8px",
        "--radius-lg": "12px",
    }
    for var_name, var_value in defaults.items():
        vars_lines.append(f"  {var_name}: {var_value};")

    return "\n".join(vars_lines)


def generate_css(name: str) -> str:
    """生成完整的主题 CSS 文件"""
    theme = load_theme(name)
    css_vars = theme_to_css_vars(theme)
    theme_label = theme.get("name", name)

    return f"""/* ═══════════════════════════════════════════════════════════
   TRIO Theme: {theme_label}
   自动生成于: {datetime.now(TZ).strftime('%Y-%m-%d %H:%M')} CST
   生成工具: theme-bridge.py
   源文件:   themes/{name}.json
   依赖:     trio-tokens.css (提供 primitives 层)
   ═══════════════════════════════════════════════════════════ */

/* 假定 trio-tokens.css 已加载（提供 --color-xxx primitives） */
@import "./trio-tokens.css";

:root,
[data-theme="light"] {{
{css_vars}
}}

/* 暗色模式: 自动反转背景/文字色 */
[data-theme="dark"] {{
  --bg-primary:    #0c0a09;
  --bg-secondary:  #1c1917;
  --bg-tertiary:   #292524;
  --text-primary:  #fafaf9;
  --text-secondary:#d6d3d1;
  --text-tertiary: #78716c;
  /* 强调色保持但调亮 */
}}
"""


def generate_tailwind_v4(name: str) -> str:
    """生成 Tailwind v4 @theme inline 代码块"""
    theme = load_theme(name)
    colors = theme.get("colors", {})

    return f"""/* Tailwind v4 @theme inline — {theme.get('name', name)} */
/* 用法: 复制到你的 index.css，放在 @import "tailwindcss" 之后 */

@theme inline {{
  --color-background: var(--bg-primary);
  --color-foreground: var(--text-primary);
  --color-card:       var(--bg-secondary);
  --color-muted:      var(--bg-tertiary);
  --color-border:     var(--border-default);
  --color-primary:    var(--accent-primary);
  --color-accent:     var(--accent-warm);
  --color-success:    var(--color-success);
  --color-danger:     var(--color-danger);
  --color-info:       var(--color-info);

  --radius-sm: var(--radius-sm);
  --radius-md: var(--radius-md);
  --radius-lg: var(--radius-lg);
}}
"""


def cmd_list():
    """列出可用主题"""
    print("可用 TRIO 主题:")
    for path in sorted(THEMES_DIR.glob("*.json")):
        theme = json.loads(path.read_text(encoding="utf-8"))
        print(f"  {path.stem:25s} — {theme.get('name', '?')}: {theme.get('description', '')[:60]}")


def cmd_generate(name: str):
    """生成主题 CSS"""
    OUTPUT_DIR.mkdir(exist_ok=True)
    css = generate_css(name)
    out_path = OUTPUT_DIR / f"trio-theme-{name}.css"
    out_path.write_text(css, encoding="utf-8")
    print(f"✅ 已生成: {out_path}")


def cmd_tailwind(name: str):
    """生成 Tailwind v4 代码"""
    tw = generate_tailwind_v4(name)
    OUTPUT_DIR.mkdir(exist_ok=True)
    out_path = OUTPUT_DIR / f"tailwind-v4-{name}.css"
    out_path.write_text(tw, encoding="utf-8")
    print(f"✅ 已生成: {out_path}")


def cmd_all():
    """生成全部主题"""
    for path in sorted(THEMES_DIR.glob("*.json")):
        cmd_generate(path.stem)
        cmd_tailwind(path.stem)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    arg = sys.argv[1]

    if arg == "--list":
        cmd_list()
    elif arg == "--all":
        cmd_all()
    elif arg == "--tailwind":
        if len(sys.argv) < 3:
            print("用法: theme-bridge.py --tailwind <theme-name>")
            sys.exit(1)
        cmd_tailwind(sys.argv[2])
    else:
        cmd_generate(arg)
