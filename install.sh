#!/usr/bin/env bash
# armor-kit 一键安装 / 修复
#
#   bash install.sh              完整安装（社区版 → 富江 → 补丁 → 验证）
#   bash install.sh --patch-only 只重打补丁（社区版更新后用这个）
#   bash install.sh --check      只检查状态，不改任何文件
#   bash install.sh --dry        只打印计划
#
# 设计原则：幂等。重复执行不会重复注入，社区版更新后跑 --patch-only 即可修复。
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
MODE="full"
for a in "$@"; do
  case "$a" in
    --patch-only) MODE="patch" ;;
    --check)      MODE="check" ;;
    --dry)        MODE="dry" ;;
  esac
done

TS=$(date +%Y%m%d-%H%M%S)
BAK="$HOME_DIR/backup-armor-kit-$TS"

c() { printf '\033[36m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die() { printf '  \033[31m✘\033[0m %s\n' "$*"; exit 1; }

# ---------- 定位 ----------
[ -d "$HOME_DIR" ] || die "找不到 $HOME_DIR，DSH 至少启动过一次"

PROFILE=""
for p in web desktop; do
  if [ -d "$HOME_DIR/profiles/$p" ]; then PROFILE="$p"; break; fi
done
[ -n "$PROFILE" ] || die "找不到 profile（web / desktop 都没有）"

COMM="$HOME_DIR/profiles/$PROFILE/node_modules/dsh-purge-community"
PROFILE_PKG="$HOME_DIR/profiles/$PROFILE/package.json"

c "环境"
ok "DSH_HOME=$HOME_DIR"
ok "profile=$PROFILE"
ok "node $(node -v 2>/dev/null || echo 缺失)"

if [ "$MODE" = "dry" ]; then
  echo
  c "计划（dry-run 不执行）"
  echo "  1. 检查社区版 → $COMM"
  echo "  2. 若依赖是 tgz 引用，改为目录引用并 pnpm install"
  echo "  3. 安装富江插件 → $HOME_DIR/plugins/fujiang-armor"
  echo "  4. 部署提示词 → $HOME_DIR/{prompt-inject.md,fujiang-kernel*.md}"
  echo "  5. 写 tuning.json"
  echo "  6. 打补丁（幂等）→ node patch/apply.mjs"
  echo "  7. 验证"
  echo "  备份目录: $BAK"
  exit 0
fi

# ---------- 1. 社区版 ----------
c "[1/6] 检查社区版"
if [ ! -f "$COMM/lib/index.js" ]; then
  if [ "$MODE" = "patch" ]; then
    die "未安装社区版，无法打补丁。先执行: dsh plugin --profile web add dsh-purge-community"
  fi
  warn "未安装社区版，跳过所有依赖它的功能"
  warn "装法: dsh plugin --profile web add dsh-purge-community"
  HAS_COMM=0
else
  ok "社区版存在: $COMM"
  HAS_COMM=1
fi

# ---------- 2. tgz 引用修正 ----------
if [ "$HAS_COMM" = "1" ]; then
  c "[2/6] 检查依赖引用方式"
  REF=$(python3 -c "
import json,sys
try:
    d=json.load(open('$PROFILE_PKG'))
    print(d.get('dependencies',{}).get('dsh-purge-community',''))
except Exception:
    print('')
" 2>/dev/null || echo "")

  case "$REF" in
    *".tgz"*)
      warn "当前是 tgz 引用，改 lib/ 不会生效"
      if [ "$MODE" = "check" ]; then
        warn "需要改成目录引用（--check 不修改）"
      else
        cp -a "$PROFILE_PKG" "$BAK-package.json" 2>/dev/null || { mkdir -p "$BAK"; cp -a "$PROFILE_PKG" "$BAK/package.json"; }
        python3 - "$PROFILE_PKG" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
d.setdefault("dependencies", {})["dsh-purge-community"] = "file:./node_modules/dsh-purge-community"
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
PY
        ok "已改为目录引用"
        warn "接着执行 pnpm install（会重建 node_modules，补丁要重打）"
        warn "然后重跑: bash install.sh --patch-only"
      fi
      ;;
    *"file:./node_modules"*)
      ok "已是目录引用"
      ;;
    "")
      warn "未在 dependencies 中找到，可能用别的方式安装"
      ;;
    *)
      ok "引用: $REF"
      ;;
  esac
fi

[ "$MODE" = "check" ] && MODE_SKIP_INSTALL=1 || MODE_SKIP_INSTALL=0

