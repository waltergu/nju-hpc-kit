#!/usr/bin/env bash
# start-session.sh — 校外网模式：建立持久会话（人工完成密码+两步认证）
#
# 机制：本地 ssh 进程的标准口接命名管道 CMD_FIFO，远程跑一个逐行
# 读取并执行命令的循环。run-session.sh 往 FIFO 写一行，远程执行，
# 输出经 ssh 带回并追加进 OUT_LOG。
set -euo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$KIT_DIR/hpc.conf"
source "$CONF"

SESSION_DIR="$KIT_DIR/.session"
CMD_FIFO="$SESSION_DIR/commands.fifo"
OUT_LOG="$SESSION_DIR/output.log"
PID_FILE="$SESSION_DIR/ssh.pid"

mkdir -p "$SESSION_DIR"
[ -p "$CMD_FIFO" ] || mkfifo "$CMD_FIFO"
: > "$OUT_LOG"

if [ -s "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "会话已存在（pid=$(cat "$PID_FILE")），无需重复建立。" >&2
    exit 0
fi

echo "即将连接 $ENTRY_HOST（用户 $HPC_USER）。"
echo "请在提示后输入集群密码和两步认证码。"
ssh -tt "$SSH_ALIAS_ENTRY" 'bash -s' < "$CMD_FIFO" >> "$OUT_LOG" 2>&1 &
ssh_pid=$!
echo "$ssh_pid" > "$PID_FILE"

sleep 3
if ! kill -0 "$ssh_pid" 2>/dev/null; then
    rm -f "$PID_FILE"
    echo "会话建立失败（认证未通过或网络不可达）。" >&2
    exit 1
fi
echo "会话已建立（pid=$ssh_pid），可用 run-session.sh 执行命令。"

# 自愈步骤：确保 login 节点上用户态 sshd 在跑、本机公钥已授权。
# 这样 campus 模式（校内网/VPN 免密直连）在节点重启后也能恢复。
pub_file="$KEY_FILE.pub"
[ -f "$pub_file" ] || pub_file="$HOME/.ssh/nju_hpc_auto.pub"
if [ -f "$pub_file" ]; then
    pub="$(base64 -w0 "$pub_file")"
    bash "$KIT_DIR/send-file.sh" "$KIT_DIR/ensure-userland.sh" "\$HOME/.ensure-userland.sh" >/dev/null 2>&1 || true
    out="$(bash "$KIT_DIR/run-session.sh" "PUB_B64='$pub' PORT='$USERLAND_PORT' bash \$HOME/.ensure-userland.sh" 2>/dev/null || true)"
    printf '%s\n' "$out" | grep -q USERLAND_OK \
        || echo "（自愈步骤未成功；campus 模式可能不可用，校外网模式不受影响。）" >&2
    # 把自愈报告的实际端口与最新校园网 IP 回写 hpc.conf
    newport="$(printf '%s\n' "$out" | sed -n 's/.*USERLAND_OK port=\([0-9][0-9]*\).*/\1/p' | tail -1)"
    [ -n "$newport" ] && sed -i "s/^USERLAND_PORT=.*/USERLAND_PORT='$newport'/" "$CONF" 2>/dev/null || true
    ip="$(bash "$KIT_DIR/run-session.sh" 'hostname -I' 2>/dev/null | tr " " "\n" | grep -E "^210\.28\." | head -1)"
    if [ -n "$ip" ] && ! grep -q "^LOGIN_IP='$ip'" "$CONF"; then
        sed -i "s/^LOGIN_IP=.*/LOGIN_IP='$ip'/" "$CONF" 2>/dev/null || true
    fi
fi

echo "注意：闲置约 8 小时会被网关断开；断开后重新运行本脚本即可。"
