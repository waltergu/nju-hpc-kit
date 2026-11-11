#!/usr/bin/env bash
# send-file.sh <本地路径> <远程路径> — 小文件上行（base64 + md5 校验）
set -euo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -eq 2 ] || { echo "用法: send-file.sh <本地路径> <远程路径>" >&2; exit 2; }
local_path="$1" remote_path="$2"
case "$remote_path" in "~") remote_path="\$HOME";; "~/"*) remote_path="\$HOME/${remote_path#"~"/}";; esac
[ -f "$local_path" ] || { echo "本地文件不存在: $local_path" >&2; exit 2; }
size="$(wc -c < "$local_path")"
[ "$size" -lt 92160 ] || { echo "文件 $size 字节，超过 kit 传输上限 90KB；大文件请用 SFTP 客户端（见 README 3.2）。" >&2; exit 2; }

b64="$(base64 -w0 "$local_path")"
sum="$(md5sum "$local_path" | awk '{print $1}')"
bash "$KIT_DIR/run-session.sh" "echo '$b64' | base64 -d > \"$remote_path\" && md5sum \"$remote_path\""
echo "本地 md5: $sum （远程值见上，应一致）"
