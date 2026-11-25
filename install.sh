#!/bin/bash
# fog2bx 一键安装 / 升级。用法：
#   1. 在线安装（按 CPU 架构自动从 GitHub Release 下载对应程序并核对校验和）：
#        bash <(curl -fsSL https://raw.githubusercontent.com/FogMaly/fog2bx/main/install.sh)
#   2. 离线安装：把 install.sh 和 fog2bx-linux-amd64（或 arm64）传到节点机器同一个目录，运行 bash install.sh
#   3. 指定下载地址：FOG2BX_URL=https://你的地址/fog2bx-linux-amd64 bash install.sh
# 可选：FOG2BX_VERSION=v1.0.0 指定版本（默认装最新发布的版本）。
# 装好后用 fog2bx 命令管理（和 V2bX 一样，不带参数进菜单）。
set -e
REPO=FogMaly/fog2bx
FALLBACK_VERSION=v1.0.0
red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

# fetch URL OUT：下载到文件（OUT 为 - 时输出到 stdout）；第三个参数非空时不显示进度。失败重试 3 次
fetch() {
  local i
  for i in 1 2 3; do
    if command -v curl >/dev/null; then
      if [ -n "$3" ] || [ "$2" = - ]; then
        curl -fsSL --connect-timeout 15 -o "$2" "$1" && return 0
      else
        curl -fL --connect-timeout 15 --progress-bar -o "$2" "$1" && return 0
      fi
    elif command -v wget >/dev/null; then
      wget -q -T 15 -O "$2" "$1" && return 0
    else
      red "需要 curl 或 wget"; return 1
    fi
    [ $i = 3 ] || sleep 2
  done
  return 1
}

[ "$(uname -s)" = Linux ] || { red "只支持 Linux"; exit 1; }
[ "$(id -u)" = 0 ] || { red "请用 root 运行"; exit 1; }
command -v systemctl >/dev/null || { red "需要 systemd"; exit 1; }

case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64|armv8*) ARCH=arm64 ;;
  *) red "不支持的架构：$(uname -m)（只有 amd64 和 arm64）"; exit 1 ;;
esac

DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)
SRC="$DIR/fog2bx-linux-$ARCH"
BIN=$(mktemp)
SUMS=$(mktemp)
trap 'rm -f "$BIN" "$SUMS"' EXIT
if [ -n "$FOG2BX_URL" ]; then
  echo "下载 $FOG2BX_URL ..."
  fetch "$FOG2BX_URL" "$BIN" || { red "下载失败"; exit 1; }
elif [ -f "$SRC" ]; then
  cp "$SRC" "$BIN"
else
  VERSION=$FOG2BX_VERSION
  if [ -z "$VERSION" ]; then
    # 最新发布的版本（包括预发布）；查不到就用脚本自带的版本
    VERSION=$(fetch "https://api.github.com/repos/$REPO/releases?per_page=1" - 2>/dev/null \
      | grep -m1 '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    VERSION=${VERSION:-$FALLBACK_VERSION}
  fi
  BASE="https://github.com/$REPO/releases/download/$VERSION"
  echo "检测到 $ARCH 架构，下载 fog2bx $VERSION ..."
  fetch "$BASE/fog2bx-linux-$ARCH" "$BIN" || {
    red "下载失败：$BASE/fog2bx-linux-$ARCH"
    red "网络连不上 GitHub 时，可以把程序放到自己的地址，用 FOG2BX_URL 指定"
    exit 1
  }
  fetch "$BASE/SHA256SUMS" "$SUMS" quiet || { red "下载校验和失败：$BASE/SHA256SUMS，已停止安装"; exit 1; }
  if command -v sha256sum >/dev/null; then
    WANT=$(grep " fog2bx-linux-$ARCH\$" "$SUMS" | cut -d' ' -f1)
    GOT=$(sha256sum "$BIN" | cut -d' ' -f1)
    if [ -z "$WANT" ] || [ "$WANT" != "$GOT" ]; then
      red "校验和不对，下载的文件可能不完整或被改过，已停止安装"
      exit 1
    fi
    green "校验和核对通过"
  else
    yellow "系统没有 sha256sum，跳过校验和核对"
  fi
fi
chmod +x "$BIN"
"$BIN" version >/dev/null || { red "$BIN 不能运行，架构对吗？"; exit 1; }

UPGRADE=0
systemctl is-active --quiet fog2bx && UPGRADE=1
"$BIN" install

if [ ! -f /etc/fog2bx/config.json ]; then
  # 生成配置是交互式的；用 curl ... | bash 运行时 stdin 不是终端，改从终端读
  if [ -t 0 ]; then
    fog2bx generate || { red "没有生成配置，之后运行 fog2bx generate 再 fog2bx start"; exit 1; }
  elif (: </dev/tty) 2>/dev/null; then
    fog2bx generate </dev/tty || { red "没有生成配置，之后运行 fog2bx generate 再 fog2bx start"; exit 1; }
  else
    yellow "程序已装好，但当前没有可交互的终端，没法生成配置"
    yellow "登录到机器上运行 fog2bx generate，再运行 fog2bx start"
    exit 1
  fi
fi
if [ $UPGRADE = 1 ]; then
  fog2bx restart
else
  fog2bx start
fi
echo
green "完成。管理菜单：fog2bx    看日志：fog2bx log"
