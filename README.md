# Hermes Mobile

Hermes Agent 的移动端远程控制应用。通过手机随时随地控制你的 AI 编程代理。

## 功能

- **实时对话** — WebSocket 流式消息，实时查看 Agent 输出
- **审批管理** — 一键批准/拒绝 Agent 的工具调用请求
- **语音输入** — 按住说话，自动转文字发送
- **代码浏览** — 浏览 Git 仓库文件树，查看代码
- **Diff 审查** — 查看代码变更，统一/并排视图
- **Agent 编排** — 创建和管理多 Agent 任务
- **会话历史** — 查看所有平台的历史会话
- **离线草稿** — 离线写 prompt，恢复网络自动发送

## 连接方式

手机通过以下方式连接到你的 Hermes Gateway（PC）:

1. **Tailscale**（推荐）— 零配置 VPN，手机直连家里 PC
2. **局域网** — 同一 WiFi 下直接用局域网 IP
3. **Cloudflare Tunnel** — 无需暴露端口

## 架构

```
手机 App (Flutter)
    ↕ WebSocket + REST API
Hermes Gateway (PC, port 8642)
    ↕
Hermes Agent Runtime
```

## 技术栈

- Flutter 3.x + Riverpod
- WebSocket 实时通信
- Material Design 3 深色主题

## 开发

```bash
flutter pub get
flutter run              # 连接设备运行
flutter build apk        # 编译 APK
flutter build windows    # 编译 Windows 版
```

## 配置

首次打开 App，进入设置页面配置 Gateway 连接：

- 主机地址：你的 PC 的 Tailscale IP 或局域网 IP
- 端口：8642（默认）
- Token：可选认证 token
