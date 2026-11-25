#!/bin/bash
# fog2bx 一键安装 / 升级。用法：
#   1. 在线安装（按 CPU 架构自动从 GitHub Release 下载对应程序并核对校验和）：
#        bash <(curl -fsSL https://raw.githubusercontent.com/FogMaly/fog2bx/main/install.sh)
#   2. 离线安装：把 install.sh 和 fog2bx-linux-amd64（或 arm64）传到节点机器同一个目录，运行 bash install.sh
#   3. 指定下载地址：FOG2BX_URL=https://你的地址/fog2bx-linux-amd64 bash install.sh
# 可选：FOG2BX_VERSION=v1.0.0 指定版本（默认装最新发布的版本）。
#       FOG2BX_STOP_OLD=y/n 事先回答「要不要停掉 V2bX / v2node / XrayR」（默认会问，没有终端时停）。
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
# 节点端口：从 fog2bx check 的输出里取（「端口 44330」）
PORTS=$(fog2bx check 2>/dev/null | grep -o '端口 [0-9]*' | cut -d' ' -f2 | sort -un || true)
# listeners PORT：占着这个 TCP 端口的进程，每行「进程名 pid」
listeners() {
  command -v ss >/dev/null || return 0
  ss -ltnp 2>/dev/null | awk -v p="$1" '$4 ~ ":"p"$"' \
    | grep -o '(("[^"]*",pid=[0-9]*' | sed 's/(("\([^"]*\)",pid=/\1 /' | sort -u || true
}
# unit_of PID：进程所属的 systemd 服务
unit_of() { sed -n 's#.*/\([^/]*\.service\)$#\1#p' "/proc/$1/cgroup" 2>/dev/null | head -1; }
# ask 提示：问 y/n，默认是。FOG2BX_STOP_OLD=y/n 时直接用它；没有终端时按默认
ask() {
  local a
  if [ -n "$FOG2BX_STOP_OLD" ]; then a=$FOG2BX_STOP_OLD
  elif [ -t 0 ]; then read -r -p "$1 (Y/n)：" a || a=
  elif (: </dev/tty) 2>/dev/null; then read -r -p "$1 (Y/n)：" a </dev/tty || a=
  fi
  case "$a" in [nN]*) return 1 ;; *) return 0 ;; esac
}

# fog2bx 是用来代替 V2bX / v2node / XrayR 的，同时跑会抢面板节点的端口，让 fog2bx 的节点起不来。
# 问过之后先把它们停掉并取消开机自启，再启动 fog2bx。配置文件不动，随时能恢复
for u in V2bX v2node XrayR; do
  systemctl is-active --quiet "$u" 2>/dev/null || systemctl is-enabled --quiet "$u" 2>/dev/null || continue
  HELD=
  for p in $PORTS; do
    while read -r name pid; do
      [ -n "$pid" ] && [ "$(unit_of "$pid")" = "$u.service" ] && HELD="$HELD $p" && break
    done <<<"$(listeners "$p")"
  done
  echo
  if [ -n "$HELD" ]; then
    yellow "检测到 $u 正在运行，占着节点端口$HELD，不停掉的话这些节点起不来"
  elif systemctl is-active --quiet "$u" 2>/dev/null; then
    yellow "检测到 $u 正在运行，fog2bx 就是用来代替它的"
  else
    yellow "检测到 $u 设了开机自启（现在没运行），重启机器后会和 fog2bx 抢端口"
  fi
  yellow "停掉后 $u 上的所有节点都会停，配置文件不动"
  if ask "停掉 $u 并取消开机自启？"; then
    systemctl stop "$u" 2>/dev/null || true
    systemctl disable "$u" >/dev/null 2>&1 || true
    green "已停止 $u 并取消开机自启（要换回：systemctl disable --now fog2bx && systemctl enable --now $u）"
  else
    yellow "保留 $u。之后要停：systemctl disable --now $u，再运行 fog2bx restart"
  fi
done

if command -v ss >/dev/null; then
  # 别的程序占着节点端口时只提示，不替用户停（可能是 nginx 之类的正经服务）
  for p in $PORTS; do
    listeners "$p" | while read -r name pid; do
      [ "$name" = fog2bx ] && continue
      unit=$(unit_of "$pid")
      if [ -n "$unit" ]; then stop="systemctl disable --now $unit"; else stop="kill $pid"; fi
      red "端口 $p 被 $name（pid $pid${unit:+，$unit}）占着，用这个端口的节点起不来"
      red "  确认它不用了就停掉：$stop，再运行 fog2bx restart"
    done
  done
fi

if [ $UPGRADE = 1 ]; then
  fog2bx restart
else
  fog2bx start
fi

# 启动后核对：每个节点端口都由 fog2bx 在监听
if command -v ss >/dev/null && [ -n "$PORTS" ]; then
  BAD=
  for i in 1 2 3 4 5; do
    sleep 1
    BAD=
    for p in $PORTS; do
      listeners "$p" | grep -q '^fog2bx ' || BAD="$BAD $p"
    done
    [ -z "$BAD" ] && break
  done
  if [ -n "$BAD" ]; then
    red "这些端口 fog2bx 没监听上：$(echo $BAD)，用 fog2bx log 看原因"
  else
    green "节点端口都已由 fog2bx 监听：$(echo $PORTS)"
  fi
fi
echo
green "完成。管理菜单：fog2bx    看日志：fog2bx log"
