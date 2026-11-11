---
name: nju-hpc
description: 南京大学高性能计算中心（NJU HPC）集群的自动化操作——登录环境配置、双网络模式连接、Slurm 作业提交与监测、文件传输。当用户要求在南大集群上提交/管理作业、查询 HPC 资源、运行计算任务、或配置/迁移该环境时使用。
---

# NJU HPC 集群自动化套件（skill 入口）

本 skill 只是入口。**权威文档在 `~/nju-hpc-kit/`（git 仓库）**，执行任何
操作前先读对应文档，细节以文档为准：

- `README-agent.md` — 安装配置、双网络模式（campus/offcampus）、自愈、
  文件传输、安全红线；
- `docs/TASK-WORKFLOW.md` — 通用任务提交与自动监测工作流；
- `docs/TASK-CONVENTIONS.md` — 任务约定（任务如何被指定、验收、迭代）。

## 使用前检查（按顺序）

1. **`~/nju-hpc-kit` 不存在** → 这是首次安装场景，引导第一部分流程：
   `git clone <repo-url> ~/nju-hpc-kit` → `bash ~/nju-hpc-kit/setup.sh`
   （配置项一律向用户提问，不猜测、不设默认假设）→ 需要双重认证时，
   明确告诉用户在终端运行 `bash ~/nju-hpc-kit/start-session.sh` 并等待
   完成。完整流程见 README-agent.md。
2. **已存在** → 日常唯一入口：
   `bash ~/nju-hpc-kit/run-session.sh '<远程命令>'`
   （自动探测 campus 免密直连 / offcampus 持久会话）。

## 核心红线（任何情况下不可违背）

- 永不向用户索要集群密码 / 两步认证码；不在磁盘上写任何凭证；
- 不修改集群上他人目录；删除/清理前先列清单请用户确认；
- 代理会话中断恢复后，先查集群侧真实状态（sacct/结果文件），
  不凭记忆推断、不重复提交在跑作业；
- 长时间计算一律经 Slurm 提交；作业命令细节与故障诊断优先查官方
  cicam-hpc-skill；其余约定见两份 docs 文档。
