# cua-driver（Computer Use 桌面驱动，2026-10 弃用）。niri 下只能截图、不能用输入动作：
# 上游没有 niri 的窗口 adapter（trycua/cua issue #3735）。
#
# 两个会踩的坑：必须用 Nix 构建版，官方 curl|bash 二进制关了 portal-libei，点击派发不出去；
# 不要 follows 根 nixpkgs，上游把构建 pin 在自己的 nixos-26.05（libei/pipewire 组合）。
{ inputs, pkgs, ... }:
{
  imports = [ inputs.cua.nixosModules.cua-driver ];

  services.cua-driver = {
    enable = true;
    package = inputs.cua.packages.${pkgs.stdenv.hostPlatform.system}.cua-driver;
  };

  # 默认后端走 X11/XWayland，在纯 Wayland 下枚举不到 niri 窗口（"no on-screen window"）。
  # 已知限制：开启后 list_windows 的 bounds 仍为 0x0、pid 为 null（上游 issue #1922）。
  environment.variables.CUA_DRIVER_RS_ENABLE_WAYLAND = "1";
}
