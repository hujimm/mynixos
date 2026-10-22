# Waydroid（Android 容器，2026-09 弃用）。waydroid-script 来自 NUR 输入
# github:nix-community/NUR，别处没有用到 NUR。
{ inputs, pkgs, ... }:
{
  imports = [ inputs.nur.modules.nixos.default ];

  virtualisation.waydroid = {
    enable = true;
    # 较新的内核需要 nftables 后端。
    package = pkgs.waydroid-nftables;
  };

  # NAT masquerade 需要 ip_forward，NixOS 默认关闭。
  boot.kernel.sysctl."net.ipv4.ip_forward" = true;

  environment.systemPackages = [
    pkgs.wl-clipboard
    # 用法：sudo waydroid-script → 选 Android 13 → Install → libhoudini（AMD 用 libndk）。
    pkgs.nur.repos.ataraxiasjel.waydroid-script
    # 共享目录需要登录后手动 `systemctl --user start waydroid-monitor`。
    pkgs.waydroid-helper
  ];

  systemd = {
    packages = [ pkgs.waydroid-helper ];
    services.waydroid-mount.wantedBy = [ "multi-user.target" ];
  };
}
