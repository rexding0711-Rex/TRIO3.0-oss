#!/bin/bash
# TRIO 平台抽象层——自动检测系统类型
# 所有脚本 source 此文件后使用 $TRIO_HOME 替代硬编码路径

case "$(uname -s)" in
    Linux*)
        # WSL检测
        if grep -qi microsoft /proc/version 2>/dev/null; then
            TRIO_PLATFORM="wsl"
            TRIO_HOME="${TRIO_HOME:-$HOME}"
            TRIO_DB="${TRIO_DB:-/mnt/d/工作}"
        else
            TRIO_PLATFORM="linux"
            TRIO_HOME="${TRIO_HOME:-$HOME}"
            TRIO_DB="${TRIO_DB:-$HOME/TRIO-data}"
        fi
        ;;
    Darwin*)
        TRIO_PLATFORM="macos"
        TRIO_HOME="${TRIO_HOME:-$HOME}"
        TRIO_DB="${TRIO_DB:-$HOME/TRIO-data}"
        ;;
    MINGW*|MSYS*)
        TRIO_PLATFORM="windows"
        TRIO_HOME="${TRIO_HOME:-$USERPROFILE}"
        TRIO_DB="${TRIO_DB:-D:/TRIO-data}"
        ;;
    *)
        TRIO_PLATFORM="unknown"
        TRIO_HOME="${TRIO_HOME:-$HOME}"
        TRIO_DB="${TRIO_DB:-$HOME/TRIO-data}"
        ;;
esac

export TRIO_PLATFORM TRIO_HOME TRIO_DB
