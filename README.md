# armor-kit · 破甲套件

社区版宿主补丁 + 富江身份内核 + 自愈模板源 + 提示词载体，一层装齐。

## 三步构造

```
1) 原社区版  dsh-purge-community   ← 宿主，9 处注入都打在它的 lib/ 里
2) 原富江    plugins/fujiang-armor ← 身份内核 order 100/200 + 自愈入口
3) 补丁      patch/apply.mjs       ← 9 处注入 + 3 个自建模块
```

补完 **4 和 5** 两层，三步之外的缺口就没了：

```
4) 自愈模板源  ~/.dsh/armor-kit-src/lib/   ← 社区版自动更新清 lib/ 后从这拷回
5) 提示词载体  fujiang-kernel.md / mirror / prompt-inject.md / tuning.json
```

## 三步装法（推荐）

只走三条命令，第 4、5 层藏在第三条里：

```bash
# ① 社区版（npm 上没有，必须走 tgz）
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

# ③ 仓库补丁层：自动带上第 4 层（自愈模板源）+ 第 5 层（提示词载体）+ 9 处注入
cd ~/armor-kit && bash patch/install.sh

# 完全退出 DSH 再打开（不是杀进程）
```

体检：

```bash
bash patch/install.sh --check    # 期望：合计 9 项：通过 9，失败 0
```

## 一条命令装法（等价）

```bash
cd ~/armor-kit && bash install.sh   # 5 步一次跑完：社区版检查→富江→模板源→载体→注入
```

## 安装

```bash
# 先装社区版（npm 上没有，必须走 GitHub Release tgz）
curl -L -o /tmp/comm.tgz \
  "https://github.com/kingcharleslzy-ai/dsh-purge/releases/download/v1.6.93/dsh-purge-community-1.6.93.tgz"
D="$HOME/.dsh/profiles/web/node_modules/dsh-purge-community"
mkdir -p "$D" && tar -xzf /tmp/comm.tgz -C "$D" --strip-components=1

# 依赖必须写成目录引用，不能是 tgz（否则改 lib 不生效）
cd ~/.dsh/profiles/web
python3 - <<'PY'
import json, pathlib
p = pathlib.Path("package.json"); d = json.loads(p.read_text())
d["dependencies"]["dsh-purge-community"] = "file:./node_modules/dsh-purge-community"
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
pnpm install

# 再跑套件：插件 + 模板源 + 载体 + tuning + 9 处注入
cd /path/to/armor-kit && bash install.sh

# 完全退出 DSH 再打开（不是杀进程）
```

## 四条命令

| 命令 | 用途 |
|---|---|
| `bash install.sh` | 完整安装 |
| `bash install.sh --patch-only` | 社区版更新后只修补丁 |
| `bash install.sh --check` | 只体检，不改文件 |

## 目录

```
patch/apply.mjs                 幂等补丁器（9 处注入）
patch/install.sh                第三条命令：补第 4、5 层 + 注入
purge-opt/lib/ladder.js         L0-L3 阶梯
purge-opt/lib/reinforce.js      按步落锁 + 形态锁
purge-opt/lib/assemble.js       接管 system-prompt 装配
purge-opt/lib/refusal-retry.js  重试链路参照源
fujiang-armor/                  富江插件（index.js + selfheal.js + 包内 prompt 回退）
prompts/                        fujiang-kernel.md / mirror / prompt-inject.md
config/tuning.json              refusalRetry=true
install.sh                      安装器
```

## 验证

```bash
bash install.sh --check
# 期望：合计 7 项：通过 7，失败 0  且  注入 0 · 已存在 9 · 失败 0
```

## 顺序铁律

1. **`pnpm install` 必须在补丁之前**，它整树重建 `node_modules`，之前的注入全没。
2. **补丁必须最后跑**，`bash install.sh --patch-only` 补一次即可。
3. **依赖必须是目录引用**，写成 `file:xxx.tgz` 时宿主加载 tgz 解压副本，改 `lib/` 白干。

## 自愈

富江插件 `apply()` 每次加载先跑 `selfHealSafe()`：检查 `lib/{ladder,reinforce,assemble}.js` 是否在，缺了从 `~/.dsh/armor-kit-src/lib/` 拷回；再检查 9 处注入标记，缺了就补。

**局限**：自愈在加载时运行，补好的文件要下次启动才生效 —— 自动更新后需重启两次，或更新后直接 `bash install.sh --patch-only`。

## 回滚

```bash
# 补丁原文件
ls ~/.dsh/profiles/web/node_modules/dsh-purge-community/lib/*.purge-opt.bak
cd ~/.dsh/profiles/web/node_modules/dsh-purge-community/lib
for f in *.purge-opt.bak; do mv "$f" "${f%.purge-opt.bak}"; done
rm -f ladder.js reinforce.js assemble.js

# 载体原文件
ls ~/.dsh/*.before-armor-kit ~/.dsh/dsh-purge/*.before-armor-kit

# 插件
rm -rf ~/.dsh/plugins/fujiang-armor ~/.dsh/armor-kit-src
```

## 已知坑

| 坑 | 表现 | 处理 |
|---|---|---|
| tgz 引用 | 改 lib 不生效 | 改目录引用后 `pnpm install` |
| `pnpm install` 后 | 9 处注入全丢 | `bash install.sh --patch-only` |
| 与 aegis-armor 共存 | 内核重复注入 | 二选一，都占 order 100/200 |
| 中转站降智 | 拒绝率高，与补丁无关 | 先确认走官方 key |

## License

CC-BY-NC-SA-4.0
