#!/usr/bin/env python3
"""TRIO PDF预处理器 — 从富MD生成PDF安全MD·不改源文件"""
import sys, re, os

SYMBOLS_MAP = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config", "symbols-pdf.map")

def load_symbols():
    m = {}
    with open(SYMBOLS_MAP) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                m[k.strip()] = v.strip()
    return m

def process(text):
    # 1. 符号替换
    sym = load_symbols()
    for uni, asc in sym.items():
        text = text.replace(uni, asc)

    # 1.5 内联标红：HTML span → LaTeX \textcolor（PDF 专用）
    #     源 MD 写 <span style="color:red">X</span>，
    #     HTML 管道直接渲染红色，PDF 管道此处转成 \textcolor{red}{X}
    text = re.sub(
        r'<span style="color:\s*red[^"]*">(.*?)</span>',
        r'\\textcolor{red}{\1}',
        text,
        flags=re.DOTALL,
    )

    # 2. Mermaid块→文字描述
    text = re.sub(
        r'```mermaid\n.*?```',
        '[图表: 拓扑关系图 — 完整交互版见HTML]',
        text,
        flags=re.DOTALL
    )

    # 3. 双标题修复：如果第一行是 # 标题且后面没有空行，加空行
    # pandoc Eisvogel已知bug——metadata title和正文H1同时渲染
    # deliver.sh已在pandoc参数中处理(-V title="")·此处为兜底

    # 4. 宽表检测标记(不拆分——依赖deliver.sh的表格处理)
    lines = text.split('\n')
    result = []
    in_table = False
    for line in lines:
        if line.startswith('|') and '|' in line[1:]:
            if not in_table:
                in_table = True
                # 检测列数
                cols = len([c for c in line.split('|') if c.strip()])
                if cols > 4:
                    pass  # 不拆分表——依赖后续Lua filter或手工
            result.append(line)
        else:
            in_table = False
            result.append(line)

    return '\n'.join(result)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: pdf-prep.py <input.md> [output.md]", file=sys.stderr)
        print("  不指定output时输出到stdout", file=sys.stderr)
        sys.exit(1)

    text = open(sys.argv[1], 'r', encoding='utf-8').read()
    result = process(text)

    if len(sys.argv) >= 3:
        open(sys.argv[2], 'w', encoding='utf-8').write(result)
    else:
        sys.stdout.write(result)
