#!/usr/bin/env bash
# ============================================================
# trio-record.sh — TRIO 会话/分析自动落库
# 让「自动记录 run + decision」成为可执行动作（取代纸面规则）
# 用法: trio-record.sh --run "<任务类型>" --id "<run_id>" [--score N] [--note "..."]
#       或 AI 在完成正式分析后调用，自动写 run-history + decision-log
# ============================================================
set -euo pipefail

# 动态推导（config/paths.conf 纪律：禁止硬编码绝对路径，已修）
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_HISTORY="$ROOT/state/run-history.jsonl"
DECISION_LOG="$ROOT/state/decision-log.jsonl"
TODAY=$(TZ=Asia/Shanghai date +%Y-%m-%d)
NOW=$(TZ=Asia/Shanghai date +%Y-%m-%dT%H:%M:%S%z)

# 解析参数
RUN_TYPE=""
RUN_ID=""
SCORE=""
NOTE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) RUN_TYPE="$2"; shift 2;;
    --id) RUN_ID="$2"; shift 2;;
    --score) SCORE="$2"; shift 2;;
    --note) NOTE="$2"; shift 2;;
    *) echo "❌ 未知参数: $1"; exit 1;;
  esac
done

if [ -z "$RUN_TYPE" ]; then
  echo "❌ 用法: trio-record.sh --run '<任务类型>' [--id '<run_id>'] [--score N] [--note '...']"
  exit 1
fi

# 默认 run_id（python 生成安全 id，避免中文被 tr 删光）
if [ -z "$RUN_ID" ]; then
  RUN_ID=$(python3 -c "
import hashlib, sys
t = sys.argv[1] or 'run'
h = hashlib.md5(t.encode()).hexdigest()[:6]
print(f'run-{h}')
" "$RUN_TYPE")
fi

# ── 1. 写 run-history ──
export TRIO_RUN_HISTORY="$RUN_HISTORY"
python3 - "$RUN_ID" "$TODAY" "$RUN_TYPE" "$SCORE" "$NOTE" << 'PYEOF'
import json, os, sys
run_id, date, task_type, score, note = sys.argv[1:6]
record = {
    "run_id": run_id,
    "date": date,
    "task_type": task_type,
    "engines": [],
    "eval_score_client": int(score) if score else 0,
    "eval_score_timeliness": 0,
    "eval_score_audit": 0,
    "eval_score_external": 0,
    "improvement_bonus": 0,
    "composite_score": float(score) if score else 0,
    "post_mortem": note or "",
}
with open(os.environ["TRIO_RUN_HISTORY"], "a", encoding="utf-8") as f:
    f.write(json.dumps(record, ensure_ascii=False) + "\n")
print(f"✅ run-history 记录: {run_id} | {task_type} | score={score or 'n/a'}")
PYEOF

# ── 2. 写 decision-log（主判断） ──
export TRIO_DECISION_LOG="$DECISION_LOG"
python3 - "$RUN_ID" "$RUN_TYPE" "$NOTE" "$NOW" << 'PYEOF'
import json, os, sys
run_id, task_type, note, ts = sys.argv[1:5]
record = {
    "ts": ts,
    "persona": "trio",
    "claim_type": "run_completion",
    "claim": f"完成 {task_type} 分析",
    "confidence": 3,
    "basis": note or "",
    "upstream": run_id,
    "id": f"trio-{ts[:10]}-{abs(hash(run_id)) % 10000:04d}",
}
with open(os.environ["TRIO_DECISION_LOG"], "a", encoding="utf-8") as f:
    f.write(json.dumps(record, ensure_ascii=False) + "\n")
print(f"✅ decision-log 记录: {run_id}")
PYEOF

echo "📝 已落库: $RUN_ID ($TODAY) — $RUN_TYPE"
