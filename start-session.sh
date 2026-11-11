#!/usr/bin/env bash
# start-session.sh — 校外网模式：建立持久会话
# 用法: start-session.sh [--force]   --force 先拆除旧会话再重建
#
# 机制（生产验证过的版本）：凭证以"密码 认证码"单行格式在本机盲输，
# 经 SSH_ASKPASS 提供给 ssh（不落盘、不经命令行参数）；ssh -T 后台
# 常驻，FIFO 以读写模式 <> 打开；就绪以远端回显标记判定。
set -euo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$KIT_DIR/hpc.conf"
source "$CONF"

SESSION_DIR="$KIT_DIR/.session"
CMD_FIFO="$SESSION_DIR/commands.fifo"
OUT_LOG="$SESSION_DIR/output.log"
PID_FILE="$SESSION_DIR/ssh.pid"

session_alive() {
    [ -s "$PID_FILE" ] || return 1
    local pid
    pid="$(cat "$PID_FILE")"
    kill -0 "$pid" 2>/dev/null || return 1
    is_ssh_pid "$pid" || return 1
    return 0
}

is_ssh_pid() {  # 校验 pid 确实属于 ssh 进程（防 pid 复用误判）；跨平台
    local pid="$1" comm
    if comm="$(ps -o comm= -p "$pid" 2>/dev/null)" && [ -n "$comm" ]; then
        case "$comm" in *ssh*) return 0 ;; *) return 1 ;; esac
    fi
    if command -v tasklist >/dev/null 2>&1; then  # Windows (Git Bash) 回退
        case "$(tasklist //FI "PID eq $pid" 2>/dev/null)" in
            *ssh*) return 0 ;; *) return 1 ;;
        esac
    fi
    return 1
}

if session_alive && [ "${1:-}" != "--force" ]; then
    echo "会话已存在（pid=$(cat "$PID_FILE")），无需重复建立；如状态异常可 --force 重建。" >&2
    exit 0
fi

# 清理半死会话与残留状态
if [ -s "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
fi
rm -f "$PID_FILE"
mkdir -p "$SESSION_DIR"
[ -p "$CMD_FIFO" ] || mkfifo "$CMD_FIFO"
: > "$OUT_LOG"

IFS= read -rs -p "请输入 NJU 集群密码和当前两步认证码（格式：密码 认证码）: " credential
printf '\n'
[ -n "$credential" ] || { echo "未输入认证信息。" >&2; exit 1; }

export SSH_ASKPASS="$KIT_DIR/askpass.sh"
export SSH_ASKPASS_REQUIRE=force
export NJU_HPC_CREDENTIAL="$credential"
unset credential

echo "正在连接 $ENTRY_HOST（用户 $HPC_USER）..."
# 记录启动前已存在的 ssh 进程（Windows 任务管理器 pid），用于区分本会话
pre_pids=""
if command -v tasklist >/dev/null 2>&1; then
    pre_pids="$(tasklist //FI "IMAGENAME eq ssh.exe" 2>/dev/null | awk '/ssh\.exe/{print $2}' | tr '\n' ' ')"
fi
nohup ssh -T \
    -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password \
    -o NumberOfPasswordPrompts=1 \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o TCPKeepAlive=yes \
    "$SSH_ALIAS_ENTRY" "bash -lc 'echo __KIMI_SESSION_READY__; exec bash -s'" \
    <>"$CMD_FIFO" >> "$OUT_LOG" 2>&1 &
ssh_pid=$!
disown "$ssh_pid" 2>/dev/null || true

# 发现真实的 ssh 进程 pid（MSYS $! 与 Windows pid 不一致时用任务管理器）
if command -v tasklist >/dev/null 2>&1; then
    sleep 1
    for p in $(tasklist //FI "IMAGENAME eq ssh.exe" 2>/dev/null | awk '/ssh\.exe/{print $2}'); do
        case " $pre_pids " in
            *" $p "*) ;;
            *) ssh_pid="$p"; break ;;
        esac
    done
fi
echo "$ssh_pid" > "$PID_FILE"

# 就绪等待（连接与认证通常数秒完成）
ready=0
for _ in $(seq 1 60); do
    if grep -q '__KIMI_SESSION_READY__' "$OUT_LOG" 2>/dev/null; then
        ready=1
        break
    fi
    if ! is_ssh_pid "$ssh_pid" 2>/dev/null; then
        break
    fi
    sleep 1
done

if [ "$ready" != "1" ]; then
    echo "会话建立失败（密码/认证码错误、账号或 IP 被临时锁定、网络不可达），ssh 输出如下：" >&2
    tail -n 20 "$OUT_LOG" >&2 || true
    rm -f "$PID_FILE"
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
    newport="$(printf '%s\n' "$out" | sed -n 's/.*USERLAND_OK port=\([0-9][0-9]*\).*/\1/p' | tail -1)"
    [ -n "$newport" ] && sed -i "s/^USERLAND_PORT=.*/USERLAND_PORT='$newport'/" "$CONF" 2>/dev/null || true
    ip="$(bash "$KIT_DIR/run-session.sh" 'hostname -I' 2>/dev/null | tr " " "\n" | grep -E "^210\.28\." | head -1 || true)"
    if [ -n "$ip" ] && ! grep -q "^LOGIN_IP='$ip'" "$CONF"; then
        sed -i "s/^LOGIN_IP=.*/LOGIN_IP='$ip'/" "$CONF" 2>/dev/null || true
    fi
fi

echo "注意：会话会被网关定期断开（经验观察为数小时，具体时长未公开）；断开后重新运行本脚本即可。"
echo "若多次失败后提示 account is locked：请停止一切重试，等待数分钟后重试或改换其他网络环境（锁定时长未公开）。"
