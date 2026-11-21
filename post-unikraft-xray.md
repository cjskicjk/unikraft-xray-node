标题：在 Unikraft Cloud 上自建 Xray 节点（VLESS + WebSocket + TLS，免费，附源码）

原文参考：加西（gaoyy9）2026-11-19 的 X 文章《在 Unikraft Cloud 上部署 Xray 节点（VLESS + WebSocket + TLS）》，https://x.com/gaoyy9/status/2123457160516604292

## 这是什么

在 Unikraft Cloud 的免费层上跑一个 Xray 节点：VLESS + WebSocket + TLS，443 端口，客户端导入一条链接就能用。

免费层 Hobby 是 $0 永久：2 个运行实例、2 vCPU、4 GiB 内存、5 个 standby 实例、8 GiB 存储。机房有 dal、fra、sfo、sin、was 五个，国内用选 sin（新加坡）最近。

实测：2026-11-20 按下面步骤搭完，sing-box 经节点访问 Google 200，共测 3 次都通，出口 IP 173.234.10.239（新加坡）。

## 准备工作

1. 一个 Unikraft 账号：https://console.unikraft.com 注册，免费层不用绑卡（注册第 2 步如果索要银行卡，先停下确认）
2. 本机装 unikraft 命令行：

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://unikraft.com/cli/install.sh | sh
echo 'export PATH=$HOME/.local/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

3. 附件里的 unikraft-xray.zip，解压得到 config.json、Kraftfile、Dockerfile、README

## 部署步骤

### 第 1 步：登录

```bash
unikraft login
```

浏览器打开登录页授权。注意两点：命令行只等约 30 秒，浏览器授权慢了设备码就过期，得重拿新码再授一次；谷歌登录可能要手机点数字匹配验证，按浏览器页上显示的数字点就行。

登录后看组织名：

```bash
unikraft profile list
```

输出里 NAME 那一列就是组织名，下文用 `<组织名>` 表示。

### 第 2 步：准备项目文件

```bash
mkdir ~/xray-test && cd ~/xray-test
```

生成一个 UUID（相当于节点密码），再自己定一个随机路径，比如 `/ws-k7q2x9`：

```bash
cat /proc/sys/kernel/random/uuid
```

把附件里的 config.json、Kraftfile、Dockerfile 放进这个目录，把里面的 `你的UUID` 和 `/你的路径` 换成自己的。

config.json（Xray 监听 8080，VLESS + ws）：

```json
{
  "log": { "loglevel": "warning" },
  "dns": { "servers": ["1.1.1.1", "8.8.8.8"] },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "你的UUID" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/你的路径" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "settings": { "domainStrategy": "UseIPv4" } }
  ]
}
```

关键：Xray 必须是从源码编译成的静态 PIE 格式，官方下载的二进制不是 PIE，在 Unikraft 上启动会报 `ELF executable is not position-independent` 然后马上退出。附件 Dockerfile 里就是按这个要求写的：

```dockerfile
FROM golang:bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends git gcc libc6-dev ca-certificates \
 && git clone --depth 1 https://github.com/XTLS/Xray-core.git /src
WORKDIR /src
RUN CGO_ENABLED=1 go build -trimpath -buildmode=pie -tags netgo \
    -ldflags "-s -w -buildid= -linkmode external -extldflags -static-pie" \
    -o /xray ./main

FROM scratch
COPY --from=build /xray /usr/bin/xray
COPY config.json /etc/xray/config.json
```

Kraftfile：

```
spec: v0.6

runtime: base:latest

rootfs: ./Dockerfile

cmd: ["/usr/bin/xray", "run", "-c", "/etc/xray/config.json"]
```

### 第 3 步：构建镜像并部署

```bash
cd ~/xray-test
unikraft build . --output <组织名>/xray-node:v1
```

第一次构建要下载 Go 环境和源码，需要几分钟，最后出现 `saved image output=oci://...` 就是成功了。

启动实例：

```bash
unikraft run --metro=sin -n xray-test -m 512MiB --restart=on-failure \
  -p 443:8080/http+tls --image=<组织名>/xray-node:v1
```

