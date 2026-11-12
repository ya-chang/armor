#!/usr/bin/env bash
# 第三条命令：只跑补丁层，但把第 4、5 层一起补齐
# 用法：bash patch/install.sh [--check]
# 前提：社区版已装、富江插件已装（第 1、2 条命令做过的事）
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

ok(){ echo "  ✔ $*"; }
bad(){ echo "  ✘ $*"; }
FAIL=0; TOTAL=0
t(){ TOTAL=$((TOTAL+1)); }

echo "DSH_HOME = $HOME_DIR"
echo

# ---------- 前置检查：1 和 2 有没有做 ----------
echo "[前置] 第 1、2 条命令是否已完成"
COMM="$HOME_DIR/profiles/web/node_modules/dsh-purge-community/lib"
PLUG="$HOME_DIR/plugins/fujiang-armor"
t; [ -f "$COMM/index.js" ] && ok "社区版在位" || { bad "社区版缺失 → 先做第 1 条命令"; FAIL=$((FAIL+1)); }
t; [ -f "$PLUG/index.js" ] && ok "富江插件在位" || { bad "富江缺失 → 先做第 2 条命令"; FAIL=$((FAIL+1)); }
[ "$FAIL" -eq 0 ] || { echo; echo "前置不满足，先补齐 1、2 再跑本条"; exit 1; }

# ---------- 第 4 层：自愈模板源 ----------
echo
echo "[第4层] 自愈模板源 → armor-kit-src/lib/"
SRC="$HOME_DIR/armor-kit-src/lib"
if [ "$CHECK" = 1 ]; then
  n=0; for f in ladder.js reinforce.js assemble.js; do [ -f "$SRC/$f" ] && n=$((n+1)); done
  t; [ "$n" = 3 ] && ok "3/3" || { bad "$n/3"; FAIL=$((FAIL+1)); }
else
  mkdir -p "$SRC"
  for f in ladder.js reinforce.js assemble.js; do cp "$KIT/purge-opt/lib/$f" "$SRC/$f"; done
  t; ok "三个模块已部署"
fi

# ---------- 第 5 层：提示词载体 ----------
echo
echo "[第5层] 提示词载体 → \$DSH_HOME/"
for f in fujiang-kernel.md fujiang-kernel.mirror.md prompt-inject.md; do
  if [ "$CHECK" = 1 ]; then
    t; [ -f "$HOME_DIR/$f" ] && ok "$f" || { bad "$f 缺失"; FAIL=$((FAIL+1)); }
  else
    [ -f "$HOME_DIR/$f" ] && { cp "$HOME_DIR/$f" "$HOME_DIR/$f.before-armor-kit"; echo "  ! $f 已存在，原文件存为 .before-armor-kit"; }
    cp "$KIT/prompts/$f" "$HOME_DIR/$f"
    t; ok "$f"
  fi
done

mkdir -p "$HOME_DIR/dsh-purge"
if [ "$CHECK" = 1 ]; then
  t; [ -f "$HOME_DIR/dsh-purge/tuning.json" ] && ok "tuning.json" || { bad "tuning.json 缺失"; FAIL=$((FAIL+1)); }
else
  [ -f "$HOME_DIR/dsh-purge/tuning.json" ] && cp "$HOME_DIR/dsh-purge/tuning.json" "$HOME_DIR/dsh-purge/tuning.json.before-armor-kit"
  cp "$KIT/config/tuning.json" "$HOME_DIR/dsh-purge/tuning.json"
  t; ok "tuning.json（refusalRetry=true）"
fi

if [ ! -f "$HOME_DIR/AGENTS.md" ] && [ "$CHECK" = 0 ]; then
  cp "$KIT/prompts/AGENTS.md.example" "$HOME_DIR/AGENTS.md"
  t; ok "AGENTS.md 从示例创建"
else
  t; ok "AGENTS.md 已存在或跳过"
fi

# ---------- 第 3 层：9 处注入 ----------
echo
echo "[补丁] 9 处注入"
if [ "$CHECK" = 1 ]; then
  DSH_HOME="$HOME_DIR" node "$KIT/patch/apply.mjs" --check | tail -3
  t; ok "已检查"
else
  OUT=$(DSH_HOME="$HOME_DIR" node "$KIT/patch/apply.mjs" 2>&1)
  echo "$OUT" | grep -E '自建模块|注入' -A4 | tail -8
  echo "$OUT" | grep -q '失败 0' && ok "注入完成" || { bad "注入有失败"; FAIL=$((FAIL+1)); }
  t
fi

echo
echo "========= 合计 $TOTAL 项：通过 $((TOTAL-FAIL))，失败 $FAIL ========="
[ "$FAIL" -eq 0 ] || exit 1
[ "$CHECK" = 1 ] || echo "装完完全退出 DSH 再打开（不是杀进程）"
