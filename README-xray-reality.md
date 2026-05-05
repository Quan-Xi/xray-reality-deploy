# Xray REALITY 一键部署

这个目录里的 `deploy-xray-reality.sh` 会在 VPS 上部署：

- Xray-core
- VLESS
- REALITY
- Vision flow：`xtls-rprx-vision`
- 运行时选择直连公网端口，或放在 Nginx SNI 分流后面
- 不创建 HTTP/SOCKS 公网入口
- 不配置 access log 文件
- 默认固定安装 Xray-core `v26.3.27`

## 使用方式

把脚本上传到 VPS 后执行：

```bash
sudo bash deploy-xray-reality.sh
```

也可以直接从 GitHub 拉取并执行：

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Quan-Xi/xray-reality-deploy/main/deploy-xray-reality.sh)"
```

脚本会提示选择部署模式：

```text
1) Direct public listen, no Nginx
2) Behind Nginx SNI stream forwarding
```

模式 1 是直连模式，不需要 Nginx：

```text
客户端 -> 服务器公网 443 -> Xray REALITY
```

模式 2 适合这种部署结构：

```text
客户端 -> 服务器公网 443 -> Nginx SNI 分流 -> 127.0.0.1:10443 -> Xray REALITY
```

非交互直连部署：

```bash
sudo DEPLOY_MODE=direct PUBLIC_HOST=你的域名或服务器IP bash deploy-xray-reality.sh
```

直接从 GitHub 执行直连部署：

```bash
sudo DEPLOY_MODE=direct PUBLIC_HOST=你的域名或服务器IP bash -c "$(curl -fsSL https://raw.githubusercontent.com/Quan-Xi/xray-reality-deploy/main/deploy-xray-reality.sh)"
```

非交互 Nginx 分流部署：

```bash
sudo DEPLOY_MODE=nginx PUBLIC_HOST=proxy.example.com SNI=www.microsoft.com DEST=www.microsoft.com:443 bash deploy-xray-reality.sh
```

直接从 GitHub 执行 Nginx 分流部署：

```bash
sudo DEPLOY_MODE=nginx PUBLIC_HOST=proxy.example.com SNI=www.microsoft.com DEST=www.microsoft.com:443 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Quan-Xi/xray-reality-deploy/main/deploy-xray-reality.sh)"
```

固定其他 Xray 版本：

```bash
sudo XRAY_VERSION=v26.3.27 bash deploy-xray-reality.sh
```

执行完成后，终端会输出一条 `vless://` 链接，可以直接复制到 Shadowrocket 导入。

## Shadowrocket 参数

- 类型：VLESS
- 加密：`none`
- 流控：`xtls-rprx-vision`
- 传输：TCP
- TLS/Security：REALITY
- Fingerprint：Chrome
- 地址：脚本输出的 `Address`，或运行时传入的 `PUBLIC_HOST`
- 端口：脚本输出的 `Port`，或运行时传入的 `PUBLIC_PORT`

`SNI`、`PublicKey`、`ShortID`、`UUID` 必须和脚本输出完全一致。

## 参数说明

- `DEPLOY_MODE=direct`：Xray 直接监听公网端口，默认 `0.0.0.0:443`。
- `DEPLOY_MODE=nginx`：Xray 只监听本机端口，默认 `127.0.0.1:10443`，由 Nginx 转发公网 `443`。
- `PUBLIC_HOST`：客户端连接的地址，例如域名或服务器 IP。
- `PUBLIC_PORT`：客户端连接的公网端口，默认 `443`。
- `SNI`：REALITY 伪装站点，默认 `www.microsoft.com`。
- `DEST`：REALITY 回落目标，默认 `${SNI}:443`。

使用 Nginx SNI 分流时，Nginx `ssl_preread` 应该匹配的是 `SNI` 的值，不是 `PUBLIC_HOST`。例如 `SNI=www.microsoft.com` 时，Nginx 的分流规则应匹配 `www.microsoft.com`，再转发到 `127.0.0.1:10443`。

如果需要覆盖监听地址或端口，可以显式传入：

```bash
sudo DEPLOY_MODE=direct PORT=8443 LISTEN=0.0.0.0 PUBLIC_HOST=你的域名或服务器IP PUBLIC_PORT=8443 bash deploy-xray-reality.sh
```

## 运维命令

```bash
systemctl status xray
journalctl -u xray -e --no-pager
systemctl restart xray
```

配置文件位置：

```text
/usr/local/etc/xray/config.json
```

## 想完全冻结上游依赖

只把这个仓库放到自己的 GitHub 还不算完全冻结，因为脚本仍会下载 `XTLS/Xray-install` 安装器。更严格的做法有两种：

1. 把 `XRAY_INSTALL_URL` 从 `raw/main/install-release.sh` 改成某个 Git commit 的 raw URL。
2. 直接把 `install-release.sh` 保存进你的仓库，然后把脚本里的 `XRAY_INSTALL_URL` 改成本仓库文件地址，或改成本地路径执行。

同时建议保留 `XRAY_VERSION`，不要默认安装 latest。
