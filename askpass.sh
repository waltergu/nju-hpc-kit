#!/bin/sh
# askpass.sh — ssh 的 askpass 辅助脚本：输出环境变量里的组合凭证
# 仅由 start-session.sh 设置 SSH_ASKPASS_REQUIRE=force 后调用；
# 凭证只存在于内存环境变量，不落盘。
printf '%s\n' "${NJU_HPC_CREDENTIAL:?NJU_HPC_CREDENTIAL is not set}"
