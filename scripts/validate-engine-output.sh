#!/bin/bash
# ============================================================================
# validate-engine-output.sh
# TRIO 3.0 引擎输出硬阻断验证器
# 用法: ./validate-engine-output.sh <raw-output.json> [--strict]
# 退出码: 0=全部通过  1=部分通过(降级输出)  2=全部失败(空输出)
# ============================================================================
set -uo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'

if [ $# -lt 1 ]; then
    echo -e "${RED}[BLOCK] 用法: $0 <raw-output.json> [--strict]${NC}"
    exit 2
fi

RAW_FILE="$1"
STRICT_MODE=false
[ "${2:-}" = "--strict" ] && STRICT_MODE=true

OUTPUT_DIR=$(dirname "$RAW_FILE")
VALIDATED_FILE="${OUTPUT_DIR}/validated-output.json"
VALIDATION_LOG="${OUTPUT_DIR}/validation-log.txt"

if [ ! -f "$RAW_FILE" ]; then
    echo -e "${RED}[BLOCK] 文件不存在: $RAW_FILE${NC}"
    echo '{}' > "$VALIDATED_FILE"; exit 2
fi

if ! jq empty "$RAW_FILE" 2>/dev/null; then
    echo -e "${RED}[BLOCK] JSON 格式无效: $RAW_FILE${NC}"
    echo '{}' > "$VALIDATED_FILE"; exit 2
fi

declare -A REQUIRED_FIELDS=(
    ["calculation_process"]=".scoring.calculation_process"
    ["signal_coverage"]=".scoring.signal_coverage"
    ["brake_check"]=".brake_check"
    ["formula_expansion"]=".scoring.formula_expansion"
    ["engine_version"]=".meta.engine_version"
)

declare -A FIELD_DESCRIPTIONS=(
    ["calculation_process"]="评分计算过程（必须展示公式展开）"
    ["signal_coverage"]="信号覆盖率（N/6 类信号标注）"
    ["brake_check"]="刹车检查结果（信号不足时是否拦截）"
    ["formula_expansion"]="评分公式展开"
    ["engine_version"]="引擎版本号"
)

PASS_COUNT=0; FAIL_COUNT=0; FAIL_FIELDS=(); VALIDATED_JSON="{}"

echo "=== TRIO 3.0 引擎输出验证 $(date +'%Y-%m-%d %H:%M:%S') ===" | tee "$VALIDATION_LOG"
echo " 输入: $RAW_FILE | 模式: $([ "$STRICT_MODE" = true ] && echo '严格' || echo '降级')" | tee -a "$VALIDATION_LOG"

for field in "${!REQUIRED_FIELDS[@]}"; do
    json_path="${REQUIRED_FIELDS[$field]}"
    description="${FIELD_DESCRIPTIONS[$field]}"
    value=$(jq -r "$json_path // empty" "$RAW_FILE" 2>/dev/null || true)

    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo -e "${RED}[FAIL] $field${NC} — $description" | tee -a "$VALIDATION_LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_FIELDS+=("$field"); continue
    fi

    if [ "$field" = "signal_coverage" ] && ! echo "$value" | grep -qE '^[0-6]/6$'; then
        echo -e "${YELLOW}[FORMAT] $field${NC} — 应为 N/6，实际: $value" | tee -a "$VALIDATION_LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_FIELDS+=("$field"); continue
    fi

    if [ "$field" = "calculation_process" ] && ! echo "$value" | grep -qE '[×x*+÷/=]'; then
        echo -e "${YELLOW}[SHALLOW] $field${NC} — 未检测到计算符号" | tee -a "$VALIDATION_LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_FIELDS+=("$field"); continue
    fi

    if [ "$field" = "brake_check" ] && ! echo "$value" | grep -qE '(通过|阻断|PASS|BLOCK|继续|中止|should_brake)'; then
        echo -e "${YELLOW}[STRUCT] $field${NC} — 缺少结构化判断" | tee -a "$VALIDATION_LOG"
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_FIELDS+=("$field"); continue
    fi

    echo -e "${GREEN}[PASS] $field${NC}" | tee -a "$VALIDATION_LOG"
    PASS_COUNT=$((PASS_COUNT + 1))
    VALIDATED_JSON=$(echo "$VALIDATED_JSON" | jq --arg key "$field" --arg val "$value" '. + {($key): $val}')
done

TOTAL=${#REQUIRED_FIELDS[@]}
echo " 结果: $PASS_COUNT/$TOTAL 通过 | $FAIL_COUNT/$TOTAL 失败" | tee -a "$VALIDATION_LOG"

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}[FULL PASS] validated-output.json 已生成${NC}" | tee -a "$VALIDATION_LOG"
    cp "$RAW_FILE" "$VALIDATED_FILE"
    jq --arg ts "$(date -Iseconds)" --arg status "FULL_PASS" \
        '. + {_validation: {timestamp: $ts, status: $status, fields_passed: 5, fields_total: 5}}' \
        "$VALIDATED_FILE" > "${VALIDATED_FILE}.tmp" && mv "${VALIDATED_FILE}.tmp" "$VALIDATED_FILE"
    exit 0
elif [ "$STRICT_MODE" = true ]; then
    echo -e "${RED}[BLOCK] 严格模式：${FAIL_COUNT}字段失败 → 流水线中断${NC}" | tee -a "$VALIDATION_LOG"
    echo -e "${RED}  缺失: ${FAIL_FIELDS[*]}${NC}" | tee -a "$VALIDATION_LOG"
    jq -n --arg ts "$(date -Iseconds)" --arg fails "${FAIL_FIELDS[*]}" \
        '{_validation: {timestamp: $ts, status: "BLOCKED", missing_fields: ($fails | split(" ")), message: "流水线已阻断——修复缺失字段后重新运行引擎"}}' \
        > "$VALIDATED_FILE"
    exit 2
else
    echo -e "${YELLOW}[DEGRADE] 降级输出：${PASS_COUNT}/${TOTAL}字段${NC}" | tee -a "$VALIDATION_LOG"
    echo "$VALIDATED_JSON" | jq --arg ts "$(date -Iseconds)" --arg fails "${FAIL_FIELDS[*]}" \
        --argjson passed "$PASS_COUNT" --argjson total "$TOTAL" \
        '. + {_validation: {timestamp: $ts, status: "DEGRADED", fields_passed: $passed, fields_total: $total, missing_fields: ($fails | split(" ")), warning: "本次输出不完整——缺失字段的结论不可引用"}}' \
        > "$VALIDATED_FILE"
    exit 1
fi
