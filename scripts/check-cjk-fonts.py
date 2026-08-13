#!/usr/bin/env python3
"""CJK 字体校验工具 — 检查 PPTX/PDF 中是否错误使用了拉丁字体写中文

用法:
    python3 check-cjk-fonts.py <file.pptx>        # 检查 PPTX
    python3 check-cjk-fonts.py <file.pdf>         # 检查 PDF
    python3 check-cjk-fonts.py <file.pptx> --strict  # 严格模式：含拉丁字体=失败

退出码:
    0  = 通过（无中文+拉丁字体混用）
    1  = 警告（发现问题但不阻塞）
    2  = 错误（严格模式下发现混用）
"""

import sys
import zipfile
import xml.etree.ElementTree as ET
import re
import os
from pathlib import Path

# 配置
FORBIDDEN_LATIN_FONTS = [
    "Arial", "Calibri", "Helvetica", "Times New Roman",
    "Cambria", "Liberation Sans", "DejaVu Sans", "IPAMincho",
]

ALLOWED_CJK_FONTS = [
    "Microsoft YaHei", "MicrosoftYaHei", "微软雅黑",
    "Noto Sans CJK", "NotoSansCJK", "Noto-Sans-CJK",  # weasyprint 用连字符命名
    "SimHei",
    "DengXian", "等线", "Source Han Sans", "宋体", "SimSun",
]

# 中文检测正则
CJK_RE = re.compile(r"[一-鿿㐀-䶿豈-﫿]")


def has_cjk(text: str) -> bool:
    """检查文本是否包含中文字符"""
    return bool(CJK_RE.search(text))


def check_pptx(filepath: str) -> list[str]:
    """检查 PPTX 文件中的字体使用"""
    errors = []
    try:
        with zipfile.ZipFile(filepath, "r") as z:
            # 遍历所有 XML 文件
            xml_files = [f for f in z.namelist() if f.endswith(".xml")]
            for xml_name in xml_files:
                try:
                    with z.open(xml_name) as f:
                        content = f.read().decode("utf-8", errors="ignore")
                except Exception:
                    continue

                # 检查每个文本运行
                # 简化方法：找所有 <a:rPr> 中的字体名，然后找这个运行的文本
                # 更直接的方法：扫描整个 XML 中的字体引用
                for forbidden in FORBIDDEN_LATIN_FONTS:
                    # 跳过 theme 文件——主题中 Arial 作为默认拉丁字体是正常的
                    if "theme" in xml_name.lower():
                        continue
                    if forbidden.lower() in content.lower():
                        # 检查同一文件中是否有 CJK 文本
                        if has_cjk(content):
                            errors.append(
                                f"[{xml_name}] 检测到拉丁字体 '{forbidden}' 与中文文本共存"
                            )
                            break  # 每个文件只报一次

        if not errors:
            print(f"✅ PPTX 字体检查通过: {filepath}")
        else:
            print(f"❌ PPTX 字体检查发现 {len(errors)} 个问题:")
            for e in errors:
                print(f"   {e}")
    except Exception as e:
        errors.append(f"无法打开 PPTX: {e}")
        print(f"❌ {e}")

    return errors


def check_docx(filepath: str) -> list[str]:
    """检查 DOCX 文件中的字体使用（docx 与 pptx 同为 zip+XML 容器，复用扫描逻辑）。"""
    errors = []
    try:
        with zipfile.ZipFile(filepath, "r") as z:
            # 只查正文/表头 XML，跳过 theme / fontTable / styles 默认声明
            xml_files = [
                f for f in z.namelist()
                if f.endswith(".xml")
                and "theme" not in f.lower()
                and "fonttable" not in f.lower()
            ]
            for xml_name in xml_files:
                try:
                    with z.open(xml_name) as f:
                        content = f.read().decode("utf-8", errors="ignore")
                except Exception:
                    continue
                for forbidden in FORBIDDEN_LATIN_FONTS:
                    if forbidden.lower() in content.lower():
                        if has_cjk(content):
                            errors.append(
                                f"[{xml_name}] 检测到拉丁字体 '{forbidden}' 与中文文本共存"
                            )
                            break  # 每个文件只报一次

        if not errors:
            print(f"✅ DOCX 字体检查通过: {filepath}")
        else:
            print(f"❌ DOCX 字体检查发现 {len(errors)} 个问题:")
            for e in errors:
                print(f"   {e}")
    except Exception as e:
        errors.append(f"无法打开 DOCX: {e}")
        print(f"❌ {e}")

    return errors


