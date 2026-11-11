#!/usr/bin/env bash
# detect-net.sh — 探测当前网络环境
# 输出: campus | offcampus | none ，退出码 0/0/1
#
# campus 判据：login2 的校园网地址上用户态 sshd（公钥免密）可达。
#   该服务按集群官方文档部署（仅公钥、高位端口），校内网与校园 VPN 均可用。
#   USERLAND_PORT 为空（尚未首次连接/自动选端口）时跳过 campus 探测。
# offcampus 判据：双认证网关 TCP 可达。
set -euo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$KIT_DIR/hpc.conf"

if [ -n "$USERLAND_PORT" ] && \
        ssh -o BatchMode=yes -o ConnectTimeout=6 -p "$USERLAND_PORT" -i "$KEY_FILE" \
        -o StrictHostKeyChecking=accept-new "$HPC_USER@$LOGIN_IP" true 2>/dev/null; then
    echo "campus"
    exit 0
fi

if (exec 3<>"/dev/tcp/$ENTRY_HOST/22") 2>/dev/null; then
    exec 3>&- 3<&-
    echo "offcampus"
    exit 0
fi

echo "none"
exit 1
