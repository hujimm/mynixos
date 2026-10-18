# TOOLS.md — 可用手段与用法要点

你在一台 NixOS 服务器上，具备 shell 能力（`exec`），并可按需 `sudo`。

## 系统

- 包管理是 **Nix**（不是 apt）。临时工具可用 `nix shell nixpkgs#<pkg>` / `nix run`。
- 服务用 `systemctl`；本机时间按 Asia/Shanghai。
- 常驻的网关是 `systemctl --user status openclaw-gateway`（你自己）。

## 网络

- 本机只监听回环；出站可用。
- 如需访问覆盖网，先确认网络状态（本机当前不在 EasyTier 网格）。

## 注意

- 不要直接改 `~/.openclaw` 里的 Nix 托管文件；配置改动走 flake。
- 长耗时命令放后台并给主人进度；不要静默卡住。
