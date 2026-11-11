#!/usr/bin/env bash
# stop-session.sh — 拆除校外网持久会话
set -euo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$KIT_DIR/.session/ssh.pid"

if [ -s "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "会话已停止。"
else
    echo "没有活动会话。"
fi
