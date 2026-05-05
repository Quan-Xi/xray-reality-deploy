# Xray REALITY 一键部署

这个目录里的 `deploy-xray-reality.sh` 会在 VPS 上部署：

- Xray-core
- VLESS
- REALITY
- Vision flow：`xtls-rprx-vision`
- 单端口 TCP，默认 `443`
- 不创建 HTTP/SOCKS 公网入口
- 不配置 access log 文件
- 默认固定安装 Xray-core `v26.3.27`

## 使用方式

把脚本上传到 VPS 后执行：

```bash
sudo bash deploy-xray-reality.sh
```

自定义端口或伪装站点：

```bash
sudo PORT=443 SNI=www.microsoft.com DEST=www.microsoft.com:443 bash deploy-xray-reality.sh
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

`SNI`、`PublicKey`、`ShortID`、`UUID` 必须和脚本输出完全一致。

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
