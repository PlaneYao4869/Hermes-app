#!/usr/bin/env python3
"""
Hermes Gateway QR Code Generator
Generate a QR code for mobile app pairing.

Usage:
    python generate_qr.py [--host HOST] [--port PORT] [--token TOKEN]

The QR code encodes connection info that the Hermes Mobile app can scan.
Requires: pip install qrcode
"""

import argparse
import json
import socket
import sys

def get_local_ip():
    """Get the local LAN IP address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def main():
    parser = argparse.ArgumentParser(description="Generate QR code for Hermes Mobile pairing")
    parser.add_argument("--host", default=None, help="Gateway host (auto-detected if not set)")
    parser.add_argument("--port", type=int, default=8642, help="Gateway port (default: 8642)")
    parser.add_argument("--token", default=None, help="Authentication token (optional)")
    parser.add_argument("--name", default=None, help="Server name (optional)")
    parser.add_argument("--json", action="store_true", help="Output JSON instead of QR code")
    args = parser.parse_args()

    host = args.host or get_local_ip()
    port = args.port

    qr_data = {
        "host": host,
        "port": port,
        "ws": f"ws://{host}:{port}/api/ws",
        "url": f"http://{host}:{port}",
        "name": args.name or socket.gethostname(),
    }
    if args.token:
        qr_data["token"] = args.token

    payload = json.dumps(qr_data)

    if args.json:
        print(payload)
        return

    try:
        import qrcode
        qr = qrcode.QRCode(version=1, box_size=1, border=1)
        qr.add_data(payload)
        qr.make(fit=True)
        qr.print_ascii(invert=True)
        print(f"\nHermes Gateway: {host}:{port}")
        print(f"WebSocket: ws://{host}:{port}/api/ws")
        print(f"\nScan this QR code with Hermes Mobile app to connect.")
    except ImportError:
        print("qrcode package not installed. Install with: pip install qrcode")
        print(f"\nManual connection info:")
        print(f"  Host: {host}")
        print(f"  Port: {port}")
        print(f"  WS:   ws://{host}:{port}/api/ws")
        print(f"\nOr use JSON mode: python generate_qr.py --json")

if __name__ == "__main__":
    main()
