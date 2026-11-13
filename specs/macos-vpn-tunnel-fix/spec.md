# Feature Specification: macOS VPN (TUN Service) 流量转发与构建修复

## 1. 背景与业务价值 (Background & Why)
在 macOS 平台上，用户将 Hiddify 代理模式从「系统代理 (System Proxy)」切换为「VPN (TUN)」模式时，虽然客户端显示连接成功，且系统弹窗请求了管理员权限并拉起了后台特权隧道服务（`HiddifyTunnelService`），但实际网络流量并未经过代理节点，而是全部变成了直连（Direct）或出现回环阻塞。
解决此核心缺陷可确保 macOS 用户在普通用户权限下开启 VPN 模式时，系统全局 TCP/UDP 流量均能通过 `utun` 虚拟网卡准确路由至主进程代理核心，实现真正的系统级全局透明代理。

## 2. 用户故事 (User Stories)
- **作为** macOS 桌面端用户，**我希望** 在开启 VPN 模式并授予管理员权限后，所有应用的网络流量都能正常通过所选代理节点转发，**以便** 不支持系统代理的终端工具与原生应用也能正常使用代理网络。
- **作为** 项目维护者与构建发布者，**我希望** 执行 macOS 构建打包流程时自动编译本地最新的 `libcore.dylib` 与 `HiddifyCli` 双架构二进制，**以便** 对 `libcore` 隧道服务的修复能真实生效于最终生成的 `.dmg` / `.pkg` 安装包中。

## 3. 范围与边界 (Scope & Non-Goals)
### 包含范围 (In Scope)
- 修复后台特权隧道服务（`TunnelService`）生成的 sing-box 配置中关于默认出站路由与 macOS 应用包进程豁免的规则；
- 修复 macOS 下通过 `osascript` 提权安装/启动 `HiddifyTunnelService` 时的端口就绪检测与回退直接运行机制；
- 修复 macOS 构建脚本（`Makefile` 与 `libcore/Makefile`），确保本地源码编译通用二进制（Universal Binary）并同时产出 `libcore.dylib` 和 `HiddifyCli`。

### 排除范围 (Out of Scope / Non-Goals)
- 不改变 Windows 或 Android/iOS 平台的 TUN 驱动架构；
- 不引入 Apple Developer 付费 Network Extension (NEPacketTunnelProvider) 签名体系，保持现有的 root 守护进程 `utun` 桥接方案。

## 4. 验收准则 (Acceptance Criteria - AC)
1. **Given** 用户在 macOS 下以非 root 普通权限启动 Hiddify 并选择「VPN」模式点击连接，**When** 授权管理员密码拉起隧道服务后，**Then** 本地 `127.0.0.1:18020` 隧道控制端口处于监听状态且 `utun` 接口成功创建。
2. **Given** 隧道服务已启动并接管系统路由，**When** 任何非 Hiddify 自身的系统进程发起公网连接（未命中私有 IP 与 DNS 规则），**Then** 流量必须100%命中默认出站（`socks-out`）转发至主进程 Mixed 端口（如 `127.0.0.1:12334`），严禁落入直连出站或产生死循环回环。
3. **Given** Hiddify 主应用运行在 `/Applications/Hiddify.app/Contents/MacOS/Hiddify` 路径下，**When** 主应用向远端代理服务器发起连接，**Then** 隧道服务能够通过进程名与 `.app` 路径正则准确豁免主进程流量直连出站，避免 TUN 回环死锁。
4. **Given** 开发者执行 `make macos-prepare` 或 `make build-macos-libs`，**When** 构建命令完成，**Then** `libcore/bin` 目录下必须生成由本地最新 Go 源码编译出的 Universal 架构 `libcore.dylib` 与 `HiddifyCli`，而非从远端下载旧版预编译压缩包覆盖。

## 5. 极端场景与边界条件 (Edge Cases & Failure Modes)
- **LaunchDaemon 服务未即时拉起**：在部分 macOS 系统版本中，`launchctl` 注册 `HiddifyTunnelService` 后可能因权限或 SIP 状态未立即监听 `18020` 端口；此时即使 `install` 命令返回码为 0，系统也必须在等待超时后自动检测端口占用并回退到 `tunnel run` 直接提权启动。
- **构建包内缺少独立 CLI 可执行文件**：若 App Bundle 的 `Frameworks` 目录中仅有 `libcore.dylib` 或同时存在 `HiddifyCli`，构建脚本与路径查找器均需保证一致可用。