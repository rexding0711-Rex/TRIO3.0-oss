#!/usr/bin/env python3
"""
TRIO 拓扑图渲染引擎 — networkx 自动布局 + CJK 字体
用法: python topology_draw.py <config.json> <output.svg>
config.json: {"nodes":{...}, "edges":[...], "dashed":[...], "colors":{...}, "title":"..."}
"""
import sys, json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import networkx as nx

# 注册 CJK 字体
for fpath in fm.findSystemFonts():
    if 'NotoSansCJK' in fpath and 'Regular' in fpath:
        fm.fontManager.addfont(fpath)
        break
plt.rcParams['font.family'] = 'Noto Sans CJK SC'


def draw(config: dict, output: str):
    nodes = config["nodes"]
    edges = config.get("edges", [])
    dashed = config.get("dashed", [])
    title = config.get("title", "拓扑图")
    colors = config.get("colors", {})
    scale = config.get("scale", 3.5)
    figsize = config.get("figsize", [14, 10])

    G = nx.DiGraph()
    G.add_nodes_from(nodes.keys())
    G.add_edges_from(edges)
    G.add_edges_from(dashed)

    pos = nx.kamada_kawai_layout(G, scale=scale)

    fig, ax = plt.subplots(figsize=figsize)
    fig.patch.set_facecolor('#1a1a2e')
    ax.set_facecolor('#1a1a2e')

    # 虚线
    if dashed:
        nx.draw_networkx_edges(G, pos, edgelist=dashed, ax=ax,
                               edge_color='#e74c3c', style='dashed',
                               width=2.5, alpha=0.6, arrowsize=18,
                               connectionstyle='arc3,rad=0.12')
    # 实线
    solid = [(s, d) for s, d in edges if (s, d) not in dashed]
    if solid:
        nx.draw_networkx_edges(G, pos, edgelist=solid, ax=ax,
                               edge_color='#555555', style='solid',
                               width=2.5, alpha=0.75, arrowsize=18,
                               connectionstyle='arc3,rad=0.12')

    # 节点
    for node_id, (x, y) in pos.items():
        color = colors.get(node_id, '#3498db')
        circle = plt.Circle((x, y), 0.38, facecolor=color, edgecolor='white',
                            linewidth=2.5, alpha=0.93, zorder=3)
        ax.add_patch(circle)
        label = nodes.get(node_id, node_id)
        for i, line in enumerate(label.split('\n')):
            y_off = (len(label.split('\n')) - 1) * 0.07 - i * 0.14
            ax.text(x, y + y_off, line, ha='center', va='center',
                    fontsize=8, fontweight='bold', color='white', zorder=4)

    margin = scale * 1.4
    ax.set_xlim(-margin, margin)
    ax.set_ylim(-margin, margin)
    ax.axis('off')
    ax.set_title(title, fontsize=15, color='white', fontweight='bold', pad=18)

    plt.tight_layout()
    plt.savefig(output, dpi=150, bbox_inches='tight',
                facecolor='#1a1a2e', edgecolor='none')
    plt.close()
    return output


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法: python topology_draw.py <config.json> [output.svg]")
        sys.exit(1)

    with open(sys.argv[1]) as f:
        config = json.load(f)
    output = sys.argv[2] if len(sys.argv) > 2 else 'topology.svg'
    draw(config, output)
    print(f"✅ {output}")
