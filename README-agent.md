# NJU HPC 集群自动化套件 —— AI Agent 配置与使用说明
#
# 本文档面向 AI 编程代理（如 Kimi Code / Claude Code）。阅读本文后，
# 你应当能够：在新机器上自动安装本套件、通过向用户提问完成配置、
# 并在此后自主地对南京大学高性能计算中心集群执行命令与文件传输。
#
# 人工用户只需在"校外网模式"的会话建立时输入一次集群密码 + 两步认证码。
# 你（AI 代理）在任何情况下都不得向用户索要密码或两步验证码，
# 也不得把凭证写入任何文件。检测到会话失效时，必须停下并请用户执行
# 本文档指定的人工命令。

## 0. 套件内容

本套件是一个 git 仓库，**只包含通用代码与文档**；所有机器/用户相关的
配置（用户名、节点 IP、端口、密钥路径）都由首次安装程序生成本地的
`hpc.conf`，该文件已被 .gitignore 排除，绝不入库。因此同一个仓库
可服务任意用户、任意多台电脑：每台机器各自 clone、各自运行 setup.sh。

```
nju-hpc-kit/
├── README-agent.md    # 本文件
├── setup.sh           # 一次性配置（交互式，AI 代理由此向用户提问）
├── hpc.conf.example   # 配置模板（实际 hpc.conf 由 setup.sh 生成本地副本）
├── .gitignore         # 排除 hpc.conf / .session/ 等本机状态
├── detect-net.sh      # 探测当前网络环境：campus / offcampus / none
├── start-session.sh   # 校外网模式：建立持久会话（人工双重认证 + 自动自愈）
├── run-session.sh     # 统一入口：在集群上执行命令（自动选择网络模式）
├── stop-session.sh    # 拆除校外网持久会话
├── ensure-userland.sh # 远端自愈脚本：部署/重启 login 节点的用户态 sshd
├── send-file.sh       # 本地 -> 集群 小文件传输（base64 + md5 校验）
└── fetch-file.sh      # 集群 -> 本地 小文件传输（base64 + md5 校验）
```

## 1. 安装流程（新机器上按顺序执行）

1. 前提：机器上有 git、OpenSSH 客户端（`ssh -V` 可用）与 bash。
   Windows 用户推荐 Git Bash（本套件全部脚本用 bash 编写）。
2. 克隆本仓库到用户主目录：
   `git clone <repo-url> ~/nju-hpc-kit`
   （`hpc.conf` 不入库；若目录里已有旧配置，git 操作不受影响。）
3. 运行 `bash ~/nju-hpc-kit/setup.sh`，依次回答（均有默认值，集群用户名必填）：
   - 集群用户名（**必填**，不设默认值；任何账号都适用）；
   - 登录节点（默认 login2；集群迁移后入口只有 login2，不要再用 login1）；
   - 双认证网关（默认 entry.nju.edu.cn）；
   - 用户态 sshd 端口**无需回答**：首次连接时由 ensure-userland.sh
     在登录节点自动选择空闲高位端口（20000–59999 随机），
     并回写到本机 hpc.conf；如与他人冲突，自愈时会自动让位并回填新端口。
   - 当前是否为校内网 / 已连校园 VPN：
     * **y** —— 引导输入一次集群密码，随后自动完成：公钥安装、
       用户态 sshd 部署（按集群官方文档：仅公钥、高位端口、绑 0.0.0.0）、
       记录节点校园网 IP（210.28.x.x）到 hpc.conf。
       完成后即进入免密的 campus 模式。
     * **n** —— 跳过部署；之后首次 `start-session.sh` 完成密码+两步
       认证时，会自动补做同样部署（自愈设计，见第 2 节）。
4. setup.sh 还会：生成本机 `hpc.conf`、追加 SSH config 别名
   （`nju-hpc-entry` = 双认证网关；`nju-hpc` = 直连别名）、
   生成或复用本机密钥 `~/.ssh/id_ed25519`。
