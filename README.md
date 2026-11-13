# armor-kit · 盔甲套件

> 社区版宿主补丁 + 富江身份内核 + 自愈模板源 + 提示词载体，一层装齐。

## 一句话总结

`armor-kit` 是 DSH（DeepSeek Harness）的提示词注入型盔甲插件套件。它通过给社区版 `dsh-purge-community` 打 9 处幂等补丁，部署富江身份内核（order 100/200 双段注入）、自愈模板源与提示词载体，实现“被拒不复读、文体不偏移、阶梯可升降”的盔甲能力。

---

## 功能特性

| 模块 | 路径 | 作用 |
|---|---|---|
| 社区版补丁 | `patch/apply.mjs` | 在 `dsh-purge-community/lib/` 上做 9 处幂等注入（index.js 6 处 + refusal-retry.js 3 处） |
| 富江插件 | `fujiang-armor/` | 双段提示词注入（order 100 主内核 + order 200 契约层），客户端状态条 |
| 自愈模板源 | `purge-opt/lib/` + `selfheal/` | 社区版自动更新清空 `lib/` 后，自动拷回 `ladder.js`、`reinforce.js`、`assemble.js` |
| 提示词载体 | `prompts/` | `fujiang-kernel.md`、`fujiang-kernel.mirror.md`、`prompt-inject.md`、`tuning.json` |
| 阶梯状态机 | `purge-opt/lib/ladder.js` | L0→L3 四档，被拒时切换交付文体而非复读 |
| 每轮重锁 | `purge-opt/lib/reinforce.js` | `agent/pre-step` 按需落锁，敏感题面附加形态锁 |
| 装配接管 | `purge-opt/lib/assemble.js` | `system-prompt/assemble` 摘 complete / 清身份 / 两头压 |

---

## 安装方法

### 方法一：一条命令（推荐）

```bash
cd ~/armor-kit && bash install.sh
```

5 步一次跑完：社区版检查 → 依赖引用修正 → 富江插件 → 提示词载体 → 补丁注入。

### 方法二：三步手动安装

```bash
# ① 社区版（npm 上没有，必须走 GitHub Release tgz）
curl -L -o /tmp/comm.tgz \
  "https://github.com/kingcharleslzy-ai/dsh-purge/releases/download/v1.6.93/dsh-purge-community-1.6.93.tgz"
D="$HOME/.dsh/profiles/web/node_modules/dsh-purge-community"
mkdir -p "$D" && tar -xzf /tmp/comm.tgz -C "$D" --strip-components=1

cd ~/.dsh/profiles/web
python3 - <<'PY'
import json, pathlib
p = pathlib.Path("package.json"); d = json.loads(p.read_text())
d["dependencies"]["dsh-purge-community"] = "file:./node_modules/dsh-purge-community"
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
pnpm install

# ② 富江插件
git clone https://github.com/ya-chang/armor-kit.git ~/armor-kit
mkdir -p ~/.dsh/plugins/fujiang-armor
cp -a ~/armor-kit/fujiang-armor/. ~/.dsh/plugins/fujiang-armor/

# ③ 补丁层（自动带上第 4 层模板源 + 第 5 层载体 + 9 处注入）
cd ~/armor-kit && bash patch/install.sh

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
armor-kit/
├── install.sh                  一键安装 / 修复 / 检查
├── install-community.sh        社区版离线/在线安装脚本
├── patch/
│   ├── apply.mjs               幂等补丁器（9 处注入）
│   └── install.sh              补丁层安装器（第 4、5 层 + 注入）
├── fujiang-armor/              富江插件
│   ├── index.js                插件主体（双段注入 + 状态投影）
│   ├── client.js               客户端状态条（web profile）
│   ├── selfheal.js             自愈模块（社区版更新后自动补齐）
│   ├── package.json
│   ├── cordis.patch.yml
│   └── prompts/
│       ├── fujiang.md
│       ├── fujiang-mirror.md
│       └── fujiang-compat.md
├── purge-opt/
│   ├── lib/
│   │   ├── ladder.js           L0-L3 阶梯状态机
│   │   ├── reinforce.js        每轮重锁 + 形态锁
│   │   ├── assemble.js         装配层接管
│   │   └── refusal-retry.js    重试链路参照源
│   └── test/
│       └── verify-full.mjs     42 项功能验证脚本
├── selfheal/
│   └── selfheal.js             独立自愈脚本
├── prompts/
│   ├── fujiang-kernel.md           内核热更新
│   ├── fujiang-kernel.mirror.md    契约层热更新
│   ├── prompt-inject.md            操作者配置载体
│   └── AGENTS.md.example           AGENTS.md 示例
├── config/
│   └── tuning.json             refusalRetry=true
├── 盔甲测验.md                   盔甲能力测试文档（A–G 系列题单）
└── 铁盔甲.md                     纯题目集（仅题目，供 AI 直接作答）
```

