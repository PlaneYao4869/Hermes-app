#!/usr/bin/env python3
"""
WebSocket proxy for Hermes Gateway.
Runs on port 8643, bridges WebSocket clients to Gateway REST API.

Usage: python ws_proxy.py [--port 8643] [--gateway http://localhost:8642]

Protocol (JSON over WebSocket):
  Client: {"type":"chat","session_id":"...","content":"hello"}
  Server: {"type":"delta","content":"hel"}
  Server: {"type":"delta","content":"lo"}
  Server: {"type":"done","content":"hello world"}
  Server: {"type":"error","message":"..."}
"""

import asyncio
import json
import sys
import argparse
from aiohttp import web, ClientSession

class WebSocketProxy:
    def __init__(self, gateway_url, api_key):
        self.gateway_url = gateway_url
        self.api_key = api_key
        self.session = None
    
    async def get_session(self):
        if self.session is None:
            self.session = ClientSession()
        return self.session
    
    async def handle_ws(self, request):
        ws = web.WebSocketResponse()
        await ws.prepare(request)
        
        await ws.send_json({"type": "ready"})
        
        try:
            async for msg in ws:
                if msg.type == web.WSMsgType.TEXT:
                    try:
                        data = json.loads(msg.data)
                        msg_type = data.get("type", "")
                        
                        if msg_type == "chat":
                            session_id = data.get("session_id")
                            content = data.get("content", "")
                            if content:
                                await self._handle_chat(ws, session_id, content)
                        
                        elif msg_type == "ping":
                            await ws.send_json({"type": "pong"})
                    
                    except json.JSONDecodeError:
                        await ws.send_json({"type": "error", "message": "Invalid JSON"})
                    except Exception as e:
                        await ws.send_json({"type": "error", "message": str(e)})
                
                elif msg.type == web.WSMsgType.ERROR:
                    break
        except Exception:
            pass
        
        return ws
    
    async def _handle_chat(self, ws, session_id, content):
        session = await self.get_session()
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        
        if session_id:
            url = f"{self.gateway_url}/api/sessions/{session_id}/chat/stream"
            body = {"message": content, "stream": True}
        else:
            url = f"{self.gateway_url}/v1/chat/completions"
            body = {
                "messages": [{"role": "user", "content": content}],
                "stream": True,
            }
        
        try:
            async with session.post(url, json=body, headers=headers, timeout=None) as resp:
                if resp.status != 200:
                    error_text = await resp.text()
                    await ws.send_json({"type": "error", "message": f"HTTP {resp.status}: {error_text[:200]}"})
                    return
                
                current_event = ""
                async for line in resp.content:
                    line_str = line.decode("utf-8", errors="replace").strip()
                    
                    if line_str.startswith("event: "):
                        current_event = line_str[7:].strip()
                        continue
                    
                    if line_str.startswith("data: "):
                        data_str = line_str[6:].strip()
                        if data_str == "[DONE]":
                            break
                        if not data_str:
                            continue
                        
                        try:
                            json_data = json.loads(data_str)
                            
                            # OpenAI format
                            choices = json_data.get("choices")
                            if choices:
                                delta = choices[0].get("delta", {})
                                c = delta.get("content", "")
                                if c:
                                    await ws.send_json({"type": "delta", "content": c})
                                continue
                            
                            # Hermes session format
                            if current_event == "assistant.delta":
                                delta = json_data.get("delta", "")
                                if delta:
                                    await ws.send_json({"type": "delta", "content": delta})
                                continue
                            
                            if current_event == "assistant.completed":
                                final = json_data.get("content", "")
                                if final:
                                    await ws.send_json({"type": "done", "content": final})
                                continue
                            
                            # Skip metadata events
                            if current_event in ("run.started", "message.started", "run.completed"):
                                continue
                        
                        except json.JSONDecodeError:
                            pass
                
                await ws.send_json({"type": "done", "content": ""})
        
        except Exception as e:
            await ws.send_json({"type": "error", "message": str(e)})
    
    async def handle_health(self, request):
        return web.json_response({"status": "ok", "proxy": "hermes-ws"})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8643)
    parser.add_argument("--gateway", default="http://127.0.0.1:8642")
    parser.add_argument("--key", default="hermes...26")
    parser.add_argument("--host", default="0.0.0.0")
    args = parser.parse_args()
    
    proxy = WebSocketProxy(args.gateway, args.key)
    
    app = web.Application()
    app.router.add_get("/ws", proxy.handle_ws)
    app.router.add_get("/health", proxy.handle_health)
    
    print(f"WebSocket proxy starting on {args.host}:{args.port}")
    print(f"Gateway: {args.gateway}")
    print(f"Connect: ws://{args.host}:{args.port}/ws")
    
    web.run_app(app, host=args.host, port=args.port, print=None)


if __name__ == "__main__":
    main()