5. 冒烟测试：
   - `bash ~/nju-hpc-kit/detect-net.sh` → 应输出 `campus` 或 `offcampus`
   - `bash ~/nju-hpc-kit/run-session.sh 'hostname'` → 应输出 `login2`

### 套件更新

仓库改进后，每台机器执行 `cd ~/nju-hpc-kit && git pull` 即可更新
工具脚本；本机 `hpc.conf`、密钥、会话状态不受影响。

## 2. 两种网络模式（每次现场探测，自动选择）

套件**每次执行命令前**都调用 `detect-net.sh` 探测，禁止把网络模式
当作机器的固定属性（用户可能随时开关校园 VPN）。探测顺序与降级行为：

1. 先试 campus（用户态 sshd 免密直连）；
2. **campus 失败但网关可达 → 自动降级为 offcampus**——典型场景是
   用户态 sshd 死亡或节点 IP 变更；此时行为是请用户做一次 2FA
   会话（start-session），会话建立时的自愈步骤会修复 campus 通道
   （补装公钥、拉起 sshd、回填新 IP），下次探测即恢复 campus；
3. 网关也不可达 → none，报告网络不可用。

- **campus（校内网模式）**：探测命令
  `ssh -p $USERLAND_PORT -i $KEY_FILE $HPC_USER@$LOGIN_IP true` 成功。
  通道是登录节点上的**用户态 sshd**（按集群官方文档部署，仅公钥、
  高位端口），校内网与校园 VPN 下都可达。命令直接经 ssh 执行，
  断线由 OpenSSH 自动重连，**全程无需人工**。
- **offcampus（校外网模式）**：登录节点不可直连但网关 entry 可达。
  命令经"持久会话"执行——一条长驻 SSH 连接（建立时已人工完成
  密码+两步认证）。
- **none**：两者都不可达 → 报告网络不可用，停止。

### 自愈设计（重要）

登录节点重启或用户态 sshd 意外死亡后，campus 模式会失效。
`start-session.sh` 在每次（人工认证）会话建立后，会自动通过该会话
在登录节点上执行 `ensure-userland.sh`：补装公钥、按模板重建
sshd_config（端口沿用现有空闲端口；被占用则自动另选并把新端口
回填本机 hpc.conf）、sshd 没在跑就拉起，并把最新校园网 IP 回写
`hpc.conf`。因此：**用户每次做两步认证，都在同时修复 campus 通道**。

### 校外网持久会话生命周期

- 建立：`bash ~/nju-hpc-kit/start-session.sh`
  （用户输入集群密码和两步验证码）。
- 失效：网关掉线（闲置约 8 小时）或网络波动。
  你检测到"会话不存在/已退出"时，必须明确告诉用户：
  "校外网会话已断开，请运行 bash ~/nju-hpc-kit/start-session.sh 重新认证"，
  然后停止相关操作，等用户完成后再继续。
- 拆除：`bash ~/nju-hpc-kit/stop-session.sh`。

### 断开与卸载

**campus 模式**：无连接需要断开——`run-session.sh` 每次执行都是独立的
瞬时连接，命令结束即关闭；login 节点上的用户态 sshd 是常驻服务，
不占本地资源，与本机开关机无关。

**校外网会话**：主动拆除用 `bash ~/nju-hpc-kit/stop-session.sh`；
闲置约 8 小时网关也会自动断开；合上电脑/断网同样会断。
会话断开**不影响**已提交到调度系统的集群作业（结果在集群磁盘上）。

**完全卸载**（不再使用本套件）：
1. 本地：删除 `~/nju-hpc-kit/`；如私钥只用于集群，删除
   `~/.ssh/id_ed25519*`；手动清理 `~/.ssh/config` 中的 nju-hpc 别名段；
2. 集群（在 login 节点执行）：`pkill -u $USER -x sshd && rm -rf ~/.sshd`；
   并从 `~/.ssh/authorized_keys` 中删除对应机器的公钥行。

## 3. 日常使用规则（AI 代理必读）

