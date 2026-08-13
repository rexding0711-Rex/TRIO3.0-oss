#!/usr/bin/env python3
"""TRIO 报告 Manifest 生成器 v1.0
每份报告完成时自动生成 manifest.yaml，解决「分析→沉淀」断头路。
用法: python3 manifest.py <报告.md> [--dry-run]
"""
import sys, os, re, json, yaml
from datetime import datetime, timezone, timedelta

CST = timezone(timedelta(hours=8))

def extract_entities(text):
    """从报告中提取实体候选（启发式·后续可升级为LLM抽取）"""
    entities = set()
    # 公司名模式
    for m in re.finditer(r'(?:公司|企业|集团)[：:]\s*([^\s，,。\n]+)', text):
        entities.add(('company', m.group(1)))
    # 人名模式
    for m in re.finditer(r'(?:创始人|CEO|总裁|教授)[：:]*\s*([^\s，,。\n]{2,4})', text):
        entities.add(('person', m.group(1)))
    # 技术/产品
    for m in re.finditer(r'(?:模型|系统|平台)[：:]*\s*([A-Za-z][^\s，,。\n]+)', text):
        entities.add(('technology', m.group(1)))
    return [{'type': t, 'name': n, 'id': f'{t}:cn:{n}'} for t, n in entities]

def extract_candidate_facts(text):
    """提取候选事实（简版：找包含数字+单位的句子）"""
    facts = []
    for m in re.finditer(r'([^。\n]{10,80}(?:[0-9,.]+(?:亿|万|%|吨|家|年))[^。\n]{10,80})[。\n]', text):
        facts.append(m.group(1).strip())
    return facts[:20]  # 最多20条

def generate(report_path):
    text = open(report_path, 'r', encoding='utf-8').read()
    title = (re.search(r'^#\s+(.+)$', text, re.MULTILINE) or [None, report_path])[1]
    now = datetime.now(CST).isoformat()

    manifest = {
        'report_id': os.path.basename(report_path).replace('.md', ''),
        'title': title,
        'generated_at': now,
        'entities': extract_entities(text),
        'candidate_facts': extract_candidate_facts(text),
        'candidate_facts_count': len(extract_candidate_facts(text)),
        'has_mermaid': '```mermaid' in text,
        'has_unicode': bool(re.search(r'[★🔴🟠🟡✅⚠️⏳π₀]', text)),
        'has_wide_tables': False,  # 待实现：检测>4列表格
        'pending_actions': {
            'graph_sync': True,
            'benchmark_update': False,
            'decision_ledger': True,
        },
        'status': 'pending_review'
    }
    return manifest

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法: manifest.py <报告.md>", file=sys.stderr)
        sys.exit(1)

    report_path = sys.argv[1]
    manifest = generate(report_path)

    # 输出到报告同级目录
    out = report_path.replace('.md', '.manifest.yaml')
    with open(out, 'w', encoding='utf-8') as f:
        yaml.dump(manifest, f, allow_unicode=True, default_flow_style=False)

    # 终端提醒
    pending = manifest['pending_actions']
    actions = [k for k, v in pending.items() if v]
    print(f"[TRIO Manifest] {manifest['report_id']}")
    print(f"  实体: {len(manifest['entities'])} 个")
    print(f"  候选事实: {manifest['candidate_facts_count']} 条")
    print(f"  待处理: {', '.join(actions)}")
    if manifest['has_mermaid']:
        print(f"  [!] 含Mermaid图 — HTML版保留·PDF版已降级")
