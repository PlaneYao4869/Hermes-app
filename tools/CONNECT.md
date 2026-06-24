# Hermes Mobile — 连接指南

## 方案 1: 同一 WiFi（最简单）

手机和 PC 在同一 WiFi 下，直接用局域网 IP：

```bash
# 终端运行
python tools/hermes_qr.py
# 手机扫码即可
```

## 方案 2: 外网访问（手机用 4G/5G 也能连）

### 方案 2A: Cloudflare Tunnel（免费，一行命令）

```bash
# 1. 下载 cloudflared
# https://github.com/cloudflare/cloudflared/releases/latest
# 下载 cloudflared-windows-amd64.exe，重命名为 cloudflared.exe

# 2. 运行隧道
cloudflared tunnel --url http://localhost:8642
# 会输出类似: https://xxx-yyy-zzz.trycloudflare.com

# 3. 用这个地址生成 QR 码
python tools/hermes_qr.py --host xxx-yyy-zzz.trycloudflare.com
```

注意：trycloudflare.com 地址每次重启会变。绑定自定义域名可固定。

### 方案 2B: Tailscale（推荐，最稳定）

```bash
# 1. 手机和 PC 都安装 Tailscale
# PC: https://tailscale.com/download/windows
# 手机: 应用商店搜 Tailscale

# 2. 两边都登录同一个账号

# 3. 获取 PC 的 Tailscale IP
tailscale ip -4
# 输出类似: 100.x.x.x

# 4. 生成 QR 码
python tools/hermes_qr.py --host 100.x.x.x
```

手机用 4G/5G 也能通过 Tailscale 内网直连，不需要公网 IP。

### 方案 2C: frp 自建隧道（最可靠，需要 VPS）

见 tools/frp/ 目录（待补充）。

## 方案 3: mDNS 自动发现（同一网络免扫码）

手机打开 Hermes App 会自动扫描局域网的 Gateway，直接点连接。

## QR 码格式

```json
{
  "name": "PC名称",
  "host": "192.168.x.x",
  "port": 8642,
  "ws": "ws://192.168.x.x:8642/api/ws",
  "url": "http://192.168.x.x:8642",
  "token": "API_KEY",
  "version": "1.0"
}
```
