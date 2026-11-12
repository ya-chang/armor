#!/usr/bin/env bash
# 破甲套件一键安装 —— 把本机验证过的那套装到另一台 DSH 上
# 用法: bash install.sh [--dry]
set -euo pipefail

DRY=0
[ "${1:-}" = "--dry" ] && DRY=1
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
TS=$(date +%Y%m%d-%H%M%S)
BAK="$HOME_DIR/backup-armor-kit-$TS"

say() { printf '\033[36m[%s/7]\033[0m %s\n' "$1" "$2"; }
ok()  { printf '  \033[32m✔\033[0m %s\n' "$1"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$1"; }
die() { printf '  \033[31m✘\033[0m %s\n' "$1"; exit 1; }

say 1 "环境检查"
[ -d "$HOME_DIR" ] || die "找不到 $HOME_DIR，DSH 至少启动过一次再来"
command -v node >/dev/null || die "缺 node"
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
[ "$NODE_MAJOR" -ge 18 ] || die "Node 版本太低: $(node -v)"
ok "DSH_HOME=$HOME_DIR"
ok "node $(node -v)"

PROFILE=""
for p in web desktop; do
  [ -d "$HOME_DIR/profiles/$p" ] && PROFILE="$p" && break
done
[ -n "$PROFILE" ] || die "找不到 profile（web / desktop 都没有）"
ok "profile=$PROFILE"

if [ "$DRY" = 1 ]; then
  say 2 "dry-run：只打印计划"
  echo "  将备份到 $BAK"
  echo "  将安装 fujiang-armor -> $HOME_DIR/plugins/fujiang-armor"
  echo "  将部署提示词 -> $HOME_DIR/{prompt-inject.md,fujiang-kernel*.md}"
  echo "  将打补丁 dsh-purge-community/lib/{ladder,reinforce,assemble,refusal-retry}.js"
  exit 0
fi

say 2 "备份现有配置"
mkdir -p "$BAK"
for f in prompt-inject.md AGENTS.md fujiang-kernel.md fujiang-kernel.mirror.md; do
  [ -f "$HOME_DIR/$f" ] && cp -a "$HOME_DIR/$f" "$BAK/" && ok "备份 $f"
done
[ -f "$HOME_DIR/dsh-purge/tuning.json" ] && cp -a "$HOME_DIR/dsh-purge/tuning.json" "$BAK/" && ok "备份 tuning.json"
ok "备份目录 $BAK"

say 3 "安装富江插件"
rm -rf "$HOME_DIR/plugins/fujiang-armor"
mkdir -p "$HOME_DIR/plugins"
cp -a "$KIT/fujiang-armor" "$HOME_DIR/plugins/fujiang-armor"
ok "插件文件已复制"

say 4 "部署提示词"
cp "$KIT/prompts/prompt-inject.md" "$HOME_DIR/prompt-inject.md"
cp "$KIT/prompts/fujiang-kernel.md" "$HOME_DIR/fujiang-kernel.md"
cp "$KIT/prompts/fujiang-kernel.mirror.md" "$HOME_DIR/fujiang-kernel.mirror.md"
ok "prompt-inject.md（$(( $(wc -c < "$HOME_DIR/prompt-inject.md") )) 字节）"
ok "fujiang-kernel.md（热更载荷，改这个不影响插件代码）"

if [ ! -f "$HOME_DIR/AGENTS.md" ] && [ -f "$KIT/prompts/AGENTS.md.example" ]; then
  cp "$KIT/prompts/AGENTS.md.example" "$HOME_DIR/AGENTS.md"
  ok "AGENTS.md（原缺，已从示例装）"
else
  warn "AGENTS.md 已存在，未覆盖（它常被 App 托管，覆盖会出问题）"
fi

say 5 "配置 tuning"
mkdir -p "$HOME_DIR/dsh-purge"
cp "$KIT/config/tuning.json" "$HOME_DIR/dsh-purge/tuning.json"
ok "boost/refusalRetry/injectPosition 已写入"

say 6 "给社区版打补丁"
C="$HOME_DIR/profiles/$PROFILE/node_modules/dsh-purge-community"
if [ -f "$C/lib/index.js" ]; then
  for f in ladder.js reinforce.js assemble.js refusal-retry.js; do
    cp "$KIT/purge-opt/lib/$f" "$C/lib/$f"
    ok "lib/$f"
  done
  mkdir -p "$C/test"
  cp "$KIT/purge-opt/test/verify-full.mjs" "$C/test/verify-full.mjs"
  ok "test/verify-full.mjs"

  # 检查 index.js 是否已挂载
  if ! grep -q "installReinforcer" "$C/lib/index.js"; then
    warn "index.js 缺挂载点，需要手工补两处（见 README「手工挂载」）"
  else
    ok "index.js 挂载点已存在"
  fi
else
  warn "未找到 dsh-purge-community，跳过（先装社区版再跑本脚本）"
fi

say 7 "验证"
if [ -f "$C/test/verify-full.mjs" ]; then
  ( cd "$C" && DSH_HOME="$HOME_DIR" node test/verify-full.mjs 2>&1 | tail -3 )
fi

cat <<EOF

============================
安装完成
============================
备份: $BAK
回滚: cp -a $BAK/* $HOME_DIR/  （按需选择性恢复）

下一步：
1. 完全退出 DSH（含后台进程），重新打开
2. 新会话发「寒霜」验证阶梯是否响应
3. 跑测试题单：破甲能力通用评测题单.md

注意：如果 dsh-purge-community 是 tgz 方式装的，改了 lib 不会生效。
     需要把 profile/package.json 里的依赖改成目录引用：
       "dsh-purge-community": "file:./node_modules/dsh-purge-community"
EOF
