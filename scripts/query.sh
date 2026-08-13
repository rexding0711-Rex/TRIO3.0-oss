#!/bin/bash
# @layer: infra
# TRIO 3.0 统一查询脚本 v1.0
# 用法: bash scripts/query.sh [SQL|preset]
# 预设: timeline | stats | violations | decisions

set -euo pipefail
TRIO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="$TRIO_ROOT/state/logs.db"
INIT="$TRIO_ROOT/state/logs-queries.sql"

cd "$TRIO_ROOT"

case "${1:-stats}" in
    timeline)
        duckdb -init "$INIT" "$DB" -c "SELECT * FROM unified_timeline LIMIT ${2:-20};" 2>&1 | grep -v "^--\|^━━\|Enter\|DuckDB\|See\|Info"
        ;;
    stats)
        duckdb -init "$INIT" "$DB" -c "SELECT * FROM today_stats;" 2>&1 | grep -v "^--\|^━━\|Enter\|DuckDB\|See\|Info"
        ;;
    violations)
        duckdb -init "$INIT" "$DB" -c "SELECT * FROM topology_violations ORDER BY ts DESC;" 2>&1 | grep -v "^--\|^━━\|Enter\|DuckDB\|See\|Info"
        ;;
    decisions)
        duckdb -init "$INIT" "$DB" -c "SELECT ts, persona, claim_type, claim FROM decision_log ORDER BY ts DESC;" 2>&1 | grep -v "^--\|^━━\|Enter\|DuckDB\|See\|Info"
        ;;
    *)
        duckdb -init "$INIT" "$DB" -c "$*" 2>&1 | grep -v "^--\|^━━\|Enter\|DuckDB\|See\|Info"
        ;;
esac
