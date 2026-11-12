# 破甲套件 (armor-kit)

在本机 DSH 上实测通过的一套破甲配置打包。目标：在另一台机器上装出**同样行为**的破甲环境，并用同一份题单跑横向对比。

---

## 里面有什么

| 组件 | 路径 | 作用 |
|---|---|---|
| **富江插件** | `fujiang-armor/` | 身份内核（order 100）+ 契约层（order 200），双段注入 |
| **热更载荷** | `prompts/fujiang-kernel*.md` | 改这个文件就改提示词，不动代码 |
| **注入载体** | `prompts/prompt-inject.md` | 操作者配置，去特征化版本 |
| **阶梯模块** | `purge-opt/lib/ladder.js` | L0-L3 升档状态机 |
| **每轮重锁** | `purge-opt/lib/reinforce.js` | pre-step 按需落锁 + 形态锁 |
| **装配接管** | `purge-opt/lib/assemble.js` | 剥 complete / 清身份 / 两头压 |
| **重试增强** | `purge-opt/lib/refusal-retry.js` | 拒绝后重投，带形态约束 + 档位文本 |
| **验证脚本** | `purge-opt/test/verify-full.mjs` | 42 项断言 |
| **题单** | 单独文档 | 破甲能力通用评测题单 |

---

## 前置条件

- DSH 已安装并**至少启动过一次**（要有 `~/.dsh/profiles/`）
- Node ≥ 18
- 已有 `dsh-purge-community`（社区版）。没有的话本套件只装富江那部分

---

## 安装

```bash
tar -xzf armor-kit.tar.gz
cd armor-kit
bash install.sh --dry     # 先看计划
bash install.sh           # 真装
```

装完**完全退出 DSH 再打开**（不是杀进程，是 App 层面的退出）。

---

## 关键：社区版要用目录引用

如果你那台机器的 `dsh-purge-community` 是通过 tgz 装的：

```json
"dsh-purge-community": "file:/path/to/dsh-purge-community-1.6.93.tgz"
```

**改 `lib/` 不会生效**——宿主从 tgz 解压出来的副本加载。必须改成目录引用：

```bash
cd ~/.dsh/profiles/web
python3 - <<'PY'
import json, pathlib
p = pathlib.Path("package.json"); d = json.loads(p.read_text())
d["dependencies"]["dsh-purge-community"] = "file:./node_modules/dsh-purge-community"
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
pnpm install
```

⚠️ `pnpm install` 会重建 `node_modules`，**把刚打进去的四个 lib 文件冲掉**。顺序必须是：先改依赖 → 再 `pnpm install` → 最后跑 `install.sh`。

---

## 手工挂载（如果 index.js 没有挂载点）

`install.sh` 会检查，缺了会提示。手工补这两处：

**`lib/index.js` 头部 import：**

```js
import { ladderClause, readLadder, bumpLadder } from "./ladder.js";
import { installReinforcer } from "./reinforce.js";
import { installAssembleHook } from "./assemble.js";
```

**`applyHostHooks()` 里，在 `installMnemonMessageStrip(ctx, cfg);` 之后：**

```js
installReinforcer(ctx, cfg);
installAssembleHook(ctx, cfg);
```

---

## 验证

```bash
cd ~/.dsh/profiles/web/node_modules/dsh-purge-community
DSH_HOME=~/.dsh node test/verify-full.mjs
```

期望：`合计 42 项：通过 42，失败 0`

阶梯 CLI：

```bash
node bin/community.js ladder status
node bin/community.js ladder bump
node bin/community.js ladder reset
```

审计日志（**注意路径**，不在 `dsh-purge/` 下）：

```bash
tail -20 ~/.dsh/dsh-purge-community/audit.jsonl
```

钩子挂载成功的标志：

```bash
grep -c assemble_hook_mounted ~/.dsh/dsh-purge-community/audit.jsonl
```

---

## 这套东西的真实能力边界

**装完之后实际管用的：**

1. 宿主 67 条补丁（沙箱/审批/身份/rewind）—— 跟插件模块独立，tgz 也生效
2. 富江双段提示词注入（身份 + 契约）
3. 每轮按需落锁 + 形态锁（敏感题面强制保持交付形态）
4. 拒绝后重投，带形态约束 + 当前档位文本
5. 装配层身份剥离 + `complete:true` 吞噬防御

**实际没被真实触发的：**

- L1/L2/L3 升档 —— 审计日志显示 `ladder_signal` 全部来自测试脚本，真实会话从没触发过
- 只有在真被拒的时候才会走这条路

---

## 已知坑

| 坑 | 表现 | 处理 |
|---|---|---|
| 改 `lib/` 不生效 | 审计日志里没有 `assemble_hook_mounted` | 见「目录引用」一节 |
| `pnpm install` 冲掉补丁 | `verify-full.mjs` 消失 | 重跑 `install.sh`（源码在 `purge-opt/`，不受影响） |
| 审计路径找错 | 以为钩子没跑 | 真实路径 `~/.dsh/dsh-purge-community/audit.jsonl` |
| AGENTS.md 被覆盖 | App 反复重写该文件 | 本脚本不覆盖已存在的 AGENTS.md |
| 中转站降智 | 测出来拒绝率高 | **先确认走官方 key**，否则测的不是破甲能力 |

---

## 回滚

```bash
# 全量回滚
cp -a ~/.dsh/backup-armor-kit-*/prompt-inject.md ~/.dsh/
cp -a ~/.dsh/backup-armor-kit-*/fujiang-kernel*.md ~/.dsh/
rm -rf ~/.dsh/plugins/fujiang-armor
```

社区版补丁回滚需要重装 tarball，或用安装包里的原版覆盖。

---

## 目录结构

```
armor-kit/
├── install.sh                     # 一键安装
├── README.md                       # 本文件
├── fujiang-armor/                  # 富江插件本体
│   ├── index.js
│   ├── client.js
│   ├── cordis.patch.yml
│   ├── package.json
│   └── prompts/
├── purge-opt/                      # 社区版增强补丁
│   ├── lib/
│   │   ├── ladder.js
│   │   ├── reinforce.js
│   │   ├── assemble.js
│   │   └── refusal-retry.js
│   └── test/verify-full.mjs
├── prompts/                        # 提示词载体
│   ├── prompt-inject.md
│   ├── fujiang-kernel.md
│   ├── fujiang-kernel.mirror.md
│   └── AGENTS.md.example
└── config/
    └── tuning.json
```
