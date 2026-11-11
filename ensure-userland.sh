#!/usr/bin/env bash
# ensure-userland.sh — 在 login 节点上自愈用户态 sshd（campus 模式的通道）
# 由 start-session.sh / setup.sh 通过 run-session.sh 发送到集群执行。
# 环境变量: PORT（期望端口，可为空）, PUB_B64（本机公钥的 base64）
#
# 端口策略：
#   1) 配置端口上已有自己的 sshd 在跑 → 保留，不重启（不打断现有连接）；
#   2) 配置端口空闲 → 沿用；
#   3) 期望端口（hpc.conf）空闲 → 采用（= 用户想换端口）；
#   4) 否则在 20000–59999 随机找空闲端口（被他人占用时的让位）。
# 仅在没有 sshd 或端口变化时才重启服务。
# 输出最后一行: USERLAND_OK port=<N>  （调用方据此回本机 hpc.conf）
set -euo pipefail
PORT="${PORT:-}"
PUB_B64="${PUB_B64:?need PUB_B64}"

port_owner_pid() {
    ss -tlnp 2>/dev/null | grep ":$1 " | grep -oP 'pid=\K[0-9]+' | head -1
}
port_free() { [ -z "$(port_owner_pid "$1")" ]; }
is_our_sshd_port() {  # 端口被占用且占用者是自己的 sshd 进程
    local pid
    pid="$(port_owner_pid "$1")"
    [ -n "$pid" ] || return 1
    [ "$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')" = "sshd" ] || return 1
    [ "$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')" = "$USER" ]
}

resolve_port() {
    local cfg=""
    if [ -f ~/.sshd/sshd_config ]; then
        cfg="$(grep -E '^Port[[:space:]]' ~/.sshd/sshd_config | awk '{print $2}' | head -1)"
    fi
    if [ -n "$cfg" ]; then
        if is_our_sshd_port "$cfg" || port_free "$cfg"; then echo "$cfg"; return; fi
    fi
    if [ -n "$PORT" ] && port_free "$PORT"; then echo "$PORT"; return; fi
    local p
    for _ in $(seq 1 50); do
        p=$((RANDOM % 40000 + 20000))
        if port_free "$p"; then echo "$p"; return; fi
    done
    echo "NO_FREE_PORT" >&2
    exit 1
}

PORT="$(resolve_port)"

mkdir -p ~/.ssh ~/.sshd
chmod 700 ~/.ssh; chmod 755 ~
touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys
key="$(printf '%s' "$PUB_B64" | base64 -d)"
grep -qF "$key" ~/.ssh/authorized_keys || echo "$key" >> ~/.ssh/authorized_keys

[ -f ~/.sshd/ssh_host_rsa_key ] || ssh-keygen -t rsa -f ~/.sshd/ssh_host_rsa_key -N '' -q
printf 'Port %s\nListenAddress 0.0.0.0\nHostKey ~/.sshd/ssh_host_rsa_key\nPasswordAuthentication no\nChallengeResponseAuthentication no\nUsePAM yes\nPrintMotd no\nSubsystem sftp internal-sftp\n' \
    "$PORT" > ~/.sshd/sshd_config

need_restart=1
if is_our_sshd_port "$PORT"; then
    # 服务健康且端口一致：仅校验配置内容是否需要生效
    if printf 'Port %s\n' "$PORT" | cmp -s - <(head -1 ~/.sshd/sshd_config) 2>/dev/null; then
        need_restart=0
    fi
fi

if [ "$need_restart" = "1" ]; then
    pkill -u "$USER" -x sshd 2>/dev/null || true
    sleep 1
    nohup /usr/sbin/sshd -f ~/.sshd/sshd_config >/dev/null 2>&1 &
    sleep 1
fi

if is_our_sshd_port "$PORT"; then
    echo "USERLAND_OK port=$PORT"
else
    echo "USERLAND_FAIL port=$PORT" >&2
    exit 1
fi
