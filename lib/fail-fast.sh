#!/usr/bin/env bash
# ============================================================
# 死端点快速失败（magi 吸收 P0-3）
# 网络端点失败时快速分类：死端点立即失败，不烧重试预算
# 用法: source lib/fail-fast.sh
# ============================================================

# 检查端口连通性：返回 0=通，1=死端点(快速失败)，2=超时(可重试)
fail_fast_port() {
  local host="$1" port="$2" timeout_s="${3:-3}"
  if ! command -v timeout >/dev/null 2>&1; then
    # 无 timeout 命令的环境退化用 /dev/tcp 直连
    bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null && return 0 || return 1
    return
  fi
  timeout "$timeout_s" bash -c "echo > /dev/tcp/$host/$port" 2>/dev/null
  case $? in
    0)   return 0 ;;   # 通
    124) return 2 ;;   # 超时（网络抖动，可重试）
    *)   return 1 ;;   # 死端点（DNS失败/拒连/无效），快速失败
  esac
}

# 检查 DNS 解析：返回 0=可解析，1=死
fail_fast_dns() {
  local host="$1"
  getent hosts "$host" >/dev/null 2>&1 && return 0 || return 1
}

# 错误类型是否值得重试（对齐 magi retryable 分类）
# 可重试: timeout/rate_limit/server_error/model_unavailable/network
# 快速失败: auth/bad_request/dns/connection_refused/invalid_url
fail_fast_is_retryable() {
  local err_type="$1"
  case "$err_type" in
    timeout|rate_limit|server_error|model_unavailable|network) return 0 ;;
    auth|bad_request|dns|connection_refused|invalid_url) return 1 ;;
    *) return 1 ;;
  esac
}

# 快速失败包装：命令失败时按错误类型决定是否建议重试
# 用法: fail_fast_run "错误类型" 命令...
fail_fast_run() {
  local err_type="$1"; shift
  if ! "$@"; then
    if fail_fast_is_retryable "$err_type"; then
      echo "⚠️ 失败类型[$err_type]可重试——按指数退避重试" >&2
      return 2
    fi
    echo "🚫 失败类型[$err_type]为死端点——快速失败，不重试" >&2
    return 1
  fi
  return 0
}
