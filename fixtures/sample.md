---
title: "TRIO 管道验证报告"
subtitle: "字体 · 表格 · 代码块 · 数学公式"
author: "TRIO 3.0"
date: "2026-07-15"
mainfont: Noto Serif
sansfont: Noto Sans
CJKmainfont: Noto Serif CJK SC
CJKsansfont: Noto Sans CJK SC
monofont: Noto Sans Mono CJK SC
pdf-engine: xelatex
toc: true
numbersections: true
colorlinks: true
---

# 字体测试

## 中文正文

这是一段中文正文，用于验证 Noto Serif CJK SC 字体是否正确嵌入 PDF。
TRIO 3.0 是三视角协同分析引擎，包含 Claude、Kimi、DeepSeek 三个独立 Agent。

## 中英混排

Claude 负责工程与交付（Engineering & Delivery），Kimi 负责内容与洞察（Content & Insight），
DeepSeek 负责质控与审计（Quality Control & Audit）。三者在同一平台上运行，无需跨 App 搬运。

## 特殊字符

- 中文标点：，。！？；：""''（）【】《》
- 数字：1234567890
- 符号：© ® ™ ± × ÷ ≤ ≥ ≠ ≈ ∞
- 粗体：**这是粗体中文** and **bold English**
- 斜体：*这是斜体中文* and *italic English*

---

# 表格测试

## 简单表格

| 指标 | 方案 A | 方案 B | 方案 C |
|------|--------|--------|--------|
| 成本 | 低 | 中 | 高 |
| 风险 | 高 | 中 | 低 |
| 速度 | 快 | 中 | 慢 |

## 长表格（验证跨页不断裂）

| # | 组件 | 状态 | 负责人 | 截止日期 | 备注 |
|---|------|------|--------|----------|------|
| 1 | 字体预检脚本 | 已完成 | Claude | 2026-07-15 | font-preflight.sh |
| 2 | Eisvogel 加固补丁 | 已完成 | Claude | 2026-07-15 | eisvogel-hardening.tex |
| 3 | 回归测试脚本 | 已完成 | Claude | 2026-07-15 | regression-test.sh |
| 4 | 构建路由脚本 | 已完成 | Claude | 2026-07-15 | trio-build.sh |
| 5 | Docker 镜像 | 待完成 | Claude | 2026-07-16 | Dockerfile.pandoc |
| 6 | CI/CD 集成 | 待开始 | — | 2026-07-20 | GitHub Actions |
| 7 | Typst 评估 | 待开始 | — | 2026-08-01 | 观察生态成熟度 |
| 8 | 回归测试样本库 | 待开始 | — | 2026-07-25 | 10+ 典型报告 |
| 9 | Mermaid 预渲染管道 | 待开始 | — | 2026-07-30 | mermaid-cli → SVG |
| 10 | 字体子集化 | 待开始 | — | 2026-08-15 | 减小 PDF 体积 |
| 11 | 多主题支持 | 待开始 | — | 2026-08-20 | consulting-light/tech-deep/data-heavy |
| 12 | Word 导出管道 | 待开始 | — | 2026-09-01 | Pandoc → reference.docx |
| 13 | PPTX 导出管道 | 待开始 | — | 2026-09-15 | python-pptx |
| 14 | HTML 交互报告 | 待开始 | — | 2026-09-30 | Playwright 全页截图 |
| 15 | 自动目录生成 | 待开始 | — | 2026-10-01 | Eisvogel 已有，验证 |
| 16 | 交叉引用 | 待开始 | — | 2026-10-15 | pandoc-crossref |
| 17 | 数学公式增强 | 待开始 | — | 2026-11-01 | 验证 \begin{align} 等环境 |
| 18 | PDF/A 兼容 | 待开始 | — | 2026-11-15 | 长期归档 |
| 19 | 多语言报告 | 待开始 | — | 2026-12-01 | 中/英/日 |
| 20 | 最终压测 | 待开始 | — | 2026-12-15 | 100 页 + 50 表格 + 20 图 |

---

# 代码块测试

## Python 代码

```python
def analyze_supply_chain(company: str, depth: int = 3) -> dict:
    """TRIO 供应链分析核心函数。

    Args:
        company: 目标企业名称
        depth: 追溯层级深度（默认 3 层）

    Returns:
        包含供应商图谱、风险评分、脆弱点分析的字典
    """
    graph = Neo4jGraph()
    suppliers = graph.traverse(company, depth=depth)

    return {
        "company": company,
        "suppliers": suppliers,
        "risk_score": calculate_risk(suppliers),
        "single_points_of_failure": find_spof(suppliers),
        "bottlenecks": identify_bottlenecks(suppliers),
    }


# 中文注释
结果 = analyze_supply_chain("比亚迪", depth=2)
print(f"风险评分: {结果['risk_score']}")
```

## Shell 脚本

```bash
#!/bin/bash
# 批量构建 TRIO 报告
for report in reports/*.md; do
    echo "📖 构建: $report"
    bash scripts/trio-build.sh "$report" || {
        echo "❌ 失败: $report"
        continue
    }
done
echo "✅ 全部完成"
```

## 长代码块（验证跨页断裂控制）

```python
# 这是一个超过 30 行的长代码块，用于测试 tcolorbox breakable 能力
# TRIO 3.0 — 配置管理模块

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional
import json
import os


@dataclass
class TRIOConfig:
    """TRIO 全局配置"""
    project_root: Path = Path(".")
    output_dir: Path = Path("out")
    theme: str = "consulting-light"
    pdf_engine: str = "xelatex"
    cjk_main_font: str = "Noto Serif CJK SC"
    cjk_sans_font: str = "Noto Sans CJK SC"
    cjk_mono_font: str = "Noto Sans Mono CJK SC"
    enable_toc: bool = True
    enable_number_sections: bool = True

    def load_from_file(self, path: Path) -> None:
        """从 JSON 文件加载配置"""
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8"))
            for key, value in data.items():
                if hasattr(self, key):
                    setattr(self, key, value)

    def to_pandoc_args(self) -> list[str]:
        """转换为 pandoc 命令行参数"""
        return [
            f"--pdf-engine={self.pdf_engine}",
            f"-V CJKmainfont={self.cjk_main_font}",
            f"-V CJKsansfont={self.cjk_sans_font}",
        ]
```

---

# 数学公式测试

行内公式：$E = mc^2$ 和 $a^2 + b^2 = c^2$。

块级公式：

$$
\frac{d}{dx}\left( \int_{a}^{x} f(t) dt \right) = f(x)
$$

多行公式：

$$
\begin{aligned}
\nabla \cdot \mathbf{E} &= \frac{\rho}{\epsilon_0} \\
\nabla \cdot \mathbf{B} &= 0 \\
\nabla \times \mathbf{E} &= -\frac{\partial \mathbf{B}}{\partial t}
\end{aligned}
$$

---

# 引用块测试

> TRIO 3.0 的核心洞察：AI 对话的价值不在于模型多强，而在于视角多样性和结论可追溯。
> 三根柱子——认知隔离、结构化怀疑、自验证闭环——不可跳过。
> 每个 Agent 的输出末尾强制写一句：「从我这个视角看不到什么」

---

# 结论

如果本文档在 PDF 中：
- 中文无方框（tofu）
- 表格跨页不断裂
- 代码块跨页不截断
- 数学公式正常渲染
- 页眉页脚完整
- 目录自动生成

则 TRIO LaTeX 管道验证通过。
