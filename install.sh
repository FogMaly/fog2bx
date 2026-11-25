#!/bin/bash
# fog2bx 一键安装。用法：
#   1. 把 install.sh 和 fog2bx-linux-amd64（或 arm64）传到节点机器同一个目录，运行 bash install.sh
#   2. 或者指定下载地址：FOG2BX_URL=https://你的地址/fog2bx-linux-amd64 bash install.sh
# 装好后用 fog2bx 命令管理（和 V2bX 一样，不带参数进菜单）。
set -e
red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

[ "$(id -u)" = 0 ] || { red "请用 root 运行"; exit 1; }
command -v systemctl >/dev/null || { red "需要 systemd"; exit 1; }

case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) red "不支持的架构：$(uname -m)"; exit 1 ;;
esac

DIR=$(cd "$(dirname "$0")" && pwd)
SRC="$DIR/fog2bx-linux-$ARCH"
BIN=$(mktemp)
trap 'rm -f "$BIN"' EXIT
if [ -n "$FOG2BX_URL" ]; then
  echo "下载 $FOG2BX_URL ..."
  curl -fsSL -o "$BIN" "$FOG2BX_URL" || { red "下载失败"; exit 1; }
elif [ -f "$SRC" ]; then
  cp "$SRC" "$BIN"
else
  red "找不到 $SRC"
  red "把 fog2bx-linux-$ARCH 放到 install.sh 同一个目录，或者用 FOG2BX_URL 指定下载地址"
  exit 1
fi
chmod +x "$BIN"
"$BIN" version >/dev/null || { red "$BIN 不能运行，架构对吗？"; exit 1; }

UPGRADE=0
systemctl is-active --quiet fog2bx && UPGRADE=1
"$BIN" install

if [ ! -f /etc/fog2bx/config.json ]; then
  fog2bx generate || { red "没有生成配置，之后运行 fog2bx generate 再 fog2bx start"; exit 1; }
fi
if [ $UPGRADE = 1 ]; then
  fog2bx restart
else
  fog2bx start
fi
echo
green "完成。管理菜单：fog2bx    看日志：fog2bx log"
