#!/usr/bin/env bash
# run-session.sh '<远程命令>' — 在集群上执行命令，自动选择网络模式
# 退出码 = 远程命令的退出码；stdout/stderr 原样带回（不含内部标记）。
set -euo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$KIT_DIR/hpc.conf"

[ $# -ge 1 ] || { echo "用法: run-session.sh '<远程命令>'" >&2; exit 2; }
remote_cmd="$1"

MODE="$(bash "$KIT_DIR/detect-net.sh" 2>/dev/null || echo none)"

if [ "$MODE" = "campus" ]; then
    payload="$(printf '%s' "$remote_cmd" | base64 -w0)"
    ssh -o BatchMode=yes -p "$USERLAND_PORT" -i "$KEY_FILE" \
        -o StrictHostKeyChecking=accept-new "$HPC_USER@$LOGIN_IP" \
        '__p='"$payload"'; bash -c "$(printf %s "$__p" | base64 -d)"'
    exit $?
fi

if [ "$MODE" = "offcampus" ]; then
    SESSION_DIR="$KIT_DIR/.session"
    CMD_FIFO="$SESSION_DIR/commands.fifo"
    OUT_LOG="$SESSION_DIR/output.log"
    PID_FILE="$SESSION_DIR/ssh.pid"

    if [ ! -p "$CMD_FIFO" ] || [ ! -s "$PID_FILE" ] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        cat >&2 <<EOF
校外网会话不存在或已断开。
请用户运行： bash $KIT_DIR/start-session.sh
完成密码 + 两步认证后，再重新执行本命令。
EOF
        exit 2
    fi

    id="$(date +%s%N)_${RANDOM}"
    begin="__KIMI_BEGIN_${id}__"
    end="__KIMI_END_${id}__"
    offset="$(wc -c < "$OUT_LOG")"
    payload="$(printf '%s' "$remote_cmd" | base64 -w0)"
    inner='__p='"$payload"'; bash -c "$(printf %s "$__p" | base64 -d)"'
    line="printf '%s\\n' '$begin'; ( $inner ); __rc=\$?; printf '%s\\n' '${end}':\$__rc"
    printf '%s\n' "$line" > "$CMD_FIFO"

    for _ in $(seq 1 30); do
        if tail -c +$((offset + 1)) "$OUT_LOG" 2>/dev/null | grep -qF "$end"; then
            break
        fi
        kill -0 "$(cat "$PID_FILE")" 2>/dev/null || { echo "命令执行中会话断开。" >&2; exit 2; }
        sleep 1
    done
    if ! tail -c +$((offset + 1)) "$OUT_LOG" 2>/dev/null | grep -qF "$end"; then
        echo "同步命令等待超时（30s）。" >&2
        exit 124
    fi
    new_output="$(awk -v b="$begin" -v e="$end" '
        index($0, b) { found = 1; next }
        index($0, e) { found = 0; line = $0 }
        found { print }
        END { sub(/.*:/, "", line); printf "%s", line > "/dev/stderr" }
    ' <(tail -c +$((offset + 1)) "$OUT_LOG") 2> "$SESSION_DIR/.rc")"
    rc="$(cat "$SESSION_DIR/.rc")"
    printf '%s\n' "$new_output"
    exit "${rc:-0}"
fi

echo "网络不可用（既非校内网，网关也不可达）。请检查网络或 VPN。" >&2
exit 1
