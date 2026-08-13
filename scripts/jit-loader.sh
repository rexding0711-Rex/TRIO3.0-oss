#!/bin/bash
# TRIO 3.0 JIT Schema Loader——从引擎 JSON 的 jit_schemas 字段按需加载
# 用法: source jit-loader.sh <engine_json_path>
set -uo pipefail
ENGINE_JSON="${1:?需要引擎 JSON 路径}"
TRIO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"

SCHEMAS=$(python3 -c "import json,sys; e=json.load(open(sys.argv[1])); eng=e.get('engine',{}); schemas=eng.get('jit_schemas', e.get('jit_schemas',[])); print('\n'.join(schemas))" "$ENGINE_JSON" 2>/dev/null)

if [ -z "$SCHEMAS" ]; then
    echo "[JIT] 引擎无 jit_schemas 字段——跳过" >&2
    exit 0
fi

echo "[JIT] 加载 Schema..." >&2
: > /tmp/jit-context.md  # 确保文件存在
for schema in $SCHEMAS; do
    if [ -f "$TRIO_ROOT/$schema" ]; then
        cat "$TRIO_ROOT/$schema" >> /tmp/jit-context.md 2>/dev/null
        echo "  ✅ $schema" >&2
    fi
done
echo "[JIT] $(wc -c < /tmp/jit-context.md 2>/dev/null || echo 0) bytes loaded" >&2
