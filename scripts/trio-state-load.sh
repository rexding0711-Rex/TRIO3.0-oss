#!/bin/bash
# TRIO 状态热加载 — SessionStart Hook
# 读取 TRIO 3.0/state.json，输出关键状态摘要
# 使每次 Claude Code 会话启动时自动感知 TRIO 当前进度

STATE_FILE="/mnt/d/TRIO 3.0/state.json"

if [ ! -f "$STATE_FILE" ]; then
  echo "⚠️ TRIO state.json 不存在 — 首次运行？"
  exit 0
fi

# 用 python3 解析 JSON（更可靠的跨平台方案）
python3 - "$STATE_FILE" << 'PYEOF'
import json, sys
from datetime import datetime

with open(sys.argv[1]) as f:
    s = json.load(f)

print("📊 TRIO 3.0 状态快照")
print(f"  更新时间: {s.get('_updated', 'unknown')}")

# 里程碑
ms = s.get("milestones", {})
active = [k for k,v in ms.items() if v.get("status") in ("active_perpetual", "running")]
pending = [k for k,v in ms.items() if v.get("status") == "pending"]
print(f"  里程碑: {' | '.join([f'{k.split('_')[0]}={v['status']}' for k,v in ms.items()])}")

# 活跃训练
at = s.get("active_training", {})
if at.get("next"):
    n = at["next"]
    print(f"  🎯 下次训练: #{n['session']} — {n['dimension']} ({n['instruction'][:40]}...)")

# 待办
pa = s.get("pending_actions", [])
if pa:
    high = [p for p in pa if p["priority"] == "high"]
    print(f"  📋 高优待办: {len(high)} 项")
    for p in high:
        print(f"     - {p['action']}")

print()
PYEOF
