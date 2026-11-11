# 集群任务提交与自动监测工作流（模板）

本文是**通用模板**：任何计算项目复制本文件为项目内的 `TASK-WORKFLOW.md`，
替换其中的项目特定部分即可。它假定你已按 `README-agent.md` 装好
`nju-hpc-kit` 并能用 `run-session.sh` 执行远程命令。

## 0. 总原则

1. **计算一律经 Slurm 提交**，绝不在会话里前台跑长任务（>2 分钟）；
   本地（AI 代理）只做四件事：提交、轮询、分析、决策。
2. **中间结果逐点落盘**：长计算每完成一个子单元（温度点、参数点）
   立即写/更新结果文件。作业被墙时截杀、节点故障、需要续跑时，
   已完成部分都不丢失。
3. **自适应而非硬扫**：先便宜探针定位、再高精度确认；参数调整由
   分析驱动，不预先固定网格。

## 1. 计算项目目录约定

```
<project>/
├── TASK.toml            # 任务目标与验收标准（全自动模式必填；可选）
├── TASK_SPEC_REVIEW.md  # 任务描述的定稿记录（用户 review 通过的文件）
├── source/              # 计算源码（julia/python 脚本）
├── jobs/                # Slurm 模板脚本
├── runs/                # 结果根目录（由环境变量指向，见下）
└── logs/                # Slurm 输出日志
```

## 2. Slurm 提交模板要点

```bash
#SBATCH --partition=<分区>      # 组内节点优先（免费），满了再公共分区
#SBATCH --account=<账号>
#SBATCH --cpus-per-task=<N>     # 与代码线程数一致（JULIA_NUM_THREADS=$SLURM_CPUS_PER_TASK）
#SBATCH --mem=<G>
#SBATCH --time=0-<H>:00         # 墙时预算，见 2.1
#SBATCH --output=<绝对路径>/logs/%x_%j.out
#SBATCH --error=<绝对路径>/logs/%x_%j.err
```

### 2.1 墙时预算方法

`墙时 = 单点实测耗时 × 点数 × 安全系数(≈1.5–2)`。没有实测值时先跑
单点 pilot 取数。宁可多报 30%（共享分区被他人作业拖慢是常态），
不要少报被腰斩。

### 2.2 向作业传参：`--export` 的逗号陷阱（真实事故）

`sbatch --export=ALL,FOO=a,b,c` 中**逗号是 --export 的分隔符**，
`FOO` 只会得到 `a`。多值参数必须：

```bash
sbatch --export=ALL,U=5.5,VZ=32.5,TAG=D0,'TEMPS=0.5;1;2;3' 脚本.slurm
```

即**分号分隔 + 单引号**。同时脚本侧解析器要兼容逗号和分号两种
分隔符（防手误）。作业脚本开头用 `echo` 回显关键参数，便于核验
解析是否正确。

## 3. 续跑协议（超时/中断恢复）

1. 作业超时（TIMEOUT）被 Sacct 标记后，读结果文件确认已完成哪些
   子单元；
2. 以**剩余子单元**重新提交（如 `'TEMPS=10;15;20;30'`），
   TAG 保持一致便于归档；
3. 多次续跑产生的同名结果文件按"追加但不重复"的原则合并，
   分析时以文件实际内容为准，不依赖作业号。

## 4. 自动监测模式

- 定时轮询（示例 20–30 分钟一次）：
  `run-session.sh 'sacct -j <ids> --format=JobID,State,Elapsed,MaxRSS'`；
- 状态机：`PENDING → RUNNING → COMPLETED/FAILED/TIMEOUT`；
  - FAILED：读 `.err` 日志定位原因，修后重交；
  - TIMEOUT：按第 3 节续跑；
- 轮询由 AI 代理会话内的定时机制触发；代理会话本身可能中断——
  恢复后**先检查集群侧真实状态**（sacct），不要凭记忆推断；
- 网络模式（campus/offcampus）由 `run-session.sh` 自动选择，
  监测逻辑不需要关心。

## 5. 数值质量门槛（通用）

- 计算结果必须带数值健康度字段（如 DOS 负权重、和规则校验），
  超阈值的点标记为 invalid 并计入报告；
- 精度分级（粗/中/高），报告里注明每结论所用的精度档；
- 关键结论（验收依据）必须用最高档精度复核过。

## 6. 项目特定内容（复制后填写）

- 计算代码与配置入口：`source/xxx.jl`，环境变量约定；
- 结果文件格式与读取方法；
- 当前活跃作业号与 TAG 对照表；
- 验收标准引用：`TASK.toml` / `TASK_SPEC_REVIEW.md`。
