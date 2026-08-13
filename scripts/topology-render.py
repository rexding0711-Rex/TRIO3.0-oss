#!/usr/bin/env python3
# TRIO 3.0 拓扑图渲染器 v1.0
# 从 topology-state.json → Mermaid 5阶段图
import json, sys

COLORS = {
    "founder": "fill:#ff6b6b,stroke:#ff0000,color:#fff",
    "core":    "fill:#1a1a2e,stroke:#e94560,color:#fff",
    "risk":    "fill:#e74c3c,stroke:#c0392b,color:#fff",
    "growth":  "fill:#0f3460,stroke:#2ecc71,color:#fff",
    "rival":   "fill:#f39c12,stroke:#e67e22,color:#fff",
    "dead":    "fill:#95a5a6,stroke:#7f8c8d,color:#fff",
    "future":  "fill:#8e44ad,stroke:#9b59b6,color:#fff",
    "unknown": "fill:#ecf0f1,stroke:#999,color:#333,stroke-dasharray:5 5",
}

def render(data):
    nodes = {}
    for entry in data.get("n", []):
        parts = entry.split("|")
        nid = parts[0].strip()
        label = parts[1].strip() if len(parts) > 1 else nid
        ntype = parts[2].strip() if len(parts) > 2 else "core"
        phase = int(parts[3]) if len(parts) > 3 else 0
        nodes[nid] = {"label": label, "type": ntype, "phase": phase}

    lines = ["```mermaid", "flowchart LR"]

    # classDefs
    for t, style in COLORS.items():
        used = any(n["type"] == t for n in nodes.values())
        if used:
            lines.append(f"    classDef {t} {style}")

    # nodes grouped by type
    for nid, n in nodes.items():
        is_unknown = n["type"] == "unknown"
        prefix = "?" if is_unknown else ""
        display_id = nid.lstrip("?")
        lines.append(f"    {display_id}[{n['label']}]:::{n['type']}")

    # edges
    for entry in data.get("e", []):
        parts = entry.split(":")
        path = parts[0]  # FROM>TO
        label = parts[1] if len(parts) > 1 else ""
        conf = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 3
        dashed = len(parts) > 3 and "d" in parts[3]

        frm, to = path.split(">")
        frm = frm.lstrip("?")
        to = to.lstrip("?")

        arrow = "-.->" if (dashed or conf <= 2) else "-->"
        lbl = f"|{label}|" if label else ""
        lines.append(f"    {frm} {arrow}{lbl} {to}")

    # phase insights
    ph = data.get("ph", {})
    for pkey in ["0","1","2","3","4"]:
        if pkey in ph:
            rf = ph[pkey].get("rf", "")
            if rf:
                lines.append(f"    %% Phase {pkey} insight: {rf}")

    lines.append("```")
    return "\n".join(lines)


def render_phase(data, phase_key):
    """渲染单个Phase的快照"""
    pn = int(phase_key)
    nodes = {}
    for entry in data.get("n", []):
        parts = entry.split("|")
        if len(parts) > 3 and int(parts[3]) <= pn:
            nid = parts[0].strip().lstrip("?")
            nodes[nid] = parts[1].strip() if len(parts) > 1 else nid

    edges = []
    for entry in data.get("e", []):
        parts = entry.split(":")
        ep = int(parts[4]) if len(parts) > 4 and parts[4].isdigit() else 0
        if ep <= pn:
            path = parts[0]
            frm, to = path.split(">")
            frm = frm.lstrip("?")
            to = to.lstrip("?")
            label = parts[1] if len(parts) > 1 else ""
            conf = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 3
            dashed = len(parts) > 3 and "d" in parts[3]
            edges.append((frm, to, label, dashed or conf <= 2))

    return nodes, edges


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python topology-render.py <topology-state.json> [--phase N]")
        print("  --phase N  只渲染第N阶段快照")
        sys.exit(1)

    with open(sys.argv[1]) as f:
        data = json.load(f)

    if "--phase" in sys.argv:
        idx = sys.argv.index("--phase")
        pkey = sys.argv[idx + 1]
        print(render_phase_snapshot(data, pkey))
    else:
        print(render(data))