参数说明：`--metro=sin` 是新加坡机房；`-m 512MiB` 内存只认 MiB/M，写 512Mi 会报错；`-p 443:8080/http+tls` 里 443 必须写成 http+tls；`--restart=on-failure` 崩溃后自动重启；**不写 `--scale-to-zero`**，默认不休眠，正适合常驻代理（开了 scale-to-zero，闲时实例会停机）。

成功输出里会有：

```
state:   running
  - fqdn:  xxxx-xxxx-xxxxxxxx.sin.unikraft.app
```

fqdn 后面就是你的节点域名。

### 第 4 步：检查

看日志：

```bash
unikraft instance logs xray-test
```

能看到 `Xray x.x.x started` 就说明启动成功了。日志里的 libvirtio 报错和 WebSocket、domainStrategy 的弃用警告都可以不管。

用 curl 测一下，返回 400 说明 Xray 正常：

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://你的域名/你的路径
```

## 客户端配置

在 v2rayN、v2rayNG、Clash Verge 这类客户端里导入下面的链接（把域名、UUID、路径换成你自己的，路径里的 `/` 要写成 `%2F`）：

```
vless://你的UUID@你的域名:443?encryption=none&security=tls&sni=你的域名&type=ws&host=你的域名&path=%2F你的路径#unikraft-test
```

也可以手动填：协议 VLESS，地址你的域名，端口 443，UUID 你的 UUID，加密 none，传输 ws，路径 /你的路径，TLS 开启，SNI 填你的域名。

## 踩坑记录（都是 2026-11-20 实测遇到的）

- **远程构建走不通**：`unikraft build` 的远程构建服务当时有平台侧故障，构建器实例一直 standby，报 `platform stop: image pull failed`，拉不到自己的 buildkit 镜像，换 dal、sin 机房都一样，删构建器重建也没用。这条路先别试。
- **本地 Docker 也可能起不来**：有的环境缺 cap_net_admin 权限，dockerd 建 NAT 链报 Permission denied，Docker 构建直接失败。走不通就换下面这条路。
- **能走通的替代路：本地用 Go 编，再本地打包**：装 Go 1.27.4（Xray 源码 go.mod 要求 go 1.27，1.25 不够），按 Dockerfile 里同一条命令本地编出静态 PIE 版 Xray（`file` 验证是 `static-pie linked`），放进 `rootfs/usr/bin/xray`，config.json 放进 `rootfs/etc/xray/config.json`，Kraftfile 的 rootfs 改指目录 `./rootfs`，再 `unikraft build .`，不用 Docker、不用远程构建，直接出镜像。附件 README 里有这条路的完整命令。
- **第一个实例可能有边缘问题**：Xray 启动正常、curl 路径回 400、WS 升级回 101，但 sing-box 实测报 `handshake error: bad "Connection" header`——那个实例的边缘把响应头改成了 `Connection: upgrade, close`，严格客户端拒绝。解决办法：删掉这个实例重建一个，同一镜像、同一配置，新实例就正常了。
- **8443/tls 端口是死的**：别加，不用管。
- **Kraftfile 的 spec v0.6 会报版本旧**：构建日志提示 `spec version is older than minimum`，不影响出镜像，不用改。
- **客机文件描述符上限低，并发一多会短暂断连**：2026-11-20 13:17 实测，Xray 在约 35 秒内报了 83 次 `too many open files`，那段时间接不了任何新连接，之后自己恢复。config.json 已加 policy（connIdle 300→60 秒，uplinkOnly/downlinkOnly 1→0），空闲连接更快断开，降低复发概率；2026-11-21 已部署为镜像 v2。这只是缓解，并发一高仍可能耗尽，反复出现就重启实例清掉。

## 注意事项

- 免费层同时只能跑 2 个运行实例，规划好别超
- UUID 和 WS 路径相当于节点密码，别发到公开地方，帖子里只贴占位符
- scale-to-zero 只适合断断续续的小工具，别拿它跑常驻服务

## 附件

unikraft-xray.zip：config.json（占位符版）、Kraftfile、Dockerfile、README（含无 Docker 的本地编译路线）
