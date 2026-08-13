#!/usr/bin/env bash
# ============================================================
# trio-verify.sh — 决策验证工具（阶段二·校准对账）
# 把 decision-log 里 pending 的决策标记为 verified/falsified
# 用法:
#   trio-verify.sh list                # 列出所有 pending 决策
#   trio-verify.sh <decision-id> ok    # 标记为 verified
#   trio-verify.sh <decision-id> no "<实际结果>"  # 标记为 falsified
# 数据源: state/decision-log.jsonl
# ============================================================
set -euo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8

LOG="/mnt/d/TRIO 3.0/state/decision-log.jsonl"
TMP="/tmp/trio-verify-tmp.jsonl"

ACTION="${1:-list}"

case "$ACTION" in
  list)
    echo "📋 待验证决策（pending）:"
    python3 -c "
import json
count = 0
for l in open('$LOG', encoding='utf-8'):
    l = l.strip()
    if not l or l.startswith('#'): continue
    try:
        d = json.loads(l)
        if d.get('verification', 'pending') == 'pending':
            count += 1
            print(f'  {d.get(\"id\")} | {d.get(\"claim\",\"\")[:50]} | conf={d.get(\"confidence\")}')
    except: pass
print(f'共 {count} 条 pending')
"
    ;;
  *)
    ID="${1:-}"
    RESULT="${2:-}"
    if [ -z "$ID" ] || [ -z "$RESULT" ]; then
      echo "❌ 用法: trio-verify.sh <id> ok|no <实际结果>"
      exit 1
    fi
    ACTUAL="${3:-}"
    python3 - "$ID" "$RESULT" "$ACTUAL" "$LOG" << 'PYEOF'
import json, sys, datetime
did, result, actual, log_path = sys.argv[1:5]
rows = []
updated = False
for l in open(log_path, encoding='utf-8'):
    l = l.rstrip('\n')
    if not l or l.startswith('#'):
        rows.append(l); continue
    try:
        d = json.loads(l)
        if d.get('id') == did:
            d['verification'] = 'verified' if result == 'ok' else 'falsified'
            d['verification_date'] = datetime.date.today().isoformat()
            if actual: d['actual_outcome'] = actual
            updated = True
        rows.append(json.dumps(d, ensure_ascii=False))
    except:
        rows.append(l)
if not updated:
    print(f'❌ 未找到决策: {did}'); sys.exit(1)
with open(log_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(rows) + '\n')
print(f'✅ 决策 {did} 标记为 {result}（{'verified' if result=='ok' else 'falsified'}）')
PYEOF
    ;;
esac
