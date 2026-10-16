# ─────────────────────────────────────────────────────────────────────────────
# 【已停用 · 放入垃圾桶】cua-driver：Computer Use 后台桌面驱动（trycua/cua）
#
# 移除日期：2026-10-14
# 移除原因：用户判定用不上。niri（纯 Wayland）下这个驱动只能"看"不能"操作"：
#   · 能看：整屏截图（tier-1 wlr-screencopy 车道）、list_windows / list_apps 可用；
#   · 不能用：所有输入动作被驱动主动拒绝——
#       foreground_unavailable: no trusted Wayland compositor adapter can confirm
#         exact target window（上游没有 niri 目标窗口 adapter）
#       background_unavailable: Electron/Chromium 不接受 X11 后台注入
#   · 上游无进展：issue #3735（2026-09-11 提交，33 天 0 回复 0 标签）、#2041
#     （2026-06-26 起无回应）；trycua/cua 的 wayland 适配器只覆盖 Hyprland / Sway /
#     KWin / GNOME，没有 niri 车道，升级驱动版本也不解决。
#   · 连带影响：Hermes 的 computer_use 工具集已同时禁用（`hermes tools list` 显示
#     disabled），所以本文件恢复之前，连截屏能力也不存在。
#
# ── 将来若要恢复，按下面 5 步做 ──────────────────────────────────────────────
# 1) 把本文件复制回原位（去掉文件名的 _trash 路径即可）：
#      cp modules/_trash/nixos/cua-driver.nix modules/nixos/programs/cua-driver.nix
# 2) 在 modules/nixos/programs/default.nix 的 imports 里加回一行：
#      ./cua-driver.nix
# 3) 在 flake.nix 的 inputs = { ... } 里加回（放在 disko 之后即可）：
#      cua.url = "github:trycua/cua";
#    注意：不要加 inputs.nixpkgs.follows —— 上游把包构建 pin 在它自带的
#    nixos-26.05（libei/pipewire 组合经过验证），跟随 nixos-unstable 有
#    libspa/libei API 漂移风险。
# 4) 拉回 lock 节点并重建：
#      nix flake lock && sudo nixos-rebuild switch --flake .#mynixos
# 5) Hermes 侧重新启用（工具集当时被禁用、config 里的 backend 键被 unset）：
#      hermes tools enable computer_use --platform cli
#      hermes tools enable computer_use --platform telegram
#      hermes config set computer_use.backend cua
#    最后在聊天里发 /restart，让网关加载新配置。
#
# 另一条更省事的路子：恢复前先看 git 历史，本文件与 flake.nix、default.nix 的旧版本
# 都在删除前的提交里：
#      git log --oneline -- modules/nixos/programs/cua-driver.nix
#      git checkout <那个提交> -- modules/nixos/programs/cua-driver.nix \
#                                  flake.nix modules/nixos/programs/default.nix
#
# 何时值得恢复：上游补上 niri adapter 之后（跟踪 trycua/cua issue #3735 的后续）。
# 在那之前恢复它，得到的仍然只是"能看不能操作"。
# ═════════════════════════════════════════════════════════════════════════════
# ↓↓↓ 以下为停用前的原始内容，保持原样、未作任何修改 ↓↓↓
# cua-driver：Computer Use 后台桌面驱动（trycua/cua）。
#
# 采用官方 NixOS 模块（inputs.cua.nixosModules.cua-driver）——它会自动带上
# cua-driver 真正需要的运行时依赖：
#   - imagemagick   （capture.rs 窗口截图用的 `import` 命令）
#   - at-spi2-core  （AT-SPI 无障碍总线守护进程；元素识别/无障碍树的关键）
#   - services.dbus.enable = true
#   - environment.variables.CUA_DRIVER_BIN
#
# 注意：只用 Nix 构建版（inputs.cua.packages.<system>.cua-driver），不要用官方
# curl|bash 预编译二进制——那个把 portal-libei（Wayland 输入）feature-gate 关掉了，
# 在 niri（纯 Wayland）上只能看到代理光标、点击无法派发（trycua/cua issue #1982）。
# Nix 包用 --features portal-input,portal-capture（== portal-libei）已编入 libei + pipewire。
#
# 为何不 follow 根 nixpkgs：cua 上游将包构建 pin 在它自带的 nixos-26.05（libei/pipewire
# 组合经过验证），跟 nixos-unstable 走有 libspa/libei API 漂移风险。升级走
# `nix flake lock --update-input cua`。
{ inputs, pkgs, ... }:
{
  imports = [ inputs.cua.nixosModules.cua-driver ];

  services.cua-driver = {
    enable = true;
    package = inputs.cua.packages.${pkgs.stdenv.hostPlatform.system}.cua-driver;
  };

  # 开启 cua-driver 的原生 Wayland 后端（niri 是纯 Wayland，默认的 X11/XWayland 后端
  # 枚举不到 niri 原生窗口 → “no on-screen window”，见 doctor 的 wayland_backend 提示）。
  # 实测（0.22.0）：加此变量后列表窗口 ✓、zwlr_screencopy 原生截图 ✓、屏幕尺寸 ✓；
  # 已知限制：list_windows 返回的 bounds 仍为 0x0、pid 为 null（上游 issue #1922）。
  # 此变量仅在 cua-driver 内部生效，对本仓库其它部分无副作用。
  environment.variables.CUA_DRIVER_RS_ENABLE_WAYLAND = "1";
}
