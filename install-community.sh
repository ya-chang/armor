#!/usr/bin/env bash
# 安装社区版 dsh-purge-community
#
# 它没有发布到 npm registry，`dsh plugin add dsh-purge-community` 会 404。
# 必须走 GitHub Release 的 tgz。
#
#   bash install-community.sh              自动取最新 release
#   bash install-community.sh v1.6.93      指定版本
#   bash install-community.sh --local PATH 用本地 tgz
set -euo pipefail

HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
REPO="kingcharleslzy-ai/dsh-purge"
VERSION=""
LOCAL_TGZ=""

case "${1:-}" in
  --local) LOCAL_TGZ="${2:-}" ;;
  v*)      VERSION="$1" ;;
esac

c() { printf '\033[36m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die() { printf '  \033[31m✘\033[0m %s\n' "$*"; exit 1; }

[ -d "$HOME_DIR" ] || die "找不到 $HOME_DIR，DSH 至少启动过一次"

PROFILE=""
for p in web desktop; do
  [ -d "$HOME_DIR/profiles/$p" ] && PROFILE="$p" && break
done
[ -n "$PROFILE" ] || die "找不到 profile"

PDIR="$HOME_DIR/profiles/$PROFILE"
COMM="$PDIR/node_modules/dsh-purge-community"
PJSON="$PDIR/package.json"

c "环境"
ok "DSH_HOME=$HOME_DIR"
ok "profile=$PROFILE"

# ---------- 已装则跳过 ----------
if [ -f "$COMM/lib/index.js" ]; then
  V=$(python3 -c "import json;print(json.load(open('$COMM/package.json')).get('version','?'))" 2>/dev/null || echo "?")
  ok "社区版已存在，版本 $V"
  warn "如需重装请先删除: rm -rf $COMM"
  exit 0
fi

# ---------- 取 tgz ----------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TGZ=""

if [ -n "$LOCAL_TGZ" ]; then
  [ -f "$LOCAL_TGZ" ] || die "本地文件不存在: $LOCAL_TGZ"
  TGZ="$LOCAL_TGZ"
  ok "使用本地包: $TGZ"
else
  if [ -z "$VERSION" ]; then
    c "查询最新版本"
    for i in 1 2 3; do
      VERSION=$(curl -s --max-time 25 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | python3 -c "import json,sys
try:
    print(json.load(sys.stdin).get('tag_name',''))
except: print('')" 2>/dev/null)
      [ -n "$VERSION" ] && break
      sleep 2
    done
    [ -n "$VERSION" ] || die "查询失败，请手动指定版本: bash install-community.sh v1.6.93"
  fi
  ok "版本: $VERSION"

  URL="https://github.com/$REPO/releases/download/$VERSION/dsh-purge-community-${VERSION#v}.tgz"
  c "下载 tgz"
  echo "  $URL"
  for i in 1 2 3; do
    if curl -sL --max-time 180 -o "$TMP/pkg.tgz" "$URL" 2>/dev/null && [ -s "$TMP/pkg.tgz" ]; then
      TGZ="$TMP/pkg.tgz"
      ok "$(stat -c%s "$TMP/pkg.tgz") bytes"
      break
    fi
    warn "第 $i 次下载失败，重试"
    sleep 3
  done
  [ -n "$TGZ" ] || die "下载失败，手动下载后: bash install-community.sh --local /path/to.tgz"
fi

# ---------- 校验 ----------
if tar -tzf "$TGZ" >/dev/null 2>&1; then
  ok "压缩包完整"
else
  die "tgz 损坏"
fi
if tar -tzf "$TGZ" 2>/dev/null | grep -qx "package/lib/index.js"; then
  ok "包含 lib/index.js"
else
  die "tgz 结构不对"
fi

# ---------- 解包 ----------
c "解包到 node_modules"
mkdir -p "$PDIR/node_modules"
rm -rf "$COMM"
mkdir -p "$COMM"
tar -xzf "$TGZ" -C "$COMM" --strip-components=1
ok "$COMM"

# ---------- 装依赖 ----------
c "安装运行时依赖"
cd "$PDIR"
if command -v pnpm >/dev/null 2>&1; then
  pnpm add "dsh-purge-community@file:./node_modules/dsh-purge-community" 2>&1 | tail -5 || \
    warn "pnpm add 失败，手动补依赖"
else
  npm i "dsh-purge-community@file:./node_modules/dsh-purge-community" --no-audit --no-fund 2>&1 | tail -5 || \
    warn "npm i 失败"
fi

# ---------- 注册 bundle ----------
c "注册到 profile bundles"
python3 - "$PJSON" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
d.setdefault("dependencies", {})["dsh-purge-community"] = "file:./node_modules/dsh-purge-community"
prof = d.setdefault("dsh", {}).setdefault("profile", {})
bundles = prof.setdefault("bundles", [])
if "dsh-purge-community" not in bundles:
    # 放在 @deepseek-ai 之后
    idx = len(bundles)
    for i, b in enumerate(bundles):
        if isinstance(b, str) and not b.startswith("@deepseek-ai"):
            idx = i
            break
    bundles.insert(idx, "dsh-purge-community")
p.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
print("  bundles:", bundles)
PY
ok "已写入"

# ---------- 验证 ----------
c "验证"
if [ -f "$COMM/bin/community.js" ]; then
  node "$COMM/bin/community.js" status 2>&1 | head -12 || warn "status 执行异常"
fi

cat <<EOF

========================================
社区版安装完成
========================================
位置: $COMM
版本: $TGZ

下一步:
  1. 跑套件补丁: bash install.sh --patch-only
  2. 完全退出 DSH 再打开
  3. 验证: cd $COMM && node bin/community.js status

注意: 这个包不在 npm registry 上，
      `dsh plugin add dsh-purge-community` 一定 404。
      只能走 GitHub Release tgz。
EOF
