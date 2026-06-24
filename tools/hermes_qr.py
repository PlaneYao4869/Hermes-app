#!/usr/bin/env python3
"""
hermes qr — 为 Hermes Mobile App 生成连接用 QR 码

用法:
    hermes qr                    # 自动检测 Gateway 配置
    hermes qr --host 1.2.3.4     # 指定外部地址
    hermes qr --port 8642        # 指定端口
    hermes qr --tunnel           # 使用 Cloudflare Tunnel 地址

在任何安装了 Hermes 的机器上都能用。
"""

import argparse
import json
import os
import socket
import sys
from pathlib import Path


def find_hermes_home():
    """查找 Hermes 配置目录"""
    # 优先 HERMES_HOME 环境变量
    env_home = os.environ.get("HERMES_HOME")
    if env_home and Path(env_home).exists():
        return Path(env_home)
    # 默认位置
    local_app_data = os.environ.get("LOCALAPPDATA", "")
    default = Path(local_app_data) / "hermes"
    if default.exists():
        return default
    home = Path.home()
    dot_hermes = home / ".hermes"
    if dot_hermes.exists():
        return dot_hermes
    return None


def read_api_key(hermes_home):
    """从 .env 或 config.yaml 读取 API key"""
    # 尝试 .env
    env_file = hermes_home / ".env"
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("API_SERVER_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")

    # 尝试 config.yaml
    config_file = hermes_home / "config.yaml"
    if config_file.exists():
        try:
            import yaml
            with open(config_file, "r", encoding="utf-8") as f:
                config = yaml.safe_load(f)
            api_config = config.get("api_server", {})
            key = api_config.get("key", "")
            if key:
                return key
        except ImportError:
            # 没有 yaml 库，手动解析
            in_api = False
            for line in config_file.read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if stripped == "api_server:":
                    in_api = True
                    continue
                if in_api:
                    if stripped.startswith("key:"):
                        return stripped.split(":", 1)[1].strip().strip('"').strip("'")
                    if stripped and not stripped.startswith(" ") and not stripped.startswith("\t"):
                        break
    return None


def read_gateway_state(hermes_home):
    """从 gateway_state.json 读取 Gateway 状态"""
    state_file = hermes_home / "gateway_state.json"
    if state_file.exists():
        try:
            return json.loads(state_file.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return None


def get_local_ip():
    """获取局域网 IP"""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def get_tailscale_ip():
    """尝试获取 Tailscale IP"""
    try:
        result = os.popen("tailscale ip -4 2>/dev/null").read().strip()
        if result and result.startswith("100."):
            return result
    except Exception:
        pass
    return None


def main():
    parser = argparse.ArgumentParser(
        description="为 Hermes Mobile App 生成连接 QR 码"
    )
    parser.add_argument("--host", help="Gateway 外部地址（默认自动检测）")
    parser.add_argument("--port", type=int, default=8642, help="Gateway 端口（默认 8642）")
    parser.add_argument("--key", help="API Key（默认从配置读取）")
    parser.add_argument("--tunnel", action="store_true", help="使用 Cloudflare Tunnel 地址")
    parser.add_argument("--json", action="store_true", help="只输出 JSON，不显示 QR 码")
    parser.add_argument("--name", help="服务器名称（显示用）")
    args = parser.parse_args()

    hermes_home = find_hermes_home()
    if not hermes_home:
        print("错误: 找不到 Hermes 配置目录", file=sys.stderr)
        print("请设置 HERMES_HOME 环境变量，或确认 Hermes 已安装", file=sys.stderr)
        sys.exit(1)

    # 读取 API key
    api_key = args.key or read_api_key(hermes_home)
    if not api_key:
        print("错误: 找不到 API_SERVER_KEY", file=sys.stderr)
        print(f"检查 {hermes_home / '.env'} 或 {hermes_home / 'config.yaml'}", file=sys.stderr)
        sys.exit(1)

    # 检查 Gateway 是否运行
    state = read_gateway_state(hermes_home)
    gateway_running = state and state.get("gateway_state") == "running"

    # 确定 host
    if args.host:
        host = args.host
    elif args.tunnel:
        # 尝试从环境变量或配置读取 tunnel URL
        tunnel_url = os.environ.get("HERMES_TUNNEL_URL", "")
        if not tunnel_url:
            print("错误: 请设置 HERMES_TUNNEL_URL 环境变量", file=sys.stderr)
            print("或使用 --host 指定 tunnel 地址", file=sys.stderr)
            sys.exit(1)
        host = tunnel_url
    else:
        host = get_local_ip()

    port = args.port

    # 获取 Tailscale IP 作为备选
    tailscale_ip = get_tailscale_ip()

    # 构建连接信息
    ws_url = f"ws://{host}:{port}/api/ws"
    http_url = f"http://{host}:{port}"
    server_name = args.name or socket.gethostname()

    qr_data = {
        "name": server_name,
        "host": host,
        "port": port,
        "ws": ws_url,
        "url": http_url,
        "token": api_key,
        "version": "1.0",
    }

    if args.json:
        print(json.dumps(qr_data, indent=2, ensure_ascii=False))
        return

    # 显示状态
    print(f"\n  Hermes Gateway QR 码生成器")
    print(f"  {'=' * 40}")
    print(f"  配置目录: {hermes_home}")
    print(f"  Gateway:  {'运行中 ✓' if gateway_running else '未运行 ✗'}")
    print(f"  服务器:   {server_name}")
    print(f"  地址:     {host}:{port}")
    print(f"  WebSocket: {ws_url}")
    if tailscale_ip and host != tailscale_ip:
        print(f"  Tailscale: {tailscale_ip}:{port} (备选)")
    print()

    # 生成 QR 码
    try:
        import qrcode
        qr = qrcode.QRCode(version=1, box_size=1, border=1)
        qr.add_data(json.dumps(qr_data, ensure_ascii=False))
        qr.make(fit=True)
        qr.print_ascii(invert=True)
    except ImportError:
        print("需要安装 qrcode 库: pip install qrcode")
        print(f"\n手动连接信息:")
        print(json.dumps(qr_data, indent=2, ensure_ascii=False))
        return

    print(f"\n  用 Hermes Mobile App 扫描上方 QR 码即可连接")
    if tailscale_ip and host != tailscale_ip:
        print(f"  外网访问请用 Tailscale: {tailscale_ip}:{port}")
    print()


if __name__ == "__main__":
    main()
