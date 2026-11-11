#!/usr/bin/env bash
# ensure-userland.sh — 在 login 节点上自愈用户态 sshd（campus 模式的通道）
# 由 start-session.sh / setup.sh 通过 run-session.sh 发送到集群执行。
# 环境变量: PORT（用户态 sshd 端口）, PUB_B64（本机公钥的 base64）
set -euo pipefail
PORT="${PORT:?need PORT}"
PUB_B64="${PUB_B64:?need PUB_B64}"

mkdir -p ~/.ssh ~/.sshd
chmod 700 ~/.ssh; chmod 755 ~
touch ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys
key="$(printf '%s' "$PUB_B64" | base64 -d)"
grep -qF "$key" ~/.ssh/authorized_keys || echo "$key" >> ~/.ssh/authorized_keys

[ -f ~/.sshd/ssh_host_rsa_key ] || ssh-keygen -t rsa -f ~/.sshd/ssh_host_rsa_key -N '' -q
if [ ! -f ~/.sshd/sshd_config ]; then
    printf 'Port %s\nListenAddress 0.0.0.0\nHostKey ~/.sshd/ssh_host_rsa_key\nPasswordAuthentication no\nChallengeResponseAuthentication no\nUsePAM yes\nPrintMotd no\nSubsystem sftp internal-sftp\n' \
        "$PORT" > ~/.sshd/sshd_config
fi

if ! ss -tln 2>/dev/null | grep -q ":$PORT "; then
    nohup /usr/sbin/sshd -f ~/.sshd/sshd_config >/dev/null 2>&1 &
    sleep 1
fi

if ss -tln 2>/dev/null | grep -q ":$PORT "; then
    echo "USERLAND_OK port=$PORT"
else
    echo "USERLAND_FAIL" >&2
    exit 1
fi
