# armor-kit · 补丁本体

只含社区版 `dsh-purge-community` 的 9 处注入与 3 个自建模块。

## 内容

```
patch/apply.mjs                 幂等补丁器（9 处注入 + 拷 3 个模块）
purge-opt/lib/ladder.js         L0-L3 阶梯状态机
purge-opt/lib/reinforce.js      agent/pre-step 落锁
purge-opt/lib/assemble.js       接管 system-prompt 装配
purge-opt/lib/refusal-retry.js  重试链路参照源
```

## 用法

```bash
# 先确认社区版已装并改成目录引用
ls ~/.dsh/profiles/web/node_modules/dsh-purge-community/lib/index.js

# 检查（不改文件）
DSH_HOME=~/.dsh node patch/apply.mjs --check

# 注入
DSH_HOME=~/.dsh node patch/apply.mjs
```

期望输出：`注入 9 · 已存在 0 · 失败 0`，重复执行变成 `注入 0 · 已存在 9 · 失败 0`。

## 回滚

```bash
cd ~/.dsh/profiles/web/node_modules/dsh-purge-community/lib
for f in *.purge-opt.bak; do mv "$f" "${f%.purge-opt.bak}"; done
rm -f ladder.js reinforce.js assemble.js
```

装完完全退出 DSH 再打开。
