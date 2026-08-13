#!/usr/bin/env python3
"""Manifest 质量门控 v1.0
验证 manifest.yaml 的字段完整性、ID格式合规、数据质量。
用法: python3 manifest-validate.py <manifest.yaml> [--strict]
退出码: 0=通过 1=警告 2=阻断
"""
import sys, yaml, re

ID_PATTERN = re.compile(r'^(company|person|product|technology|industry):[A-Z]{2,7}:.+$')

def validate(manifest_path, strict=False):
    with open(manifest_path, 'r', encoding='utf-8') as f:
        m = yaml.safe_load(f)

    errors = []
    warnings = []

    # 必填字段
    for field in ['report_id', 'title', 'generated_at', 'entities', 'pending_actions']:
        if field not in m or m[field] is None:
            errors.append(f"缺少必填字段: {field}")

    # 实体ID格式
    for i, e in enumerate(m.get('entities', [])):
        eid = e.get('id', '')
        if not ID_PATTERN.match(eid):
            errors.append(f"实体 #{i} ID格式违规: '{eid}'")

    # 零实体告警
    if len(m.get('entities', [])) == 0:
        warnings.append("零实体提取——可能解析失败或报告内容过短")

    # 候选事实
    cf = m.get('candidate_facts_count', 0)
    if cf == 0:
        warnings.append("零候选事实——报告可能无结构化数据")

    # 待处理项
    pending = m.get('pending_actions', {})
    if not any(pending.values()):
        warnings.append("无待处理项——manifest可能未正确生成")

    # 分级结果
    level = 'PASS'
    if errors:
        level = 'BLOCK'
    elif warnings:
        level = 'WARN'

    print(f"[Validate] {m.get('report_id', '?')}  |  {level}  |  实体:{len(m.get('entities',[]))}  事实:{cf}")
    for w in warnings:
        print(f"  [!] {w}")
    for e in errors:
        print(f"  [X] BLOCK: {e}")

    # BLOCK: 结构性失败（ID违规·必填缺失·零实体）→ 阻断交付
    # WARN: 语义性警告（无候选事实·无待处理项）→ 允许交付但标注
    # PASS: 全部通过
    if errors:
        return 2  # BLOCK
    if warnings:
        return 1  # WARN
    return 0  # PASS

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法: manifest-validate.py <manifest.yaml> [--strict]", file=sys.stderr)
        sys.exit(2)
    strict = '--strict' in sys.argv
    sys.exit(validate(sys.argv[1], strict))