def check_pdf(filepath: str) -> list[str]:
    """检查 PDF 文件中是否使用了 CJK 字体（使用 pypdf 解析，支持压缩 PDF）"""
    errors = []
    try:
        from pypdf import PdfReader

        reader = PdfReader(filepath)
        base_fonts = []

        for page in reader.pages:
            if '/Resources' in page and '/Font' in page['/Resources']:
                for _k, v in page['/Resources']['/Font'].items():
                    if '/BaseFont' in v:
                        # BaseFont 格式: /XXXXXX+FontName → 提取 FontName 部分
                        name = str(v['/BaseFont']).lstrip('/')
                        if '+' in name:
                            name = name.split('+', 1)[1]
                        base_fonts.append(name)

        # 去重
        base_fonts = list(dict.fromkeys(base_fonts))

        has_cjk_font = any(
            any(allowed.lower() in f.lower() for allowed in ALLOWED_CJK_FONTS)
            for f in base_fonts
        )

        # 检查是否有 Type1 CJK 字体（Subtype 不是 Type0 且含 CJK 则警告）
        type1_cjk = []
        for page in reader.pages:
            if '/Resources' in page and '/Font' in page['/Resources']:
                for _k, v in page['/Resources']['/Font'].items():
                    subtype = str(v.get('/Subtype', ''))
                    name = str(v.get('/BaseFont', '')).lstrip('/')
                    if 'CJK' in name and 'Type0' not in subtype:
                        # Type1 或 Type3 的 CJK 字体
                        if name not in type1_cjk:
                            type1_cjk.append(name)

        if has_cjk_font:
            print(f"✅ PDF 使用正确的 CJK 字体: {filepath}")
            print(f"   检测到的字体: {', '.join(base_fonts[:15])}")
        else:
            errors.append("PDF 中未检测到已知的 CJK 字体")
            print(f"⚠️  PDF 可能缺少 CJK 字体嵌入: {filepath}")
            if base_fonts:
                print(f"   实际 BaseFont: {', '.join(base_fonts[:10])}")

        if type1_cjk:
            errors.append(f"检测到 Type1 CJK 字体（会导致间距问题）: {type1_cjk}")
            print(f"❌ Type1 CJK 字体: {type1_cjk}")

        if not errors:
            print(f"✅ PDF 字体检查通过: {filepath}")

    except Exception as e:
        errors.append(f"PDF 检查失败: {e}")
        print(f"❌ {e}")

    return errors


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    filepath = sys.argv[1]
    strict = "--strict" in sys.argv

    if not os.path.exists(filepath):
        print(f"❌ 文件不存在: {filepath}")
        sys.exit(2)

    ext = Path(filepath).suffix.lower()
    errors = []

    if ext == ".pptx":
        errors = check_pptx(filepath)
    elif ext == ".pdf":
        errors = check_pdf(filepath)
    elif ext == ".docx":
        errors = check_docx(filepath)
    else:
        print(f"⚠️  不支持的文件类型: {ext}。支持的格式: .pptx, .pdf, .docx")
        sys.exit(1)

    if errors:
        if strict:
            print(f"\n🚫 严格模式：{len(errors)} 个问题 → 阻断")
            sys.exit(2)
        else:
            print(f"\n⚠️  {len(errors)} 个警告（非严格模式，不阻断）")
            sys.exit(1)
    else:
        print(f"\n✅ 全部通过")
        sys.exit(0)


if __name__ == "__main__":
    main()
