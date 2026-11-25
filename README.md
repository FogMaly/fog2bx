# fog2bx

对接 Xboard 的节点程序，代替 v2node / V2bX，只跑两种协议：

- **VLESS + REALITY**（Vision）
- **AnyTLS + REALITY**

用法照着 V2bX：一份配置里列多个节点，用 `fog2bx` 命令（不带参数进菜单）管理服务。
内核是 **官方原版 sing-box 1.14.4**，没有用任何人改过的分支。协议、TLS、REALITY 都是 sing-box 自己的实现；
本程序只负责和面板对接，代码在这个目录里，一共几百行。

## 安装

面板上要先装好 `AnytlsReality` 插件（AnyTLS 的 REALITY 密钥靠它下发），并在面板上建好节点。

### 一键安装（推荐）

在节点机器上用 root 运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/FogMaly/fog2bx/main/install.sh)
```

脚本会按机器的 CPU 架构（amd64 / arm64）从 [Releases](https://github.com/FogMaly/fog2bx/releases) 下载对应的程序，
核对 SHA256 校验和，然后进入下面说的「生成配置」。没有 curl 的机器会自动改用 wget。

- 指定版本：`FOG2BX_VERSION=v1.0.0 bash <(curl -fsSL ...)`，默认装最新发布的版本
- 机器连不上 GitHub 时，把程序放到自己的地址：`FOG2BX_URL=https://.../fog2bx-linux-amd64 bash install.sh`

### 离线安装

把 `fog2bx-1.0.0-linux.tar.gz` 传到节点机器上：

```bash
tar xzf fog2bx-1.0.0-linux.tar.gz
cd fog2bx
bash install.sh
```

安装包里同时有 amd64 和 arm64 两个程序，`install.sh` 会按机器架构选。

脚本会：

1. 把程序装到 `/usr/local/bin/fog2bx`，并注册 systemd 服务、设为开机自启；
2. 没有配置文件时进入「生成配置」：填面板地址和通讯密钥，再逐个选协议（1 VLESS+REALITY / 2 AnyTLS+REALITY）、填节点 ID。
   每填一个都会马上连面板核对：节点存不存在、协议对不对、REALITY 密钥有没有、这台机器能不能把它跑起来；
3. **先关掉旧的节点程序**：V2bX / v2node / XrayR 在运行或设了开机自启的，停掉并取消开机自启（配置文件不动）。
   它们和 fog2bx 同时跑会抢面板节点的端口，fog2bx 的节点会一直报 `address already in use` 起不来；
   节点端口被其他程序（如 nginx）占着时只提示，不会替你停；
4. 启动（升级时重启）服务，再核对每个节点端口都由 fog2bx 监听上了。

已经装过时再运行一次 `install.sh`（或一键安装命令）就是升级：替换程序、保留配置、关掉旧程序、重启。

要换回 V2bX：`systemctl disable --now fog2bx && systemctl enable --now V2bX`。

## 管理

```
fog2bx            管理菜单
fog2bx start | stop | restart | status
fog2bx log        实时日志
fog2bx generate   重新生成配置（交互式）
fog2bx check      核对配置：逐个节点连面板检查，不占端口，运行中也能用
fog2bx x25519     生成 REALITY 密钥对（VLESS 节点要填到面板上）
fog2bx uninstall  卸载（保留配置）
fog2bx version
```

## 配置文件 `/etc/fog2bx/config.json`

字段名和 V2bX 一样：

```json
{
  "Log": { "Level": "warn" },
  "AllowPrivate": false,
  "Nodes": [
    { "ApiHost": "https://panel.example.com", "ApiKey": "通讯密钥", "NodeID": 1, "NodeType": "anytls" },
    { "ApiHost": "https://panel.example.com", "ApiKey": "通讯密钥", "NodeID": 3, "NodeType": "vless" }
  ]
}
```

| 字段 | 说明 |
|---|---|
| `Log.Level` | `warn`（默认）只记问题；`info` 记录每条连接 |
| `AllowPrivate` | 是否允许用户访问节点机器所在的内网（127.0.0.1、10.x、172.16.x、192.168.x 等），默认不允许 |
| `Nodes[].NodeType` | 可不填。填了会核对面板上的节点是不是这个协议，防止节点 ID 填错把别的节点跑起来 |

端口、伪装域名、REALITY 密钥、AnyTLS 填充方案、上报间隔全部从面板拉，改面板就行，节点不用动。
配置文件里有通讯密钥，权限是 600（只有 root 能读）。

## 功能

| | |
|---|---|
| 用户同步 | 按面板的拉取间隔同步。加用户不影响别人；删除的用户、改了 UUID 或限制的用户，正在用的连接会被断开（实测 2–4 秒） |
| 流量上报 | 按面板的推送间隔上报；上报失败的流量留到下次补报，退出前会先把剩下的报掉 |
| 限速 | 面板用户的「限速」（Mbps），上传下载各算 |
| 设备数限制 | 面板用户的「设备数限制」，按在线 IP 算，包括这个用户在其他节点上的设备。同一台设备断开后重连不会被自己锁在外面 |
| 在线 IP | 上报给面板，面板后台能看到 |
| 节点配置变化 | 面板上改了端口、密钥等，下次拉取时自动换上；新配置有问题就继续用旧的并在日志里说明 |
| 填充方案 | 用面板下发的 AnyTLS 填充方案；节点会再检查一遍，有问题就改用默认方案，不会把客户端搞断线 |
| 内网保护 | 默认拒绝用户访问节点机器所在的内网 |
| 多节点 | 一台机器跑多个节点，互不影响：一个节点配置有问题，其他节点照常运行 |

不支持的（遇到会在日志里说明）：面板的路由规则（审计规则）、REALITY 以外的 TLS、TCP 以外的传输方式、其他协议。

## 编译

需要 Go 1.25.5 及以上（和 sing-box 1.14 一致）。

```bash
sh build.sh      # 输出 build/fog2bx-linux-amd64 和 build/fog2bx-linux-arm64
go test -tags with_utls .
```

`with_utls` 编译标签是 REALITY 服务端必需的。

## 测试结果（2026-11-12）

测试环境：Xboard（2025-11 镜像）+ AnytlsReality 插件；节点在跑真 systemd 的 Debian 12 容器里用 `install.sh` 安装。
arm64 版本在 QEMU 模拟的 arm64 Debian 12 里跑了同一套客户端测试，结果相同。

真实客户端连接，TCP 和 UDP 都测：

| 客户端 | AnyTLS+REALITY | VLESS+REALITY+Vision |
|---|---|---|
| sing-box 1.14.4 | ✓ | ✓ |
| Hiddify | ✓ | ✓ |
| mihomo 1.19.33 | — | ✓ |
| v2rayN（sing-box 内核） | ✓ | ✓ |
| v2rayN（Xray 内核） | — | ✓ |

mihomo 和 v2rayN 的 Xray 内核本身不支持 AnyTLS+REALITY，所以是「—」。

和面板的配合（两种协议各测一遍，23 项全过）：流量记入面板、新用户 10 秒内能连、删除用户后正在下载的连接 2–4 秒内断开且不能再连、
限速 1 Mbps 实测 122–126 KB/s、设备数限制 1 时第二个 IP 被拒绝且第一台设备断开重连正常、禁止访问内网、面板填充方案在客户端实际生效。

systemd：开机自启已设上；`kill -9` 后 systemd 自动拉起；下载 2 MB 后马上 `fog2bx stop`，停止用 0.3 秒，
这 2 MB 退出前已报进面板（面板 +2,008,929 字节，多出的是 HTTP 头）；常驻内存约 5 MB。
