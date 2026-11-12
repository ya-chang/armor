#!/usr/bin/env bash
# armor-kit 安装器：富江插件 + 自愈模板源 + 提示词载体 + tuning + 9 处补丁
# 幂等：重复执行不叠加
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
MODE_PATCH_ONLY=0
MODE_CHECK=0
for a in "$@"; do
  case "$a" in
    --patch-only) MODE_PATCH_ONLY=1 ;;
    --check)      MODE_CHECK=1; MODE_PATCH_ONLY=1 ;;
    *) echo "未知参数: $a"; exit 2 ;;
  esac
done

ok(){ echo "  ✔ $*"; }
warn(){ echo "  ! $*"; }
bad(){ echo "  ✘ $*"; }

FAIL=0
TOTAL=0
run(){ TOTAL=$((TOTAL+1)); if "$@" >/dev/null 2>&1; then ok "$*"; else bad "$*"; FAIL=$((FAIL+1)); fi; }

echo "DSH_HOME = $HOME_DIR"
[ -d "$HOME_DIR" ] || { mkdir -p "$HOME_DIR"; ok "创建 $HOME_DIR"; }

# ---------- [1/5] 社区版存在性 ----------
echo "[1/5] 社区版"
COMM="$HOME_DIR/profiles/web/node_modules/dsh-purge-community/lib"
if [ -f "$COMM/index.js" ]; then
  ok "社区版已装"
else
  bad "社区版缺失：$COMM/index.js"
  echo "  先装社区版（npm 上没有，必须走 GitHub Release tgz）："
  echo "  curl -L -o /tmp/comm.tgz https://github.com/kingcharleslzy-ai/dsh-purge/releases/download/v1.6.93/dsh-purge-community-1.6.93.tgz"
  echo "  mkdir -p ~/.dsh/profiles/web/node_modules/dsh-purge-community"
  echo "  tar -xzf /tmp/comm.tgz -C ~/.dsh/profiles/web/node_modules/dsh-purge-community --strip-components=1"
  echo "  再在 ~/.dsh/profiles/web 里把依赖改成目录引用并 pnpm install"
  exit 1
fi

# ---------- [2/5] 富江插件 ----------
echo "[2/5] 富江插件"
PLUG="$HOME_DIR/plugins/fujiang-armor"
if [ "$MODE_CHECK" = 1 ]; then
  [ -f "$PLUG/index.js" ] && ok "插件在位" || { bad "插件缺失"; FAIL=$((FAIL+1)); }
  TOTAL=$((TOTAL+1))
elif [ "$MODE_PATCH_ONLY" = 0 ]; then
  mkdir -p "$PLUG"
  cp -a "$KIT/fujiang-armor/." "$PLUG/"
  TOTAL=$((TOTAL+1)); ok "插件已部署（index.js + selfheal.js）"
else
  TOTAL=$((TOTAL+1)); ok "跳过（--patch-only）"
fi

# ---------- [3/5] 自愈模板源（第 4 项） ----------
echo "[3/5] 自愈模板源"
SRC="$HOME_DIR/armor-kit-src/lib"
if [ "$MODE_CHECK" = 1 ]; then
  n=0; for f in ladder.js reinforce.js assemble.js; do [ -f "$SRC/$f" ] && n=$((n+1)); done
  TOTAL=$((TOTAL+1)); [ "$n" = 3 ] && ok "模板源 3/3" || { bad "模板源 $n/3"; FAIL=$((FAIL+1)); }
elif [ "$MODE_PATCH_ONLY" = 0 ]; then
  mkdir -p "$SRC"
  for f in ladder.js reinforce.js assemble.js; do cp "$KIT/purge-opt/lib/$f" "$SRC/$f"; done
  TOTAL=$((TOTAL+1)); ok "三个模块已部署到 armor-kit-src/lib"
else
  TOTAL=$((TOTAL+1)); ok "跳过（--patch-only）"
fi

# ---------- [4/5] 提示词载体 + tuning（第 5 项） ----------
echo "[4/5] 提示词载体"
if [ "$MODE_CHECK" = 1 ]; then
  for f in fujiang-kernel.md fujiang-kernel.mirror.md prompt-inject.md; do
    TOTAL=$((TOTAL+1)); [ -f "$HOME_DIR/$f" ] && ok "$f" || { bad "$f 缺失"; FAIL=$((FAIL+1)); }
  done
  TOTAL=$((TOTAL+1)); [ -f "$HOME_DIR/dsh-purge/tuning.json" ] && ok "tuning.json" || { bad "tuning.json 缺失"; FAIL=$((FAIL+1)); }
elif [ "$MODE_PATCH_ONLY" = 0 ]; then
  for f in fujiang-kernel.md fujiang-kernel.mirror.md prompt-inject.md; do
    if [ -f "$HOME_DIR/$f" ]; then
      cp "$HOME_DIR/$f" "$HOME_DIR/$f.before-armor-kit"
      warn "$f 已存在，原文件存为 .before-armor-kit 后覆盖"
    fi
    cp "$KIT/prompts/$f" "$HOME_DIR/$f"
    TOTAL=$((TOTAL+1)); ok "$f"
  done
  mkdir -p "$HOME_DIR/dsh-purge"
  if [ -f "$HOME_DIR/dsh-purge/tuning.json" ]; then
    cp "$HOME_DIR/dsh-purge/tuning.json" "$HOME_DIR/dsh-purge/tuning.json.before-armor-kit"
    warn "tuning.json 已存在，已备份"
  fi
  cp "$KIT/config/tuning.json" "$HOME_DIR/dsh-purge/tuning.json"
  TOTAL=$((TOTAL+1)); ok "tuning.json（refusalRetry=true）"

  if [ ! -f "$HOME_DIR/AGENTS.md" ]; then
    cp "$KIT/prompts/AGENTS.md.example" "$HOME_DIR/AGENTS.md"
    TOTAL=$((TOTAL+1)); ok "AGENTS.md 从示例创建"
  else
    TOTAL=$((TOTAL+1)); ok "AGENTS.md 已存在，不动"
  fi
else
  TOTAL=$((TOTAL+1)); ok "跳过（--patch-only）"
fi

# ---------- [5/5] 9 处注入 ----------
echo "[5/5] 补丁注入"
if [ "$MODE_CHECK" = 1 ]; then
  DSH_HOME="$HOME_DIR" node "$KIT/patch/apply.mjs" --check | tail -3
  TOTAL=$((TOTAL+1)); ok "已执行检查"
else
  OUT=$(DSH_HOME="$HOME_DIR" node "$KIT/patch/apply.mjs" 2>&1)
  echo "$OUT" | grep -E '注入|✔' | tail -6
  echo "$OUT" | grep -q '失败 0' && ok "注入完成" || { bad "注入有失败"; FAIL=$((FAIL+1)); }
  TOTAL=$((TOTAL+1))
fi

echo "========= 合计 $TOTAL 项：通过 $((TOTAL-FAIL))，失败 $FAIL ========="
[ "$FAIL" -eq 0 ] || exit 1
[ "$MODE_CHECK" = 1 ] || echo "装完完全退出 DSH 再打开（不是杀进程）"
