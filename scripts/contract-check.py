#!/usr/bin/env python3
"""联邦契约合规检查 v1.0
验证子系统产出是否符合 FEDERATION-CONTRACT 的接口格式。
用法: python3 contract-check.py <子系统名> <产出文件>
退出码: 0=合规 1=不合规
"""
import sys, os, re

CONTRACT = {
    'TRIO 3.0': {
        'required_sections': ['核心判断', '风险'],
        'required_meta': ['分析日期'],
        'manifest_required': True,
        'deliver_sh_required': True,
    },
    'Stock': {
        'required_sections': ['评分', '财务数据'],
        'required_meta': ['标的代码', '分析日期'],
        'manifest_required': False,  # P1 待接入
        'deliver_sh_required': False,  # P1 待接入
    },
    'Investor': {
        'required_sections': ['尽调结论', 'IRON-LAW检查'],
        'required_meta': ['deal名称', '分析日期'],
        'manifest_required': False,
        'deliver_sh_required': False,
    },
}

def check(subsystem, filepath):
    if subsystem not in CONTRACT:
        print(f"[Contract] 未知子系统: {subsystem}")
        return 1

    contract = CONTRACT[subsystem]
    text = open(filepath, 'r', encoding='utf-8').read()
    violations = []

    for section in contract['required_sections']:
        if section not in text:
            violations.append(f"缺少必需章节: {section}")

    for meta in contract['required_meta']:
        if meta not in text:
            violations.append(f"缺少必需元数据: {meta}")

    # Manifest检查
    manifest_path = filepath.replace('.md', '.manifest.yaml')
    if contract['manifest_required'] and not os.path.exists(manifest_path):
        violations.append("缺少 manifest.yaml（契约要求）")

    # deliver.sh检查（启发式：PDF/HTML是否存在）
    if contract['deliver_sh_required']:
        pdf = filepath.replace('.md', '.pdf')
        if not os.path.exists(pdf):
            violations.append("缺少 PDF 交付物（契约要求通过 deliver.sh）")

    status = 'PASS' if not violations else 'FAIL'
    print(f"[Contract] {subsystem} | {status} | {len(violations)}项违规")
    for v in violations:
        print(f"  [!] {v}")

    return 0 if not violations else 1

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("用法: contract-check.py <子系统名> <产出文件>", file=sys.stderr)
        print("  子系统: TRIO 3.0 | Stock | Investor", file=sys.stderr)
        sys.exit(1)
    sys.exit(check(sys.argv[1], sys.argv[2]))