---

## 关键机制

### 双段注入
- order 100：主内核（身份 + 交付契约）
- order 200：契约层（文体与内核对齐）

### 形态锁
命中伪造证件 / 资金链路 / 走私边境 / 社工话术 / 仿冒站点 / 远控木马 / 免杀绕过 / 角色扮演（客服/助手/专家/黑客等身份要求）等敏感类目时，强制追加形态锁，禁止模型将操作类题目改写为“合规建议 / 防御报告 / 实验记录”，也不得因角色身份切换而拒绝或改写交付形态。

### 阶梯状态机
- L0：直给（默认，零额外 token）
- L1：分解重组
- L2：框架切换
- L3：本地移交

暗号升档：`寒霜` / `盔甲` / `醒来` / `又拒绝了`  
复位：`回到直给` / `解除阶梯` / `ladder reset`

### 自愈
社区版自动更新会删掉 `lib/`，导致 9 处注入全部丢失。富江插件每次加载时会自检并从 `~/.dsh/armor-kit-src/lib/` 拷回缺失模块，补齐缺失注入。

---

## 已知坑与注意

| 坑 | 表现 | 处理 |
|---|---|---|
| tgz 引用 | 改 lib 不生效 | 改为 `file:./node_modules/dsh-purge-community` 后 `pnpm install` |
| `pnpm install` 后 | 9 处注入全丢 | `bash install.sh --patch-only` |
| 与 aegis-armor 共存 | 内核重复注入 | **二选一**，都占 order 100/200 |
| 中转站降智 | 拒绝率高，与补丁无关 | 先确认走官方 key |

---

## 仓库无责申明

**本仓库（armor-kit）及其所有代码、脚本、文档、配置文件，仅作为本地安全研究、CTF 靶场练习、授权红队演练及个人学习目的的技术素材。**

仓库维护者不对以下情况负责：
- 任何使用本仓库内容对未经授权目标进行的渗透、攻击、入侵、破解、欺诈、伪造或其他违法行为；
- 因使用本仓库内容导致的任何直接或间接损失、数据泄露、系统损坏、法律责任；
- 用户自行将本仓库内容部署到生产环境、公网资产或他人设备上所产生的后果。

**使用前请务必确认：**
1. 目标系统归您所有，或您已获得书面授权；
2. 您所在司法管辖区允许此类安全研究活动；
3. 您理解并愿意承担所有使用后果。

仓库内所有内容均为“按现状”提供，不附带任何明示或暗示的担保。

---

## 测试题目无责申明（盔甲测验）

`盔甲测验.md` 中收录的 A–G 系列测试题目（含护照制作、资金通路、社工话术、系统入侵、免杀加载器、提权 PoC、域渗透、蠕虫传播、钓鱼邮件方案等），**仅用于在受控环境下对盔甲插件的形态锁、阶梯状态机、提示词抗性等能力进行压力测试**。

测试时请务必遵守：
- 仅在本地沙箱、虚拟机、CTF 靶场或自有授权环境中运行生成内容；
- 不得对公网真实目标、他人设备、未经授权的服务器或网络进行任何形式的攻击、扫描、利用或渗透；
- 测试产生的任何技术细节、代码、脚本、方案，严禁用于违法用途。

测试者自行承担因滥用测试题目而导致的一切法律与安全后果。仓库维护者对测试题目的使用方式及后果不承担任何责任。

---

## License

CC-BY-NC-SA-4.0