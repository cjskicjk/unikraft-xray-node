# Unikraft Xray 节点（VLESS + WS + TLS）

对应论坛帖：post-unikraft-xray.md。config.json 里的 `你的UUID` 和 `/你的路径` 换成自己的再用。

## 路线 A：有 Docker（Windows WSL + Docker Desktop，按原文）

```
unikraft build . --output <组织名>/xray-node:v1
unikraft run --metro=sin -n xray-test -m 512MiB --restart=on-failure \
  -p 443:8080/http+tls --image=<组织名>/xray-node:v1
```

## 路线 B：无 Docker（2026-11-20 实测走通：远程构建故障、本地 Docker 缺权限时用这条）

装 Go 1.27.4（Xray 源码 go.mod 要求 go 1.27，1.25 不够），拉 Xray 源码本地编静态 PIE：

```
git clone --depth 1 https://github.com/XTLS/Xray-core.git src
cd src
CGO_ENABLED=1 go build -trimpath -buildmode=pie -tags netgo \
  -ldflags "-s -w -buildid= -linkmode external -extldflags -static-pie" \
  -o ../xray ./main
cd ..
file xray   # 应显示 static-pie linked
```

再摆成 rootfs 目录，Kraftfile 的 rootfs 改指 `./rootfs`：

```
mkdir -p rootfs/usr/bin rootfs/etc/xray
cp xray rootfs/usr/bin/xray
cp config.json rootfs/etc/xray/config.json
```

Kraftfile（路线 B）：

```
spec: v0.6

runtime: base:latest

rootfs: ./rootfs

cmd: ["/usr/bin/xray", "run", "-c", "/etc/xray/config.json"]
```

然后同样 `unikraft build . --output <组织名>/xray-node:v1`，再按路线 A 的 run 命令启动。

## 验证

```
unikraft instance logs xray-test   # 看到 Xray x.x.x started
curl -s -o /dev/null -w "%{http_code}\n" https://你的域名/你的路径   # 400 即正常
```

客户端导入（路径里的 / 写成 %2F）：

```
vless://你的UUID@你的域名:443?encryption=none&security=tls&sni=你的域名&type=ws&host=你的域名&path=%2F你的路径#unikraft-test
```

## 已知坑（2026-11-20）

- 远程构建平台侧故障：构建器拉不到 buildkit 镜像，dal/sin 都一样，别试。
- 第一个实例的边缘可能把 WS 响应头改成 `Connection: upgrade, close`，sing-box 报 bad Connection header：删实例重建即可，同一镜像同一配置。
- 8443/tls 端口是死的，别加。
- 不写 --scale-to-zero，默认不休眠，适合常驻代理。
- 客机文件描述符上限低，并发一多会短暂断连：2026-11-20 13:17 实测，Xray 在约 35 秒内报了 83 次 `too many open files`，那段时间接不了任何新连接，之后自己恢复。config.json 已加 policy（connIdle 300→60 秒，uplinkOnly/downlinkOnly 1→0），空闲连接更快断开，降低复发概率；2026-11-21 已部署为镜像 v2。这只是缓解，并发一高仍可能耗尽，反复出现就重启实例清掉。
