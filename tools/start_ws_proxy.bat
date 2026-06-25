@echo off
echo Starting Hermes WebSocket Proxy on port 8643...
echo Gateway: http://127.0.0.1:8642
echo Connect: ws://0.0.0.0:8643/ws
echo.
echo Press Ctrl+C to stop
echo.
python "%~dp0ws_proxy.py" --host 0.0.0.0 --port 8643 --gateway http://127.0.0.1:8642 --key hermes-mobile-2026
pause
