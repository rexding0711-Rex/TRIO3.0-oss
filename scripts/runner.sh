#!/bin/bash
# ============================================================
# 确定性场景 Runner（外部评测 C2 最小落地 · DS 单模型）
# 代码强制: 步骤顺序/状态迁移/断点恢复/可选跳过/退出码
# 模型只负责 action（DS 单模型），Runner 保证状态与门禁
# 用法: bash scripts/runner.sh <scenario.json> [--resume] [--run-id <id>]
# ============================================================
set -uo pipefail

TRIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS="$TRIO_ROOT/state/runs"
SCENARIO="${1:-}"

[ -n "$SCENARIO" ] || { echo "用法: runner.sh <scenario.json> [--resume]"; exit 1; }
[ -f "$SCENARIO" ] || { echo "❌ 场景不存在: $SCENARIO"; exit 1; }

# ── 参数解析 ──────────────────────────────────────────────
RESUME=0; RUN_ID=""
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --resume) RESUME=1; shift ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ── run 标识与状态目录 ────────────────────────────────────
if [ "$RESUME" = "1" ] && [ -n "$RUN_ID" ]; then
  RUN_DIR="$RUNS/$RUN_ID"
  [ -d "$RUN_DIR" ] || { echo "❌ run 不存在: $RUN_ID（无法恢复）"; exit 1; }
  echo "🔄 恢复 run: $RUN_ID"
else
  RUN_ID="run-$(TZ=Asia/Shanghai date +%m%d-%H%M%S)"
  RUN_DIR="$RUNS/$RUN_ID"
  mkdir -p "$RUN_DIR"
  echo "🚀 新建 run: $RUN_ID"
fi
STATE="$RUN_DIR/state.json"
[ -f "$STATE" ] || echo '{"status":"created","steps":{}}' > "$STATE"

# ── 解析场景 steps（python 输出 TSV）──────────────────────
python3 -c "
import json
d=json.load(open('$SCENARIO'))
print(f\"# {d.get('name','?')} | {d.get('id','?')} | mode={d.get('mode','?')}\")
for s in sorted(d.get('steps',[]), key=lambda x:x.get('order',999)):
    en=s.get('enable_condition','') or ''
    ac=s.get('acceptance_criteria','') or ''
    print(f\"{s.get('order')}|{s.get('mask','')}|{1 if s.get('optional') else 0}|{s.get('action','')[:90]}|{en[:40]}\")
" > "$RUN_DIR/steps.txt"

SCENE_NAME=$(head -1 "$RUN_DIR/steps.txt")
tail -n +2 "$RUN_DIR/steps.txt" > "$RUN_DIR/steps.tsv"

echo "═══ 场景 Runner: $SCENE_NAME ═══"
echo "  状态目录: $RUN_DIR"

# ── 逐步执行（代码强制顺序 + 状态 + 可选跳过）────────────
# 保存原始 stdin 到 fd3（while 读文件，read -p 读用户输入——修复 stdin 冲突）
exec 3<&0
FAIL=0
while IFS='|' read -r order mask optional action enable_cond; do
  [ -n "$order" ] || continue
  # 断点恢复：该步已完成则跳过
  STEP_STATUS=$(python3 -c "
import json
st=json.load(open('$STATE'))['steps']
print(st.get('step$order',{}).get('status',''))" 2>/dev/null)
  if [ "$STEP_STATUS" = "completed" ]; then
    echo "  ✓ Step $order 已完成（跳过）"
    continue
  fi
  # enable_condition：含"跳过/简单/可选/非复杂"提示确认
  if echo "$enable_cond" | grep -qE "跳过|简单|可选|非.*复杂"; then
    echo "  ⚪ Step $order ($mask): 条件=[$enable_cond]"
    read -u 3 -p "    启用此步？(y/回车=启用, n=跳过) " ans
    [ "$ans" = "n" ] && { python3 -c "import json; st=json.load(open('$STATE')); st['steps']['step$order']={'status':'skipped'}; json.dump(st,open('$STATE','w'))"; echo "    ⏭️  已跳过 Step $order"; continue; }
  fi
  # optional 步
  if [ "$optional" = "1" ]; then
    read -u 3 -p "  ⏭️  Step $order (optional/$mask): $action 执行？(y/回车=执行, n=跳过) " ans
    [ "$ans" = "n" ] && { python3 -c "import json; st=json.load(open('$STATE')); st['steps']['step$order']={'status':'skipped'}; json.dump(st,open('$STATE','w'))"; echo "    ⏭️  已跳过"; continue; }
  fi
  # 执行标记：in_progress → 提示模型执行
  echo "  ▶️  Step $order ($mask): $action"
  echo "     （DS 单模型：由当前会话面具执行此步 action，完成后确认）"
  read -u 3 -p "     此步完成？(y=完成, n=失败, r=标记进行中继续) " ans2
  case "${ans2:-}" in
    y|Y) STATUS="completed" ;;
    n|N) STATUS="failed"; FAIL=1 ;;
    r|R) STATUS="in_progress" ;;
    *) STATUS="completed" ;;  # 回车/未知 → 视为完成
  esac
  python3 -c "import json; st=json.load(open('$STATE')); st['steps']['step$order']={'status':'$STATUS'}; json.dump(st,open('$STATE','w'),ensure_ascii=False,indent=2)"
  echo "    → Step $order 状态: $STATUS"
done < "$RUN_DIR/steps.tsv"

# ── 收尾 ──────────────────────────────────────────────────
DONE=$(python3 -c "import json; st=json.load(open('$STATE')); print(sum(1 for s in st['steps'].values() if s['status']=='completed'))")
TOTAL=$(wc -l < "$RUN_DIR/steps.tsv")
echo ""
if [ "$FAIL" -eq 0 ] && [ "$DONE" -ge "$TOTAL" ]; then
  python3 -c "import json; st=json.load(open('$STATE')); st['status']='completed'; json.dump(st,open('$STATE','w'))"
  echo "✅ Runner 完成 ($DONE/$TOTAL 步)——状态已持久化 $STATE"
  exit 0
else
  python3 -c "import json; st=json.load(open('$STATE')); st['status']='paused'; json.dump(st,open('$STATE','w'))"
  echo "⏸️  暂停 ($DONE/$TOTAL 步完成)——可用 --resume --run-id $RUN_ID 恢复"
  exit 1
fi