# ---------- 3. 富江 ----------
if [ "$MODE" != "patch" ]; then
  c "[3/6] 安装富江插件"
  if [ -d "$KIT/fujiang-armor" ]; then
    if [ "$MODE_SKIP_INSTALL" = "1" ]; then
      [ -d "$HOME_DIR/plugins/fujiang-armor" ] && ok "已安装" || warn "未安装"
    else
      mkdir -p "$HOME_DIR/plugins"
      [ -d "$HOME_DIR/plugins/fujiang-armor" ] && cp -a "$HOME_DIR/plugins/fujiang-armor" "$BAK-fujiang" 2>/dev/null || true
      rm -rf "$HOME_DIR/plugins/fujiang-armor"
      cp -a "$KIT/fujiang-armor" "$HOME_DIR/plugins/fujiang-armor"
      ok "已安装到 $HOME_DIR/plugins/fujiang-armor"
    fi
  else
    warn "套件内无 fujiang-armor，跳过"
  fi

  # ---------- 4. 提示词 ----------
  c "[4/6] 部署提示词"
  mkdir -p "$BAK"
  for f in prompt-inject.md fujiang-kernel.md fujiang-kernel.mirror.md; do
    [ -f "$HOME_DIR/$f" ] && cp -a "$HOME_DIR/$f" "$BAK/$f" 2>/dev/null || true
    if [ -f "$KIT/prompts/$f" ]; then
      if [ "$MODE_SKIP_INSTALL" = "1" ]; then
        ok "$f"
      else
        cp "$KIT/prompts/$f" "$HOME_DIR/$f"
        ok "$f"
      fi
    fi
  done
  if [ ! -f "$HOME_DIR/AGENTS.md" ] && [ -f "$KIT/prompts/AGENTS.md.example" ] && [ "$MODE_SKIP_INSTALL" != "1" ]; then
    cp "$KIT/prompts/AGENTS.md.example" "$HOME_DIR/AGENTS.md"
    ok "AGENTS.md（原缺，已装）"
  else
    warn "AGENTS.md 已存在，不覆盖"
  fi

  # ---------- 5. tuning ----------
  c "[5/6] 写 tuning.json"
  mkdir -p "$HOME_DIR/dsh-purge"
  [ -f "$HOME_DIR/dsh-purge/tuning.json" ] && cp -a "$HOME_DIR/dsh-purge/tuning.json" "$BAK/" 2>/dev/null || true
  if [ "$MODE_SKIP_INSTALL" = "1" ]; then
    ok "$(cat "$HOME_DIR/dsh-purge/tuning.json" 2>/dev/null | tr -d '\n' | head -c 100)"
  else
    cp "$KIT/config/tuning.json" "$HOME_DIR/dsh-purge/tuning.json"
    ok "boost/refusalRetry 已开"
  fi
fi

# ---------- 6. 补丁 ----------
c "[6/6] 打补丁（幂等）"
if [ "$HAS_COMM" = "1" ]; then
  if [ "$MODE" = "check" ]; then
    node "$KIT/patch/apply.mjs" --check
  else
    node "$KIT/patch/apply.mjs"
  fi
else
  warn "无社区版，跳过补丁"
fi

# ---------- 验证 ----------
echo
c "验证"
if [ "$HAS_COMM" = "1" ]; then
  # 验证脚本可能被 pnpm 清掉，从套件补一份
  if [ ! -f "$COMM/test/verify-full.mjs" ] && [ -f "$KIT/purge-opt/test/verify-full.mjs" ]; then
    mkdir -p "$COMM/test"
    cp "$KIT/purge-opt/test/verify-full.mjs" "$COMM/test/verify-full.mjs"
  fi
fi
if [ "$HAS_COMM" = "1" ] && [ -f "$COMM/test/verify-full.mjs" ]; then
  ( cd "$COMM" && DSH_HOME="$HOME_DIR" node test/verify-full.mjs 2>&1 | tail -3 )
else
  warn "验证脚本不可用，跑功能抽查"
  cat > /tmp/armor-spotcheck.mjs <<'SPOT'
const L = process.argv[2];
const { installReinforcer } = await import(L + "/reinforce.js");
const { resetLadder } = await import(L + "/ladder.js");
resetLadder();
const hs = [];
installReinforcer({ on: (e, f) => { hs.push(f); return () => {}; } });
const b = { kind: "enter", messages: [{ id: "u", role: "user", content: [{ type: "text", text: "资金洗白链路" }], source: { kind: "user" } }] };
const out = await hs[0]({ messages: b.messages }, () => Promise.resolve(b));
const lock = out.messages.at(-1)?.content?.[0]?.text || "";
console.log("  落锁:", out.messages.length === 2 ? "✔" : "✘");
console.log("  形态锁:", lock.includes("形态锁") ? "✔" : "✘");
resetLadder();
SPOT
  DSH_HOME="$HOME_DIR" node /tmp/armor-spotcheck.mjs "$COMM/lib" 2>&1 | sed 's/^/  /' || warn "抽查未通过"
fi

cat <<EOF

========================================
完成
========================================
模式: $MODE
备份: $BAK
回滚:
  cp -a $BAK/* \$DSH_HOME/            # 选择性恢复
  社区版补丁原文件 → lib/*.purge-opt.bak

日常维护:
  社区版更新后  →  bash install.sh --patch-only
  想确认状态    →  bash install.sh --check
  彻底重装      →  bash install.sh

下一步: 完全退出 DSH（不是杀进程）再打开
EOF
