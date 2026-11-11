#!/usr/bin/env bash
# fetch-file.sh <远程路径> <本地路径> — 小文件下行（base64 + md5 校验）
set -euo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -eq 2 ] || { echo "用法: fetch-file.sh <远程路径> <本地路径>" >&2; exit 2; }
remote_path="$1" local_path="$2"
case "$remote_path" in "~") remote_path="\$HOME";; "~/"*) remote_path="\$HOME/${remote_path#"~"/}";; esac
case "$local_path" in "~") local_path="$HOME";; "~/"*) local_path="$HOME/${local_path#~/}";; esac

# 先取远程大小与 md5
info="$(bash "$KIT_DIR/run-session.sh" "wc -c < \"$remote_path\"; md5sum \"$remote_path\" | awk '{print \$1}'")"
size="$(printf '%s\n' "$info" | sed -n 1p)"
sum="$(printf '%s\n' "$info" | sed -n 2p)"
[ "$size" -lt 1048576 ] || { echo "文件 $size 字节，超过 1MB；请用 XFTP 手动传输。" >&2; exit 2; }

b64="$(bash "$KIT_DIR/run-session.sh" "base64 -w0 \"$remote_path\"")"
printf '%s' "$b64" | base64 -d > "$local_path"
local_sum="$(md5sum "$local_path" | awk '{print $1}')"
echo "远程 md5: $sum"
echo "本地 md5: $local_sum"
[ "$local_sum" = "$sum" ] && echo "校验一致 ✓" || { echo "校验不一致！!" >&2; exit 1; }