0. **日常入口只有一个**：无论校内网还是校外网，执行远程命令一律用
   `bash ~/nju-hpc-kit/run-session.sh '远程命令'`（模式自动探测）。
   校内网/VPN 零前置、零人工；校外网唯一的前置是"会话失效时"跑一次
   `start-session.sh`（密码+两步认证），之后日常同样只用 run-session.sh。
1. 命令约定：
   - 返回的是远程命令的真实退出码；stdout/stderr 原样带回。
   - 命令经 base64 编码传输，**不要在命令里做本地 shell 转义**，
     整段命令用单引号交给 run-session.sh 即可（含空格、引号、
     下标字符、中文路径等特殊字符都没问题）。
2. 文件传输：
   - 小文件（脚本、配置、CSV 等几十 KB 级）：`send-file.sh <本地> <远程>` /
     `fetch-file.sh <远程> <本地>`，自带 md5 校验，支持 `~/` 开头路径。
   - 大文件/批量：kit 的 base64 传输有尺寸边界（campus 模式受 ssh 单参数
     上限约束，约 96KB），且不支持断点续传——请改用任意 SFTP/SCP 客户端
     （WinSCP、FileZilla、rsync、XFTP 等均可），连接参数：
     - 校内网/VPN：`sftp -P <USERLAND_PORT> -i <KEY_FILE> <HPC_USER>@<LOGIN_IP>`（免密）；
     - 校外网：经网关 entry.nju.edu.cn，交互式输入密码 + 两步认证。
3. 批量操作请把远程逻辑写成脚本文件，send-file 上去后一条命令执行，
   避免几十个往返（每次 run-session 有 1–3 秒开销）。
4. 长时间任务**不要**挂在前台 ssh：用集群调度系统（Slurm）提交，
   本地只做轮询。约定见套件 `docs/TASK-WORKFLOW.md`（通用版，直接
   阅读，不复制到项目；与官方 cicam-hpc-skill 的分工见其第 0 节）。
5. 安全红线：
   - 永不向用户索要密码 / 两步验证码；
   - 永不在磁盘上写含凭证的文件；
   - 用户态 sshd 仅校内网/VPN 使用，勿向公网暴露端口、勿开密码登录；
   - 永不修改集群上他人目录；清理只限自己账号下、先列清单给用户确认。
   - **每台机器一把钥匙**：各机器的 id_ed25519 独立生成、独立追加到
     集群 authorized_keys；某机器丢失时，从 authorized_keys 删除对应
     行即可单独吊销。

## 4. 故障排查

| 现象 | 处理 |
|---|---|
| run-session 报"会话不存在" | 校外网会话断了；请用户重新 start-session（会自动自愈 campus 通道） |
| 重跑 start 提示"会话已存在"/旧脚本要求先 stop | 套件只认真实存活且确实是 ssh 的会话，失效会话会直接重建；状态混乱时用 `start-session.sh --force` |
| detect-net 输出 none | 本机断网或网关不可达；请用户检查网络/VPN |
| campus 模式探测失败 | 用户态 sshd 死了或端口变了；请用户 start-session 一次（自愈并回填端口/IP），或重跑 setup.sh |
| 想更换用户态 sshd 端口 | 直接改本机 hpc.conf 的 USERLAND_PORT，再跑一次 start-session（或等下次自愈）自动重建 |
| 命令返回 255 / Connection timed out | 网络抖动；重试一次，仍失败则重新探测网络模式 |
| setup 时直连密码登录失败 | 确认在校内网/VPN 环境；否则选 n，走 start-session 路径 |

## 5. 参考

集群的官方文档（含常见问题、登录方式、节点/分区调整与迁移通知）：

- 文档首页：https://doc.nju.edu.cn/books/efe93
- 常见问题（网络接入、用户态 sshd、作业调度等）：
  https://doc.nju.edu.cn/books/efe93/page/a1d0c

集群策略（登录入口、分区划分、迁移计划）可能随时间变化；当本套件的
行为与集群实际表现不符时，以官方文档为准并相应更新套件。
