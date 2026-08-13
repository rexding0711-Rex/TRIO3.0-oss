# TRIO state 目录（生成文件，勿手编）

> 由 `scripts/state-catalog.py` 扫描 `state/*.jsonl` 实际 schema 生成。
> 变更 state 写入后运行 `python3 scripts/state-catalog.py` 重新生成并提交。

## 概览

| 文件 | 格式 | 漂移行 | 坏行 |
|------|------|--------|------|
| `behavior-log.jsonl` | jsonl | 0 | 0 |
| `credit-log.jsonl` | jsonl | 0 | 0 |
| `decision-log.jsonl` | jsonl | 50 | 0 |
| `memory-weights.psv` | pipe | 0 | 0 |
| `run-history.jsonl` | jsonl | 0 | 0 |
| `topology-scores.jsonl` | jsonl | 0 | 0 |

## `behavior-log.jsonl`

| 字段 | 覆盖 |
|------|------|
| `event` | 全覆盖 |
| `note` | 全覆盖 |
| `ts` | 全覆盖 |

## `credit-log.jsonl`

| 字段 | 覆盖 |
|------|------|
| `analysis_id` | 全覆盖 |
| `category` | 全覆盖 |
| `claim` | 全覆盖 |
| `confidence` | 全覆盖 |
| `id` | 全覆盖 |
| `mask` | 全覆盖 |
| `review_due` | 全覆盖 |
| `status` | 全覆盖 |
| `timestamp` | 全覆盖 |

## `decision-log.jsonl`

| 字段 | 覆盖 |
|------|------|
| `basis` | 全覆盖 |
| `claim` | 全覆盖 |
| `claim_type` | 全覆盖 |
| `confidence` | 全覆盖 |
| `persona` | 全覆盖 |
| `ts` | 全覆盖 |
| `id` | 部分(158/183) |
| `upstream` | 部分(158/183) |
| `verification` | 部分(25/183) |
| `counter_evidence` | 部分(12/183) |
| `expiry_date` | 部分(9/183) |
| `falsification_date` | 部分(9/183) |
| `prediction_contract` | 部分(9/183) |
| `verification_date` | 部分(7/183) |
| `actual_outcome` | 部分(6/183) |

⚠️ 50 行字段集与多数行不一致。
   独有字段（多为合法演进，需核对是否 schema 预期）：`verification`×25、`counter_evidence`×12、`expiry_date`×9、`falsification_date`×9、`prediction_contract`×9、`verification_date`×7、`actual_outcome`×6

## `memory-weights.psv`

`pipe` 分隔格式，扩展名匹配。

## `run-history.jsonl`

| 字段 | 覆盖 |
|------|------|
| `composite_score` | 全覆盖 |
| `date` | 全覆盖 |
| `engines` | 全覆盖 |
| `eval_score_audit` | 全覆盖 |
| `eval_score_client` | 全覆盖 |
| `eval_score_external` | 全覆盖 |
| `eval_score_timeliness` | 全覆盖 |
| `improvement_bonus` | 全覆盖 |
| `post_mortem` | 全覆盖 |
| `run_id` | 全覆盖 |
| `task_type` | 全覆盖 |

## `topology-scores.jsonl`

| 字段 | 覆盖 |
|------|------|
| `domain` | 全覆盖 |
| `fails` | 全覆盖 |
| `file` | 全覆盖 |
| `passed` | 全覆盖 |
| `score` | 全覆盖 |
| `timestamp` | 全覆盖 |
| `warns` | 全覆盖 |

