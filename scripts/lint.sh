#!/bin/bash
# TRIO 3.0 代码质量检查——Shell+Python+JSON 三合一
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRIO_ROOT="$(dirname "$SCRIPT_DIR")"
PASS=0; FAIL=0

echo "=== Lint: $(date +%H:%M) ==="

# Shell
for f in "$SCRIPT_DIR"/*.sh; do
    if shellcheck -s bash -e SC2086,SC2034 "$f" 2>/dev/null; then
        PASS=$((PASS+1))
    else
        echo "  ❌ shellcheck: $(basename $f)"
        FAIL=$((FAIL+1))
    fi
done

# Python（覆盖 scripts/ + core/——2026-08-14 修复：validator.py 曾不进编译路径导致运行时 bug 漏检）
for f in "$SCRIPT_DIR"/*.py "$TRIO_ROOT"/core/*.py; do
    if python3 -m py_compile "$f" 2>/dev/null; then
        PASS=$((PASS+1))
    else
        echo "  ❌ syntax: ${f#$TRIO_ROOT/}"
        FAIL=$((FAIL+1))
    fi
done

# JSON
for f in "$TRIO_ROOT/config/protocols"/*.json; do
    if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
        PASS=$((PASS+1))
    else
        echo "  ❌ json: $(basename $f)"
        FAIL=$((FAIL+1))
    fi
done

echo "  $PASS pass / $FAIL fail"
[ $FAIL -eq 0 ] && exit 0 || exit 1
