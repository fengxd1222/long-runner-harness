#!/bin/bash
# dispatch.sh v4.0 - Skills 调度器脚本（简化版）
# 调用 long-runner-dispatch.sh 统一脚本
# 保留此文件作为快捷入口

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH_SCRIPT="$HOME/.claude/scripts/long-runner-dispatch.sh"

if [ -f "$DISPATCH_SCRIPT" ]; then
    exec bash "$DISPATCH_SCRIPT" "$@"
else
    echo "[ERROR] Main dispatch script not found: $DISPATCH_SCRIPT"
    echo "Please ensure ~/.claude/scripts/long-runner-dispatch.sh exists."
    exit 1
fi
