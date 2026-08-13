# TRIO LaTeX 管道加固方案

> 决策: 保留 LaTeX + Eisvogel 作为 PDF 主路径。不换引擎，修管道。
> 理由: LaTeX 排版质量（断行/数学/表格美感）仍优于浏览器打印。问题在稳定性，不在能力。

---

## 一、根因定位

其他模型说的对了一半——LaTeX 管道不稳定确实存在。但它们的解决方案（换 Playwright/Typst）杀鸡用牛刀。真正的问题只有两个：

1. **CJK 字体**: WSL2 访问 Windows 字体路径不稳定 → 方框
2. **分页控制**: Eisvogel 模板没有针对长表格/代码块的 break 策略

两个都是配置问题，不需要换引擎。

---

## 二、CJK 字体一键根治

### 2.1 安装 Noto CJK（WSL2 内，不依赖 Windows 字体）

```bash
sudo apt install -y fonts-noto-cjk fonts-noto-cjk-extra
fc-cache -fv
# 验证
fc-list :lang=zh | head -5
```

### 2.2 Pandoc YAML 固定配置

```yaml
# 每个报告的 YAML 头部固定这 4 行
mainfont: Noto Serif
sansfont: Noto Sans
CJKmainfont: Noto Serif CJK SC
CJKsansfont: Noto Sans CJK SC
monofont: Noto Sans Mono CJK SC
pdf-engine: xelatex
```

### 2.3 字体预检脚本

```bash
#!/bin/bash
# font-preflight.sh — 生成 PDF 前跑一次
FONTS=("Noto Serif CJK SC" "Noto Sans CJK SC" "Noto Sans Mono CJK SC")
for f in "${FONTS[@]}"; do
  if fc-list | grep -qi "$f"; then
    echo "✅ $f"
  else
    echo "❌ $f — 缺失！运行: sudo apt install fonts-noto-cjk"
    exit 1
  fi
done
echo "字体检查通过"
```

---

## 三、分页策略（Eisvogel 模板增强）

在 Eisvogel 模板的 header-includes 中加入：

```latex
% 表格行不断裂
\usepackage{longtable}
\usepackage{booktabs}

% 代码块不断裂 — 用 tcolorbox 替代默认 listing
\usepackage{tcolorbox}
\tcbuselibrary{listings, breakable}
\newtcblisting{codeblock}[1][]{
  listing only,
  breakable,
  colback=gray!5,
  colframe=gray!30,
  sharp corners,
  #1
}

% 图片不断裂
\renewcommand{\floatpagefraction}{0.8}
```

---

## 四、双管道架构（最终方案）

不合并。两条管道各司其职：

```
Markdown 源文件
    │
    ├── 纯文字报告 (白皮书/分析报告/备忘录)
    │   └── pandoc + xelatex + Eisvogel → PDF ✅
    │       优势: 排版美感、数学公式、断行算法
    │
    └── 含图表的报告 (仪表盘/Mermaid/SVG 密集)
        └── HTML + Playwright → PDF ✅
            优势: Mermaid 原生、CSS 灵活、JS 交互
```

**判断规则**: 有 Mermaid 图 → HTML 管道。无 Mermaid → LaTeX 管道。

---

## 五、一劳永逸的 Docker 镜像

如果 WSL2 环境不稳定（字体缓存/路径问题反复出现），就封 Docker：

```dockerfile
FROM pandoc/latex:latest
RUN apt update && apt install -y fonts-noto-cjk fonts-noto-cjk-extra
RUN fc-cache -fv
# 验证 CJK 可用
RUN fc-list :lang=zh | grep -i noto
```

```bash
# 使用
docker run --rm -v $(pwd):/data trio-pandoc \
  pandoc report.md -o report.pdf \
  --pdf-engine=xelatex --template=eisvogel \
  -V CJKmainfont="Noto Serif CJK SC"
```

---

## 六、为什么不用 Typst（现在）

| 维度 | 现在换 | 半年后换 |
|------|--------|---------|
| Eisvogel 模板价值 | 丢弃 | 继续用 |
| 迁移成本 | 2-3 天重写模板 | 生态更成熟后成本更低 |
| 排版质量 | Typst 约 LaTeX 90% | 预计 95%+ |
| 风险 | 新工具链未知坑 | 社区验证过的坑都有解 |

**结论**: 现在不换。等 Typst 生态再成熟 6 个月，同时关注 Eisvogel 的 Typst 平替是否出现。届时评估一次，成本应该更低。

---

## 七、可执行工具链（已就位）

| 文件 | 路径 | 用途 |
|------|------|------|
| 字体预检 | `scripts/font-preflight.sh` | 5 层检查：缓存→文件→匹配→编译→嵌入 |
| Eisvogel 补丁 | `design/eisvogel-hardening.tex` | tcolorbox 接管代码块 + longtable + microtype |
| 回归测试 | `scripts/regression-test.sh` | 改模板后 diff PDF，防静默退化 |
| 构建路由 | `scripts/trio-build.sh` | 自动检测 Mermaid → 选 LaTeX 或 HTML 管道 |
| Docker 固化 | `scripts/Dockerfile.pandoc` | 消除 WSL2 环境漂移 |

### 立即跑通

```bash
# 1. 装字体（一次性）
sudo apt install -y fonts-noto-cjk fonts-noto-cjk-extra && fc-cache -fv

# 2. 预检——如果能通过这 5 层，字体永不方框
bash scripts/font-preflight.sh

# 3. 构建报告（自动检测图文，选最优管道）
bash scripts/trio-build.sh report.md

# 4. 改模板后跑回归测试
bash scripts/regression-test.sh fixtures/sample.md
```
