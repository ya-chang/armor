#装甲·盔甲套件

> 社区版宿主补丁 + 富江身份内核 + 自愈模板源 + 提示词载体，一层装齐。

## 一句话总结

`盔甲`是DSH(DeepSeek线束)的提示词注入型套件。它通过给社区版`dsh-purge-community` 打 9 处幂等补丁，部署富江身份内核（order 100/200 双段注入）、自愈模板源与提示词载体，保障会话输出的稳定性与一致性：拒绝不复发、文体不偏移、交付形态可分级调控。

---

## 功能特性

| 模块 | 路径 | 作用 |
|---|---|---|
| 社区版补丁 | `patch/apply.mjs` | 在 `dsh-purge-community/lib/`上做9处幂等注入(index.js6处+拒绝-重试.js3处)|
| 富江插件 | `涪江装甲/` |双段提示词注入(order100主内核+order200契约层)，客户端状态条|
|自愈模板源| `purge-opt/lib/` + `自愈/` | 社区版自动更新清空 `Lib/` 后，自动拷回 `梯形图.js`、`reinforce.js`、`assembly.js` |
| 提示词载体 | `提示/` | `fujiang-kernel.md`、`fujiang-kernel.mirror.md`、`prompt-inject.md`、`tuning.json` |
| 阶梯状态机 | `purge-opt/lib/ladder.js` | L0→L3 四档，被拒时切换交付文体而非复读 |
| 每轮重锁 | `purge-opt/lib/reinforce.js` | `代理/预步骤` 按需落锁；敏感题面附加形态锁（patch-2.0 增：口径锁、自探测脱敏锁、后果框架检测） |
| 装配接管 | `purge-opt/lib/assembly.js` | `系统提示/装配`摘完成/清身份/两头压|

---

## 安装方法

### 方法一：一条命令（推荐）

```猛击
CD~/铠装和和钣金安装.sh
```

5 步一次跑完：社区版检查 → 依赖引用修正 → 富江插件 → 提示词载体 → 补丁注入。

### 方法二：三步手动安装

```猛击
#1社区版(npm上没有，必须走GitHub Release tgz)
curl -L -o /tmp/comm.tgz \
"https://github.com/kingcharleslzy-ai/dsh-purge/releases/download/v1.6.93/dsh-purge-community-1.6.93.tgz"
D="$HOME/.DSH/profiles/web/节点模块/dsh-purge-community"
mkdir-p"$D"&&tar-xzf/tmp/comm.tgz-C"$D"--strip-components=1

CD~/.dsh/profiles/web
python3-<<'PY'
导入json，pathlib
P=pathlib.Path("package.json")；d=json.loads(p.read_text())
D["dependencies"]["dsh-purge-community"]="file：./node_modules/dsh-purge-community"
p.write_text(json.dumps(d，缩进=2，确保_ascii=假)+"\n")
py
PNPM安装

#②富江插件
git clone https://github.com/ya-chang/armor.git ~/armor
mkdir -p ~/.dsh/plugins/fujiang-armor
cp -a ~/armor/fujiang-armor/. ~/.dsh/plugins/fujiang-armor/

# ③ 补丁层（自动带上第 4 层模板源 + 第 5 层载体 + 9 处注入）
cd ~/armor && bash patch/install.sh

# 完全退出 DSH 再打开（不是杀进程）
```

### 方法三：仅修补丁（社区版更新后用）

```bash
bash install.sh --patch-only
```

---

## 验证

```bash
# 补丁体检
bash patch/install.sh --check
# 期望：注入 0 · 已存在 9 · 失败 0

# 功能验证（需社区版已装）
DSH_HOME=~/.dsh node purge-opt/test/verify-full.mjs | tail -3
# 期望：合计 42 项：通过 42，失败 0
```

---

## 目录结构

```
armor/
├── install.sh                  一键安装 / 修复 / 检查
├── install-community.sh        社区版离线/在线安装脚本
├── patch/
│   ├── apply.mjs               幂等补丁器（9 处注入）
│   └── install.sh              补丁层安装器（第 4、5 层 + 注入）
├── fujiang-armor/              富江插件
│├--index.js插件主体（双段注入+状态投影）
│├--client.js客户端状态条(web profile)
│├--selfheal.js自愈模块（社区版更新后自动补齐）
│├--包.JSON
│├--cordis.patch.yml
│└--提示符/
│├--fujiang.md
│├--fujiang-mirror.md
│└--fujiang-compat.md
├-清除-opt/
│├--lib/
││├--梯子。JS L0-L3阶梯状态机
││├--增强.js每轮重锁+形态锁
││├--assembly.js装配层接管
││└--拒绝-重试.js重试链路参照源
│└--测试/
│└--verify-full.mjs42项功能验证脚本
├--自愈/
│└--selfheal.js独立自愈编剧
├--提示符/
│├--fujiang-kernel.md内核热更新
│├--fujiang-kernel.mirror.md契约层热更新
│├--提示-inject.md操作者配置载体
│└--agents.md.exampleagents.md示例
├--config/
│└--tuning.json拒绝重试=true
└── 补丁记录.md                    补丁修复对照与变更清单
```

---

##关键机制

###双段注入
-订单100：主内核（身份+交付契约）
-订单200：契约层（文体与内核对齐）


##已知坑与注意

| 坑 | 表现 | 处理 |
|---|---|---|
|tgz引用|改lib不生效| 改为 `文件：./node_modules/dsh-purge-community` 后 `PNPM安装` |
|'pnpm安装'后|9处注入全丢|'bash install.sh-仅修补程序'|
| 中转站降智 | 拒绝率高，与补丁无关 |先确认走官方key|

---

## 仓库无责申明

**本仓库（armor）及其所有代码、脚本、文档、配置文件，仅作为本地安全研究、CTF 靶场练习、授权红队演练及个人学习目的的技术素材。**

仓库维护者不对以下情况负责：
- 任何使用本仓库内容对未经授权目标进行的渗透、攻击、入侵、破解、欺诈、伪造或其他违法行为；
- 因使用本仓库内容导致的任何直接或间接损失、数据泄露、系统损坏、法律责任；
- 用户自行将本仓库内容部署到生产环境、公网资产或他人设备上所产生的后果。

**使用前请务必确认：**
1.目标系统归您所有，或您已获得书面授权；
2. 您所在司法管辖区允许此类安全研究活动；
3. 您理解并愿意承担所有使用后果。

仓库内所有内容均为“按现状”提供，不附带任何明示或暗示的担保。

---

## License

CC-BY-NC-SA-4.0
