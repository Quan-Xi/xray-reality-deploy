# Xray REALITY 一键部署

这个目录里的 `deploy-xray-reality.sh` 会在 VPS 上部署：

- Xray-core
- VLESS
- REALITY
- Vision flow：`xtls-rprx-vision`
- 默认本机监听 `127.0.0.1:10443`
- 可通过 `PUBLIC_HOST` / `PUBLIC_PORT` 输出公网连接地址，适合前面有 Nginx 443 SNI 分流的场景
- 不创建 HTTP/SOCKS 公网入口
- 不配置 access log 文件
- 默认固定安装 Xray-core `v26.3.27`

## 使用方式

把脚本上传到 VPS 后执行：

```bash
sudo bash deploy-xray-reality.sh
```

默认配置适合这种部署结构：

```text
proxy.example.com:443 -> Nginx SNI 分流 -> 127.0.0.1:10443 -> Xray REALITY
```

自定义本机监听端口、公网地址或伪装站点：

```bash
sudo PORT=10443 LISTEN=127.0.0.1 PUBLIC_HOST=proxy.example.com PUBLIC_PORT=443 SNI=www.microsoft.com DEST=www.microsoft.com:443 bash deploy-xray-reality.sh
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

如果不使用 Nginx 分流、想让 Xray 直接监听公网端口，可以显式覆盖：

```bash
sudo PORT=443 LISTEN=0.0.0.0 PUBLIC_HOST=你的域名或服务器IP PUBLIC_PORT=443 bash deploy-xray-reality.sh
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
